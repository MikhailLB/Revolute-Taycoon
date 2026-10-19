//! Milestones that guide the player from a back-street club to a casino chain.

use serde::Serialize;

use crate::finance;
use crate::model::GameState;

pub struct GoalDef {
    pub id: &'static str,
    pub title: &'static str,
    pub description: &'static str,
    pub reward_cash: f64,
    pub reward_rep: f64,
    check: fn(&GameState) -> (f64, f64),
}

fn slots_max(gs: &GameState) -> f64 {
    gs.venues
        .iter()
        .map(|v| v.count_where(|d| d.category == crate::catalog::ItemCategory::Slot))
        .max()
        .unwrap_or(0) as f64
}

fn best_month(gs: &GameState, f: fn(&crate::model::MonthReport) -> f64) -> f64 {
    gs.reports.iter().map(f).fold(f64::MIN, f64::max).max(0.0)
}

pub const GOALS: &[GoalDef] = &[
    GoalDef { id: "floor_15", title: "Fill the floor", description: "Have 15 machines in one venue.", reward_cash: 5_000.0, reward_rep: 1.0,
        check: |gs| (slots_max(gs), 15.0) },
    GoalDef { id: "first_research", title: "Invest in know-how", description: "Complete any development project.", reward_cash: 3_000.0, reward_rep: 1.0,
        check: |gs| (gs.research_done.len() as f64, 1.0) },
    GoalDef { id: "profit_month", title: "In the black", description: "Close a month with positive net income.", reward_cash: 0.0, reward_rep: 2.0,
        check: |gs| (if gs.reports.iter().any(|r| r.net_income > 0.0) { 1.0 } else { 0.0 }, 1.0) },
    GoalDef { id: "rep_30", title: "Good name", description: "Reach 30 reputation.", reward_cash: 5_000.0, reward_rep: 0.0,
        check: |gs| (gs.reputation, 30.0) },
    GoalDef { id: "regional", title: "Go regional", description: "Obtain the Regional License.", reward_cash: 15_000.0, reward_rep: 2.0,
        check: |gs| (gs.license as f64, 1.0) },
    GoalDef { id: "hall", title: "Gaming Hall", description: "Upgrade a venue to a Gaming Hall.", reward_cash: 20_000.0, reward_rep: 3.0,
        check: |gs| (gs.venues.iter().map(|v| v.format).max().unwrap_or(0) as f64, 1.0) },
    GoalDef { id: "branch_2", title: "Second branch", description: "Operate two venues.", reward_cash: 25_000.0, reward_rep: 3.0,
        check: |gs| (gs.venues.len() as f64, 2.0) },
    GoalDef { id: "ggr_500k", title: "Half a million", description: "Reach $500,000 GGR in a single month.", reward_cash: 40_000.0, reward_rep: 2.0,
        check: |gs| (best_month(gs, |r| r.ggr), 500_000.0) },
    GoalDef { id: "national", title: "National player", description: "Obtain the National Casino License.", reward_cash: 100_000.0, reward_rep: 4.0,
        check: |gs| (gs.license as f64, 2.0) },
    GoalDef { id: "casino", title: "A real casino", description: "Upgrade a venue to a Casino.", reward_cash: 150_000.0, reward_rep: 5.0,
        check: |gs| (gs.venues.iter().map(|v| v.format).max().unwrap_or(0) as f64, 2.0) },
    GoalDef { id: "branch_4", title: "Casino chain", description: "Operate four venues.", reward_cash: 200_000.0, reward_rep: 4.0,
        check: |gs| (gs.venues.len() as f64, 4.0) },
    GoalDef { id: "ebitda_1m", title: "Million-dollar month", description: "Reach $1,000,000 EBITDA in a single month.", reward_cash: 250_000.0, reward_rep: 5.0,
        check: |gs| (best_month(gs, |r| r.ebitda), 1_000_000.0) },
    GoalDef { id: "nw_50m", title: "Tycoon", description: "Reach a net worth of $50,000,000.", reward_cash: 0.0, reward_rep: 10.0,
        check: |gs| (finance::net_worth(gs).max(0.0), 50_000_000.0) },
];

#[derive(Serialize)]
pub struct GoalView {
    pub id: &'static str,
    pub title: &'static str,
    pub description: &'static str,
    pub reward_cash: f64,
    pub reward_rep: f64,
    pub progress: f64,
    pub target: f64,
    pub done: bool,
}

pub fn views(gs: &GameState) -> Vec<GoalView> {
    GOALS
        .iter()
        .map(|g| {
            let (p, t) = (g.check)(gs);
            GoalView {
                id: g.id,
                title: g.title,
                description: g.description,
                reward_cash: g.reward_cash,
                reward_rep: g.reward_rep,
                progress: p.min(t),
                target: t,
                done: gs.goals_done.iter().any(|d| d == g.id),
            }
        })
        .collect()
}

pub fn check(gs: &mut GameState) {
    for g in GOALS {
        if gs.goals_done.iter().any(|d| d == g.id) {
            continue;
        }
        let (p, t) = (g.check)(gs);
        if p >= t {
            gs.goals_done.push(g.id.to_owned());
            gs.add_cash(g.reward_cash);
            gs.reputation = (gs.reputation + g.reward_rep).min(100.0);
            let mut reward = Vec::new();
            if g.reward_cash > 0.0 {
                reward.push(crate::model::usd(g.reward_cash));
            }
            if g.reward_rep > 0.0 {
                reward.push(format!("+{:.0} reputation", g.reward_rep));
            }
            gs.log("goal", format!("Milestone: {}", g.title), format!("Reward: {}", reward.join(", ")));
        }
    }
}
