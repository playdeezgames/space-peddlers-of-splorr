// Scripted players for balance play-testing. They play the real game (the
// transpiled C on the emulated Palm OS): docked actions run the game's own
// procedures through playtest-only `.Call` inputs, everything else (encounter
// buttons, alerts, dialogs) is answered with the taps and keys a player would
// use. Results go to stdout; see PLAYTEST.md.
//
//   odin build playtest -o:speed -out:build/playtest
//   build/playtest [games] [strategy|all] [difficulty|all] [days]
package playtest

import game "../src/game"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"

// ---------------------------------------------------------------- strategies

Strategy :: struct {
	name:      string,
	fight:     bool, // attack pirates (and monsters) when stronger, instead of fleeing
	smuggle:   bool, // trade firearms and narcotics too
	upgrade:   bool, // buy better ships and equipment
	insure:    bool, // escape pod and insurance
	skills:    [4]i32, // pilot, fighter, trader, engineer (16 points to spread on top of 1 each)
	moon:      bool, // buy the moon when it can, ending the game
}

STRATEGIES := []Strategy {
	{name = "trader", upgrade = true, insure = true, skills = {4, 4, 4, 4}, moon = true},
	{name = "fighter", fight = true, upgrade = true, insure = true, skills = {4, 6, 3, 3}, moon = true},
	{name = "smuggler", smuggle = true, upgrade = true, insure = true, skills = {6, 2, 5, 3}, moon = true},
	{name = "no-upgrades", skills = {4, 4, 4, 4}, moon = true},
	{name = "pure-trader", upgrade = true, insure = true, skills = {5, 1, 9, 1}, moon = true},
}

// ---------------------------------------------------------------- input helpers

feed :: proc(inp: game.Input) {game.feed(inp)}
tap :: proc(x, y: i32) {feed({kind = .Tap, x = i16(x), y = i16(y)})}
key :: proc(c: u16) {feed({kind = .Key, chr = c})}
call :: proc(op: Op, a: i32 = 0, b: i32 = 0) {
	if verbose {fmt.printfln("  day %d form %d: call %v %d %d (credits %d)", g.Days, game.FrmGetActiveFormID(), op, a, b, g.Credits)}
	feed({kind = .Call, chr = u16(op), a = a, b = b})
}

verbose: bool

press :: proc(id: u16) -> bool {
	f := game.FrmGetActiveForm()
	if f == nil {return false}
	o := game.obj_by_id(f, id)
	if verbose {fmt.printfln("  day %d form %d: press %d -> %v usable %v", g.Days, f.id, id, o != nil ? [4]i32{o.x, o.y, o.w, o.h} : [4]i32{}, o != nil && o.usable)}
	if o == nil || !o.usable {return false}
	tap(o.x + o.w / 2, o.y + o.h / 2)
	return true
}

visible :: proc(id: u16) -> bool {
	f := game.FrmGetActiveForm()
	if f == nil {return false}
	o := game.obj_by_id(f, id)
	return o != nil && o.usable
}

// ---------------------------------------------------------------- bot calls

Op :: enum u16 {
	SetDifficulty,
	Sell, // a = item
	Dump, // a = item, b = amount (jettison is not used; selling only)
	Buy, // a = item, b = amount
	Fuel,
	Repair,
	Weapon, // a = type
	Shield,
	Gadget,
	Goto, // a = form id
	Warp, // a = system
}

g: ^game.Globals

