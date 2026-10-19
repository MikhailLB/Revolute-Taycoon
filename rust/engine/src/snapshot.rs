//! Read-only view of the game handed to Swift as JSON. Everything derived
//! (staffing needs, block reasons, rating, loan limits) is computed here so
//! the UI only renders.

use serde::Serialize;

use crate::actions;
use crate::catalog::{self, ROLE_COUNT};
use crate::finance;
use crate::goals::{self, GoalView};
use crate::model::{
    DayStat, Decision, GameState, Ledger, LogEntry, MonthReport, Placed, START_YEAR, WEEKDAYS,
    month_label,
};
use crate::secure;
use crate::sim;

#[derive(Serialize)]
pub struct Clock {
    pub day: u32,
    pub hour: u32,
    pub weekday: &'static str,
    pub day_of_month: u32,
    pub month_label: String,
    pub year: u32,
    pub days_to_close: u32,
}

#[derive(Serialize)]
pub struct StaffLine {
    pub role: &'static str,
    pub have: u32,
    pub need: u32,
    pub coverage: f64,
    pub monthly_cost: f64,
}

#[derive(Serialize)]
pub struct ItemOption {
    pub id: &'static str,
    pub blocked: Option<String>,
}

#[derive(Serialize)]
pub struct VenueView<'a> {
    pub id: u32,
    pub name: &'a str,
    pub city: &'a str,
    pub city_name: &'static str,
    pub format: u8,
    pub format_name: &'static str,
    pub grid_w: u8,
    pub grid_h: u8,
    pub area_m2: f64,
    pub items: &'a [Placed],
    pub staff: Vec<StaffLine>,
    pub wage_level: f64,
    pub marketing_month: f64,
    pub comp_rate: f64,
    pub construction_days: u32,
    pub renovation_days: u32,
    pub suspended_days: u32,
    pub tables_closed_days: u32,
    pub satisfaction: f64,
    pub morale: f64,
    pub compliance: f64,
    pub security: f64,
    pub buzz: f64,
    pub open_now: bool,
    pub open_from: u32,
    pub open_to: u32,
    pub closed_reason: Option<String>,
    pub guests_now: f64,
    pub occupancy_now: f64,
    pub forecast_visitors: f64,
    pub gaming_seats: u32,
    pub machines: u32,
    pub tables: u32,
    pub broken: u32,
    pub appeal: f64,
    pub monthly_payroll: f64,
    pub monthly_rent: f64,
    pub month: &'a Ledger,
    pub today: &'a Ledger,
    pub days: Vec<&'a DayStat>,
    pub item_options: Vec<ItemOption>,
    pub upgrade_blocked: Option<String>,
    pub next_format: Option<&'static catalog::FormatDef>,
}

#[derive(Serialize)]
pub struct ResearchView {
    pub id: &'static str,
    pub state: &'static str,
    pub days_left: u32,
}

#[derive(Serialize)]
pub struct LicenseView {
    pub tier: u8,
    pub state: &'static str,
    pub blocked: Option<String>,
}

#[derive(Serialize)]
pub struct CityView {
    pub id: &'static str,
    pub venues: u32,
    pub pressure: f64,
    pub branch_cost: f64,
    pub branch_days: u32,
    pub blocked: Option<String>,
}

#[derive(Serialize)]
pub struct LoanOfferView {
    pub id: &'static str,
    pub rate: f64,
    pub limit: f64,
}

#[derive(Serialize)]
pub struct Company<'a> {
    pub name: &'a str,
    pub cash: f64,
    pub reputation: f64,
    pub license: u8,
    pub license_name: &'static str,
    pub rating: &'static str,
    pub net_worth: f64,
    pub assets: f64,
    pub debt: f64,
    pub ebitda_annual: f64,
    pub loss_carryforward: f64,
    pub economy: f64,
    pub insolvent_days: u32,
    pub missed_payments: u32,
    pub max_venues: usize,
    pub taxes_paid: f64,
    pub lifetime_ggr: f64,
    pub lifetime_visitors: f64,
    pub game_over: bool,
    pub integrity: bool,
}

#[derive(Serialize)]
pub struct Snapshot<'a> {
    pub clock: Clock,
    pub company: Company<'a>,
    pub venues: Vec<VenueView<'a>>,
    pub research: Vec<ResearchView>,
    pub research_active: Option<&'a str>,
    pub licenses: Vec<LicenseView>,
    pub cities: Vec<CityView>,
    pub loans: &'a [crate::model::Loan],
    pub loan_offers: Vec<LoanOfferView>,
    pub reports: Vec<&'a MonthReport>,
    pub company_days: Vec<&'a DayStat>,
    pub log: Vec<&'a LogEntry>,
    pub decision: Option<&'a Decision>,
    pub goals: Vec<GoalView>,
}

