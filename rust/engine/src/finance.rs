//! Month-end close, taxes, debt and credit rating.

use crate::catalog;
use crate::model::{GameState, MonthReport, VenueMonth, month_label, usd};
use crate::secure;

pub const CORPORATE_TAX: f64 = 0.20;
pub const ITEM_LIFE_MONTHS: f64 = 60.0;
pub const FITOUT_LIFE_MONTHS: f64 = 120.0;
pub const INSURANCE_MONTHLY: f64 = 0.0025;
pub const RATINGS: [&str; 7] = ["CCC", "B", "BB", "BBB", "A", "AA", "AAA"];
const SPREADS: [f64; 7] = [0.14, 0.08, 0.05, 0.03, 0.015, 0.008, 0.0];

pub fn max_venues(license: u8) -> usize {
    match license {
        0 => 1,
        1 => 4,
        2 => 12,
        _ => 40,
    }
}

pub fn assets_book(gs: &GameState) -> f64 {
    gs.venues
        .iter()
        .map(|v| v.fitout_value + v.items.iter().map(|p| p.book_value).sum::<f64>())
        .sum()
}

pub fn debt(gs: &GameState) -> f64 {
    gs.loans.iter().map(|l| l.balance).sum()
}

pub fn net_worth(gs: &GameState) -> f64 {
    gs.cash() + assets_book(gs) - debt(gs)
}

/// EBITDA of the last three closed months, annualised.
pub fn ebitda_annual(gs: &GameState) -> f64 {
    let recent: Vec<f64> = gs.reports.iter().rev().take(3).map(|r| r.ebitda).collect();
    if recent.is_empty() {
        return 0.0;
    }
    recent.iter().sum::<f64>() / recent.len() as f64 * 12.0
}

pub fn rating(gs: &GameState) -> usize {
    let mut score: i32 = 3;
    let e = ebitda_annual(gs);
    let d = debt(gs);
    if d > 0.0 {
        let lev = if e > 0.0 { d / e } else { 99.0 };
        if lev < 1.0 {
            score += 1;
        } else if lev > 5.0 {
            score -= 2;
        } else if lev > 3.0 {
            score -= 1;
        }
    } else if e > 0.0 {
        score += 1;
    }
    if e < 0.0 {
        score -= 1;
    }
    if gs.reports.len() < 3 {
        score -= 1;
    }
    if gs.has("bank_relations") {
        score += 1;
    }
    if gs.reputation > 60.0 {
        score += 1;
    }
    score -= gs.missed_payments.min(3) as i32;
    if gs.cash() < 0.0 {
        score -= 1;
    }
    score.clamp(0, 6) as usize
}

pub fn loan_rate(gs: &GameState, base: f64) -> f64 {
    base + SPREADS[rating(gs)]
}

pub fn loan_limit(gs: &GameState, offer: &catalog::LoanOffer) -> f64 {
    let r = rating(gs);
    if r == 0 {
        return 0.0;
    }
    let capacity = ebitda_annual(gs).max(0.0) * offer.ebitda_multiple
        + assets_book(gs) * offer.asset_ltv
        - debt(gs);
    let rounded = (capacity / 1_000.0).floor() * 1_000.0;
    rounded.max(0.0)
}

pub fn annuity(principal: f64, annual_rate: f64, months: u32) -> f64 {
    let r = annual_rate / 12.0;
    if r <= 0.0 {
        return principal / months.max(1) as f64;
    }
    principal * r / (1.0 - (1.0 + r).powi(-(months as i32)))
}