hook :: proc(inp: game.Input) {
	g = game.g
	op := Op(inp.chr)
	switch op {
	case .SetDifficulty:
		g.Difficulty = u8(inp.a)
	case .Sell:
		game.SellCargo(inp.a, 999, game.SELLCARGO)
	case .Dump:
	case .Buy:
		game.BuyCargo(inp.a, inp.b, false)
	case .Fuel:
		game.BuyFuel(1_000_000)
	case .Repair:
		game.BuyRepairs(1_000_000)
	case .Weapon:
		w := game.Weapontype[inp.a]
		game.BuyItem(game.Shiptype[g.Ship.Type].WeaponSlots, &g.Ship.Weapon[0], game.BasePrice(w.TechLevel, w.Price), w.Name, inp.a)
	case .Shield:
		s := game.Shieldtype[inp.a]
		game.BuyItem(game.Shiptype[g.Ship.Type].ShieldSlots, &g.Ship.Shield[0], game.BasePrice(s.TechLevel, s.Price), s.Name, inp.a)
	case .Gadget:
		d := game.Gadgettype[inp.a]
		game.BuyItem(game.Shiptype[g.Ship.Type].GadgetSlots, &g.Ship.Gadget[0], game.BasePrice(d.TechLevel, d.Price), d.Name, inp.a)
	case .Goto:
		g.CurForm = inp.a
		game.FrmGotoForm(u16(inp.a))
	case .Warp:
		g.WarpSystem = inp.a
		game.DoWarp(false)
	}
}

// ---------------------------------------------------------------- results

CHECK_DAYS :: [?]i32{25, 50, 100, 200, 400}
WORTH_MARKS :: [?]i32{10_000, 50_000, 100_000, 250_000, 500_000, 1_000_000}
N_PHASE :: len(CHECK_DAYS) + 1

End :: enum {Killed, Moon, Retired, DayCap, Stuck}

Result :: struct {
	end:        End,
	days:       i32,
	worth:      [len(CHECK_DAYS)]i32, // -1 when the game ended earlier
	ship:       [len(CHECK_DAYS)]u8,
	reach_day:  [len(WORTH_MARKS)]i32, // -1 never
	final_worth: i32,
	pods:       i32, // escape pod used
	pod_phase:  [N_PHASE]i32,
	pod_by:     [4]i32, // what the ship was fighting when the pod fired: police, pirate, trader, other
	arrests:    i32,
	enc:        [N_PHASE][4]i32, // per phase: police, pirate, trader, other
	fights_won: i32,
	died_ship:  u8,
	died_phase: int,
	police:     i32, // police record score at the end
	kills:      [3]i32, // pirate, police, trader
	trips:      i32,
	stuck_note: string,
}

phase_of :: proc(day: i32) -> int {
	for d, i in CHECK_DAYS {if day < d {return i}}
	return len(CHECK_DAYS)
}

// Alert and dialog titles seen, for checking the policies.
seen: map[string]int

// ---------------------------------------------------------------- one game

cmd :: proc() -> ^game.CREWMEMBER {return &g.Mercenary[0]}
cursys :: proc() -> ^game.SOLARSYSTEM {return &g.SolarSystem[cmd().CurSystem]}

worth :: proc() -> i32 {return game.CurrentWorth()}

