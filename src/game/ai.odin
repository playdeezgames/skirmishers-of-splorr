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
	end_turn(g)
	return true
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

// Attack if something is in range; otherwise move to the cheapest hex that puts
// an enemy in range, or failing that as close to an enemy as it can, then attack.
ai_unit :: proc(g: ^Game, unit: int) {
	if t := ai_pick_target(g, unit); t >= 0 {
		attack(g, unit, t)
		return
	}
	u := &g.units[unit]
	ut := unit_type(u)
	costs := movement_costs(g, unit)
	best := u.pos
	best_score := [2]int{ai_enemy_score(g, u.faction, ut, u.pos), 0}
	for row in 0 ..< ROWS {
		for col in 0 ..< COLS {
			h := Hex{col, row}
			if !can_move(g, unit, h, &costs) { continue }
			score := [2]int{ai_enemy_score(g, u.faction, ut, h), costs[row][col]}
			if score.x < best_score.x || (score.x == best_score.x && score.y < best_score.y) {
				best = h
				best_score = score
			}
		}
	}
	if best != u.pos { move_unit(g, unit, best) }
	if t := ai_pick_target(g, unit); t >= 0 { attack(g, unit, t) }
}

// 0 when an enemy would be in attack range from h, else the distance to the
// nearest enemy (lower is better).
ai_enemy_score :: proc(g: ^Game, faction: int, ut: ^Unit_Type, h: Hex) -> int {
	nearest := max(int)
	for i in 0 ..< g.unit_count {
		e := &g.units[i]
		if !e.alive || e.faction == faction { continue }
		d := hex_distance(h, e.pos)
		if d >= ut.min_range && d <= ut.max_range { return 0 }
		nearest = min(nearest, d)
	}
	return nearest
}
