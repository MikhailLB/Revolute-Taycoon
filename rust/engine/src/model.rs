use std::collections::VecDeque;

use serde::{Deserialize, Serialize};

use crate::catalog::{self, ItemDef, ROLE_COUNT};
use crate::rng::Rng;
use crate::secure::Guarded;

pub const HOURS_PER_DAY: u32 = 24;
pub const DAYS_PER_MONTH: u32 = 30;
pub const MONTHS_PER_YEAR: u32 = 12;
pub const START_YEAR: u32 = 2027;

#[derive(Clone, Serialize, Deserialize)]
pub struct Placed {
    pub id: u32,
    pub item: String,
    pub x: u8,
    pub y: u8,
    /// Days left until a broken machine is back in service.
    pub broken_days: u32,
    pub book_value: f64,
}

impl Placed {
    pub fn def(&self) -> Option<&'static ItemDef> {
        catalog::item(&self.item)
    }
}

/// Monthly accumulators for one venue. Every line of the P&L is booked here
/// as it happens and folded into a [`MonthReport`] when the books close.
#[derive(Clone, Default, Serialize, Deserialize)]
pub struct Ledger {
    pub slot_ggr: f64,
    pub table_ggr: f64,
    pub poker_rake: f64,
    pub vip_ggr: f64,
    pub fnb_revenue: f64,
    pub show_revenue: f64,
    pub comps: f64,
    pub cogs: f64,
    pub wages: f64,
    pub payroll_tax: f64,
    pub rent: f64,
    pub utilities: f64,
    pub upkeep: f64,
    pub repairs: f64,
    pub marketing: f64,
    pub overhead: f64,
    pub fraud: f64,
    pub fines: f64,
    pub other: f64,
    pub visitors: f64,
    pub turned_away: f64,
}

impl Ledger {
    pub fn ggr(&self) -> f64 {
        self.slot_ggr + self.table_ggr + self.poker_rake + self.vip_ggr
    }
    pub fn non_gaming_gross(&self) -> f64 {
        self.fnb_revenue + self.show_revenue
    }
    pub fn add(&mut self, o: &Ledger) {
        self.slot_ggr += o.slot_ggr;
        self.table_ggr += o.table_ggr;
        self.poker_rake += o.poker_rake;
        self.vip_ggr += o.vip_ggr;
        self.fnb_revenue += o.fnb_revenue;
        self.show_revenue += o.show_revenue;
        self.comps += o.comps;
        self.cogs += o.cogs;
        self.wages += o.wages;
        self.payroll_tax += o.payroll_tax;
        self.rent += o.rent;
        self.utilities += o.utilities;
        self.upkeep += o.upkeep;
        self.repairs += o.repairs;
        self.marketing += o.marketing;
        self.overhead += o.overhead;
        self.fraud += o.fraud;
        self.fines += o.fines;
        self.other += o.other;
        self.visitors += o.visitors;
        self.turned_away += o.turned_away;
    }
}

#[derive(Clone, Default, Serialize, Deserialize)]
pub struct DayStat {
    pub day: u32,
    pub visitors: f64,
    pub ggr: f64,
    pub revenue: f64,
    pub costs: f64,
    pub occupancy: f64,
    pub cash: f64,
}

#[derive(Clone, Serialize, Deserialize)]
pub struct Venue {
    pub id: u32,
    pub name: String,
    pub city: String,
    pub format: u8,
    pub items: Vec<Placed>,
    pub next_item_id: u32,
    pub staff: [u32; ROLE_COUNT],
    /// Pay relative to the city market rate (0.8 – 1.5).
    pub wage_level: f64,
    pub marketing_month: f64,
    /// Share of GGR returned to guests as complimentaries.
    pub comp_rate: f64,
    /// Days until a newly built branch opens.
    pub construction_days: u32,
    /// Days of renovation after a format upgrade (floor runs at half capacity).
    pub renovation_days: u32,
    pub suspended_days: u32,
    pub satisfaction: f64,
    pub morale: f64,
    pub compliance: f64,
    pub security: f64,
    pub buzz: f64,
    pub buzz_days: u32,
    pub tables_closed_days: u32,
    /// Daily visitor potential computed at the start of each day.
    pub day_potential: f64,
    /// Live figures for the floor view.
    pub guests_now: f64,
    pub occupancy_now: f64,
    pub month: Ledger,
    pub today: Ledger,
    pub days: VecDeque<DayStat>,
    pub fitout_value: f64,
    pub closed_reason: Option<String>,
}

