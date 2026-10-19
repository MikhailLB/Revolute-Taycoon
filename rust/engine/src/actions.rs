//! Player commands. Swift never mutates state: it sends one of these and the
//! engine validates it against money, licenses, research and floor space.

use serde::Deserialize;

use crate::catalog::{self, ItemCategory, ROLE_COUNT, Role};
use crate::finance;
use crate::model::{ActiveResearch, GameState, Loan, Placed, Venue};
use crate::sim;

#[derive(Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Action {
    Place { venue: u32, item: String, x: u8, y: u8 },
    Move { venue: u32, id: u32, x: u8, y: u8 },
    Sell { venue: u32, id: u32 },
    Hire { venue: u32, role: String, count: i32 },
    AutoStaff { venue: u32 },
    SetWage { venue: u32, level: f64 },
    SetMarketing { venue: u32, amount: f64 },
    SetComps { venue: u32, rate: f64 },
    RepairAll { venue: u32 },
    Research { id: String },
    BuyLicense,
    UpgradeFormat { venue: u32 },
    OpenBranch { city: String, name: String },
    RenameVenue { venue: u32, name: String },
    RenameCompany { name: String },
    TakeLoan { offer: String, amount: f64 },
    RepayLoan { id: u32, amount: f64 },
    Decide { option: u32 },
}

type Res = Result<String, String>;

fn money(v: f64) -> String {
    let a = v.abs();
    let s = if a >= 1e6 {
        format!("{:.2}M", a / 1e6)
    } else if a >= 1e3 {
        format!("{:.1}K", a / 1e3)
    } else {
        format!("{a:.0}")
    };
    if v < 0.0 { format!("-${s}") } else { format!("${s}") }
}

fn require_cash(gs: &GameState, amount: f64) -> Result<(), String> {
    if gs.cash() < amount {
        return Err(format!("Not enough cash: need {}", money(amount)));
    }
    Ok(())
}

fn venue_index(gs: &GameState, id: u32) -> Result<usize, String> {
    gs.venues
        .iter()
        .position(|v| v.id == id)
        .ok_or_else(|| "Unknown venue".to_owned())
}

fn clean_name(name: &str, fallback: &str) -> String {
    let n: String = name.chars().filter(|c| !c.is_control()).take(28).collect();
    let n = n.trim().to_owned();
    if n.is_empty() { fallback.to_owned() } else { n }
}

pub fn item_block_reason(gs: &GameState, v: &Venue, item: &catalog::ItemDef) -> Option<String> {
    if let Some(r) = item.requires_research
        && !gs.has(r)
    {
        let name = catalog::research(r).map(|d| d.name).unwrap_or(r);
        return Some(format!("Requires development: {name}"));
    }
    if v.format < item.min_format {
        return Some(format!("Requires venue format: {}", catalog::format(item.min_format).name));
    }
    let lic = catalog::license(gs.license);
    match item.category {
        ItemCategory::Slot => {
            let n: u32 = v.count_where(|d| d.category == ItemCategory::Slot);
            if n >= lic.max_slots {
                return Some(format!("{} allows {} machines per venue", lic.name, lic.max_slots));
            }
        }
        ItemCategory::Table => {
            let n: u32 = v.count_where(|d| d.category == ItemCategory::Table);
            if n >= lic.max_tables {
                return Some(format!("{} allows {} tables per venue", lic.name, lic.max_tables));
            }
        }
        _ => {}
    }
    None
}

pub fn license_block_reason(gs: &GameState) -> Option<String> {
    let next = gs.license + 1;
    if next as usize >= catalog::LICENSES.len() {
        return Some("Highest license already held".into());
    }
    let l = catalog::license(next);
    if l.early_access_locked {
        return Some("Coming in a future update".into());
    }
    if gs.reputation < l.min_reputation {
        return Some(format!("Reputation {:.0} of {:.0} needed", gs.reputation, l.min_reputation));
    }
    let ops: Vec<&Venue> = gs.venues.iter().filter(|v| v.construction_days == 0).collect();
    let avg = if ops.is_empty() {
        0.0
    } else {
        ops.iter().map(|v| v.compliance).sum::<f64>() / ops.len() as f64
    };
    if avg < l.min_compliance {
        return Some(format!("Average compliance {:.0} of {:.0} needed", avg, l.min_compliance));
    }
    if let Some(r) = l.requires_research
        && !gs.has(r)
    {
        let name = catalog::research(r).map(|d| d.name).unwrap_or(r);
        return Some(format!("Requires development: {name}"));
    }
    if gs.cash() < l.price {
        return Some(format!("Costs {}", money(l.price)));
    }
    None
}

