//! Random events: regulator inspections, incidents, fraud, word of mouth,
//! the macro economy, competitors, and decisions the player has to make.

use crate::catalog::{self, Role};
use crate::model::{Decision, DecisionOption, GameState, usd};
use crate::sim;

fn opt(label: &str, detail: impl Into<String>) -> DecisionOption {
    DecisionOption {
        label: label.to_owned(),
        detail: detail.into(),
    }
}

pub fn venue_daily_risks(gs: &mut GameState, vi: usize) {
    if gs.venues[vi].closed_reason.is_some() && gs.venues[vi].suspended_days == 0 {
        return;
    }
    let name = gs.venues[vi].name.clone();
    let city_id = gs.venues[vi].city.clone();
    let c = sim::floor_counts(&gs.venues[vi]);
    let security = gs.venues[vi].security;
    let compliance = gs.venues[vi].compliance;
    let table_day = gs.venues[vi].today.table_ggr.max(0.0) + gs.venues[vi].today.vip_ggr.max(0.0);

    // Regulator inspection.
    let strict = if city_id == "metropolis" { 1.0 / 30.0 } else { 1.0 / 45.0 };
    if gs.rng.chance(strict) {
        let month_ggr = gs.venues[vi].month.ggr() + gs.venues[vi].today.ggr();
        if compliance >= 75.0 {
            gs.reputation = (gs.reputation + 1.0).min(100.0);
            gs.log("good", "Clean inspection", format!("The gaming regulator inspected {name} and found no issues."));
        } else if compliance >= 50.0 {
            gs.log("info", "Inspection: remarks", format!("Minor remarks at {name}. Keep compliance above 75 to avoid fines."));
        } else {
            let fine = (month_ggr.max(5_000.0) * 0.03 * (50.0 - compliance) / 50.0 * 4.0).max(2_500.0);
            gs.venues[vi].today.fines += fine;
            gs.add_cash(-fine);
            gs.reputation = (gs.reputation - 3.0).max(0.0);
            if compliance < 30.0 {
                gs.venues[vi].suspended_days = 3;
                gs.log("bad", "License suspended", format!("Serious AML breaches at {name}: fine {} and a 3-day suspension. Hire AML officers.", usd(fine)));
            } else {
                gs.log("bad", "Regulator fine", format!("Compliance breaches at {name}: fine {}. Hire AML officers and invest in compliance.", usd(fine)));
            }
        }
    }

    // Floor incidents.
    if gs.rng.chance(0.06 * (1.0 - security / 100.0)) {
        gs.venues[vi].satisfaction = (gs.venues[vi].satisfaction - 5.0).max(0.0);
        gs.reputation = (gs.reputation - 0.5).max(0.0);
        gs.log("warn", "Incident on the floor", format!("A fight broke out at {name}. More security would have prevented it."));
    }

    // Cheating rings at the tables.
    if c.live_tables + c.vip > 0 {
        let surv = if c.surveillance > 0 { 0.3 } else { 1.0 };
        if gs.rng.chance(0.035 * (1.0 - security / 100.0) * surv) {
            let loss = (table_day.max(800.0)) * gs.rng.range(1.0, 3.0);
            gs.venues[vi].today.fraud += loss;
            gs.add_cash(-loss);
            gs.log("bad", "Cheating ring", format!("A team of advantage cheats took {} from the tables at {name}.", usd(loss)));
        }
    }

    // Word of mouth.
    if gs.venues[vi].buzz_days == 0 && gs.rng.chance(0.012) {
        let sat = gs.venues[vi].satisfaction;
        if sat > 68.0 {
            gs.venues[vi].buzz = 0.2;
            gs.venues[vi].buzz_days = 7;
            gs.log("good", "Viral review", format!("Guests are raving about {name} online. +20% traffic this week."));
        } else if sat < 40.0 {
            gs.venues[vi].buzz = -0.2;
            gs.venues[vi].buzz_days = 7;
            gs.log("bad", "Bad reviews", format!("Angry reviews of {name} are spreading. -20% traffic this week."));
        }
    }

    if gs.decision.is_some() {
        return;
    }
    let v = &gs.venues[vi];
    let morale = v.morale;
    let fmt = v.format;
    let vid = v.id;
    let managers = v.staff[Role::Manager.index()];
    let wealth = catalog::city(&v.city).map(|c| c.wealth).unwrap_or(1.0);
    let has_high_limit = v.count_item("table_baccarat") + v.count_item("vip_salon") > 0;

    if morale < 35.0 && v.staff[Role::Dealer.index()] > 0 && gs.rng.chance(0.08) {
        gs.decision = Some(Decision {
            kind: "strike".into(),
            venue_id: vid,
            title: "Dealers threaten to strike".into(),
            text: format!("Staff at {name} are exhausted and underpaid. The dealers demand a raise or they walk out."),
            amount: 0.0,
            options: vec![
                opt("Give a 10% raise", "Wage level +10%, morale recovers"),
                opt("Refuse", "Tables close for 3 days, morale and reputation drop"),
            ],
        });
    } else if has_high_limit && gs.rng.chance(0.03) {
        let stake = (gs.rng.range(40_000.0, 260_000.0) * wealth * (1.0 + fmt as f64)).round();
        gs.decision = Some(Decision {
            kind: "high_roller".into(),
            venue_id: vid,
            title: "A high roller is in town".into(),
            text: format!("A wealthy guest wants to play baccarat at {name} with a {} bankroll. The house edge favours you, but one night can go either way. Low compliance risks an AML fine.", usd(stake)),
            amount: stake,
            options: vec![
                opt("Host the guest", "High variance: expected profit around 12% of the bankroll"),
                opt("Politely decline", "No risk, no reward"),
            ],
        });
    } else if fmt >= 1 && gs.rng.chance(0.01) {
        let fee = 15_000.0 * (fmt as f64 + 1.0);
        gs.decision = Some(Decision {
            kind: "celebrity".into(),
            venue_id: vid,
            title: "Celebrity appearance".into(),
            text: format!("An agency offers a weekend appearance by a famous singer at {name} for {}.", usd(fee)),
            amount: fee,
            options: vec![
                opt("Book the star", "+35% traffic for 10 days, +reputation"),
                opt("Not this time", "Nothing happens"),
            ],
        });
    } else if gs.rng.chance(0.007) {
        let cost = 9_000.0 * (fmt as f64 + 1.0);
        gs.decision = Some(Decision {
            kind: "council".into(),
            venue_id: vid,
            title: "Noise complaints".into(),
            text: format!("Neighbours of {name} complained to the city council about late-night noise. Soundproofing costs {}.", usd(cost)),
            amount: cost,
            options: vec![
                opt("Install soundproofing", "Problem solved"),
                opt("Ignore", "-3 reputation, -5 compliance at the venue"),
            ],
        });
    } else if managers > 0 && gs.rng.chance(0.008) {
        let bonus = catalog::role_def(Role::Manager).salary_month * 3.0;
        gs.decision = Some(Decision {
            kind: "poaching".into(),
            venue_id: vid,
            title: "Competitor poaching".into(),
            text: format!("A rival casino offered your best shift manager at {name} a better job. A retention bonus costs {}.", usd(bonus)),
            amount: bonus,
            options: vec![
                opt("Pay the bonus", "The manager stays, morale +5"),
                opt("Let them go", "Lose one shift manager"),
            ],
        });
    }
}