play :: proc(seed: u32, diff: i32, st: Strategy, max_days: i32) -> (r: Result) {
	game.init(seed, nil)
	game.replay.no_save = true
	game.headless = true
	game.bot_hook = hook
	g = game.g
	for &w in r.worth {w = -1}
	for &d in r.reach_day {d = -1}

	// Title screen: any tap; then the New Commander form.
	tap(80, 80)
	if g.CurForm != game.NewCommanderForm && game.FrmGetActiveFormID() != game.NewCommanderForm {
		r.end = .Stuck
		r.stuck_note = "no new commander form"
		return
	}
	call(.SetDifficulty, diff)
	ids := [4]u16{game.NewCommanderIncPilotButton, game.NewCommanderIncFighterButton, game.NewCommanderIncTraderButton, game.NewCommanderIncEngineerButton}
	for k in 0 ..< 4 {
		for _ in 0 ..< st.skills[k] {press(ids[k])}
	}
	press(game.NewCommanderOKButton)

	steps := 0
	last_day := i32(-1)
	same_day_steps := 0
	escape_pods := 0
	cur_result = &r
	defer cur_result = nil
	for {
		steps += 1
		if g.Days != last_day {last_day = g.Days; same_day_steps = 0} else {same_day_steps += 1}
		if same_day_steps > 400 {
			r.end = .Stuck
			r.stuck_note = fmt.aprintf("form %d active %d, alert %d, dialog %d, credits %d, hull %d/%d, fuel %d/%d, pod %v", g.CurForm, game.FrmGetActiveFormID(), game.replay.wait.alert, game.replay.wait.dialog, g.Credits, g.Ship.Hull, game.GetHullStrength(), game.GetFuel(), game.GetFuelTanks(), g.EscapePod)
			break
		}
		for d, i in CHECK_DAYS {
			if g.Days >= d && r.worth[i] < 0 {
				r.worth[i] = worth()
				r.ship[i] = g.Ship.Type
			}
		}
		w := worth()
		for m, i in WORTH_MARKS {if w >= m && r.reach_day[i] < 0 {r.reach_day[i] = g.Days}}

		if game.in_modal() {
			answer_wait(st)
			continue
		}
		form := g.CurForm
		active := i32(game.FrmGetActiveFormID())
		switch {
		case active == game.DestroyedForm || form == game.DestroyedForm:
			r.end = .Killed
		case active == game.UtopiaForm || form == game.UtopiaForm:
			r.end = .Moon
		case active == game.RetireForm || form == game.RetireForm:
			r.end = .Retired
		case active == game.HighScoresForm || active == game.MainForm || active == game.FinalScoreForm:
			if r.end == .Killed || r.end == .Moon || r.end == .Retired {break}
			r.end = .Killed
		}
		if active == game.DestroyedForm || active == game.UtopiaForm || active == game.RetireForm ||
		   active == game.HighScoresForm || active == game.MainForm || active == game.FinalScoreForm {
			if r.end == .Killed {
				r.died_ship = g.Ship.Type
				r.died_phase = phase_of(g.Days)
			}
			break
		}
		if g.Days >= max_days {r.end = .DayCap; break}

		switch active {
		case game.EncounterForm:
			encounter(st, &r)
		case game.PlunderForm:
			if !press(game.PlunderDoneButton) {key(game.chrLineFeed)}
		case:
			docked(st, &r, &escape_pods)
		}
	}
	r.days = g.Days
	r.final_worth = worth()
	r.police = g.PoliceRecordScore
	r.kills = {g.PirateKills, g.PoliceKills, g.TraderKills}
	return
}

alert_title :: proc(id: u16) -> string {
	a := game.alert_def(id)
	return a.title if a != nil else "?"
}

answer_wait :: proc(st: Strategy) {
	w := game.replay.wait
	if w.alert != 0 {
		title := alert_title(w.alert)
		seen[fmt.aprintf("alert %d %s", w.alert, title)] += 1
		if title == "Escape Pod Activated" {
			cur_result.pods += 1
			cur_result.pod_phase[phase_of(g.Days)] += 1
			cur_result.pod_by[enc_kind(g.EncounterType)] += 1
		}
		if title == "Arrested" {cur_result.arrests += 1}
		a := game.alert_def(w.alert)
		btn := i32(a.default_button)
		// Overrides: answers a sensible player gives that are not the default.
		for i in 0 ..< i32(a.count) {
			label := game.RSRC_POOL[i32(a.first) + i]
			switch title {
			case "Pay Interest", "Wormhole Tax":
			}
			if st.insure && title == "Escape Pod" && label == "Yes" {btn = i}
			if title == "Buy Insurance" && label == "Yes" && st.insure {btn = i}
		}
		if btn >= w.nb {btn = 0}
		tap(w.bx[btn] + w.bw[btn] / 2, w.by + 4)
		return
	}
	if w.dialog != 0 {
		seen[fmt.aprintf("dialog %d", w.dialog)] += 1
		want: u16
		switch w.dialog {
		case game.BuyItemForm:
			want = game.BuyItemYesButton
		case game.TradeInShipForm:
			want = game.TradeInShipYesButton
		}
		if want != 0 {
			for i in 0 ..< w.nids {
				if w.ids[i] == want {
					rc := w.rects[i]
					tap(rc[0] + rc[2] / 2, rc[1] + rc[3] / 2)
					return
				}
			}
		}
		key(game.chrLineFeed)
		return
	}
	// Waiting on something the bot does not drive (menu, help, popup): back out.
	seen["wait other"] += 1
	key(game.chrLineFeed)
}

