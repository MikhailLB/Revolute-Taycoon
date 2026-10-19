//! Revolute Taycoon engine: casino business simulation, finance and the
//! anti-tamper layer, exposed to Swift through a small C ABI in [`ffi`].

pub mod actions;
pub mod catalog;
pub mod events;
pub mod ffi;
pub mod finance;
pub mod goals;
pub mod model;
pub mod rng;
pub mod save;
pub mod secure;
pub mod sim;
pub mod snapshot;

use std::collections::VecDeque;

use catalog::{ROLE_COUNT, Role};
use model::{GameState, Ledger, Lifetime, Placed, Venue};
use rng::Rng;
use secure::Guarded;

pub const STATE_VERSION: u32 = 1;
pub const STARTING_CASH: f64 = 120_000.0;

pub fn new_venue(id: u32, name: String, city: &str, fitout: f64) -> Venue {
    Venue {
        id,
        name,
        city: city.to_owned(),
        format: 0,
        items: Vec::new(),
        next_item_id: 0,
        staff: [0; ROLE_COUNT],
        wage_level: 1.0,
        marketing_month: 2_000.0,
        comp_rate: 0.03,
        construction_days: 0,
        renovation_days: 0,
        suspended_days: 0,
        satisfaction: 55.0,
        morale: 65.0,
        compliance: 50.0,
        security: 55.0,
        buzz: 0.0,
        buzz_days: 0,
        tables_closed_days: 0,
        day_potential: 0.0,
        guests_now: 0.0,
        occupancy_now: 0.0,
        month: Ledger::default(),
        today: Ledger::default(),
        days: VecDeque::new(),
        fitout_value: fitout,
        closed_reason: None,
    }
}

fn starter_club() -> Venue {
    let mut v = new_venue(0, "Revolute Club".into(), "port_river", 60_000.0);
    let layout: &[(&str, u8, u8)] = &[
        ("cashier", 0, 0),
        ("restroom", 9, 0),
        ("slot_classic", 0, 2),
        ("slot_classic", 1, 2),
        ("slot_classic", 2, 2),
        ("slot_classic", 3, 2),
        ("slot_classic", 4, 2),
        ("slot_classic", 0, 5),
        ("slot_classic", 1, 5),
        ("slot_classic", 2, 5),
        ("slot_classic", 3, 5),
        ("slot_classic", 4, 5),
        ("table_blackjack", 6, 2),
        ("table_blackjack", 6, 5),
        ("bar", 3, 7),
        ("plant", 9, 4),
        ("plant", 9, 7),
        ("plant", 0, 7),
    ];
    for (i, (id, x, y)) in layout.iter().enumerate() {
        let price = catalog::item(id).map(|d| d.price).unwrap_or(0.0);
        v.items.push(Placed {
            id: i as u32,
            item: (*id).to_owned(),
            x: *x,
            y: *y,
            broken_days: 0,
            book_value: price * 0.7,
        });
    }
    v.next_item_id = layout.len() as u32;
    let staff: [(Role, u32); 8] = [
        (Role::Dealer, 5),
        (Role::Attendant, 2),
        (Role::Cashier, 2),
        (Role::Security, 2),
        (Role::Hospitality, 2),
        (Role::Technician, 1),
        (Role::Manager, 1),
        (Role::Compliance, 1),
    ];
    for (r, n) in staff {
        v.staff[r.index()] = n;
    }
    v
}

pub fn new_game(seed: u64) -> GameState {
    let mut gs = GameState {
        version: STATE_VERSION,
        company: "Revolute Holdings".into(),
        rng: Rng::new(seed),
        day: 0,
        hour: 8,
        cash: Guarded::new(STARTING_CASH),
        reputation: 20.0,
        license: 0,
        research_done: Vec::new(),
        research_active: None,
        loans: Vec::new(),
        next_loan_id: 1,
        missed_payments: 0,
        venues: vec![starter_club()],
        next_venue_id: 1,
        loss_carryforward: 0.0,
        reports: VecDeque::new(),
        company_days: VecDeque::new(),
        log: VecDeque::new(),
        decision: None,
        economy: 1.0,
        economy_trend: 0.0,
        city_pressure: Vec::new(),
        goals_done: Vec::new(),
        insolvent_days: 0,
        game_over: false,
        lifetime: Lifetime::default(),
        month_license_fees: 0.0,
        month_interest: 0.0,
        month_other: 0.0,
        month_fines: 0.0,
    };
    let pot = sim::day_potential(&gs, &gs.venues[0]);
    gs.venues[0].day_potential = pot;
    gs.log(
        "info",
        "Welcome to Revolute Taycoon",
        "You run a small gaming club in Port River. Staff it, grow the floor, keep the regulator happy and build a casino empire.",
    );
    gs
}

pub struct Engine {
    pub state: GameState,
    steps_since_probe: u32,
}

