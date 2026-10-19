import Foundation

// Mirrors of the JSON produced by the Rust engine (snake_case keys are
// converted automatically). The engine owns the state; these are read-only.

struct Catalog: Decodable {
    let items: [ItemDef]
    let formats: [FormatDef]
    let licenses: [LicenseDef]
    let cities: [CityDef]
    let roles: [RoleDef]
    let research: [ResearchDef]
    let loans: [LoanOffer]

    func item(_ id: String) -> ItemDef? { items.first { $0.id == id } }
    func city(_ id: String) -> CityDef? { cities.first { $0.id == id } }
    func role(_ id: String) -> RoleDef? { roles.first { $0.id == id } }
    func research(_ id: String) -> ResearchDef? { research.first { $0.id == id } }
    func loan(_ id: String) -> LoanOffer? { loans.first { $0.id == id } }
}

struct ItemDef: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let category: String
    let revenue: String
    let w: Int
    let h: Int
    let price: Double
    let upkeepDay: Double
    let powerKw: Double
    let seats: Int
    let perSeatHour: Double
    let hold: Double
    let appeal: Double
    let volatility: Double
    let requiresResearch: String?
    let minFormat: Int
}

struct FormatDef: Decodable, Identifiable, Hashable {
    var id: Int { level }
    let level: Int
    let name: String
    let description: String
    let gridW: Int
    let gridH: Int
    let areaM2: Double
    let upgradeCost: Double
    let buildCost: Double
    let buildDays: Int
    let minLicense: Int
    let minReputation: Double
    let trafficMult: Double
    let overheadMonth: Double
    let earlyAccessLocked: Bool
}

struct LicenseDef: Decodable, Identifiable {
    var id: Int { tier }
    let tier: Int
    let name: String
    let description: String
    let price: Double
    let monthlyFee: Double
    let minReputation: Double
    let minCompliance: Double
    let requiresResearch: String?
    let maxSlots: Int
    let maxTables: Int
    let earlyAccessLocked: Bool
}

struct CityDef: Decodable, Identifiable {
    let id: String
    let name: String
    let description: String
    let population: Double
    let wealth: Double
    let tourism: Double
    let competition: Double
    let rentM2Month: Double
    let wageIndex: Double
    let taxSchedule: Int
    let vat: Double
    let payrollTax: Double
    let minLicense: Int
    let mapX: Double
    let mapY: Double
    let earlyAccessLocked: Bool
}

struct RoleDef: Decodable, Identifiable {
    let role: String
    let id: String
    let name: String
    let description: String
    let salaryMonth: Double
    let hireCost: Double
}

struct ResearchDef: Decodable, Identifiable {
    let id: String
    let name: String
    let description: String
    let branch: String
    let tier: Int
    let cost: Double
    let days: Int
    let requires: [String]
    let earlyAccessLocked: Bool
}

struct LoanOffer: Decodable, Identifiable {
    let id: String
    let name: String
    let months: Int
    let baseRate: Double
    let ebitdaMultiple: Double
    let assetLtv: Double
}

// MARK: - Snapshot

struct Snapshot: Decodable {
    let clock: Clock
    let company: Company
    let venues: [VenueView]
    let research: [ResearchView]
    let researchActive: String?
    let licenses: [LicenseView]
    let cities: [CityView]
    let loans: [Loan]
    let loanOffers: [LoanOfferView]
    let reports: [MonthReport]
    let companyDays: [DayStat]
    let log: [LogEntry]
    let decision: Decision?
    let goals: [GoalView]

    func venue(_ id: Int) -> VenueView? { venues.first { $0.id == id } }
}

struct Clock: Decodable {
    let day: Int
    let hour: Int
    let weekday: String
    let dayOfMonth: Int
    let monthLabel: String
    let year: Int
    let daysToClose: Int
}

struct Company: Decodable {
    let name: String
    let cash: Double
    let reputation: Double
    let license: Int
    let licenseName: String
    let rating: String
    let netWorth: Double
    let assets: Double
    let debt: Double
    let ebitdaAnnual: Double
    let lossCarryforward: Double
    let economy: Double
    let insolventDays: Int
    let missedPayments: Int
    let maxVenues: Int
    let taxesPaid: Double
    let lifetimeGgr: Double
    let lifetimeVisitors: Double
    let gameOver: Bool
    let integrity: Bool
}

struct Placed: Decodable, Identifiable, Hashable {
    let id: Int
    let item: String
    let x: Int
    let y: Int
    let brokenDays: Int
    let bookValue: Double
}

struct StaffLine: Decodable, Identifiable {
    var id: String { role }
    let role: String
    let have: Int
    let need: Int
    let coverage: Double
    let monthlyCost: Double
}

struct ItemOption: Decodable {
    let id: String
    let blocked: String?
}

struct Ledger: Decodable {
    let slotGgr: Double
    let tableGgr: Double
    let pokerRake: Double
    let vipGgr: Double
    let fnbRevenue: Double
    let showRevenue: Double
    let comps: Double
    let cogs: Double
    let wages: Double
    let payrollTax: Double
    let rent: Double
    let utilities: Double
    let upkeep: Double
    let repairs: Double
    let marketing: Double
    let overhead: Double
    let fraud: Double
    let fines: Double
    let other: Double
    let visitors: Double
    let turnedAway: Double