// ---------------------------------------------------------------- encounters

encounter :: proc(st: Strategy, r: ^Result) {
	et := g.EncounterType
	ph := phase_of(g.Days)
	// count each encounter once, on its first round
	if !in_encounter {
		in_encounter = true
		switch {
		case et >= 0 && et < 10:
			r.enc[ph][0] += 1
		case et >= 10 && et < 20:
			r.enc[ph][1] += 1
		case et >= 20 && et < 30:
			r.enc[ph][2] += 1
		case:
			r.enc[ph][3] += 1
		}
	}
	illegal := g.Ship.Cargo[game.FIREARMS] > 0 || g.Ship.Cargo[game.NARCOTICS] > 0
	ours := game.TotalWeapons(&g.Ship, -1, -1)
	theirs := game.TotalWeapons(&g.Opponent, -1, -1)
	stronger := ours > 0 && ours * (g.Ship.Hull + game.TotalShieldStrength(&g.Ship)) >= theirs * (g.Opponent.Hull + game.TotalShieldStrength(&g.Opponent))

	prefs: []u16
	switch et {
	case game.POLICEINSPECTION:
		if illegal {
			prefs = {game.EncounterFleeButton, game.EncounterSubmitButton}
		} else {
			prefs = {game.EncounterSubmitButton}
		}
	case game.POSTMARIEPOLICEENCOUNTER:
		prefs = {game.EncounterYieldButton}
	case game.PIRATEATTACK, game.SPACEMONSTERATTACK, game.DRAGONFLYATTACK, game.SCARABATTACK, game.POLICEATTACK, game.FAMOUSCAPATTACK:
		if st.fight && stronger && et != game.POLICEATTACK {
			prefs = {game.EncounterAttackButton, game.EncounterFleeButton}
		} else {
			prefs = {game.EncounterFleeButton, game.EncounterSurrenderButton}
		}
	case game.PIRATESURRENDER:
		prefs = {game.EncounterPlunderButton, game.EncounterIgnoreButton}
	case game.PIRATEFLEE, game.PIRATEIGNORE:
		if st.fight && stronger {prefs = {game.EncounterAttackButton, game.EncounterIgnoreButton}} else {prefs = {game.EncounterIgnoreButton}}
	}
	all := []u16{game.EncounterIgnoreButton, game.EncounterFleeButton, game.EncounterSubmitButton, game.EncounterYieldButton,
		game.EncounterSurrenderButton, game.EncounterAttackButton, game.EncounterPlunderButton}
	for id in prefs {if press(id) {return}}
	for id in all {if press(id) {return}}
	// Nothing to press (e.g. the encounter ended): tap the screen.
	key(game.chrLineFeed)
}

in_encounter: bool
cur_result: ^Result

enc_kind :: proc(et: i32) -> int {
	switch {
	case et >= 0 && et < 10: return 0
	case et >= 10 && et < 20: return 1
	case et >= 20 && et < 30: return 2
	}
	return 3
}

// ---------------------------------------------------------------- docked

