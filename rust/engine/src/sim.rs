//! Hour-by-hour operation of every venue and the daily close.

use crate::catalog::{self, ItemCategory, ROLE_COUNT, Revenue, Role};
use crate::model::{DayStat, GameState, HOURS_PER_DAY, Ledger, Venue};
use crate::{events, finance, goals};

/// Staff needed to keep one post filled around the clock (shifts, days off, leave).
pub const POST_COVER_24H: f64 = 4.0;

/// Relative guest arrivals by hour of day.
const HOUR_CURVE: [f64; 24] = [
    0.040, 0.030, 0.020, 0.012, 0.007, 0.005, 0.006, 0.009, 0.013, 0.018, 0.024, 0.031, 0.038,
    0.042, 0.045, 0.048, 0.053, 0.060, 0.068, 0.078, 0.084, 0.082, 0.072, 0.055,
];

const WEEKDAY_TRAFFIC: [f64; 7] = [0.82, 0.80, 0.86, 0.95, 1.25, 1.40, 1.08];

pub fn open_hours(format: u8) -> (u32, u32) {
    match format {
        0 => (14, 4),
        1 => (12, 6),
        _ => (0, 24),
    }
}

pub fn is_open_hour(format: u8, hour: u32) -> bool {
    let (open, close) = open_hours(format);
    if close == 24 {
        return true;
    }
    hour >= open || hour < close
}

pub fn hours_open(format: u8) -> u32 {
    (0..HOURS_PER_DAY).filter(|h| is_open_hour(format, *h)).count() as u32
}

fn curve_share(format: u8, hour: u32) -> f64 {
    let total: f64 = (0..24)
        .filter(|h| is_open_hour(format, *h))
        .map(|h| HOUR_CURVE[h as usize])
        .sum();
    if total <= 0.0 || !is_open_hour(format, hour) {
        return 0.0;
    }
    HOUR_CURVE[hour as usize] / total
}

#[derive(Default, Clone, Copy)]
pub struct FloorCounts {
    pub machines: u32,
    pub machine_seats: u32,
    pub live_tables: u32,
    pub vip: u32,
    pub cages: u32,
    pub bars: u32,
    pub restaurants: u32,
    pub stages: u32,
    pub restrooms: u32,
    pub lounges: u32,
    pub security_posts: u32,
    pub surveillance: u32,
    pub gaming_seats: u32,
    pub appeal: f64,
    pub decor_appeal: f64,
    pub broken: u32,
    pub slots: u32,
    pub tables: u32,
}

pub fn floor_counts(v: &Venue) -> FloorCounts {
    let mut c = FloorCounts::default();
    for p in &v.items {
        let Some(d) = p.def() else { continue };
        c.appeal += d.appeal;
        match d.revenue {
            Revenue::Machine => {
                c.machines += 1;
                c.machine_seats += d.seats;
                c.gaming_seats += d.seats;
                if p.broken_days > 0 {
                    c.broken += 1;
                }
            }
            Revenue::LiveTable | Revenue::Rake => {
                c.live_tables += 1;
                c.gaming_seats += d.seats;
            }
            Revenue::HighLimit => {
                c.vip += 1;
                c.gaming_seats += d.seats;
            }
            _ => {}
        }
        match d.category {
            ItemCategory::Slot => c.slots += 1,
            ItemCategory::Table => c.tables += 1,
            ItemCategory::Decor => c.decor_appeal += d.appeal,
            _ => {}
        }
        match d.id {
            "cashier" => c.cages += 1,
            "bar" => c.bars += 1,
            "restaurant" => c.restaurants += 1,
            "stage" => c.stages += 1,
            "restroom" => c.restrooms += 1,
            "lounge" => c.lounges += 1,
            "security_post" => c.security_posts += 1,
            "surveillance" => c.surveillance += 1,
            _ => {}
        }
    }
    c
}

