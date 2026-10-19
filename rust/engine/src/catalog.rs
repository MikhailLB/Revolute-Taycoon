//! Static game data: floor objects, venue formats, cities, licenses, staff
//! roles and the development tree. Numbers follow how land-based casinos are
//! actually run: slot hold of 6–12 %, table hold on drop of 12–25 %, gaming
//! taxes levied progressively on gross gaming revenue, 3+ shifts per post.

use serde::Serialize;

#[derive(Serialize, Clone, Copy, PartialEq, Eq, Debug)]
#[serde(rename_all = "snake_case")]
pub enum ItemCategory {
    Slot,
    Table,
    Hospitality,
    Service,
    Security,
    Decor,
}

#[derive(Serialize, Clone, Copy, PartialEq, Eq, Debug)]
#[serde(rename_all = "snake_case")]
pub enum Revenue {
    /// Electronic gaming: seat-hours × coin-in per hour × hold.
    Machine,
    /// Live table: seat-hours × drop per seat-hour × hold; needs a dealer.
    LiveTable,
    /// Poker: guests play each other, the house takes a rake.
    Rake,
    /// High-limit salon: few guests, very large and volatile drop.
    HighLimit,
    /// Food & beverage: spend per served guest, cost of goods applies.
    FoodBeverage,
    /// Show tickets, mostly on weekends.
    Show,
    None,
}

#[derive(Serialize, Clone, Debug)]
pub struct ItemDef {
    pub id: &'static str,
    pub name: &'static str,
    pub description: &'static str,
    pub category: ItemCategory,
    pub revenue: Revenue,
    pub w: u8,
    pub h: u8,
    pub price: f64,
    /// Maintenance and supplier service fee, per day.
    pub upkeep_day: f64,
    pub power_kw: f64,
    /// Guest seats (gaming) or guests served per hour (hospitality/service).
    pub seats: u32,
    /// Coin-in or drop per occupied seat-hour, rake per seat-hour, or spend per guest.
    pub per_seat_hour: f64,
    /// Hold fraction for gaming, gross margin for hospitality.
    pub hold: f64,
    pub appeal: f64,
    /// Daily sigma of the result as a fraction of the expectation.
    pub volatility: f64,
    pub requires_research: Option<&'static str>,
    pub min_format: u8,
}

#[allow(clippy::too_many_arguments)]
const fn it(
    id: &'static str,
    name: &'static str,
    description: &'static str,
    category: ItemCategory,
    revenue: Revenue,
    size: (u8, u8),
    price: f64,
    upkeep_day: f64,
    power_kw: f64,
    seats: u32,
    per_seat_hour: f64,
    hold: f64,
    appeal: f64,
    volatility: f64,
    requires_research: Option<&'static str>,
    min_format: u8,
) -> ItemDef {
    ItemDef {
        id,
        name,
        description,
        category,
        revenue,
        w: size.0,
        h: size.1,
        price,
        upkeep_day,
        power_kw,
        seats,
        per_seat_hour,
        hold,
        appeal,
        volatility,
        requires_research,
        min_format,
    }
}

use ItemCategory as C;
use Revenue as R;