est_sell :: proc(sys: ^game.SOLARSYSTEM, i: int) -> i32 {
	res: i32 = i32(sys.SpecialResources) if sys.Visited else -1
	p := game.StandardPrice(u8(i), sys.Size, sys.TechLevel, sys.Politics, res)
	if p <= 0 {return 0}
	if game.Tradeitem[i].DoublePriceStatus >= 0 && i32(sys.Status) == game.Tradeitem[i].DoublePriceStatus {p = p * 3 / 2}
	if g.PoliceRecordScore < game.DUBIOUSSCORE {p = p * 90 / 100}
	return p
}

legal :: proc(st: Strategy, i: int) -> bool {return st.smuggle || (i != game.FIREARMS && i != game.NARCOTICS)}

Plan :: struct {
	target: i32,
	items:  [2]i32,
	qty:    [2]i32,
	profit: i32,
}

plan_trip :: proc(st: Strategy, only: i32 = -1) -> Plan {
	best := Plan{target = -1, items = {-1, -1}}
	cur := cursys()
	fuel := i32(game.GetFuel())
	bays := game.TotalCargoBays() - game.FilledCargoBays()
	credits := g.Credits - reserve()
	for j in 0 ..< i32(len(g.SolarSystem)) {
		if j == i32(cmd().CurSystem) || (only >= 0 && j != only) {continue}
		dist := game.RealDistance(cur^, g.SolarSystem[j])
		if dist > fuel {continue}
		p := Plan{target = j, items = {-1, -1}}
		left_bays := bays
		left_cr := credits
		used := [10]bool{}
		for k in 0 ..< 2 {
			bi, bq, bv := i32(-1), i32(0), i32(0)
			for i in 0 ..< 10 {
				if used[i] || !legal(st, i) || g.BuyPrice[i] <= 0 || cur.Qty[i] <= 0 {continue}
				gain := est_sell(&g.SolarSystem[j], i) - g.BuyPrice[i]
				if gain <= 0 {continue}
				q := min(left_bays, cur.Qty[i], max(left_cr, 0) / g.BuyPrice[i])
				if q * gain > bv {bi, bq, bv = i32(i), q, q * gain}
			}
			if bi < 0 {break}
			used[bi] = true
			p.items[k], p.qty[k] = bi, bq
			p.profit += bv
			left_bays -= bq
			left_cr -= bq * g.BuyPrice[bi]
		}
		if p.profit > best.profit {best = p}
	}
	if best.target < 0 && only >= 0 {best.target = only}
	if best.target < 0 {
		// nothing profitable: go to a random system in range
		cands := make([dynamic]i32, context.temp_allocator)
		for j in 0 ..< i32(len(g.SolarSystem)) {
			if j != i32(cmd().CurSystem) && game.RealDistance(cur^, g.SolarSystem[j]) <= fuel {append(&cands, j)}
		}
		if len(cands) > 0 {best.target = cands[int(g.Days * 7 + i32(len(cands))) % len(cands)]}
	}
	return best
}

// Money kept back for trading and running costs.
reserve :: proc() -> i32 {
	return 0
}

upgrade_reserve :: proc() -> i32 {
	return 2000 + game.TotalCargoBays() * 300
}

// Ship preference: more bays and slots, then hull.
ship_score :: proc(t: int) -> i32 {
	s := game.Shiptype[t]
	return i32(s.CargoBays) * 10 + i32(s.WeaponSlots) * 25 + i32(s.ShieldSlots) * 25 + i32(s.GadgetSlots) * 10 + s.HullStrength / 10
}

