package sim

// Balance simulator: plays computer-vs-computer battles between two armies and
// reports who wins. Run it through tools/sim.sh; see usage below.

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import game "../../src/game"

USAGE :: `usage: tools/sim.sh RED BLUE [options]
  RED, BLUE   army: count+letter pairs, k = kobold (dagger), s = kobold slinger,
              h = heavy kobold (axe, chain), c = kobold champion (sword,
              plate), r = kobold scout (runner); e.g. 4k, 2k2s, 1c2h4k
options:
  -n GAMES    games to play (default 500)
  -first W    who moves first: red, blue or alt (default alt: half each)
  -inset N    columns between each army and its map edge (default 1)
  -seed N     first seed (default 1000); game i uses seed+i
  -forest P   make P percent of the map forest (0-90); default: the standard
              light clumps (about 10-15%)
  -hills P    raise P percent of the map as high ground (0-90; default 0)
  -red S      computer style for red: tactical (default) or basic (the
              first computer player, kept for comparison)
  -blue S     the same for blue
  -nofog      everyone sees everything (fog of war is on by default, as in
              the game), for comparing with results from before fog
Units are placed in columns of up to 10 rows, rear first: slingers nearest the
edge, daggers in front. Maps are grass, forest clumps and one road.`

Army :: struct {
	kinds: [game.MAX_UNITS / 2]game.Unit_Kind,
	count: int,
}

parse_army :: proc(spec: string) -> (army: Army, ok: bool) {
	counts: [game.Unit_Kind]int
	n := 0
	for c in spec {
		switch c {
		case '0' ..= '9':
			n = n * 10 + int(c - '0')
		case 'k', 's', 'h', 'c', 'r':
			if n == 0 { return }
			kind: game.Unit_Kind
			switch c {
			case 'k': kind = .Kobold
			case 's': kind = .Kobold_Slinger
			case 'h': kind = .Heavy
			case 'c': kind = .Champion
			case 'r': kind = .Scout
			}
			counts[kind] += n
			n = 0
		case:
			return
		}
	}
	if n != 0 { return }
	// rear units first: ranged, then the rest, the toughest in front
	for kind in ([]game.Unit_Kind{.Kobold_Slinger, .Scout, .Kobold, .Champion, .Heavy}) {
		for _ in 0 ..< counts[kind] {
			if army.count >= len(army.kinds) { return }
			army.kinds[army.count] = kind
			army.count += 1
		}
	}
	return army, army.count > 0
}

Totals :: struct {
	wins:         [2]int,
	draws:        int,
	turns:        int,
	survivors:    [2]int, // summed over that side's wins
	first_attack: [2]int,
	first_blood:  [2]int,
	blood_won:    int, // games won by the side that killed first
	attacks:      [2][game.Weapon_Kind]int,
	kills:        [2][game.Weapon_Kind]int,
	fortifies:    [2]int,
}

play :: proc(red, blue: ^Army, first, inset, forest, hills: int, fog: bool, styles: [2]game.Ai_Style, seed: u64, t: ^Totals) {
	g: game.Game
	g.winner = -1
	g.turn = 1
	g.rng = {seed}
	g.fog = fog
	if forest < 0 {
		game.generate_clumped_forest(&g, 9, 3, 9)
	}
	game.generate_road(&g, game.Road_Direction(game.rng_int(&g.rng, len(game.Road_Direction))))
	game.add_faction(&g, "Red", .Computer, game.RED, styles[0])
	game.add_faction(&g, "Blue", .Computer, game.BLUE, styles[1])
	game.place_block(&g, 0, red.kinds[:red.count], true, inset)
	game.place_block(&g, 1, blue.kinds[:blue.count], false, inset)
	if forest >= 0 { game.grow_forest_to(&g, forest) }
	if hills > 0 { game.grow_hills_to(&g, hills) }
	g.current = first
	game.start_faction_turn(&g)
	game.update_vision(&g, game.NO_FACTION)

	first_attack, first_blood := -1, -1
	start := [2]int{red.count, blue.count}
	for steps := 0; g.winner < 0 && steps < 100_000; steps += 1 {
		game.ai_step(&g)
		if first_attack < 0 {
			for f in 0 ..< 2 {
				for n in g.attacks[f] { if n > 0 { first_attack = f } }
			}
		}
		if first_blood < 0 {
			for f in 0 ..< 2 {
				if game.living_units(&g, f) < start[f] { first_blood = 1 - f }
			}
		}
	}
	if g.winner < 0 {
		t.draws += 1
		return
	}
	t.wins[g.winner] += 1
	t.turns += g.turn
	t.survivors[g.winner] += game.living_units(&g, g.winner)
	if first_attack >= 0 { t.first_attack[first_attack] += 1 }
	if first_blood >= 0 {
		t.first_blood[first_blood] += 1
		if first_blood == g.winner { t.blood_won += 1 }
	}
	for f in 0 ..< 2 {
		t.fortifies[f] += g.fortifies[f]
		for w in game.Weapon_Kind {
			t.attacks[f][w] += g.attacks[f][w]
			t.kills[f][w] += g.kills[f][w]
		}
	}
}