/// Head count each role needs to fully staff the floor as it stands.
pub fn staff_needs(v: &Venue) -> [u32; ROLE_COUNT] {
    let c = floor_counts(v);
    let hours = hours_open(v.format) as f64;
    let sf = hours / 24.0 * POST_COVER_24H;
    let mut need = [0.0f64; ROLE_COUNT];
    need[Role::Dealer.index()] = (c.live_tables as f64 + c.vip as f64 * 2.0) * sf;
    if c.machine_seats > 0 {
        need[Role::Attendant.index()] = (c.machine_seats as f64 / 25.0).ceil() * sf;
    }
    need[Role::Cashier.index()] = c.cages as f64 * sf;
    need[Role::Security.index()] = (c.gaming_seats as f64 / 40.0).ceil().max(1.0) * sf;
    need[Role::Hospitality.index()] =
        c.bars as f64 * sf + c.restaurants as f64 * 2.0 * sf * 0.75 + c.stages as f64 * 2.0;
    if c.machines > 0 {
        need[Role::Technician.index()] = (c.machines as f64 / 30.0).ceil();
    }
    need[Role::Manager.index()] = match v.format {
        0 => 1.0,
        f => (hours / 8.0).ceil() * f as f64,
    };
    need[Role::Compliance.index()] = [1.0, 2.0, 4.0, 8.0][(v.format as usize).min(3)];
    let mut out = [0u32; ROLE_COUNT];
    for (o, n) in out.iter_mut().zip(need.iter()) {
        *o = (n - 1e-9).ceil().max(0.0) as u32;
    }
    out
}

pub fn coverage(v: &Venue) -> [f64; ROLE_COUNT] {
    let need = staff_needs(v);
    let mut cov = [1.0f64; ROLE_COUNT];
    for i in 0..ROLE_COUNT {
        if need[i] > 0 {
            cov[i] = (v.staff[i] as f64 / need[i] as f64).min(1.0);
        }
    }
    cov
}

pub fn efficiency(gs: &GameState, v: &Venue, cov: &[f64; ROLE_COUNT]) -> f64 {
    let mut e = (0.9 + 0.1 * cov[Role::Manager.index()]) * (0.85 + 0.3 * v.morale / 100.0);
    if gs.has("staff_academy") {
        e *= 1.05;
    }
    e
}

pub fn marketing_factor(gs: &GameState, v: &Venue) -> f64 {
    let wealth = catalog::city(&v.city).map(|c| c.wealth).unwrap_or(1.0);
    let mut m = 0.35 * (1.0 + v.marketing_month / (1_500.0 * wealth)).ln();
    if gs.has("local_ads") {
        m *= 1.25;
    }
    1.0 + m
}

pub fn season_factor(gs: &GameState, tourism: f64) -> f64 {
    let m = gs.month_of_year() as f64;
    1.0 + tourism * 0.6 * (std::f64::consts::TAU * (m - 6.0) / 12.0).cos()
}

/// Expected guests per day before noise; also used for the "forecast" in the UI.
pub fn day_potential(gs: &GameState, v: &Venue) -> f64 {
    let Some(city) = catalog::city(&v.city) else {
        return 0.0;
    };
    let c = floor_counts(v);
    let base = city.population * 0.0045;
    let mut tourists = base * city.tourism * 2.0 * season_factor(gs, city.tourism);
    if gs.has("tourism_partners") {
        tourists *= 1.3;
    }
    let locals = base * (1.0 - city.tourism);
    let market = (locals + tourists) * gs.economy * WEEKDAY_TRAFFIC[gs.weekday() as usize];

    let fmt = catalog::format(v.format);
    let mut a = c.appeal.max(0.5).powf(0.78)
        * (0.55 + v.satisfaction / 100.0 * 0.9)
        * (0.7 + gs.reputation / 100.0 * 0.6)
        * marketing_factor(gs, v)
        * fmt.traffic_mult.sqrt();
    if gs.has("interior_design") {
        a *= 1.1;
    }
    if gs.has("regional_brand") {
        let others = gs.venues.iter().filter(|o| o.id != v.id && o.construction_days == 0).count();
        a *= 1.0 + (others as f64 * 0.04).min(0.3);
    }
    let competitors = city.competition * 25.0 * gs.city_pressure(&v.city);
    let own_rivals: f64 = gs
        .venues
        .iter()
        .filter(|o| o.id != v.id && o.city == v.city && o.construction_days == 0)
        .map(|o| floor_counts(o).appeal * 0.6)
        .sum();
    let share = a / (a + competitors + own_rivals);
    let mut p = market * share * (1.0 + v.buzz);
    if gs.has("loyalty_club") {
        p *= 1.12;
    }
    if v.renovation_days > 0 {
        p *= 0.5;
    }
    p.max(0.0)
}