docked :: proc(st: Strategy, r: ^Result, pods: ^int) {
	in_encounter = false
	// sell everything sellable
	for i in 0 ..< i32(10) {
		if g.Ship.Cargo[i] > 0 && g.SellPrice[i] > 0 {
			if !on(game.SellCargoForm) {return}
			call(.Sell, i)
			if game.in_modal() {return}
		}
	}
	if g.Ship.Hull < game.GetHullStrength() && g.Credits >= i32(game.Shiptype[g.Ship.Type].RepairCosts) {
		if !on(game.ShipYardForm) {return}
		call(.Repair)
		if game.in_modal() {return}
	}

	if st.upgrade && !(st.moon && worth() >= game.COSTMOON * 4 / 5) {
		if upgrade(st) {return}
	}
	if st.insure && !g.EscapePod && game.ToSpend() >= 2000 && g.Credits > 2000 + upgrade_reserve() / 2 && cursys().TechLevel >= game.Shiptype[0].MinTechLevel {
		if !on(game.ShipYardForm) {return}
		if visible(game.ShipYardEscapePodButton) {press(game.ShipYardEscapePodButton); return}
	}
	if st.insure && g.EscapePod && !g.Insurance && g.Credits > upgrade_reserve() {
		if !on(game.BankForm) {return}
		if visible(game.BankBuyInsuranceButton) {press(game.BankBuyInsuranceButton); return}
	}
	if game.GetFuel() < game.GetFuelTanks() && g.Credits >= i32(game.Shiptype[g.Ship.Type].CostOfFuel) {
		if !on(game.ShipYardForm) {return}
		call(.Fuel)
		if game.in_modal() {return}
	}

	// heading for the moon (or Utopia once it is bought)
	goal := moon_goal(st)
	if goal >= 0 && goal == i32(cmd().CurSystem) {
		if i32(game.FrmGetActiveFormID()) == game.SpecialEventForm {
			for id in ([]u16{game.SpecialEventYesButton, game.SpecialEventOKButton, game.SpecialEventNoButton}) {
				if press(id) {return}
			}
		}
		if !on(game.SystemInformationForm) {return}
		if press(game.SystemInformationSpecialButton) {return}
		r.stuck_note = "special button missing at the moon goal"
	}
	hop := next_hop(goal) if goal >= 0 else -1
	p := plan_trip(st, hop)
	if p.target < 0 {r.end = .Stuck; return}
	for k in 0 ..< 2 {
		if p.items[k] >= 0 && p.qty[k] > 0 {
			if !on(game.BuyCargoForm) {return}
			call(.Buy, p.items[k], p.qty[k])
			if game.in_modal() {return}
		}
	}
	r.trips += 1
	call(.Warp, p.target)
}

// Make `form` the screen on show, as a player would before using it. Returns
// false when it had to switch (the caller tries again next step).
on :: proc(form: i32) -> bool {
	if i32(game.FrmGetActiveFormID()) == form {return true}
	call(.Goto, form)
	return false
}

// One upgrade step per call; returns true when it did something (the caller
// comes back next step).
upgrade :: proc(st: Strategy) -> bool {
	spare := g.Credits - upgrade_reserve()
	if spare <= 0 || g.Debt > 0 {return false}
	// a better ship
	game.DetermineShipPrices()
	cur := ship_score(int(g.Ship.Type))
	best, best_score := -1, cur + 15
	for t in 0 ..< game.MAXSHIPTYPE {
		price := g.ShipPrice[t]
		if price <= 0 || price > spare {continue}
		if s := ship_score(t); s > best_score {best, best_score = t, s}
	}
	if best >= 0 && game.FilledCargoBays() == 0 {
		if !on(game.BuyShipForm) {return true}
		press(u16(game.BuyShipBuy0Button + best))
		return true
	}
	t := game.Shiptype[g.Ship.Type]
	// weapons: fill empty slots with the best available
	if game.GetFirstEmptySlot(t.WeaponSlots, &g.Ship.Weapon[0]) >= 0 {
		for w := game.MAXWEAPONTYPE - 1; w >= 0; w -= 1 {
			pr := game.BasePrice(game.Weapontype[w].TechLevel, game.Weapontype[w].Price)
			if pr > 0 && pr <= spare {if on(game.BuyEquipmentForm) {call(.Weapon, i32(w))}; return true}
		}
	}
	if game.GetFirstEmptySlot(t.ShieldSlots, &g.Ship.Shield[0]) >= 0 {
		for s := game.MAXSHIELDTYPE - 1; s >= 0; s -= 1 {
			pr := game.BasePrice(game.Shieldtype[s].TechLevel, game.Shieldtype[s].Price)
			if pr > 0 && pr <= spare {if on(game.BuyEquipmentForm) {call(.Shield, i32(s))}; return true}
		}
	}
	if game.GetFirstEmptySlot(t.GadgetSlots, &g.Ship.Gadget[0]) >= 0 {
		pr := game.BasePrice(game.Gadgettype[game.EXTRABAYS].TechLevel, game.Gadgettype[game.EXTRABAYS].Price)
		if pr > 0 && pr <= spare {if on(game.BuyEquipmentForm) {call(.Gadget, game.EXTRABAYS)}; return true}
	}
	return false
}

