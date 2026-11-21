# Space Peddlers of SPLORR!!: balance play-test

From play-testing on November 20 and 21, 2026: five scripted players, 100 games each at each of the five difficulty levels (2,500 games), on the real game: the port's code, with every alert, dialog and encounter answered the way a player would answer it. **This port is faithful, so these numbers describe Space Trader 1.2.2's own balance.** Nothing here is a change. What to do about it is the designer's call.

Rerun with:

```bash
odin build playtest -o:speed -out:build/playtest
build/playtest 100                        # every strategy and difficulty (slow: run strategies in parallel)
build/playtest 100 trader all 800         # one strategy, all difficulties, 800-day cap
build/playtest 10 trader 2 600            # one strategy on Normal, plus every alert and dialog it answered
PT_ONLY=5 PT_VERBOSE=1 build/playtest 5 trader 2 300   # trace game 5 step by step
```

## How the players work

- **Docked:** sell everything, repair, refuel, then pick the trip with the best estimated profit among the systems in range. The estimate uses only what a player can see: the local buy prices, plus the target's standard price (as on the Average Prices screen, with special resources only if visited, and the doubled price when the target's status calls for it). They buy up to two goods to fill the hold.
- **Upgrades:** with money left over after a reserve (2,000 credits plus 300 per cargo bay), they buy a better ship (scored on bays, slots and hull), then fill empty weapon, shield and gadget slots (best weapon and shield the system sells, extra cargo bays). They buy an escape pod, then insurance.
- **Encounters:** submit to police inspections when carrying nothing illegal; flee when attacked; ignore traders and ships that flee; plunder pirates who surrender.
- **The moon:** once the credits and cargo are worth 505,000, they head for the system selling the moon (shortest route on full tanks, still trading along the way), buy it, fly to Utopia and retire there. That's a win.
- They stop upgrading once worth reaches 400,000, to save for the moon.
- The actions run the game's own procedures (`SellCargo`, `BuyCargo`, `BuyFuel`, `BuyRepairs`, `BuyItem`, `DoWarp`) on the screen a player would be on. Ships, the escape pod and insurance are bought by pressing the real buttons. Drawing is switched off for speed; the game logic never reads the screen.

| Strategy | Skills (pilot, fighter, trader, engineer) | Differs by |
|---|---|---|
| trader | 5, 5, 5, 5 | the baseline above |
| pure-trader | 6, 2, 10, 2 | everything in trading and piloting |
| fighter | 5, 7, 4, 4 | attacks pirates (and monsters) when its weapons times hull plus shields beat theirs |
| smuggler | 7, 3, 6, 4 | also trades firearms and narcotics; flees police inspections when carrying them |
| no-upgrades | 5, 5, 5, 5 | keeps the Gnat, never buys equipment, a pod or insurance |

## Results

### How often the moon was bought (100 games each)

| Strategy | Beginner | Easy | Normal | Hard | Impossible |
|---|---|---|---|---|---|
| trader | 99% | 93% | 77% | 12% | 0% |
| pure-trader | 97% | 91% | **89%** | **38%** | 0% |
| fighter | 97% | 79% | 51% | 5% | 0% |
| smuggler | 99% | 97% | 79% | 5% | 0% |
| no-upgrades | 100% | 31% | 2% | 0% | 0% |

Median day the moon was bought, where it was: trader 178 / 213 / 251 / 238 on Beginner to Hard; pure-trader 158 / 174 / 211 / 243; smuggler 124 / 154 / 196 / 221; fighter 199 / 238 / 274 / 299.

### Deaths by phase (days < 25, < 50, < 100, < 200, < 400, later)

| Strategy | Normal | Hard | Impossible |
|---|---|---|---|
| trader | 19, 1, 1, 0, 1, 0 | 45, 5, 11, 9, 10, 1 | 72, 7, 4, 5, 3, 0 |
| pure-trader | 4, 0, 1, 2, 0, 0 | 24, 3, 13, 10, 6, 0 | 70, 5, 13, 3, 0, 0 |
| fighter | 28, 2, 1, 4, 5, 2 | 47, 7, 10, 11, 10, 4 | 82, 7, 3, 1, 2, 1 |
| smuggler | 10, 1, 1, 1, 0, 0 | 51, 9, 10, 9, 2, 0 | 85, 9, 1, 1, 0, 0 |
| no-upgrades | 35, 16, 31, 15, 1, 0 | 78, 16, 6, 0, 0, 0 | 91, 7, 2, 0, 0, 0 |