pub const FLAG_DECISION: u32 = 1;
pub const FLAG_GAME_OVER: u32 = 2;
pub const FLAG_TAMPERED: u32 = 4;
pub const FLAG_MONTH_CLOSED: u32 = 8;

impl Engine {
    pub fn new(seed: u64) -> Self {
        secure::clear_tamper();
        Engine {
            state: new_game(seed),
            steps_since_probe: 0,
        }
    }

    pub fn from_state(state: GameState) -> Self {
        secure::clear_tamper();
        Engine {
            state,
            steps_since_probe: 0,
        }
    }

    pub fn flags(&self) -> u32 {
        let mut f = 0;
        if self.state.decision.is_some() {
            f |= FLAG_DECISION;
        }
        if self.state.game_over {
            f |= FLAG_GAME_OVER;
        }
        if secure::tampered() {
            f |= FLAG_TAMPERED;
        }
        f
    }

    pub fn step(&mut self, hours: u32) -> u32 {
        let mut extra = 0;
        for _ in 0..hours.min(24 * 31) {
            if secure::tampered() || self.state.game_over || self.state.decision.is_some() {
                break;
            }
            self.steps_since_probe += 1;
            if self.steps_since_probe >= 48 {
                self.steps_since_probe = 0;
                if secure::debugger_attached() {
                    secure::flag_tamper();
                    break;
                }
                if !self.state.cash.verify() {
                    secure::flag_tamper();
                    break;
                }
            }
            let reports = self.state.reports.len();
            let month = self.state.month_index();
            sim::step(&mut self.state);
            if self.state.month_index() != month || self.state.reports.len() != reports {
                extra |= FLAG_MONTH_CLOSED;
            }
        }
        self.flags() | extra
    }

    pub fn save(&self) -> Option<Vec<u8>> {
        if secure::tampered() {
            return None;
        }
        let t = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos() as u64)
            .unwrap_or(0);
        let mut r = self.state.rng.clone();
        save::seal(&self.state, t ^ r.next_u64())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run_strategy(seed: u64, months: u32, verbose: bool) -> GameState {
        let mut e = Engine::new(seed);
        for m in 0..months {
            for _ in 0..30 {
                e.step(24);
                if e.state.decision.is_some() {
                    let _ = events::resolve(&mut e.state, 0);
                }
            }
            if verbose && let Some(r) = e.state.reports.back() {
                println!(
                    "m{m:>2} {} GGR {:>9.0} tax {:>8.0} NR {:>9.0} opex {:>9.0} EBITDA {:>9.0} NI {:>9.0} cash {:>10.0} vis {:>6.0} rep {:>4.1} sat {:>4.1} lic {}",
                    r.label, r.ggr, r.gaming_tax, r.net_revenue, r.opex, r.ebitda, r.net_income, r.cash_end, r.visitors, e.state.reputation, e.state.venues[0].satisfaction, e.state.license
                );
            }
            // Simple bot: research, licenses, expand the floor and keep staffing right.
            let gs = &mut e.state;
            if gs.research_active.is_none() {
                for id in ["aml_basics", "video_cabinets", "local_ads", "roulette_pit", "shift_planning", "responsible_gaming", "mixology", "loyalty_club"] {
                    if actions::apply(gs, actions::Action::Research { id: id.into() }).is_ok() {
                        break;
                    }
                }
            }
            let _ = actions::apply(gs, actions::Action::BuyLicense);
            let vid = gs.venues[0].id;
            let _ = actions::apply(gs, actions::Action::UpgradeFormat { venue: vid });
            for _ in 0..6 {
                let (gw, gh) = gs.venues[0].grid();
                let item = if gs.has("video_cabinets") { "slot_video" } else { "slot_classic" };
                'outer: for y in 0..gh {
                    for x in 0..gw {
                        if !gs.venues[0].occupied(x, y, 1, 1, None) {
                            let _ = actions::apply(gs, actions::Action::Place { venue: vid, item: item.into(), x, y });
                            break 'outer;
                        }
                    }
                }
                if gs.cash() < 60_000.0 {
                    break;
                }
            }
            let _ = actions::apply(gs, actions::Action::AutoStaff { venue: vid });
        }
        e.state
    }

    #[test]
    fn economy_balance_report() {
        let gs = run_strategy(7, 24, true);
        assert!(!gs.game_over);
        assert!(gs.reports.len() >= 23);
    }

    #[test]
    fn save_roundtrip_and_tamper_rejected() {
        let mut e = Engine::new(42);
        e.step(24 * 5);
        let Some(bytes) = e.save() else { panic!("save failed") };
        let loaded = save::open(&bytes);
        assert!(loaded.is_some());
        let mut bad = bytes.clone();
        let mid = bad.len() / 2;
        bad[mid] ^= 0x20;
        assert!(save::open(&bad).is_none());
    }
}