pct :: proc(n, d: int) -> f64 { return 100 * f64(n) / f64(max(d, 1)) }

main :: proc() {
	args := os.args[1:]
	positional: [dynamic]string
	games, inset, seed, forest, hills := 500, 1, 1000, -1, 0
	first_mode := "alt"
	fog := true
	styles: [2]game.Ai_Style
	for i := 0; i < len(args); i += 1 {
		a := args[i]
		if a == "-nofog" {
			fog = false
		} else if strings.has_prefix(a, "-") {
			if i + 1 >= len(args) { fmt.eprintln(USAGE); os.exit(2) }
			v := args[i + 1]
			i += 1
			ok := true
			switch a {
			case "-n":     games, ok = strconv.parse_int(v)
			case "-inset": inset, ok = strconv.parse_int(v)
			case "-seed":  seed, ok = strconv.parse_int(v)
			case "-forest":
				forest, ok = strconv.parse_int(v)
				ok = ok && forest >= 0 && forest <= 90
			case "-hills":
				hills, ok = strconv.parse_int(v)
				ok = ok && hills >= 0 && hills <= 90
			case "-red", "-blue":
				st, sok := parse_style(v)
				ok = sok
				styles[0 if a == "-red" else 1] = st
			case "-first": first_mode = v; ok = v == "red" || v == "blue" || v == "alt"
			case:          ok = false
			}
			if !ok { fmt.eprintln(USAGE); os.exit(2) }
		} else {
			append(&positional, a)
		}
	}
	if len(positional) != 2 { fmt.eprintln(USAGE); os.exit(2) }
	red, rok := parse_army(positional[0])
	blue, bok := parse_army(positional[1])
	if !rok || !bok { fmt.eprintln(USAGE); os.exit(2) }

	t: Totals
	for i in 0 ..< games {
		first := 0
		switch first_mode {
		case "blue": first = 1
		case "alt":  first = i % 2
		}
		play(&red, &blue, first, inset, forest, hills, fog, styles, u64(seed + i), &t)
	}

	decided := t.wins[0] + t.wins[1]
	forest_text := "standard" if forest < 0 else fmt.tprintf("%d%%", forest)
	points :: proc(a: ^Army) -> int {
		n := 0
		for k in a.kinds[:a.count] { n += game.UNIT_TYPES[k].points }
		return n
	}
	fmt.printfln("%s (red, %d points) vs %s (blue, %d points): %d games, first move %s, inset %d, forest %s, hills %d%%, fog %s",
		positional[0], points(&red), positional[1], points(&blue), games, first_mode, inset, forest_text, hills, "on" if fog else "off")
	fmt.printfln("  styles: red %v, blue %v", styles[0], styles[1])
	fmt.printfln("  red wins  %5.1f%%   avg survivors %.1f of %d", pct(t.wins[0], games), f64(t.survivors[0]) / f64(max(t.wins[0], 1)), red.count)
	fmt.printfln("  blue wins %5.1f%%   avg survivors %.1f of %d", pct(t.wins[1], games), f64(t.survivors[1]) / f64(max(t.wins[1], 1)), blue.count)
	if t.draws > 0 { fmt.printfln("  unfinished %d", t.draws) }
	fmt.printfln("  avg turns %.1f", f64(t.turns) / f64(max(decided, 1)))
	fmt.printfln("  first attack: red %.0f%%, blue %.0f%%   first kill: red %.0f%%, blue %.0f%% (that side won %.0f%%)",
		pct(t.first_attack[0], decided), pct(t.first_attack[1], decided),
		pct(t.first_blood[0], decided), pct(t.first_blood[1], decided), pct(t.blood_won, decided))
	fmt.printfln("  fortifies per game: red %.2f, blue %.2f", f64(t.fortifies[0]) / f64(max(decided, 1)), f64(t.fortifies[1]) / f64(max(decided, 1)))
	for f in 0 ..< 2 {
		name := "red " if f == 0 else "blue"
		for w in game.Weapon_Kind {
			if t.attacks[f][w] == 0 { continue }
			fmt.printfln("  %s %-6s attacks %6d  kills %5d  (%.1f%% kill rate)", name, game.WEAPONS[w].name,
				t.attacks[f][w], t.kills[f][w], pct(t.kills[f][w], t.attacks[f][w]))
		}
	}
}

parse_style :: proc(s: string) -> (game.Ai_Style, bool) {
	switch s {
	case "tactical": return .Tactical, true
	case "basic":    return .Basic, true
	}
	return .Tactical, false
}