### The trader's worth over time (median of the players still alive, and the share alive)

| Day | Beginner | Easy | Normal | Hard | Impossible |
|---|---|---|---|---|---|
| 25 | 41k (100%) | 45k (96%) | 37k (81%) | 38k (49%) | 23k (24%) |
| 50 | 92k (100%) | 86k (96%) | 76k (80%) | 72k (44%) | 36k (17%) |
| 100 | 265k (99%) | 247k (95%) | 207k (78%) | 124k (33%) | 59k (11%) |
| 200 | 564k (42%) | 558k (58%) | 471k (61%) | 255k (21%) | 66k (3%) |

(The share alive falls at day 200 on the easy levels because the players have bought the moon and retired.)

Escape pods launched per 100 games, trader: 0 / 23 / 140 / 338 / 173 from Beginner to Impossible, every one of them against pirates. Ships at day 100 on Normal: Beetle 42, Termite 27, a few Bumblebees and Fleas.

## Findings by phase

1. **The early game (days 0 to 25) is the deadly phase.** From Normal up, most deaths come in the first 25 days, in the starting Gnat, before the player can afford an escape pod (2,000 credits). All of them come from pirates, when fleeing fails. A run that survives the first month on Normal almost always reaches the moon.
2. **The mid game (days 25 to 200) is a smooth money curve.** Worth roughly doubles every 25 to 50 days early on, then grows by about 2,500 to 3,000 credits a day. Difficulty barely changes how fast a surviving trader earns. It changes how many survive.
3. **There is hardly a late game.** The moon (500,000 credits) is bought around day 180 to 250 by most survivors, and that ends the game. Players who kept going passed 1 to 5 million credits with nothing to spend them on. The top ships (Wasp, Grasshopper) were never reached by these players, so that end of ship balance is untested.
4. **Normal to Hard is a cliff.** The baseline trader goes from 77% to 12%, and the pure trader from 89% to 38%. Beginner and Easy are close to each other; Impossible was never won by any strategy.

## Findings by strategy

5. **Trading skill (and piloting) beats everything else.** The pure trader was the strongest player at every level from Normal up, and the only one that wins often on Hard. Its deaths in the first 25 days on Normal were 4, against 19 for the balanced trader: better prices fill the hold faster and pay for the escape pod sooner, and a higher pilot skill flees more often.
6. **Fighting pirates doesn't pay.** The fighter launched more than twice the trader's escape pods on Normal and won the moon in 51% of games against 77%. Its kills fall as the difficulty rises (14.7 per game on Beginner, 1.4 on Hard). Bounties don't cover the repairs and lost ships. (Its attack test is crude; see below.)
7. **Smuggling is the fastest route on the easy levels** (moon by day 124 on Beginner, against 178), but from Normal up the police become a second enemy: 27 escape pods against police on Normal and 74 on Hard, where the honest players had none.
8. **The escape pod and insurance carry the game.** Without them nobody survives past Easy. With them, a lost ship becomes a Flea and a cheque.
9. **Honest traders are never fined.** Inspections found nothing (about 27,000 "Nothing Found" alerts for the trader). No player was ever arrested, because the smugglers always fled inspections.

## Limits of these players (read the numbers with these in mind)

- **No loans.** Some runs on Hard and Impossible ended "stuck": in a Flea with no credits, no fuel and nothing to sell. A human would borrow from the bank. Those runs are counted as stuck, not dead (up to 14 per 100 games, for the smuggler on Hard).
- **No quests** apart from the moon. No wormholes, mercenaries, trading with ships in orbit, or plundering traders.
- **A crude attack test** (weapons times hull plus shields against the opponent's), with no allowance for skills, which makes the fighter look worse than a careful human.
- **A simple ship score**, so they settle on Beetles and Termites.
- **Seeds are fixed** (game k on difficulty d uses seed 1000 + 7919k + 104729d), so reruns reproduce exactly.