pub fn format_block_reason(gs: &GameState, v: &Venue) -> Option<String> {
    let next = v.format + 1;
    if next as usize >= catalog::FORMATS.len() {
        return Some("Largest format already".into());
    }
    let f = catalog::format(next);
    if f.early_access_locked {
        return Some("Coming in a future update".into());
    }
    if v.construction_days > 0 || v.renovation_days > 0 {
        return Some("Works already in progress".into());
    }
    if gs.license < f.min_license {
        return Some(format!("Requires {}", catalog::license(f.min_license).name));
    }
    if gs.reputation < f.min_reputation {
        return Some(format!("Reputation {:.0} of {:.0} needed", gs.reputation, f.min_reputation));
    }
    if gs.cash() < f.upgrade_cost {
        return Some(format!("Costs {}", money(f.upgrade_cost)));
    }
    None
}

pub fn branch_cost(gs: &GameState, city: &catalog::CityDef) -> (f64, u32) {
    let base = catalog::format(0);
    let mut cost = base.build_cost * (city.rent_m2_month / 16.0).sqrt();
    let mut days = base.build_days as f64 * 1.5;
    if gs.has("franchise_ops") {
        cost *= 0.7;
        days *= 0.7;
    }
    (cost.round(), days.ceil() as u32)
}

pub fn branch_block_reason(gs: &GameState, city: &catalog::CityDef) -> Option<String> {
    if city.early_access_locked {
        return Some("Coming in a future update".into());
    }
    if gs.venues.len() >= finance::max_venues(gs.license) {
        return Some(format!(
            "{} allows {} venue(s)",
            catalog::license(gs.license).name,
            finance::max_venues(gs.license)
        ));
    }
    if gs.license < city.min_license {
        return Some(format!("Requires {}", catalog::license(city.min_license).name));
    }
    let (cost, _) = branch_cost(gs, city);
    if gs.cash() < cost {
        return Some(format!("Costs {}", money(cost)));
    }
    None
}

pub fn research_state(gs: &GameState, r: &catalog::ResearchDef) -> &'static str {
    if gs.has(r.id) {
        "done"
    } else if gs.research_active.as_ref().is_some_and(|a| a.id == r.id) {
        "active"
    } else if r.early_access_locked {
        "early_access"
    } else if r.requires.iter().all(|q| gs.has(q)) {
        "available"
    } else {
        "locked"
    }
}