pub const ITEMS: &[ItemDef] = &[
    it("slot_classic", "Classic Slot", "Simple reel machine. Cheap and reliable, low win per unit.",
        C::Slot, R::Machine, (1, 1), 6_000.0, 6.0, 0.35, 1, 330.0, 0.09, 1.0, 0.10, None, 0),
    it("slot_video", "Video Slot", "Modern cabinet with a big screen. Higher engagement and coin-in.",
        C::Slot, R::Machine, (1, 1), 14_000.0, 12.0, 0.5, 1, 500.0, 0.085, 1.35, 0.12, Some("video_cabinets"), 0),
    it("slot_progressive", "Progressive Bank", "Linked machines sharing a jackpot. A crowd magnet, but jackpots hit the cage.",
        C::Slot, R::Machine, (1, 1), 32_000.0, 24.0, 0.6, 1, 760.0, 0.10, 1.9, 0.35, Some("progressive_link"), 1),
    it("etg_stadium", "Electronic Table", "Four-seat electronic roulette terminal. No dealer needed.",
        C::Slot, R::Machine, (2, 1), 46_000.0, 30.0, 1.2, 4, 400.0, 0.045, 1.4, 0.15, Some("electronic_tables"), 1),
    it("table_blackjack", "Blackjack Table", "Classic six-seat live table. Needs a dealer every shift.",
        C::Table, R::LiveTable, (2, 2), 9_000.0, 4.0, 0.1, 6, 90.0, 0.15, 1.6, 0.30, None, 0),
    it("table_roulette", "Roulette Table", "Eight-seat single-zero wheel. High hold on drop and great to watch.",
        C::Table, R::LiveTable, (2, 2), 16_000.0, 5.0, 0.1, 8, 70.0, 0.22, 1.9, 0.35, Some("roulette_pit"), 0),
    it("table_baccarat", "Baccarat Table", "Favourite of affluent guests. Huge drop, high volatility.",
        C::Table, R::LiveTable, (2, 2), 24_000.0, 6.0, 0.1, 7, 240.0, 0.13, 1.8, 0.55, Some("baccarat"), 1),
    it("table_poker", "Poker Table", "Guests play each other while the house takes a rake. Steady income.",
        C::Table, R::Rake, (3, 2), 12_000.0, 4.0, 0.1, 9, 6.0, 1.0, 1.3, 0.08, Some("poker_room"), 1),
    it("vip_salon", "VIP Salon", "Private high-limit room. Needs dealers and a loyalty program.",
        C::Table, R::HighLimit, (3, 3), 220_000.0, 60.0, 2.0, 6, 2_000.0, 0.12, 3.5, 1.1, Some("vip_program"), 2),
    it("cashier", "Cashier Cage", "Chip exchange and payouts. No venue can open without one. Staffed by cashiers.",
        C::Service, R::None, (2, 1), 8_000.0, 3.0, 0.4, 70, 0.0, 0.0, 0.2, 0.0, None, 0),
    it("bar", "Bar", "Drinks and snacks. Non-gaming revenue that keeps guests longer.",
        C::Hospitality, R::FoodBeverage, (2, 1), 25_000.0, 14.0, 2.5, 30, 13.0, 0.68, 0.9, 0.08, None, 0),
    it("restaurant", "Restaurant", "Full kitchen. High average check, a big boost to satisfaction.",
        C::Hospitality, R::FoodBeverage, (3, 3), 140_000.0, 55.0, 9.0, 60, 38.0, 0.62, 2.2, 0.10, Some("restaurant"), 1),
    it("stage", "Show Stage", "Live music and shows on weekends. Sells tickets and drives traffic.",
        C::Hospitality, R::Show, (3, 2), 95_000.0, 40.0, 6.0, 120, 22.0, 0.55, 2.6, 0.15, Some("show_program"), 1),
    it("lounge", "Lounge", "Soft seating to rest. Raises guest satisfaction.",
        C::Decor, R::None, (2, 2), 14_000.0, 2.0, 0.2, 0, 0.0, 0.0, 1.1, 0.0, None, 0),
    it("restroom", "Restroom", "Required by code: one per 40 guests on the floor.",
        C::Service, R::None, (1, 1), 7_000.0, 4.0, 0.3, 40, 0.0, 0.0, 0.1, 0.0, None, 0),
    it("security_post", "Security Post", "Checkpoint on the floor. Fewer incidents and less fraud.",
        C::Security, R::None, (1, 1), 4_500.0, 1.0, 0.2, 0, 0.0, 0.0, 0.0, 0.0, None, 0),
    it("surveillance", "Surveillance Room", "The eye in the sky watching tables and cages. Cuts fraud losses hard.",
        C::Security, R::None, (2, 2), 65_000.0, 18.0, 3.0, 0, 0.0, 0.0, 0.0, 0.0, Some("eye_in_the_sky"), 0),
    it("plant", "Plant", "A touch of comfort. Slightly raises appeal.",
        C::Decor, R::None, (1, 1), 600.0, 0.2, 0.0, 0, 0.0, 0.0, 0.25, 0.0, None, 0),
    it("fountain", "Fountain", "Eye-catching centrepiece. Noticeably raises appeal.",
        C::Decor, R::None, (2, 2), 38_000.0, 6.0, 1.0, 0, 0.0, 0.0, 2.0, 0.0, Some("interior_design"), 1),
];