pub fn company_daily(gs: &mut GameState) {
    // Macro economy: mean-reverting random walk.
    let shock = gs.rng.normal(0.0025);
    gs.economy_trend = (gs.economy_trend * 0.97 + shock).clamp(-0.01, 0.01);
    let before = gs.economy;
    gs.economy = (gs.economy + gs.economy_trend + (1.0 - gs.economy) * 0.01).clamp(0.78, 1.22);
    if before >= 0.9 && gs.economy < 0.9 {
        gs.log("bad", "Recession", "Consumer spending is falling. Expect fewer guests until the economy recovers.");
    } else if before <= 1.1 && gs.economy > 1.1 {
        gs.log("good", "Economic boom", "Consumers are spending freely. Traffic is up across all cities.");
    }

    let cities: Vec<&catalog::CityDef> = catalog::CITIES.iter().filter(|c| !c.early_access_locked).collect();
    if !cities.is_empty() {
        if gs.rng.chance(0.005) {
            let c = cities[gs.rng.below(cities.len() as u32) as usize];
            let p = (gs.city_pressure(c.id) * 1.15).min(1.8);
            gs.set_city_pressure(c.id, p);
            gs.log("warn", "New competitor", format!("A rival opened a new gaming venue in {}. Competition is rising.", c.name));
        } else if gs.rng.chance(0.004) {
            let c = cities[gs.rng.below(cities.len() as u32) as usize];
            let p = (gs.city_pressure(c.id) * 0.9).max(0.7);
            gs.set_city_pressure(c.id, p);
            gs.log("good", "Competitor closed", format!("A rival venue in {} shut its doors. More guests for you.", c.name));
        }
        if gs.rng.chance(0.006) {
            let c = cities[gs.rng.below(cities.len() as u32) as usize];
            let mut touched = false;
            for v in gs.venues.iter_mut().filter(|v| v.city == c.id) {
                v.buzz = v.buzz.max(0.3);
                v.buzz_days = v.buzz_days.max(5);
                touched = true;
            }
            if touched {
                gs.log("good", "City festival", format!("A festival in {} brings crowds of visitors for 5 days.", c.name));
            }
        }
    }
}

