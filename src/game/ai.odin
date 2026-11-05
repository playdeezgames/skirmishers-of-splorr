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

// Move to the best hex in reach (see ai_hex_score) if it is better than where
// the unit stands, then attack. A unit already in melee reach stays put; a
// slinger next to an enemy steps back to a hex it can sling from, if it can.
ai_unit :: proc(g: ^Game, unit: int) {
	u := &g.units[unit]
	ut := unit_type(u)
	costs := movement_costs(g, unit)
	best := u.pos
	best_score := [2]int{ai_hex_score(g, u.faction, ut, u.pos), 0}
	for row in 0 ..< ROWS {
		for col in 0 ..< COLS {
			h := Hex{col, row}
			if !can_move(g, unit, h, &costs) { continue }
			score := [2]int{ai_hex_score(g, u.faction, ut, h), costs[row][col]}
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
//   2+ no enemy in reach: 2 plus the distance to the nearest enemy
ai_hex_score :: proc(g: ^Game, faction: int, ut: ^Unit_Type, h: Hex) -> int {
	_, reach := unit_reach(ut)
	ranged := reach > 1
	nearest := max(int)
	in_reach, adjacent, ranged_shot := false, false, false
	for i in 0 ..< g.unit_count {
		e := &g.units[i]
		if !e.alive || e.faction == faction { continue }
		d := hex_distance(h, e.pos)
		nearest = min(nearest, d)
		if d == 1 { adjacent = true }
		if w, ok := weapon_for(g, ut, h, e.pos); ok {
			in_reach = true
			if WEAPONS[w].max_range > 1 { ranged_shot = true }
		}
	}
	if ranged && ranged_shot && !adjacent { return 0 }
	if in_reach { return 1 }
	return 2 + nearest
}

// True if some enemy, on its next turn, could move (with its full movement,
// around the units standing now) to a hex from which it can attack this unit.
ai_threatened :: proc(g: ^Game, unit: int) -> bool {
	u := &g.units[unit]
	for i in 0 ..< g.unit_count {
		e := &g.units[i]
		if !e.alive || e.faction == u.faction { continue }
		et := unit_type(e)
		_, reach := unit_reach(et)
		budget := et.move * HALVES_PER_POINT
		// a road step costs 1 half point, so no enemy gets further than this
		if hex_distance(e.pos, u.pos) > budget / ROAD_TO_ROAD_HALVES + reach { continue }
		costs := movement_costs(g, i)
		for row in 0 ..< ROWS {
			for col in 0 ..< COLS {
				h := Hex{col, row}
				c := costs[row][col]
				if c == UNREACHABLE || c > budget { continue }
				if h != e.pos && unit_at(g, h) >= 0 { continue }
				if _, ok := weapon_for(g, et, h, u.pos); ok { return true }
			}
		}
	}
	return false
}