pub fn closed_reason(v: &Venue) -> Option<String> {
    if v.construction_days > 0 {
        return Some(format!("Under construction: {} days left", v.construction_days));
    }
    if v.suspended_days > 0 {
        return Some(format!("License suspended by the regulator: {} days", v.suspended_days));
    }
    let c = floor_counts(v);
    if c.cages == 0 {
        return Some("No cashier cage: build one to open".into());
    }
    if v.staff[Role::Cashier.index()] == 0 {
        return Some("No cashiers on staff".into());
    }
    if v.staff[Role::Security.index()] == 0 {
        return Some("No security officers: the regulator forbids opening".into());
    }
    if c.gaming_seats == 0 {
        return Some("No gaming equipment on the floor".into());
    }
    None
}

struct GroupSeat {
    idx: usize,
    seats: f64,
    weight: f64,
}

fn allocate(demand: f64, group: &[GroupSeat], occupied: &mut [f64]) -> f64 {
    let total_w: f64 = group.iter().map(|g| g.weight).sum();
    if total_w <= 0.0 || demand <= 0.0 {
        return demand.max(0.0);
    }
    let mut left = 0.0;
    for g in group {
        let want = demand * g.weight / total_w;
        let take = want.min(g.seats);
        occupied[g.idx] += take;
        left += want - take;
    }
    // Second pass: spill-over fills whatever is still free.
    let spare: f64 = group.iter().map(|g| g.seats - occupied[g.idx]).sum();
    if left > 0.0 && spare > 0.0 {
        let fill = left.min(spare);
        for g in group {
            let free = g.seats - occupied[g.idx];
            occupied[g.idx] += fill * free / spare;
        }
        left -= fill;
    }
    left.max(0.0)
}