impl Venue {
    pub fn is_operating(&self) -> bool {
        self.construction_days == 0 && self.suspended_days == 0 && self.closed_reason.is_none()
    }

    pub fn grid(&self) -> (u8, u8) {
        let f = catalog::format(self.format);
        (f.grid_w, f.grid_h)
    }

    pub fn count_where(&self, pred: impl Fn(&ItemDef) -> bool) -> u32 {
        self.items
            .iter()
            .filter_map(|p| p.def())
            .filter(|d| pred(d))
            .count() as u32
    }

    pub fn count_item(&self, id: &str) -> u32 {
        self.items.iter().filter(|p| p.item == id).count() as u32
    }

    pub fn occupied(&self, x: u8, y: u8, w: u8, h: u8, ignore: Option<u32>) -> bool {
        self.items.iter().any(|p| {
            if Some(p.id) == ignore {
                return false;
            }
            let Some(d) = p.def() else { return false };
            x < p.x + d.w && p.x < x + w && y < p.y + d.h && p.y < y + h
        })
    }
}

#[derive(Clone, Serialize, Deserialize)]
pub struct ActiveResearch {
    pub id: String,
    pub days_left: u32,
}

#[derive(Clone, Serialize, Deserialize)]
pub struct Loan {
    pub id: u32,
    pub offer: String,
    pub name: String,
    pub principal: f64,
    pub balance: f64,
    pub annual_rate: f64,
    pub months_left: u32,
    pub payment: f64,
}

#[derive(Clone, Default, Serialize, Deserialize)]
pub struct MonthReport {
    pub month_index: u32,
    pub label: String,
    pub ggr: f64,
    pub slot_ggr: f64,
    pub table_ggr: f64,
    pub poker_rake: f64,
    pub vip_ggr: f64,
    pub gaming_tax: f64,
    pub comps: f64,
    pub net_gaming: f64,
    pub non_gaming_gross: f64,
    pub vat: f64,
    pub non_gaming_net: f64,
    pub net_revenue: f64,
    pub cogs: f64,
    pub wages: f64,
    pub payroll_tax: f64,
    pub rent: f64,
    pub utilities: f64,
    pub upkeep: f64,
    pub repairs: f64,
    pub marketing: f64,
    pub overhead: f64,
    pub license_fees: f64,
    pub insurance: f64,
    pub fraud: f64,
    pub fines: f64,
    pub other: f64,
    pub opex: f64,
    pub ebitda: f64,
    pub depreciation: f64,
    pub interest: f64,
    pub ebt: f64,
    pub income_tax: f64,
    pub net_income: f64,
    pub visitors: f64,
    pub cash_end: f64,
    pub venues: Vec<VenueMonth>,
}

#[derive(Clone, Default, Serialize, Deserialize)]
pub struct VenueMonth {
    pub venue_id: u32,
    pub name: String,
    pub ggr: f64,
    pub gaming_tax: f64,
    pub net_revenue: f64,
    pub opex: f64,
    pub ebitda: f64,
    pub visitors: f64,
}

#[derive(Clone, Serialize, Deserialize)]
pub struct LogEntry {
    pub day: u32,
    pub hour: u32,
    pub tone: String,
    pub title: String,
    pub text: String,
}

#[derive(Clone, Serialize, Deserialize)]
pub struct DecisionOption {
    pub label: String,
    pub detail: String,
}

#[derive(Clone, Serialize, Deserialize)]
pub struct Decision {
    pub kind: String,
    pub venue_id: u32,
    pub title: String,
    pub text: String,
    pub amount: f64,
    pub options: Vec<DecisionOption>,
}