pub fn item(id: &str) -> Option<&'static ItemDef> {
    ITEMS.iter().find(|i| i.id == id)
}

#[derive(Serialize, Clone, Debug)]
pub struct FormatDef {
    pub level: u8,
    pub name: &'static str,
    pub description: &'static str,
    pub grid_w: u8,
    pub grid_h: u8,
    pub area_m2: f64,
    pub upgrade_cost: f64,
    pub build_cost: f64,
    pub build_days: u32,
    pub min_license: u8,
    pub min_reputation: f64,
    pub traffic_mult: f64,
    /// General & administrative overhead: admin, accounting, IT, legal, cleaning.
    pub overhead_month: f64,
    pub early_access_locked: bool,
}

pub const FORMATS: &[FormatDef] = &[
    FormatDef { level: 0, name: "Gaming Club", description: "A small street-level room. A couple of tables and a dozen machines.",
        grid_w: 10, grid_h: 8, area_m2: 140.0, upgrade_cost: 0.0, build_cost: 60_000.0, build_days: 10,
        min_license: 0, min_reputation: 0.0, traffic_mult: 1.0, overhead_month: 5_500.0, early_access_locked: false },
    FormatDef { level: 1, name: "Gaming Hall", description: "A dedicated hall with bar and restaurant, poker and electronic tables.",
        grid_w: 16, grid_h: 11, area_m2: 520.0, upgrade_cost: 280_000.0, build_cost: 420_000.0, build_days: 25,
        min_license: 1, min_reputation: 30.0, traffic_mult: 1.8, overhead_month: 18_000.0, early_access_locked: false },
    FormatDef { level: 2, name: "Casino", description: "A full casino: table pit, VIP salon and a show program.",
        grid_w: 22, grid_h: 15, area_m2: 2_400.0, upgrade_cost: 2_600_000.0, build_cost: 3_400_000.0, build_days: 60,
        min_license: 2, min_reputation: 50.0, traffic_mult: 3.4, overhead_month: 85_000.0, early_access_locked: false },
    FormatDef { level: 3, name: "Integrated Resort", description: "Hotel, convention halls and an arena around the casino.",
        grid_w: 30, grid_h: 20, area_m2: 12_000.0, upgrade_cost: 25_000_000.0, build_cost: 40_000_000.0, build_days: 180,
        min_license: 3, min_reputation: 75.0, traffic_mult: 7.0, overhead_month: 400_000.0, early_access_locked: true },
];

pub fn format(level: u8) -> &'static FormatDef {
    &FORMATS[(level as usize).min(FORMATS.len() - 1)]
}

#[derive(Serialize, Clone, Debug)]
pub struct LicenseDef {
    pub tier: u8,
    pub name: &'static str,
    pub description: &'static str,
    pub price: f64,
    pub monthly_fee: f64,
    pub min_reputation: f64,
    pub min_compliance: f64,
    pub requires_research: Option<&'static str>,
    pub max_slots: u32,
    pub max_tables: u32,
    pub early_access_locked: bool,
}