pub fn run_hour(gs: &mut GameState) {
    let hour = gs.hour;
    let weekend = matches!(gs.weekday(), 4..=6);
    let n = gs.venues.len();
    for vi in 0..n {
        let reason = closed_reason(&gs.venues[vi]);
        let fmt = gs.venues[vi].format;
        if reason.is_some() || !is_open_hour(fmt, hour) {
            let v = &mut gs.venues[vi];
            v.closed_reason = reason;
            v.guests_now = 0.0;
            v.occupancy_now = 0.0;
            continue;
        }
        gs.venues[vi].closed_reason = None;
        let noise = 1.0 + gs.rng.normal(0.08);
        let jitter: [f64; 3] = [gs.rng.normal(1.0), gs.rng.normal(1.0), gs.rng.normal(1.0)];

        let v = &gs.venues[vi];
        let Some(city) = catalog::city(&v.city) else { continue };
        let c = floor_counts(v);
        let cov = coverage(v);
        let eff = efficiency(gs, v, &cov);
        let arrivals = (v.day_potential * curve_share(fmt, hour) * noise).max(0.0);
        let mut stay = 1.6;
        if c.bars > 0 {
            stay += 0.3;
        }
        if c.restaurants > 0 {
            stay += 0.5;
        }
        stay += (c.lounges as f64 * 0.15).min(0.45);
        let on_floor = arrivals * stay;
        let gaming_demand = on_floor * 0.82;
        let reno = if v.renovation_days > 0 { 0.5 } else { 1.0 };
        let tables_open = v.tables_closed_days == 0;
        let dealer_cov = cov[Role::Dealer.index()];

        let mut machines = Vec::new();
        let mut tables = Vec::new();
        let mut vip = Vec::new();
        for (i, p) in v.items.iter().enumerate() {
            let Some(d) = p.def() else { continue };
            match d.revenue {
                Revenue::Machine if p.broken_days == 0 => machines.push(GroupSeat {
                    idx: i,
                    seats: d.seats as f64 * reno,
                    weight: d.seats as f64 * d.appeal,
                }),
                Revenue::LiveTable | Revenue::Rake if tables_open => tables.push(GroupSeat {
                    idx: i,
                    seats: d.seats as f64 * dealer_cov * reno,
                    weight: d.seats as f64 * d.appeal,
                }),
                Revenue::HighLimit if tables_open => vip.push(GroupSeat {
                    idx: i,
                    seats: d.seats as f64 * dealer_cov,
                    weight: d.seats as f64 * d.appeal,
                }),
                _ => {}
            }
        }
        let mut occ = vec![0.0f64; v.items.len()];
        let vip_share = if vip.is_empty() { 0.0 } else { 0.025 * city.wealth };
        let left_vip = allocate(gaming_demand * vip_share, &vip, &mut occ);
        let left_m = allocate(gaming_demand * (1.0 - vip_share) * 0.66, &machines, &mut occ);
        let left_t = allocate(
            gaming_demand * (1.0 - vip_share) * 0.34 + left_vip,
            &tables,
            &mut occ,
        );
        // Half of those who found no seat in their preferred group try the other.
        let left_m2 = allocate(left_t * 0.5, &machines, &mut occ);
        let left_t2 = allocate(left_m * 0.5, &tables, &mut occ);
        let unserved = left_m * 0.5 + left_t * 0.5 + left_m2 + left_t2;

        // Cage throughput caps how much play the floor can actually process.
        let cage_cap = c.cages as f64 * 70.0 * cov[Role::Cashier.index()];
        let throughput = if arrivals > cage_cap && arrivals > 0.0 {
            (cage_cap / arrivals).sqrt()
        } else {
            1.0
        };

        let spend = city.wealth;
        let mut slot_ggr = 0.0;
        let mut table_ggr = 0.0;
        let mut rake = 0.0;
        let mut vip_ggr = 0.0;
        let mut seats_total = 0.0;
        let mut seats_used = 0.0;
        let slot_boost = if gs.has("slot_analytics") { 1.08 } else { 1.0 }
            * (0.8 + 0.2 * cov[Role::Attendant.index()]);
        for (i, p) in v.items.iter().enumerate() {
            let Some(d) = p.def() else { continue };
            let sh = occ[i];
            match d.revenue {
                Revenue::Machine => {
                    seats_total += d.seats as f64;
                    seats_used += sh;
                    slot_ggr += sh * d.per_seat_hour * spend * d.hold * slot_boost;
                }
                Revenue::LiveTable => {
                    seats_total += d.seats as f64;
                    seats_used += sh;
                    table_ggr += sh * d.per_seat_hour * spend * d.hold;
                }
                Revenue::Rake => {
                    seats_total += d.seats as f64;
                    seats_used += sh;
                    rake += sh * d.per_seat_hour * spend.sqrt();
                }
                Revenue::HighLimit => {
                    seats_total += d.seats as f64;
                    seats_used += sh;
                    vip_ggr += sh * d.per_seat_hour * spend * d.hold;
                }
                _ => {}
            }
        }
        // Hourly luck. Sigma is scaled so the daily spread matches the item volatility.
        let vol = |id: &str| catalog::item(id).map(|d| d.volatility).unwrap_or(0.1) * 3.5;
        slot_ggr *= 1.0 + jitter[0] * vol("slot_video").min(1.0) * 0.5;
        table_ggr *= 1.0 + jitter[1] * vol("table_blackjack");
        vip_ggr *= 1.0 + jitter[2] * vol("vip_salon");
        let rg = if gs.has("responsible_gaming") { 0.98 } else { 1.0 };
        let k = eff * throughput * rg;
        slot_ggr *= k;
        table_ggr *= k;
        rake *= k;
        vip_ggr *= k;

        // Food, beverage and shows.
        let hosp_cov = cov[Role::Hospitality.index()];
        let mut fnb = 0.0;
        let mut cogs = 0.0;
        let mut show = 0.0;
        let mix = if gs.has("mixology") { 1.2 } else { 1.0 };
        if let Some(bar) = catalog::item("bar") {
            let served = (arrivals * 0.35).min(c.bars as f64 * bar.seats as f64 * hosp_cov);
            let r = served * bar.per_seat_hour * spend * mix;
            fnb += r;
            cogs += r * (1.0 - bar.hold);
        }
        if let Some(rest) = catalog::item("restaurant")
            && (12..=23).contains(&hour)
        {
            let served = (arrivals * 0.22).min(c.restaurants as f64 * rest.seats as f64 * hosp_cov);
            let r = served * rest.per_seat_hour * spend;
            fnb += r;
            cogs += r * (1.0 - rest.hold);
        }
        if let Some(stage) = catalog::item("stage")
            && weekend
            && (20..=23).contains(&hour)
        {
            let tickets = (arrivals * 1.2).min(c.stages as f64 * stage.seats as f64);
            let r = tickets * stage.per_seat_hour * spend;
            show += r;
            cogs += r * (1.0 - stage.hold);
        }
        let gaming = slot_ggr + table_ggr + rake + vip_ggr;
        let comps = (gaming.max(0.0)) * v.comp_rate;
        let cash_in = gaming + fnb + show - comps - cogs;

        let v = &mut gs.venues[vi];
        let t = &mut v.today;
        t.slot_ggr += slot_ggr;
        t.table_ggr += table_ggr;
        t.poker_rake += rake;
        t.vip_ggr += vip_ggr;
        t.fnb_revenue += fnb;
        t.show_revenue += show;
        t.comps += comps;
        t.cogs += cogs;
        t.visitors += arrivals;
        t.turned_away += if on_floor > 0.0 {
            arrivals * (unserved / gaming_demand.max(1e-9)).min(1.0)
        } else {
            0.0
        };
        v.guests_now = on_floor;
        v.occupancy_now = if seats_total > 0.0 {
            seats_used / seats_total
        } else {
            0.0
        };
        gs.add_cash(cash_in);
    }
}

