package game

// The computer plays one unit per ai_step, so the page can show each action.

is_computer_turn :: proc(g: ^Game) -> bool {
	return g.winner < 0 && g.factions[g.current].controller == .Computer
}

// Does one thing for the computer: acts with its next unit, or ends its turn once
// every unit is done. Returns false when it is not the computer's turn.
ai_step :: proc(g: ^Game) -> bool {
	if !is_computer_turn(g) { return false }
	for i in 0 ..< g.unit_count {
		u := &g.units[i]
		if u.alive && u.faction == g.current && !u.done {
			ai_unit(g, i)
			u.done = true
			return true
		}
	}
	return end_turn(g)
}

// Plays a whole computer turn at once (tests, and fast-forward).
ai_take_turn :: proc(g: ^Game) {
	faction := g.current
	turn := g.turn
	for is_computer_turn(g) && g.current == faction && g.turn == turn {
		ai_step(g)
	}
}

// The living enemy in range with the fewest body points, or -1.
ai_pick_target :: proc(g: ^Game, unit: int) -> int {
	best := -1
	for i in 0 ..< g.unit_count {
		if !can_attack(g, unit, i) { continue }
		if best < 0 || g.units[i].body < g.units[best].body { best = i }
	}
	return best
}

// What one computer unit knows when it acts, gathered once per ai_unit: the
// enemies its side can see, where it believes enemies are (seen now or last
// seen), and, when it knows of none, how to scout.
Ai_View :: struct {
	enemies:     [MAX_UNITS]int, // enemy units in sight
	enemy_count: int,
	spots:       [MAX_UNITS]Hex, // enemies in sight and last-seen markers
	spot_count:  int,
	// scouting, when there are no spots: the scout heads for `goal`, the others
	// follow it at SCOUT_LEAD hexes
	is_scout:    bool,
	scout_pos:   Hex,
	goal:        Hex,
}

SCOUT_LEAD :: 2

ai_view :: proc(g: ^Game, unit: int) -> (v: Ai_View) {
	f := g.units[unit].faction
	for i in 0 ..< g.unit_count {
		e := &g.units[i]
		if !e.alive || e.faction == f { continue }
		if unit_visible(g, i, f) {
			v.enemies[v.enemy_count] = i
			v.enemy_count += 1
			v.spots[v.spot_count] = e.pos
			v.spot_count += 1
		} else if pos, ok := sighting(g, f, i); ok {
			v.spots[v.spot_count] = pos
			v.spot_count += 1
		}
	}
	if v.spot_count > 0 { return }
	// nobody known: the unit that sees furthest scouts (lowest index on a tie)
	scout := -1
	for i in 0 ..< g.unit_count {
		u := &g.units[i]
		if !u.alive || u.faction != f { continue }
		if scout < 0 || unit_type(u).vision > unit_type(&g.units[scout]).vision { scout = i }
	}
	v.is_scout = scout == unit
	v.scout_pos = g.units[scout].pos
	// the scout's goal: the unexplored hex (else the hex out of sight) that is
	// nearest by way of the map's middle, so scouting heads out across the map
	centre := Hex{COLS / 2, ROWS / 2}
	v.goal = centre
	best := max(int)
	for pass in 0 ..< 2 {
		for row in 0 ..< ROWS {
			for col in 0 ..< COLS {
				h := Hex{col, row}
				open := !hex_seen(g, f, h) if pass == 0 else !hex_watched(g, f, h)
				if !open { continue }
				d := hex_distance(v.scout_pos, h) + hex_distance(h, centre)
				if d < best {
					best = d
					v.goal = h
				}
			}
		}
		if best < max(int) { break }
	}
	return
}