pub const LICENSES: &[LicenseDef] = &[
    LicenseDef { tier: 0, name: "Gaming Club Permit", description: "Municipal permit. Up to 25 machines and 3 tables per venue.",
        price: 0.0, monthly_fee: 1_800.0, min_reputation: 0.0, min_compliance: 0.0, requires_research: None,
        max_slots: 25, max_tables: 3, early_access_locked: false },
    LicenseDef { tier: 1, name: "Regional License", description: "Gaming halls and branches across the region. Up to 150 machines and 20 tables.",
        price: 150_000.0, monthly_fee: 9_000.0, min_reputation: 25.0, min_compliance: 55.0, requires_research: Some("aml_basics"),
        max_slots: 150, max_tables: 20, early_access_locked: false },
    LicenseDef { tier: 2, name: "National Casino License", description: "Full casinos in major cities. No equipment caps.",
        price: 1_400_000.0, monthly_fee: 45_000.0, min_reputation: 45.0, min_compliance: 70.0, requires_research: Some("aml_system"),
        max_slots: 2_000, max_tables: 300, early_access_locked: false },
    LicenseDef { tier: 3, name: "Resort Concession", description: "State concession for an integrated resort.",
        price: 30_000_000.0, monthly_fee: 400_000.0, min_reputation: 75.0, min_compliance: 85.0, requires_research: None,
        max_slots: 10_000, max_tables: 1_000, early_access_locked: true },
];

pub fn license(tier: u8) -> &'static LicenseDef {
    &LICENSES[(tier as usize).min(LICENSES.len() - 1)]
}

#[derive(Serialize, Clone, Debug)]
pub struct CityDef {
    pub id: &'static str,
    pub name: &'static str,
    pub description: &'static str,
    pub population: f64,
    pub wealth: f64,
    pub tourism: f64,
    pub competition: f64,
    pub rent_m2_month: f64,
    pub wage_index: f64,
    /// Index into the gaming tax schedule hidden inside the VM.
    pub tax_schedule: u32,
    pub vat: f64,
    pub payroll_tax: f64,
    pub min_license: u8,
    pub map_x: f64,
    pub map_y: f64,
    pub early_access_locked: bool,
}

pub const CITIES: &[CityDef] = &[
    CityDef { id: "port_river", name: "Port River", description: "Quiet harbour town. Cheap rent and a friendly regulator: the perfect start.",
        population: 320_000.0, wealth: 0.85, tourism: 0.10, competition: 6.0, rent_m2_month: 16.0, wage_index: 0.85,
        tax_schedule: 0, vat: 0.18, payroll_tax: 0.22, min_license: 0, map_x: 0.18, map_y: 0.62, early_access_locked: false },
    CityDef { id: "nova_bay", name: "Nova Bay", description: "Growing business hub. Moderate taxes and guests with money to spend.",
        population: 1_150_000.0, wealth: 1.05, tourism: 0.18, competition: 18.0, rent_m2_month: 28.0, wage_index: 1.0,
        tax_schedule: 1, vat: 0.20, payroll_tax: 0.26, min_license: 1, map_x: 0.40, map_y: 0.40, early_access_locked: false },
    CityDef { id: "gold_coast", name: "Gold Coast", description: "Resort coastline. Packed with tourists in summer, quiet in winter. Fierce competition.",
        population: 640_000.0, wealth: 1.25, tourism: 0.55, competition: 30.0, rent_m2_month: 38.0, wage_index: 1.1,
        tax_schedule: 1, vat: 0.20, payroll_tax: 0.25, min_license: 1, map_x: 0.66, map_y: 0.72, early_access_locked: false },
    CityDef { id: "metropolis", name: "Metropolis", description: "The capital. A huge market with high taxes, high rent and a strict regulator.",
        population: 5_400_000.0, wealth: 1.35, tourism: 0.25, competition: 90.0, rent_m2_month: 62.0, wage_index: 1.35,
        tax_schedule: 2, vat: 0.20, payroll_tax: 0.30, min_license: 2, map_x: 0.62, map_y: 0.24, early_access_locked: false },
    CityDef { id: "lagoon_isle", name: "Lagoon Isle", description: "Offshore gaming zone with low taxes. International expansion.",
        population: 210_000.0, wealth: 1.9, tourism: 0.8, competition: 25.0, rent_m2_month: 45.0, wage_index: 1.2,
        tax_schedule: 0, vat: 0.10, payroll_tax: 0.15, min_license: 3, map_x: 0.88, map_y: 0.52, early_access_locked: true },
];