    var ggr: Double { slotGgr + tableGgr + pokerRake + vipGgr }
    var nonGaming: Double { fnbRevenue + showRevenue }
    var costs: Double {
        comps + cogs + wages + payrollTax + rent + utilities + upkeep + repairs + marketing + overhead + fraud + fines + other
    }
}

struct DayStat: Decodable, Identifiable {
    var id: Int { day }
    let day: Int
    let visitors: Double
    let ggr: Double
    let revenue: Double
    let costs: Double
    let occupancy: Double
    let cash: Double
}

struct VenueView: Decodable, Identifiable {
    let id: Int
    let name: String
    let city: String
    let cityName: String
    let format: Int
    let formatName: String
    let gridW: Int
    let gridH: Int
    let areaM2: Double
    let items: [Placed]
    let staff: [StaffLine]
    let wageLevel: Double
    let marketingMonth: Double
    let compRate: Double
    let constructionDays: Int
    let renovationDays: Int
    let suspendedDays: Int
    let tablesClosedDays: Int
    let satisfaction: Double
    let morale: Double
    let compliance: Double
    let security: Double
    let buzz: Double
    let openNow: Bool
    let openFrom: Int
    let openTo: Int
    let closedReason: String?
    let guestsNow: Double
    let occupancyNow: Double
    let forecastVisitors: Double
    let gamingSeats: Int
    let machines: Int
    let tables: Int
    let broken: Int
    let appeal: Double
    let monthlyPayroll: Double
    let monthlyRent: Double
    let month: Ledger
    let today: Ledger
    let days: [DayStat]
    let itemOptions: [ItemOption]
    let upgradeBlocked: String?
    let nextFormat: FormatDef?

    func blocked(_ item: String) -> String? {
        itemOptions.first { $0.id == item }?.blocked
    }

    var staffTotal: Int { staff.reduce(0) { $0 + $1.have } }
    var staffNeed: Int { staff.reduce(0) { $0 + $1.need } }
}

struct ResearchView: Decodable, Identifiable {
    let id: String
    let state: String
    let daysLeft: Int
}

struct LicenseView: Decodable, Identifiable {
    var id: Int { tier }
    let tier: Int
    let state: String
    let blocked: String?
}

struct CityView: Decodable, Identifiable {
    let id: String
    let venues: Int
    let pressure: Double
    let branchCost: Double
    let branchDays: Int
    let blocked: String?
}

struct Loan: Decodable, Identifiable {
    let id: Int
    let offer: String
    let name: String
    let principal: Double
    let balance: Double
    let annualRate: Double
    let monthsLeft: Int
    let payment: Double
}

struct LoanOfferView: Decodable, Identifiable {
    let id: String
    let rate: Double
    let limit: Double
}

struct VenueMonth: Decodable, Identifiable {
    var id: Int { venueId }
    let venueId: Int
    let name: String
    let ggr: Double
    let gamingTax: Double
    let netRevenue: Double
    let opex: Double
    let ebitda: Double
    let visitors: Double
}

struct MonthReport: Decodable, Identifiable {
    var id: Int { monthIndex }
    let monthIndex: Int
    let label: String
    let ggr: Double
    let slotGgr: Double
    let tableGgr: Double
    let pokerRake: Double
    let vipGgr: Double
    let gamingTax: Double
    let comps: Double
    let netGaming: Double
    let nonGamingGross: Double
    let vat: Double
    let nonGamingNet: Double
    let netRevenue: Double
    let cogs: Double
    let wages: Double
    let payrollTax: Double
    let rent: Double
    let utilities: Double
    let upkeep: Double
    let repairs: Double
    let marketing: Double
    let overhead: Double
    let licenseFees: Double
    let insurance: Double
    let fraud: Double
    let fines: Double
    let other: Double
    let opex: Double
    let ebitda: Double
    let depreciation: Double
    let interest: Double
    let ebt: Double
    let incomeTax: Double
    let netIncome: Double
    let visitors: Double
    let cashEnd: Double
    let venues: [VenueMonth]
}

struct LogEntry: Decodable, Identifiable, Hashable {
    var id: String { "\(day)-\(hour)-\(title)-\(text.hashValue)" }
    let day: Int
    let hour: Int
    let tone: String
    let title: String
    let text: String
}

struct DecisionOption: Decodable, Hashable {
    let label: String
    let detail: String
}

struct Decision: Decodable {
    let kind: String
    let venueId: Int
    let title: String
    let text: String
    let amount: Double
    let options: [DecisionOption]
}

struct GoalView: Decodable, Identifiable {
    let id: String
    let title: String
    let description: String
    let rewardCash: Double
    let rewardRep: Double
    let progress: Double
    let target: Double
    let done: Bool
}

struct ActionResult: Decodable {
    let ok: Bool
    let message: String
}