/// Book a cost to a venue's daily ledger and pay it.
fn pay(gs: &mut GameState, vi: usize, amount: f64, line: fn(&mut Ledger) -> &mut f64) {
    *line(&mut gs.venues[vi].today) += amount;
    gs.add_cash(-amount);
}

pub fn monthly_wages(gs: &GameState, v: &Venue) -> f64 {
    let wage_index = catalog::city(&v.city).map(|c| c.wage_index).unwrap_or(1.0);
    let mut total = 0.0;
    for (i, n) in v.staff.iter().enumerate() {
        total += *n as f64 * catalog::ROLES[i].salary_month;
    }
    let mut w = total * wage_index * v.wage_level;
    if gs.has("shift_planning") {
        w *= 0.92;
    }
    w
}

pub fn start_of_day(gs: &mut GameState) {
    let pm = gs.has("preventive_maintenance");
    let n = gs.venues.len();
    let mut broke_total: Vec<(String, u32)> = Vec::new();
    for vi in 0..n {
        let tech_cov = coverage(&gs.venues[vi])[Role::Technician.index()];
        let mut broke = 0;
        let mut repair_cost = 0.0;
        let operating = gs.venues[vi].construction_days == 0;
        for ii in 0..gs.venues[vi].items.len() {
            let (is_machine, price) = match gs.venues[vi].items[ii].def() {
                Some(d) => (d.revenue == Revenue::Machine, d.price),
                None => (false, 0.0),
            };
            if !is_machine || !operating {
                continue;
            }
            if gs.venues[vi].items[ii].broken_days > 0 {
                let fixes = tech_cov >= 0.5 || gs.rng.chance(0.5);
                if fixes {
                    gs.venues[vi].items[ii].broken_days -= 1;
                }
                continue;
            }
            let p = 0.009 * if pm { 0.55 } else { 1.0 } * (1.6 - 0.6 * tech_cov);
            if gs.rng.chance(p) {
                let days = 1 + gs.rng.below(2);
                gs.venues[vi].items[ii].broken_days = days;
                broke += 1;
                repair_cost += price * 0.02;
            }
        }
        if repair_cost > 0.0 {
            pay(gs, vi, repair_cost, |l| &mut l.repairs);
        }
        if broke > 0 {
            broke_total.push((gs.venues[vi].name.clone(), broke));
        }
        let pot = day_potential(gs, &gs.venues[vi]);
        let noise = 1.0 + gs.rng.normal(0.06);
        let v = &mut gs.venues[vi];
        v.day_potential = (pot * noise).max(0.0);
        v.closed_reason = closed_reason(v);
    }
    for (name, k) in broke_total {
        gs.log(
            "warn",
            "Machine breakdown",
            format!("{k} machine(s) went down at {name}. Technicians are on it."),
        );
    }
}