pub fn build(gs: &GameState) -> Snapshot<'_> {
    let clock = Clock {
        day: gs.day,
        hour: gs.hour,
        weekday: WEEKDAYS[gs.weekday() as usize],
        day_of_month: gs.day % 30 + 1,
        month_label: month_label(gs.month_index()),
        year: START_YEAR + gs.month_index() / 12,
        days_to_close: 30 - gs.day % 30,
    };
    let company = Company {
        name: &gs.company,
        cash: gs.cash(),
        reputation: gs.reputation,
        license: gs.license,
        license_name: catalog::license(gs.license).name,
        rating: finance::RATINGS[finance::rating(gs)],
        net_worth: finance::net_worth(gs),
        assets: finance::assets_book(gs),
        debt: finance::debt(gs),
        ebitda_annual: finance::ebitda_annual(gs),
        loss_carryforward: gs.loss_carryforward,
        economy: gs.economy,
        insolvent_days: gs.insolvent_days,
        missed_payments: gs.missed_payments,
        max_venues: finance::max_venues(gs.license),
        taxes_paid: gs.lifetime.taxes_paid,
        lifetime_ggr: gs.lifetime.ggr,
        lifetime_visitors: gs.lifetime.visitors,
        game_over: gs.game_over,
        integrity: !secure::tampered(),
    };

    let venues = gs
        .venues
        .iter()
        .map(|v| {
            let fmt = catalog::format(v.format);
            let city = catalog::city(&v.city);
            let need = sim::staff_needs(v);
            let cov = sim::coverage(v);
            let wage_index = city.map(|c| c.wage_index).unwrap_or(1.0);
            let staff = (0..ROLE_COUNT)
                .map(|i| StaffLine {
                    role: catalog::ROLES[i].id,
                    have: v.staff[i],
                    need: need[i],
                    coverage: cov[i],
                    monthly_cost: v.staff[i] as f64
                        * catalog::ROLES[i].salary_month
                        * wage_index
                        * v.wage_level,
                })
                .collect();
            let c = sim::floor_counts(v);
            let (open_from, open_to) = sim::open_hours(v.format);
            let next = v.format + 1;
            VenueView {
                id: v.id,
                name: &v.name,
                city: &v.city,
                city_name: city.map(|c| c.name).unwrap_or("?"),
                format: v.format,
                format_name: fmt.name,
                grid_w: fmt.grid_w,
                grid_h: fmt.grid_h,
                area_m2: fmt.area_m2,
                items: &v.items,
                staff,
                wage_level: v.wage_level,
                marketing_month: v.marketing_month,
                comp_rate: v.comp_rate,
                construction_days: v.construction_days,
                renovation_days: v.renovation_days,
                suspended_days: v.suspended_days,
                tables_closed_days: v.tables_closed_days,
                satisfaction: v.satisfaction,
                morale: v.morale,
                compliance: v.compliance,
                security: v.security,
                buzz: v.buzz,
                open_now: v.closed_reason.is_none() && sim::is_open_hour(v.format, gs.hour),
                open_from,
                open_to,
                closed_reason: v.closed_reason.clone(),
                guests_now: v.guests_now,
                occupancy_now: v.occupancy_now,
                forecast_visitors: sim::day_potential(gs, v),
                gaming_seats: c.gaming_seats,
                machines: c.machines,
                tables: c.tables,
                broken: c.broken,
                appeal: c.appeal,
                monthly_payroll: sim::monthly_wages(gs, v),
                monthly_rent: fmt.area_m2 * city.map(|c| c.rent_m2_month).unwrap_or(0.0),
                month: &v.month,
                today: &v.today,
                days: v.days.iter().rev().take(30).rev().collect(),
                item_options: catalog::ITEMS
                    .iter()
                    .map(|d| ItemOption {
                        id: d.id,
                        blocked: actions::item_block_reason(gs, v, d),
                    })
                    .collect(),
                upgrade_blocked: actions::format_block_reason(gs, v),
                next_format: if (next as usize) < catalog::FORMATS.len() {
                    Some(catalog::format(next))
                } else {
                    None
                },
            }
        })
        .collect();

    let research = catalog::RESEARCH
        .iter()
        .map(|r| ResearchView {
            id: r.id,
            state: actions::research_state(gs, r),
            days_left: gs
                .research_active
                .as_ref()
                .filter(|a| a.id == r.id)
                .map(|a| a.days_left)
                .unwrap_or(0),
        })
        .collect();

    let licenses = catalog::LICENSES
        .iter()
        .map(|l| {
            let (state, blocked) = if l.tier <= gs.license {
                ("owned", None)
            } else if l.tier == gs.license + 1 {
                let b = actions::license_block_reason(gs);
                (if l.early_access_locked { "early_access" } else { "next" }, b)
            } else if l.early_access_locked {
                ("early_access", Some("Coming in a future update".into()))
            } else {
                ("locked", Some("Obtain the previous license first".into()))
            };
            LicenseView {
                tier: l.tier,
                state,
                blocked,
            }
        })
        .collect();

    let cities = catalog::CITIES
        .iter()
        .map(|c| {
            let (cost, days) = actions::branch_cost(gs, c);
            CityView {
                id: c.id,
                venues: gs.venues.iter().filter(|v| v.city == c.id).count() as u32,
                pressure: gs.city_pressure(c.id),
                branch_cost: cost,
                branch_days: days,
                blocked: actions::branch_block_reason(gs, c),
            }
        })
        .collect();

    let loan_offers = catalog::LOANS
        .iter()
        .map(|o| LoanOfferView {
            id: o.id,
            rate: finance::loan_rate(gs, o.base_rate),
            limit: finance::loan_limit(gs, o),
        })
        .collect();

    Snapshot {
        clock,
        company,
        venues,
        research,
        research_active: gs.research_active.as_ref().map(|a| a.id.as_str()),
        licenses,
        cities,
        loans: &gs.loans,
        loan_offers,
        reports: gs.reports.iter().rev().take(24).rev().collect(),
        company_days: gs.company_days.iter().rev().take(60).rev().collect(),
        log: gs.log.iter().take(60).collect(),
        decision: gs.decision.as_ref(),
        goals: goals::views(gs),
    }
}