pub fn close_month(gs: &mut GameState) {
    let month_index = gs.month_index().saturating_sub(1);
    let mut r = MonthReport {
        month_index,
        label: month_label(month_index),
        ..Default::default()
    };
    let lic = catalog::license(gs.license);
    let mut gaming_tax_total = 0.0;
    let mut vat_total = 0.0;
    let mut depreciation = 0.0;
    let dep_speed = if gs.has("tax_advisory") { 1.25 } else { 1.0 };

    for v in gs.venues.iter_mut() {
        let Some(city) = catalog::city(&v.city) else { continue };
        let l = std::mem::take(&mut v.month);
        let ggr = l.ggr();
        let gtax = secure::gaming_tax(ggr, city.tax_schedule);
        let gross_ng = l.non_gaming_gross();
        let vat = gross_ng * city.vat / (1.0 + city.vat);
        let net_rev = ggr - gtax - l.comps + gross_ng - vat;
        let opex = l.cogs + l.wages + l.payroll_tax + l.rent + l.utilities + l.upkeep + l.repairs
            + l.marketing
            + l.overhead
            + l.fraud
            + l.fines
            + l.other;
        for p in v.items.iter_mut() {
            let price = p.def().map(|d| d.price).unwrap_or(0.0);
            let d = (price / ITEM_LIFE_MONTHS * dep_speed).min(p.book_value);
            p.book_value -= d;
            depreciation += d;
        }
        let fd = (v.fitout_value / FITOUT_LIFE_MONTHS * dep_speed).min(v.fitout_value);
        v.fitout_value -= fd;
        depreciation += fd;

        gaming_tax_total += gtax;
        vat_total += vat;
        r.slot_ggr += l.slot_ggr;
        r.table_ggr += l.table_ggr;
        r.poker_rake += l.poker_rake;
        r.vip_ggr += l.vip_ggr;
        r.comps += l.comps;
        r.non_gaming_gross += gross_ng;
        r.cogs += l.cogs;
        r.wages += l.wages;
        r.payroll_tax += l.payroll_tax;
        r.rent += l.rent;
        r.utilities += l.utilities;
        r.upkeep += l.upkeep;
        r.repairs += l.repairs;
        r.marketing += l.marketing;
        r.overhead += l.overhead;
        r.fraud += l.fraud;
        r.fines += l.fines;
        r.other += l.other;
        r.visitors += l.visitors;
        r.venues.push(VenueMonth {
            venue_id: v.id,
            name: v.name.clone(),
            ggr,
            gaming_tax: gtax,
            net_revenue: net_rev,
            opex,
            ebitda: net_rev - opex,
            visitors: l.visitors,
        });
    }

    // Per-premises license fees and property insurance.
    let open_venues = gs.venues.iter().filter(|v| v.construction_days == 0).count() as f64;
    let license_fees = lic.monthly_fee * open_venues.max(1.0);
    let insurance = assets_book(gs) * INSURANCE_MONTHLY;

    // Debt service.
    let mut interest = gs.month_interest;
    let mut principal_paid = 0.0;
    let mut missed = false;
    let mut finished = Vec::new();
    let cash_before = gs.cash();
    for loan in gs.loans.iter_mut() {
        let i = loan.balance * loan.annual_rate / 12.0;
        let pay = loan.payment.min(loan.balance + i);
        let p = (pay - i).max(0.0);
        interest += i;
        principal_paid += p;
        loan.balance -= p;
        loan.months_left = loan.months_left.saturating_sub(1);
        if loan.months_left == 0 || loan.balance < 1.0 {
            finished.push(loan.id);
        }
    }
    let debt_service = interest - gs.month_interest + principal_paid;
    if debt_service > 0.0 && cash_before < debt_service {
        missed = true;
    }
    gs.loans.retain(|l| !finished.contains(&l.id));

    r.ggr = r.slot_ggr + r.table_ggr + r.poker_rake + r.vip_ggr;
    r.gaming_tax = gaming_tax_total;
    r.net_gaming = r.ggr - r.gaming_tax - r.comps;
    r.vat = vat_total;
    r.non_gaming_net = r.non_gaming_gross - r.vat;
    r.net_revenue = r.net_gaming + r.non_gaming_net;
    r.license_fees = license_fees;
    r.insurance = insurance;
    r.fines += gs.month_fines;
    r.other += gs.month_other;
    r.opex = r.cogs + r.wages + r.payroll_tax + r.rent + r.utilities + r.upkeep + r.repairs
        + r.marketing
        + r.overhead
        + r.license_fees
        + r.insurance
        + r.fraud
        + r.fines
        + r.other;
    r.ebitda = r.net_revenue - r.opex;
    r.depreciation = depreciation;
    r.interest = interest;
    r.ebt = r.ebitda - r.depreciation - r.interest;

    let taxable = r.ebt - gs.loss_carryforward;
    let rate = CORPORATE_TAX * if gs.has("tax_advisory") { 0.85 } else { 1.0 };
    if r.ebt < 0.0 {
        gs.loss_carryforward += -r.ebt;
        r.income_tax = 0.0;
    } else if taxable > 0.0 {
        r.income_tax = taxable * rate;
        gs.loss_carryforward = 0.0;
    } else {
        gs.loss_carryforward -= r.ebt;
        r.income_tax = 0.0;
    }
    r.net_income = r.ebt - r.income_tax;

    // Daily costs were already paid; settle the month-end obligations now.
    let monthly_cash = gaming_tax_total + vat_total + license_fees + insurance + r.income_tax
        + (interest - gs.month_interest)
        + principal_paid;
    gs.add_cash(-monthly_cash);
    r.cash_end = gs.cash();

    gs.lifetime.taxes_paid += gaming_tax_total + vat_total + r.income_tax + r.payroll_tax;
    gs.lifetime.wages_paid += r.wages;
    gs.lifetime.ggr += r.ggr;
    gs.lifetime.visitors += r.visitors;

    gs.month_interest = 0.0;
    gs.month_fines = 0.0;
    gs.month_other = 0.0;
    gs.month_license_fees = 0.0;

    if missed {
        gs.missed_payments += 1;
        let penalty = debt(gs) * 0.02;
        gs.add_cash(-penalty);
        gs.log(
            "bad",
            "Missed loan payment",
            format!("Not enough cash for debt service. Penalty {}, credit rating down.", usd(penalty)),
        );
    } else if gs.missed_payments > 0 && gs.month_index() % 6 == 0 {
        gs.missed_payments -= 1;
    }

    if r.net_income > 0.0 {
        gs.reputation = (gs.reputation + 0.4).min(100.0);
    }
    let tone = if r.net_income >= 0.0 { "good" } else { "bad" };
    gs.log(
        tone,
        format!("Books closed: {}", r.label),
        format!(
            "GGR {}, EBITDA {}, net income {}. Taxes paid {}.",
            usd(r.ggr),
            usd(r.ebitda),
            usd(r.net_income),
            usd(gaming_tax_total + vat_total + r.income_tax)
        ),
    );
    let nw = net_worth(gs);
    if nw > gs.lifetime.peak_net_worth {
        gs.lifetime.peak_net_worth = nw;
    }
    gs.reports.push_back(r);
    while gs.reports.len() > 36 {
        gs.reports.pop_front();
    }
}

pub fn check_insolvency(gs: &mut GameState) {
    let limit = -(assets_book(gs) * 0.3).max(25_000.0);
    if gs.cash() < limit {
        gs.insolvent_days += 1;
        if gs.insolvent_days == 1 || gs.insolvent_days % 10 == 0 {
            let left = 45u32.saturating_sub(gs.insolvent_days);
            gs.log(
                "bad",
                "Insolvency warning",
                format!("Cash is below the overdraft limit. Recover within {left} days or the bank will force bankruptcy."),
            );
        }
        if gs.insolvent_days >= 45 {
            gs.game_over = true;
            gs.log("bad", "Bankruptcy", "Creditors have taken control of the company.");
        }
    } else {
        gs.insolvent_days = 0;
    }
}