pub fn end_of_day(gs: &mut GameState) {
    let n = gs.venues.len();
    let energy = if gs.has("energy_saving") { 0.75 } else { 1.0 };
    let central = if gs.has("central_ops") && n > 1 { 0.9 } else { 1.0 };
    let mut company = DayStat {
        day: gs.day,
        ..Default::default()
    };
    for vi in 0..n {
        let Some(city) = catalog::city(&gs.venues[vi].city) else { continue };
        let fmt = catalog::format(gs.venues[vi].format);
        let v = &gs.venues[vi];
        let c = floor_counts(v);
        let cov = coverage(v);
        let wages = monthly_wages(gs, v) / 30.0;
        let rent = fmt.area_m2 * city.rent_m2_month / 30.0;
        let kw: f64 = v.items.iter().filter_map(|p| p.def()).map(|d| d.power_kw).sum();
        let open = if v.is_operating() && v.closed_reason.is_none() {
            hours_open(v.format) as f64
        } else {
            2.0
        };
        let utilities = (fmt.area_m2 * 0.08 + kw * open * 0.16) * energy * central;
        let upkeep: f64 =
            v.items.iter().filter_map(|p| p.def()).map(|d| d.upkeep_day).sum::<f64>() * central;
        let marketing = v.marketing_month / 30.0;
        let overhead = fmt.overhead_month / 30.0 * central;
        pay(gs, vi, wages, |l| &mut l.wages);
        pay(gs, vi, wages * city.payroll_tax, |l| &mut l.payroll_tax);
        pay(gs, vi, rent, |l| &mut l.rent);
        pay(gs, vi, utilities, |l| &mut l.utilities);
        pay(gs, vi, upkeep, |l| &mut l.upkeep);
        pay(gs, vi, marketing, |l| &mut l.marketing);
        pay(gs, vi, overhead, |l| &mut l.overhead);

        let operating = gs.venues[vi].construction_days == 0;
        if operating {
            events::venue_daily_risks(gs, vi);
        }

        // Guest satisfaction, staff morale, compliance and security drift toward targets.
        let v = &gs.venues[vi];
        let visitors = v.today.visitors.max(1.0);
        let crowd = (v.today.turned_away / visitors).min(1.0);
        let peak = v.day_potential * 0.084 * 2.0;
        let rest_need = (peak / 40.0).max(1.0);
        let rest_short = ((rest_need - c.restrooms as f64) / rest_need).clamp(0.0, 1.0);
        let service =
            (cov[Role::Attendant.index()] + cov[Role::Hospitality.index()] + cov[Role::Cashier.index()]) / 3.0;
        let mut amen = 0.0;
        if c.bars > 0 {
            amen += 4.0;
        }
        if c.restaurants > 0 {
            amen += 8.0;
        }
        if c.stages > 0 {
            amen += 5.0;
        }
        amen += (c.lounges as f64 * 3.0).min(9.0);
        let decor = (c.decor_appeal * 1.5).min(10.0);
        let comps = (v.comp_rate * 150.0).min(15.0);
        let broken = if c.machines > 0 {
            c.broken as f64 / c.machines as f64
        } else {
            0.0
        };
        let target_sat = (35.0 - crowd * 40.0 - rest_short * 25.0 + service * 20.0 + amen + decor
            + comps
            - broken * 30.0
            + (v.morale - 50.0) / 5.0)
            .clamp(0.0, 100.0);

        let staffed: Vec<f64> = staff_needs(v)
            .iter()
            .enumerate()
            .filter(|(_, n)| **n > 0)
            .map(|(i, _)| cov[i])
            .collect();
        let avg_cov = if staffed.is_empty() {
            1.0
        } else {
            staffed.iter().sum::<f64>() / staffed.len() as f64
        };
        let mut target_morale = 55.0 + (v.wage_level - 1.0) * 100.0
            + cov[Role::Manager.index()] * 10.0
            - (1.0 - avg_cov) * 30.0
            + (v.satisfaction - 50.0) / 10.0;
        if gs.has("staff_academy") {
            target_morale += 8.0;
        }
        let mut target_comp = 20.0 + 50.0 * cov[Role::Compliance.index()];
        if gs.has("aml_basics") {
            target_comp += 10.0;
        }
        if gs.has("aml_system") {
            target_comp += 12.0;
        }
        if gs.has("responsible_gaming") {
            target_comp += 8.0;
        }
        if c.surveillance > 0 {
            target_comp += 5.0;
        }
        let target_sec = 25.0
            + 55.0 * cov[Role::Security.index()]
            + (c.security_posts as f64 * 4.0).min(12.0)
            + if c.surveillance > 0 { 15.0 } else { 0.0 };
        let morale_rate = if gs.has("staff_academy") { 0.15 } else { 0.1 };

        let v = &mut gs.venues[vi];
        if v.is_operating() {
            v.satisfaction += (target_sat - v.satisfaction) * 0.15;
        }
        v.morale += (target_morale.clamp(0.0, 100.0) - v.morale) * morale_rate;
        v.compliance += (target_comp.clamp(0.0, 100.0) - v.compliance) * 0.1;
        v.security += (target_sec.clamp(0.0, 100.0) - v.security) * 0.2;

        for d in [
            &mut v.construction_days,
            &mut v.renovation_days,
            &mut v.suspended_days,
            &mut v.tables_closed_days,
        ] {
            *d = d.saturating_sub(1);
        }
        if v.buzz_days > 0 {
            v.buzz_days -= 1;
            if v.buzz_days == 0 {
                v.buzz = 0.0;
            }
        }

        let t = std::mem::take(&mut v.today);
        let revenue = t.ggr() + t.non_gaming_gross();
        let costs = t.comps + t.cogs + t.wages + t.payroll_tax + t.rent + t.utilities + t.upkeep
            + t.repairs
            + t.marketing
            + t.overhead
            + t.fraud
            + t.fines
            + t.other;
        let seats = c.gaming_seats as f64 * hours_open(v.format) as f64;
        let occupancy = if seats > 0.0 {
            (t.visitors * 1.8 * 0.82 / seats).min(1.0)
        } else {
            0.0
        };
        let stat = DayStat {
            day: gs.day,
            visitors: t.visitors,
            ggr: t.ggr(),
            revenue,
            costs,
            occupancy,
            cash: 0.0,
        };
        company.visitors += stat.visitors;
        company.ggr += stat.ggr;
        company.revenue += stat.revenue;
        company.costs += stat.costs;
        v.days.push_back(stat);
        while v.days.len() > 60 {
            v.days.pop_front();
        }
        v.month.add(&t);
    }
    let was_built: Vec<String> = gs
        .venues
        .iter()
        .filter(|v| v.construction_days == 0 && v.closed_reason.as_deref().is_some_and(|r| r.starts_with("Under construction")))
        .map(|v| v.name.clone())
        .collect();
    for name in was_built {
        gs.log("good", "Branch completed", format!("Construction of {name} is finished. Equip the floor and hire staff to open."));
    }

    // Overdraft interest on negative cash.
    let cash = gs.cash();
    if cash < 0.0 {
        let interest = -cash * 0.0005;
        gs.month_interest += interest;
        gs.add_cash(-interest);
    }

    // Company reputation follows guest satisfaction across the chain.
    let ops: Vec<&Venue> = gs.venues.iter().filter(|v| v.construction_days == 0).collect();
    if !ops.is_empty() {
        let avg_sat = ops.iter().map(|v| v.satisfaction).sum::<f64>() / ops.len() as f64;
        let mut target = avg_sat * 0.75 + 5.0 * (ops.len() as f64).min(5.0) + gs.license as f64 * 3.0;
        if gs.has("responsible_gaming") {
            target += 3.0;
        }
        gs.reputation += (target.clamp(0.0, 100.0) - gs.reputation) * 0.012;
    }

    company.cash = gs.cash();
    gs.company_days.push_back(company);
    while gs.company_days.len() > 90 {
        gs.company_days.pop_front();
    }

    advance_research(gs);
    events::company_daily(gs);
    goals::check(gs);
    finance::check_insolvency(gs);
}

fn advance_research(gs: &mut GameState) {
    let Some(active) = gs.research_active.as_mut() else { return };
    active.days_left = active.days_left.saturating_sub(1);
    if active.days_left > 0 {
        return;
    }
    let id = active.id.clone();
    gs.research_active = None;
    gs.research_done.push(id.clone());
    let name = catalog::research(&id).map(|r| r.name).unwrap_or("Project");
    gs.log("good", "Development complete", format!("{name} is now active across the company."));
}

/// Advance the world by one hour.
pub fn step(gs: &mut GameState) {
    if gs.game_over {
        return;
    }
    if gs.hour == 0 {
        start_of_day(gs);
    }
    run_hour(gs);
    gs.hour += 1;
    if gs.hour >= HOURS_PER_DAY {
        gs.hour = 0;
        end_of_day(gs);
        gs.day += 1;
        if gs.day % crate::model::DAYS_PER_MONTH == 0 {
            finance::close_month(gs);
        }
    }
}