pub fn resolve(gs: &mut GameState, choice: u32) -> Result<String, String> {
    let Some(d) = gs.decision.take() else {
        return Err("Nothing to decide".into());
    };
    let Some(vi) = gs.venues.iter().position(|v| v.id == d.venue_id) else {
        return Ok("The venue no longer exists".into());
    };
    let name = gs.venues[vi].name.clone();
    let msg = match (d.kind.as_str(), choice) {
        ("strike", 0) => {
            let v = &mut gs.venues[vi];
            v.wage_level = (v.wage_level + 0.1).min(1.5);
            v.morale = (v.morale + 20.0).min(100.0);
            format!("Raise granted at {name}. The staff are back to work.")
        }
        ("strike", _) => {
            let v = &mut gs.venues[vi];
            v.tables_closed_days = 3;
            v.morale = (v.morale - 10.0).max(0.0);
            gs.reputation = (gs.reputation - 1.0).max(0.0);
            format!("Dealers at {name} walked out. Tables are closed for 3 days.")
        }
        ("high_roller", 0) => {
            let swing = d.amount * (0.12 + gs.rng.normal(0.45));
            let result = swing.clamp(-d.amount * 0.9, d.amount * 0.9);
            gs.venues[vi].today.vip_ggr += result;
            gs.add_cash(result);
            let mut text = if result >= 0.0 {
                format!("The high roller lost {} at {name}.", usd(result))
            } else {
                format!("Bad night: the high roller won {} at {name}.", usd(-result))
            };
            if gs.venues[vi].compliance < 60.0 && gs.rng.chance(0.3) {
                let fine = d.amount * 0.1;
                gs.venues[vi].today.fines += fine;
                gs.add_cash(-fine);
                text.push_str(&format!(" The regulator fined you {} for weak source-of-funds checks.", usd(fine)));
            }
            text
        }
        ("high_roller", _) => "You declined the high roller.".into(),
        ("celebrity", 0) => {
            gs.venues[vi].today.marketing += d.amount;
            gs.add_cash(-d.amount);
            let v = &mut gs.venues[vi];
            v.buzz = v.buzz.max(0.35);
            v.buzz_days = v.buzz_days.max(10);
            gs.reputation = (gs.reputation + 1.0).min(100.0);
            format!("The show at {name} is sold out. Traffic +35% for 10 days.")
        }
        ("celebrity", _) => "You passed on the celebrity booking.".into(),
        ("council", 0) => {
            gs.venues[vi].today.other += d.amount;
            gs.add_cash(-d.amount);
            format!("Soundproofing installed at {name}. The neighbours are happy.")
        }
        ("council", _) => {
            gs.reputation = (gs.reputation - 3.0).max(0.0);
            let v = &mut gs.venues[vi];
            v.compliance = (v.compliance - 5.0).max(0.0);
            "The council noted your refusal.".into()
        }
        ("poaching", 0) => {
            gs.venues[vi].today.wages += d.amount;
            gs.add_cash(-d.amount);
            let v = &mut gs.venues[vi];
            v.morale = (v.morale + 5.0).min(100.0);
            format!("Your shift manager at {name} stays.")
        }
        ("poaching", _) => {
            let v = &mut gs.venues[vi];
            let i = Role::Manager.index();
            v.staff[i] = v.staff[i].saturating_sub(1);
            format!("A shift manager left {name} for a competitor.")
        }
        _ => "Done.".into(),
    };
    gs.log("info", d.title, msg.clone());
    Ok(msg)
}