pub fn city(id: &str) -> Option<&'static CityDef> {
    CITIES.iter().find(|c| c.id == id)
}

#[derive(Serialize, Clone, Copy, PartialEq, Eq, Debug, Hash)]
#[serde(rename_all = "snake_case")]
pub enum Role {
    Dealer,
    Attendant,
    Cashier,
    Security,
    Hospitality,
    Technician,
    Manager,
    Compliance,
}

pub const ROLE_COUNT: usize = 8;

impl Role {
    pub fn index(self) -> usize {
        self as usize
    }
}

#[derive(Serialize, Clone, Debug)]
pub struct RoleDef {
    pub role: Role,
    pub id: &'static str,
    pub name: &'static str,
    pub description: &'static str,
    pub salary_month: f64,
    pub hire_cost: f64,
}

pub const ROLES: &[RoleDef] = &[
    RoleDef { role: Role::Dealer, id: "dealer", name: "Dealer", description: "Runs a live table. A table open 24/7 needs about 4 dealers across shifts.", salary_month: 3_100.0, hire_cost: 500.0 },
    RoleDef { role: Role::Attendant, id: "attendant", name: "Slot Attendant", description: "Looks after the machine floor: about one per 25 machines per shift.", salary_month: 2_500.0, hire_cost: 300.0 },
    RoleDef { role: Role::Cashier, id: "cashier", name: "Cashier", description: "Works the cage. About 3 per cashier cage.", salary_month: 2_400.0, hire_cost: 300.0 },
    RoleDef { role: Role::Security, id: "security", name: "Security Officer", description: "Keeps order. About one per 50 guests per shift, at least one per shift.", salary_month: 2_750.0, hire_cost: 400.0 },
    RoleDef { role: Role::Hospitality, id: "hospitality", name: "Bar & Floor Staff", description: "Serves the bar, restaurant and shows.", salary_month: 2_300.0, hire_cost: 250.0 },
    RoleDef { role: Role::Technician, id: "technician", name: "Technician", description: "Repairs machines. Too few means more downtime.", salary_month: 3_400.0, hire_cost: 600.0 },
    RoleDef { role: Role::Manager, id: "manager", name: "Shift Manager", description: "Lifts the efficiency of all staff. One per shift.", salary_month: 5_600.0, hire_cost: 1_500.0 },
    RoleDef { role: Role::Compliance, id: "compliance", name: "AML Officer", description: "Guest checks, regulator reporting and the responsible gaming policy.", salary_month: 5_000.0, hire_cost: 1_200.0 },
];

pub fn role_def(role: Role) -> &'static RoleDef {
    &ROLES[role.index()]
}

pub fn role_from_id(id: &str) -> Option<Role> {
    ROLES.iter().find(|r| r.id == id).map(|r| r.role)
}

#[derive(Serialize, Clone, Copy, PartialEq, Eq, Debug)]
#[serde(rename_all = "snake_case")]
pub enum Branch {
    Gaming,
    Hospitality,
    Operations,
    Marketing,
    Compliance,
    Corporate,
}

#[derive(Serialize, Clone, Debug)]
pub struct ResearchDef {
    pub id: &'static str,
    pub name: &'static str,
    pub description: &'static str,
    pub branch: Branch,
    pub tier: u8,
    pub cost: f64,
    pub days: u32,
    pub requires: &'static [&'static str],
    pub early_access_locked: bool,
}

const fn rs(
    id: &'static str,
    name: &'static str,
    description: &'static str,
    branch: Branch,
    tier: u8,
    cost: f64,
    days: u32,
    requires: &'static [&'static str],
    early_access_locked: bool,
) -> ResearchDef {
    ResearchDef { id, name, description, branch, tier, cost, days, requires, early_access_locked }
}