// Move to the best hex in reach (see ai_hex_score) if it is better than where
// the unit stands, then attack. A unit already in melee reach stays put; a
// slinger next to an enemy steps back to a hex it can sling from, if it can.
ai_unit :: proc(g: ^Game, unit: int) {
	u := &g.units[unit]
	ut := unit_type(u)
	view := ai_view(g, unit)
	costs := movement_costs(g, unit)
	best := u.pos
	best_score := [2]int{ai_hex_score(g, u.faction, ut, u.pos, &view), 0}
	for row in 0 ..< ROWS {
		for col in 0 ..< COLS {
			h := Hex{col, row}
			if !can_move(g, unit, h, &costs) { continue }
			score := [2]int{ai_hex_score(g, u.faction, ut, h, &view), costs[row][col]}
			if score.x < best_score.x || (score.x == best_score.x && score.y < best_score.y) {
				best = h
				best_score = score
			}
		}
	}
	// Nothing to attack this turn but an enemy could attack us next turn:
	// dig in rather than walk up to it.
	if best_score.x >= 2 && can_fortify(g, unit) && ai_threatened(g, unit) {
		fortify(g, unit)
		return
	}
	// staying costs 0, so any other best hex scores strictly better
	if best != u.pos { move_unit(g, unit, best) }
	if t := ai_pick_target(g, unit); t >= 0 { attack(g, unit, t) }
}

// How good a hex is to stand on (lower is better):
//   0  an enemy is in reach of a ranged weapon and no enemy is adjacent
//   1  some weapon reaches an enemy (for a ranged unit, this means melee)
//   2+ no enemy in reach: 2 plus the distance to the nearest known enemy, or
//      when scouting, to the scout's goal (the scout) or to SCOUT_LEAD hexes
//      behind the scout (the others)
// Only enemies the side can see count for reach; "adjacent" also counts only
// those, since a hidden one is unknown.
ai_hex_score :: proc(g: ^Game, faction: int, ut: ^Unit_Type, h: Hex, view: ^Ai_View) -> int {
	_, reach := unit_reach(ut)
	ranged := reach > 1
	in_reach, adjacent, ranged_shot := false, false, false
	for i in view.enemies[:view.enemy_count] {
		e := &g.units[i]
		if hex_distance(h, e.pos) == 1 { adjacent = true }
		if w, ok := weapon_for(g, ut, faction, h, e.pos); ok {
			in_reach = true
			if WEAPONS[w].max_range > 1 { ranged_shot = true }
		}
	}
	if ranged && ranged_shot && !adjacent { return 0 }
	if in_reach { return 1 }
	if view.spot_count == 0 {
		if view.is_scout { return 2 + hex_distance(h, view.goal) }
		return 2 + abs(hex_distance(h, view.scout_pos) - SCOUT_LEAD)
	}
	nearest := max(int)
	for p in view.spots[:view.spot_count] { nearest = min(nearest, hex_distance(h, p)) }
	return 2 + nearest
}

// True if some enemy the unit's side can see could, on its next turn, move
// (with its full movement, around the units its side knows of) to a hex from
// which it can attack this unit.
ai_threatened :: proc(g: ^Game, unit: int) -> bool {
	u := &g.units[unit]
	for i in 0 ..< g.unit_count {
		e := &g.units[i]
		if !e.alive || e.faction == u.faction || !unit_visible(g, i, u.faction) { continue }
		et := unit_type(e)
		_, reach := unit_reach(et)
		budget := et.move * HALVES_PER_POINT
		// a road step costs 1 half point and high ground adds half again to a
		// ranged weapon's reach, so no enemy gets further than this
		if hex_distance(e.pos, u.pos) > budget / ROAD_TO_ROAD_HALVES + max(reach, reach * 3 / 2) { continue }
		costs := movement_costs(g, i, u.faction)
		for row in 0 ..< ROWS {
			for col in 0 ..< COLS {
				h := Hex{col, row}
				c := costs[row][col]
				if c == UNREACHABLE || c > budget { continue }
				if o := unit_at(g, h); h != e.pos && o >= 0 && unit_visible(g, o, u.faction) { continue }
				if _, ok := weapon_for(g, et, e.faction, h, u.pos); ok { return true }
			}
		}
	}
	return false
}