// ---------------------------------------------------------------- report

DIFF_NAMES := [5]string{"Beginner", "Easy", "Normal", "Hard", "Impossible"}

main :: proc() {
	games := 50
	strat := "all"
	diff := "all"
	max_days := i32(500)
	args := os.args
	if len(args) > 1 {games = atoi(args[1])}
	if len(args) > 2 {strat = args[2]}
	if len(args) > 3 {diff = args[3]}
	if len(args) > 4 {max_days = i32(atoi(args[4]))}
	verbose = os.get_env("PT_VERBOSE", context.temp_allocator) != ""

	for st in STRATEGIES {
		if strat != "all" && strat != st.name {continue}
		for d in 0 ..< 5 {
			if diff != "all" && atoi(diff) != d {continue}
			results := make([]Result, games)
			only := atoi(os.get_env("PT_ONLY", context.temp_allocator)) - 1
			for k in 0 ..< games {
				if only >= 0 && k != only {results[k].end = .DayCap; continue}
				results[k] = play(u32(1000 + k * 7919 + d * 104729), i32(d), st, max_days)
			}
			report(st, d, results)
		}
	}
	if strat != "all" {
		keys := make([dynamic]string)
		for k in seen {append(&keys, k)}
		slice.sort(keys[:])
		fmt.println("\nalerts and dialogs answered:")
		for k in keys {fmt.printfln("  %6d  %s", seen[k], k)}
	}
}

median :: proc(xs: []i32) -> i32 {
	if len(xs) == 0 {return -1}
	slice.sort(xs)
	return xs[len(xs) / 2]
}