pub fn apply(gs: &mut GameState, action: Action) -> Res {
    if gs.game_over {
        return Err("The company is bankrupt. Start a new game.".into());
    }
    match action {
        Action::Place { venue, item, x, y } => {
            let vi = venue_index(gs, venue)?;
            let def = catalog::item(&item).ok_or("Unknown item")?;
            if let Some(r) = item_block_reason(gs, &gs.venues[vi], def) {
                return Err(r);
            }
            let (gw, gh) = gs.venues[vi].grid();
            if x as u32 + def.w as u32 > gw as u32 || y as u32 + def.h as u32 > gh as u32 {
                return Err("Does not fit on the floor".into());
            }
            if gs.venues[vi].occupied(x, y, def.w, def.h, None) {
                return Err("That spot is taken".into());
            }
            require_cash(gs, def.price)?;
            gs.add_cash(-def.price);
            let v = &mut gs.venues[vi];
            let id = v.next_item_id;
            v.next_item_id += 1;
            v.items.push(Placed {
                id,
                item: def.id.to_owned(),
                x,
                y,
                broken_days: 0,
                book_value: def.price,
            });
            Ok(format!("{} installed", def.name))
        }
        Action::Move { venue, id, x, y } => {
            let vi = venue_index(gs, venue)?;
            let v = &mut gs.venues[vi];
            let pos = v.items.iter().position(|p| p.id == id).ok_or("Unknown item")?;
            let def = v.items[pos].def().ok_or("Unknown item")?;
            let (gw, gh) = v.grid();
            if x as u32 + def.w as u32 > gw as u32 || y as u32 + def.h as u32 > gh as u32 {
                return Err("Does not fit on the floor".into());
            }
            if v.occupied(x, y, def.w, def.h, Some(id)) {
                return Err("That spot is taken".into());
            }
            v.items[pos].x = x;
            v.items[pos].y = y;
            Ok("Moved".into())
        }
        Action::Sell { venue, id } => {
            let vi = venue_index(gs, venue)?;
            let v = &mut gs.venues[vi];
            let pos = v.items.iter().position(|p| p.id == id).ok_or("Unknown item")?;
            let p = v.items.remove(pos);
            let refund = (p.book_value * 0.5).round();
            gs.add_cash(refund);
            Ok(format!("Sold for {}", money(refund)))
        }
        Action::Hire { venue, role, count } => {
            let vi = venue_index(gs, venue)?;
            let role = catalog::role_from_id(&role).ok_or("Unknown role")?;
            hire(gs, vi, role, count)
        }
        Action::AutoStaff { venue } => {
            let vi = venue_index(gs, venue)?;
            let need = sim::staff_needs(&gs.venues[vi]);
            let mut changed = 0;
            for i in 0..ROLE_COUNT {
                let have = gs.venues[vi].staff[i] as i32;
                let diff = need[i] as i32 - have;
                if diff != 0 {
                    hire(gs, vi, catalog::ROLES[i].role, diff)?;
                    changed += diff.abs();
                }
            }
            Ok(if changed == 0 {
                "Staffing already matches the floor".into()
            } else {
                format!("Roster adjusted: {changed} change(s)")
            })
        }
        Action::SetWage { venue, level } => {
            let vi = venue_index(gs, venue)?;
            gs.venues[vi].wage_level = level.clamp(0.8, 1.5);
            Ok("Pay level updated".into())
        }
        Action::SetMarketing { venue, amount } => {
            let vi = venue_index(gs, venue)?;
            gs.venues[vi].marketing_month = amount.clamp(0.0, 2_000_000.0).round();
            Ok("Marketing budget updated".into())
        }
        Action::SetComps { venue, rate } => {
            let vi = venue_index(gs, venue)?;
            gs.venues[vi].comp_rate = rate.clamp(0.0, 0.25);
            Ok("Comp rate updated".into())
        }
        Action::RepairAll { venue } => {
            let vi = venue_index(gs, venue)?;
            let n = gs.venues[vi].items.iter().filter(|p| p.broken_days > 0).count();
            if n == 0 {
                return Err("Nothing is broken".into());
            }
            let cost: f64 = gs.venues[vi]
                .items
                .iter()
                .filter(|p| p.broken_days > 0)
                .filter_map(|p| p.def())
                .map(|d| d.price * 0.04 + 150.0)
                .sum();
            require_cash(gs, cost)?;
            gs.add_cash(-cost);
            let v = &mut gs.venues[vi];
            v.today.repairs += cost;
            for p in v.items.iter_mut() {
                p.broken_days = 0;
            }
            Ok(format!("Express repair of {n} machine(s) for {}", money(cost)))
        }
        Action::Research { id } => {
            let r = catalog::research(&id).ok_or("Unknown project")?;
            if gs.research_active.is_some() {
                return Err("Another project is in progress".into());
            }
            match research_state(gs, r) {
                "available" => {}
                "done" => return Err("Already completed".into()),
                "early_access" => return Err("Coming in a future update".into()),
                _ => return Err("Complete the prerequisites first".into()),
            }
            require_cash(gs, r.cost)?;
            gs.add_cash(-r.cost);
            gs.month_other += r.cost;
            gs.research_active = Some(ActiveResearch {
                id: r.id.to_owned(),
                days_left: r.days,
            });
            Ok(format!("{} started: {} days", r.name, r.days))
        }
        Action::BuyLicense => {
            if let Some(r) = license_block_reason(gs) {
                return Err(r);
            }
            let l = catalog::license(gs.license + 1);
            gs.add_cash(-l.price);
            gs.license += 1;
            gs.log("good", "License granted", format!("The regulator granted the {}.", l.name));
            Ok(format!("{} granted", l.name))
        }
        Action::UpgradeFormat { venue } => {
            let vi = venue_index(gs, venue)?;
            if let Some(r) = format_block_reason(gs, &gs.venues[vi]) {
                return Err(r);
            }
            let f = catalog::format(gs.venues[vi].format + 1);
            gs.add_cash(-f.upgrade_cost);
            let v = &mut gs.venues[vi];
            v.format += 1;
            v.fitout_value += f.upgrade_cost;
            v.renovation_days = (f.build_days / 2).max(3);
            let name = v.name.clone();
            gs.log("good", "Expansion started", format!("{name} is becoming a {}. The floor runs at half capacity during works.", f.name));
            Ok(format!("Upgrading to {}", f.name))
        }
        Action::OpenBranch { city, name } => {
            let c = catalog::city(&city).ok_or("Unknown city")?;
            if let Some(r) = branch_block_reason(gs, c) {
                return Err(r);
            }
            let (cost, days) = branch_cost(gs, c);
            gs.add_cash(-cost);
            let id = gs.next_venue_id;
            gs.next_venue_id += 1;
            let fallback = format!("Revolute {}", c.name);
            let mut v = crate::new_venue(id, clean_name(&name, &fallback), c.id, cost);
            v.construction_days = days;
            v.items.push(Placed { id: 0, item: "cashier".into(), x: 0, y: 0, broken_days: 0, book_value: 0.0 });
            v.items.push(Placed { id: 1, item: "restroom".into(), x: 9, y: 0, broken_days: 0, book_value: 0.0 });
            v.next_item_id = 2;
            gs.venues.push(v);
            gs.log("info", "Branch under construction", format!("Fit-out in {} started. Opening in {days} days.", c.name));
            Ok(format!("Construction started: {days} days"))
        }
        Action::RenameVenue { venue, name } => {
            let vi = venue_index(gs, venue)?;
            let fallback = gs.venues[vi].name.clone();
            gs.venues[vi].name = clean_name(&name, &fallback);
            Ok("Renamed".into())
        }
        Action::RenameCompany { name } => {
            let fallback = gs.company.clone();
            gs.company = clean_name(&name, &fallback);
            Ok("Renamed".into())
        }
        Action::TakeLoan { offer, amount } => {
            let o = catalog::loan_offer(&offer).ok_or("Unknown offer")?;
            let limit = finance::loan_limit(gs, o);
            let amount = amount.round();
            if amount < 1_000.0 {
                return Err("Minimum loan is $1,000".into());
            }
            if amount > limit {
                return Err(format!("The bank approves up to {}", money(limit)));
            }
            let rate = finance::loan_rate(gs, o.base_rate);
            let payment = finance::annuity(amount, rate, o.months);
            let id = gs.next_loan_id;
            gs.next_loan_id += 1;
            gs.loans.push(Loan {
                id,
                offer: o.id.to_owned(),
                name: o.name.to_owned(),
                principal: amount,
                balance: amount,
                annual_rate: rate,
                months_left: o.months,
                payment,
            });
            gs.add_cash(amount);
            gs.log("info", "Loan received", format!("{} of {} at {:.1}% for {} months.", o.name, money(amount), rate * 100.0, o.months));
            Ok(format!("Received {}", money(amount)))
        }
        Action::RepayLoan { id, amount } => {
            let pos = gs.loans.iter().position(|l| l.id == id).ok_or("Unknown loan")?;
            let bal = gs.loans[pos].balance;
            let pay = amount.min(bal).max(0.0);
            if pay <= 0.0 {
                return Err("Nothing to repay".into());
            }
            require_cash(gs, pay)?;
            gs.add_cash(-pay);
            let l = &mut gs.loans[pos];
            l.balance -= pay;
            if l.balance < 1.0 {
                gs.loans.remove(pos);
                return Ok("Loan repaid in full".into());
            }
            let rate = l.annual_rate;
            let months = l.months_left;
            l.payment = finance::annuity(l.balance, rate, months.max(1));
            Ok(format!("Repaid {}", money(pay)))
        }
        Action::Decide { option } => crate::events::resolve(gs, option),
    }
}