use Branch as B;

pub const RESEARCH: &[ResearchDef] = &[
    rs("video_cabinets", "Video Cabinets", "Supplier contract for modern video slots.", B::Gaming, 0, 18_000.0, 5, &[], false),
    rs("roulette_pit", "Roulette Pit", "Train croupiers and buy wheels. Unlocks roulette.", B::Gaming, 0, 22_000.0, 6, &[], false),
    rs("slot_analytics", "Slot Floor Analytics", "Re-arrange machines by traffic data: +8% slot coin-in.", B::Gaming, 1, 45_000.0, 10, &["video_cabinets"], false),
    rs("poker_room", "Poker Room", "Rake model: guests play each other, you take a commission.", B::Gaming, 1, 60_000.0, 12, &["roulette_pit"], false),
    rs("progressive_link", "Progressive Jackpots", "Linked machine banks with a growing jackpot.", B::Gaming, 2, 120_000.0, 15, &["slot_analytics"], false),
    rs("electronic_tables", "Electronic Tables", "Multi-seat terminals that need no dealer.", B::Gaming, 2, 140_000.0, 15, &["slot_analytics"], false),
    rs("baccarat", "Baccarat", "A table for affluent guests. Big drop.", B::Gaming, 2, 160_000.0, 18, &["poker_room"], false),
    rs("vip_program", "VIP Program", "Hosts, guest credit lines and private high-limit salons.", B::Gaming, 3, 650_000.0, 30, &["baccarat", "loyalty_club"], false),
    rs("cashless", "Cashless Floor", "Digital wallets instead of cash and cage.", B::Gaming, 4, 900_000.0, 40, &["vip_program"], true),

    rs("mixology", "Signature Menu", "Signature cocktails: +20% bar average check.", B::Hospitality, 0, 12_000.0, 4, &[], false),
    rs("restaurant", "Restaurant", "Hire a chef and build a kitchen. Unlocks the restaurant.", B::Hospitality, 1, 70_000.0, 12, &["mixology"], false),
    rs("interior_design", "Interior Design", "Themed renovation: +10% appeal, unlocks fountains.", B::Hospitality, 1, 55_000.0, 10, &[], false),
    rs("show_program", "Show Program", "Weekend performers. Unlocks the show stage.", B::Hospitality, 2, 110_000.0, 14, &["restaurant"], false),
    rs("hotel_tower", "Hotel Tower", "Rooms for resort guests.", B::Hospitality, 3, 4_000_000.0, 90, &["show_program"], true),

    rs("shift_planning", "Shift Planning", "Optimised rosters: -8% payroll.", B::Operations, 0, 15_000.0, 5, &[], false),
    rs("preventive_maintenance", "Preventive Maintenance", "Machine breakdowns 45% rarer.", B::Operations, 1, 35_000.0, 8, &["shift_planning"], false),
    rs("staff_academy", "Staff Academy", "Training: +15% staff efficiency, morale recovers faster.", B::Operations, 1, 80_000.0, 14, &["shift_planning"], false),
    rs("eye_in_the_sky", "Eye in the Sky", "Casino surveillance system. Unlocks the surveillance room.", B::Operations, 2, 95_000.0, 12, &["preventive_maintenance"], false),
    rs("energy_saving", "Energy Efficiency", "LED and smart HVAC: -25% utilities.", B::Operations, 2, 70_000.0, 10, &["preventive_maintenance"], false),
    rs("central_ops", "Central Back Office", "Shared back office for all branches: -10% overhead per branch.", B::Operations, 3, 450_000.0, 25, &["staff_academy", "regional_brand"], false),

    rs("local_ads", "Local Advertising", "Billboards and radio: marketing 25% more effective.", B::Marketing, 0, 10_000.0, 4, &[], false),
    rs("loyalty_club", "Loyalty Club", "Player cards and comps: +15% guest retention.", B::Marketing, 1, 50_000.0, 10, &["local_ads"], false),
    rs("regional_brand", "Regional Brand", "One brand for the chain: every branch lifts the others.", B::Marketing, 2, 180_000.0, 20, &["loyalty_club"], false),
    rs("tourism_partners", "Tour Partners", "Deals with travel agencies: +30% tourist traffic.", B::Marketing, 2, 140_000.0, 15, &["loyalty_club"], false),
    rs("influencers", "Media Campaigns", "Online brand promotion.", B::Marketing, 3, 300_000.0, 20, &["regional_brand"], true),

    rs("aml_basics", "AML Basics", "Guest ID checks and large transaction reports. Required for the regional license.", B::Compliance, 0, 20_000.0, 6, &[], false),
    rs("responsible_gaming", "Responsible Gaming", "Self-exclusion, limits and trained staff. +reputation and compliance, -2% GGR.", B::Compliance, 1, 30_000.0, 8, &["aml_basics"], false),
    rs("aml_system", "AML Monitoring System", "Automated transaction monitoring. Required for the casino license.", B::Compliance, 2, 220_000.0, 20, &["responsible_gaming"], false),
    rs("tax_advisory", "Tax Advisory", "Legal optimisation: accelerated depreciation, -15% corporate tax.", B::Compliance, 2, 160_000.0, 15, &["aml_basics"], false),

    rs("bank_relations", "Bank Relations", "Credit rating up one notch, lower rates.", B::Corporate, 0, 25_000.0, 7, &[], false),
    rs("franchise_ops", "Branch Network", "Chain standards: new branches build 30% faster and cheaper.", B::Corporate, 1, 120_000.0, 15, &["bank_relations"], false),
    rs("holding", "Holding Structure", "A management company: shares, investors, IPO.", B::Corporate, 2, 1_500_000.0, 45, &["franchise_ops"], true),
    rs("digital_division", "Digital Division", "Brand entertainment services.", B::Corporate, 3, 3_000_000.0, 60, &["holding"], true),
];