report :: proc(st: Strategy, d: int, rs: []Result) {
	n := len(rs)
	ends: [End]int
	for r in rs {ends[r.end] += 1}
	fmt.printfln("== %s, %s: %d games: killed %d, moon %d, retired %d, day cap %d, stuck %d",
		st.name, DIFF_NAMES[d], n, ends[.Killed], ends[.Moon], ends[.Retired], ends[.DayCap], ends[.Stuck])
	// worth by day (median of the living), survival
	fmt.print("   worth at day (median, alive):")
	for day, i in CHECK_DAYS {
		xs := make([dynamic]i32, context.temp_allocator)
		for r in rs {if r.worth[i] >= 0 {append(&xs, r.worth[i])}}
		fmt.printf("  %d: %d (%d%%)", day, median(xs[:]), len(xs) * 100 / n)
	}
	fmt.println()
	fmt.print("   days to reach worth (median of those who did, share):")
	for m, i in WORTH_MARKS {
		xs := make([dynamic]i32, context.temp_allocator)
		for r in rs {if r.reach_day[i] >= 0 {append(&xs, r.reach_day[i])}}
		fmt.printf("  %dk: %d (%d%%)", m / 1000, median(xs[:]), len(xs) * 100 / n)
	}
	fmt.println()
	// deaths by phase
	dp: [N_PHASE]int
	for r in rs {if r.end == .Killed {dp[r.died_phase] += 1}}
	fmt.printfln("   deaths by phase (days <25, <50, <100, <200, <400, later): %v", dp)
	pp: [N_PHASE]i32
	pb: [4]i32
	arrests := 0
	for r in rs {
		for p in 0 ..< N_PHASE {pp[p] += r.pod_phase[p]}
		for k in 0 ..< 4 {pb[k] += r.pod_by[k]}
		arrests += int(r.arrests)
	}
	fmt.printfln("   escape pods used by phase: %v; against [police, pirate, trader, other]: %v; arrests %d", pp, pb, arrests)
	{
		xs := make([dynamic]i32, context.temp_allocator)
		for r in rs {if r.end == .Moon {append(&xs, r.days)}}
		mn, mx := i32(-1), i32(-1)
		if len(xs) > 0 {slice.sort(xs[:]); mn, mx = xs[0], xs[len(xs) - 1]}
		fmt.printfln("   moon bought and retired: %d%%, day median %d (min %d, max %d)", len(xs) * 100 / n, median(xs[:]), mn, mx)
		ks: [3]i32
		for r in rs {for k in 0 ..< 3 {ks[k] += r.kills[k]}}
		fmt.printfln("   kills per game [pirate, police, trader]: %.1f %.1f %.1f", f64(ks[0]) / f64(n), f64(ks[1]) / f64(n), f64(ks[2]) / f64(n))
	}
	// encounters per trip by phase
	enc: [N_PHASE][4]i32
	for r in rs {for p in 0 ..< N_PHASE {for k in 0 ..< 4 {enc[p][k] += r.enc[p][k]}}}
	fmt.printfln("   encounters by phase [police, pirate, trader, other]: %v", enc)
	// ship at day 100 / 200
	for i in 2 ..< 4 {
		counts: [game.MAXSHIPTYPE + 5]int
		for r in rs {if r.worth[i] >= 0 {counts[r.ship[i]] += 1}}
		cd := CHECK_DAYS
		fmt.printf("   ships at day %d:", cd[i])
		for c, t in counts {if c > 0 {fmt.printf(" %s %d", game.Shiptype[t].Name, c)}}
		fmt.println()
	}
	for r in rs {if r.end == .Stuck {fmt.printfln("   stuck: day %d: %s", r.days, r.stuck_note)}}
}

atoi :: proc(s: string) -> int {v, _ := strconv.parse_int(s); return v}

// The system the moon ending needs next: where the moon is for sale (once the
// credits are there), then Utopia (once it is bought).
moon_goal :: proc(st: Strategy) -> i32 {
	if !st.moon {return -1}
	want: i32
	if g.MoonBought {
		want = game.MOONBOUGHT
	} else {
		cargo: i32 = 0
		for i in 0 ..< 10 {cargo += g.Ship.Cargo[i] * max(g.SellPrice[i], 0)}
		if g.Credits + cargo < game.COSTMOON + 5000 {return -1}
		want = game.MOONFORSALE
	}
	for j in 0 ..< i32(len(g.SolarSystem)) {if g.SolarSystem[j].Special == want {return j}}
	return -1
}

// First system on a shortest (fewest jumps, full tanks) route to `goal`.
next_hop :: proc(goal: i32) -> i32 {
	N :: len(g.SolarSystem)
	tanks := i32(game.GetFuelTanks())
	prev: [N]i32
	for &p in prev {p = -2}
	start := i32(cmd().CurSystem)
	queue := make([dynamic]i32, context.temp_allocator)
	append(&queue, start)
	prev[start] = -1
	for qi := 0; qi < len(queue); qi += 1 {
		a := queue[qi]
		if a == goal {break}
		for b in 0 ..< i32(N) {
			if prev[b] != -2 {continue}
			if game.RealDistance(g.SolarSystem[a], g.SolarSystem[b]) <= tanks {
				prev[b] = a
				append(&queue, b)
			}
		}
	}
	if prev[goal] == -2 {return -1}
	at := goal
	for prev[at] != start && prev[at] >= 0 {at = prev[at]}
	return at
}