fn hire(gs: &mut GameState, vi: usize, role: Role, count: i32) -> Res {
    let def = catalog::role_def(role);
    let i = role.index();
    if count > 0 {
        let have = gs.venues[vi].staff[i];
        if have + count as u32 > 2_000 {
            return Err("Roster limit reached".into());
        }
        let cost = def.hire_cost * count as f64;
        require_cash(gs, cost)?;
        gs.add_cash(-cost);
        gs.venues[vi].today.other += cost;
        gs.venues[vi].staff[i] += count as u32;
        Ok(format!("Hired {count} × {}", def.name))
    } else if count < 0 {
        let n = (-count) as u32;
        let have = gs.venues[vi].staff[i];
        let n = n.min(have);
        if n == 0 {
            return Err("No one to let go".into());
        }
        let wage_index = catalog::city(&gs.venues[vi].city).map(|c| c.wage_index).unwrap_or(1.0);
        let severance = def.salary_month * wage_index * 0.5 * n as f64;
        gs.add_cash(-severance);
        let v = &mut gs.venues[vi];
        v.today.other += severance;
        v.staff[i] -= n;
        v.morale = (v.morale - 1.5 * n as f64).max(0.0);
        Ok(format!("Let go {n} × {} (severance {})", def.name, money(severance)))
    } else {
        Ok("No change".into())
    }
}