#[derive(Clone, Default, Serialize, Deserialize)]
pub struct Lifetime {
    pub ggr: f64,
    pub visitors: f64,
    pub taxes_paid: f64,
    pub wages_paid: f64,
    pub peak_net_worth: f64,
}

#[derive(Clone, Serialize, Deserialize)]
pub struct GameState {
    pub version: u32,
    pub company: String,
    pub rng: Rng,
    pub day: u32,
    pub hour: u32,
    pub cash: Guarded,
    pub reputation: f64,
    pub license: u8,
    pub research_done: Vec<String>,
    pub research_active: Option<ActiveResearch>,
    pub loans: Vec<Loan>,
    pub next_loan_id: u32,
    pub missed_payments: u32,
    pub venues: Vec<Venue>,
    pub next_venue_id: u32,
    pub loss_carryforward: f64,
    pub reports: VecDeque<MonthReport>,
    pub company_days: VecDeque<DayStat>,
    pub log: VecDeque<LogEntry>,
    pub decision: Option<Decision>,
    pub economy: f64,
    pub economy_trend: f64,
    pub city_pressure: Vec<(String, f64)>,
    pub goals_done: Vec<String>,
    pub insolvent_days: u32,
    pub game_over: bool,
    pub lifetime: Lifetime,
    /// Corporate-level costs of the running month (license fees, insurance, interest).
    pub month_license_fees: f64,
    pub month_interest: f64,
    pub month_other: f64,
    pub month_fines: f64,
}

impl GameState {
    pub fn has(&self, research: &str) -> bool {
        self.research_done.iter().any(|r| r == research)
    }

    pub fn month_index(&self) -> u32 {
        self.day / DAYS_PER_MONTH
    }

    pub fn weekday(&self) -> u32 {
        self.day % 7
    }

    pub fn month_of_year(&self) -> u32 {
        self.month_index() % MONTHS_PER_YEAR
    }

    pub fn cash(&self) -> f64 {
        self.cash.get()
    }

    pub fn add_cash(&mut self, delta: f64) {
        let v = self.cash.get() + delta;
        self.cash.set(v);
    }

    pub fn venue_mut(&mut self, id: u32) -> Option<&mut Venue> {
        self.venues.iter_mut().find(|v| v.id == id)
    }

    pub fn venue(&self, id: u32) -> Option<&Venue> {
        self.venues.iter().find(|v| v.id == id)
    }

    pub fn city_pressure(&self, city: &str) -> f64 {
        self.city_pressure
            .iter()
            .find(|(c, _)| c == city)
            .map(|(_, p)| *p)
            .unwrap_or(1.0)
    }

    pub fn set_city_pressure(&mut self, city: &str, value: f64) {
        if let Some(e) = self.city_pressure.iter_mut().find(|(c, _)| c == city) {
            e.1 = value;
        } else {
            self.city_pressure.push((city.to_owned(), value));
        }
    }

    pub fn log(&mut self, tone: &str, title: impl Into<String>, text: impl Into<String>) {
        self.log.push_front(LogEntry {
            day: self.day,
            hour: self.hour,
            tone: tone.to_owned(),
            title: title.into(),
            text: text.into(),
        });
        while self.log.len() > 120 {
            self.log.pop_back();
        }
    }
}

pub const MONTH_NAMES: [&str; 12] = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
];

pub const WEEKDAYS: [&str; 7] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

/// Whole dollars with thousands separators, e.g. `$16,800` / `-$2,100`.
pub fn usd(v: f64) -> String {
    let digits = format!("{:.0}", v.abs());
    let mut out = String::with_capacity(digits.len() + 4);
    for (i, ch) in digits.chars().enumerate() {
        if i > 0 && (digits.len() - i) % 3 == 0 {
            out.push(',');
        }
        out.push(ch);
    }
    if v < -0.5 { format!("-${out}") } else { format!("${out}") }
}

pub fn month_label(month_index: u32) -> String {
    format!(
        "{} {}",
        MONTH_NAMES[(month_index % 12) as usize],
        START_YEAR + month_index / 12
    )
}