pub fn research(id: &str) -> Option<&'static ResearchDef> {
    RESEARCH.iter().find(|r| r.id == id)
}

#[derive(Serialize, Clone, Debug)]
pub struct LoanOffer {
    pub id: &'static str,
    pub name: &'static str,
    pub months: u32,
    pub base_rate: f64,
    /// Max principal as a multiple of trailing annualised EBITDA.
    pub ebitda_multiple: f64,
    /// Max principal as a fraction of the book value of assets.
    pub asset_ltv: f64,
}

pub const LOANS: &[LoanOffer] = &[
    LoanOffer { id: "short", name: "Working Capital Loan", months: 12, base_rate: 0.14, ebitda_multiple: 0.5, asset_ltv: 0.25 },
    LoanOffer { id: "mid", name: "Investment Loan", months: 36, base_rate: 0.12, ebitda_multiple: 1.5, asset_ltv: 0.45 },
    LoanOffer { id: "long", name: "Project Finance", months: 84, base_rate: 0.105, ebitda_multiple: 3.0, asset_ltv: 0.6 },
];

pub fn loan_offer(id: &str) -> Option<&'static LoanOffer> {
    LOANS.iter().find(|l| l.id == id)
}

#[derive(Serialize)]
pub struct Catalog {
    pub items: &'static [ItemDef],
    pub formats: &'static [FormatDef],
    pub licenses: &'static [LicenseDef],
    pub cities: &'static [CityDef],
    pub roles: &'static [RoleDef],
    pub research: &'static [ResearchDef],
    pub loans: &'static [LoanOffer],
}

pub fn catalog() -> Catalog {
    Catalog {
        items: ITEMS,
        formats: FORMATS,
        licenses: LICENSES,
        cities: CITIES,
        roles: ROLES,
        research: RESEARCH,
        loans: LOANS,
    }
}
