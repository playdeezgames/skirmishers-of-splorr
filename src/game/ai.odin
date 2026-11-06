package game

// The computer plays one unit per ai_step, so the page can show each action.

is_computer_turn :: proc(g: ^Game) -> bool {
	return g.winner < 0 && g.factions[g.current].controller == .Computer
}

// Does one thing for the computer: acts with its next unit, or ends its turn once
// every unit is done. Returns false when it is not the computer's turn.
ai_step :: proc(g: ^Game) -> bool {
	if !is_computer_turn(g) { return false }
	// Wololos first, so a blessing can be spent on an attack this turn
	for i in 0 ..< g.unit_count {
		u := &g.units[i]
		if u.alive && u.faction == g.current && !u.done && unit_type(u).chants {
			ai_chanter_unit(g, i)
			u.done = true
			return true
		}
	}
	for i in 0 ..< g.unit_count {
		u := &g.units[i]
		if u.alive && u.faction == g.current && !u.done {
			if g.factions[g.current].ai == .Basic {
				ai_unit(g, i)
			} else {
				ai_tactical_unit(g, i)
			}
			u.done = true
			return true
		}
	}
	f := g.current
	g.ai_held[f] = g.ai_held[f] + 1 if g.ai_holding[f] else 0
	g.ai_holding[f] = false
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

// The living enemy in range with the fewest body points, or -1 (basic style).
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
	scout_pos:   Hex, // also where the unit itself stands, when it is the scout
	goal:        Hex,
	friends:     [MAX_UNITS]Hex, // where the rest of the side stands (for the scout's leash)
	friend_count: int,
	self_pos:    Hex,
	pikes:       [MAX_UNITS]Hex, // enemy pikes in sight that have not struck first this turn
	pike_count:  int,
}

SCOUT_LEAD :: 2
SCOUT_LEASH :: 4 // hexes the scout may get ahead of its nearest friend

ai_view :: proc(g: ^Game, unit: int) -> (v: Ai_View) {
	f := g.units[unit].faction
	v.self_pos = g.units[unit].pos
	for i in 0 ..< g.unit_count {
		e := &g.units[i]
		if !e.alive || e.faction == f { continue }
		if unit_visible(g, i, f) && !e.reacted && .Pike in unit_type(e).weapons {
			v.pikes[v.pike_count] = e.pos
			v.pike_count += 1
		}
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
	for i in 0 ..< g.unit_count {
		u := &g.units[i]
		if i == unit || !u.alive || u.faction != f { continue }
		v.friends[v.friend_count] = u.pos
		v.friend_count += 1
	}
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
		if view.is_scout {
			// ahead, but not so far that it meets the enemy alone
			lag := 0
			if view.friend_count > 0 {
				nearest := max(int)
				for p in view.friends[:view.friend_count] { nearest = min(nearest, hex_distance(h, p)) }
				lag = max(0, nearest - SCOUT_LEASH)
			}
			return 2 + hex_distance(h, view.goal) + lag * 2
		}
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

// ---------------------------------------------------------------- tactical style

// The tactical computer player:
//   - It keeps out of the enemy's reach until it can strike first: a hex no
//     known enemy could attack next turn ("safe") beats any hex closer in that
//     is not, unless the unit can attack from it. After HOLD_TURNS turns in a
//     row of holding back with no attack by anyone it advances anyway, so two
//     careful sides cannot wait for ever.
//   - Among equally good hexes it prefers safe ones, high ground (melee
//     advantage, longer sling shots) and forest (hidden beyond 2 hexes, and
//     shots cannot pass through it), then the cheapest move.
//   - It attacks the target it is likeliest to hurt: not fortified, not holding
//     the high ground against it, a slinger before a kobold.
//   - It fortifies only when it cannot get out of reach and cannot attack.
//   - It would rather not step next to an enemy pike that has yet to strike
//     first this turn (PIKE_DREAD), all else being equal.
//   - With no enemy known, its scout would rather end in forest (hidden beyond
//     2 hexes) than gain SCOUT_COVER more hexes.
// Holding back stops once anyone has attacked in the last round: by then it
// would leave the units already fighting on their own.
// Simulator, November 6, 2026 (tactical blue vs basic red, 400 games each):
// 4k 54%, 2k2s 53%, 2k2s on 35% hills 55%, 2k2s in 50% forest 54%; 15k5s 48%
// (300 games, about even). Making the first attack is worth less than it
// looks: one dagger blow kills 2 times in 9, and the whole line strikes back.

HOLD_TURNS :: 2
PIKE_DREAD :: 3 // terrain-bonus points a hex loses for each ready enemy pike next to it
SCOUT_COVER :: 2 // hexes of progress a scout gives up to end its move in forest

// Hexes some known enemy (in sight, or at its last-seen marker) could attack next turn: from every hex it could
// reach with its full movement, everything within its longest reach (half
// again from high ground for ranged weapons). Line of sight is ignored, so
// this errs on the side of caution. Cached until the turn, the known enemies
// or the living units change.
Ai_Threat :: struct {
	mask:  Hex_Mask,
	key:   [4]u64, // turn and side to move, known enemies, living units, where
	ready: bool,
}

ai_threat_map :: proc(g: ^Game, faction: int) -> ^Hex_Mask {
	// each known enemy, where it is or was last seen
	believed: [MAX_UNITS]Hex
	known, living, places: u64
	for i in 0 ..< g.unit_count {
		u := &g.units[i]
		if !u.alive { continue }
		living |= 1 << u64(i)
		if u.faction == faction { continue }
		pos, seen := u.pos, unit_visible(g, i, faction)
		if !seen { pos, seen = sighting(g, faction, i) }
		if !seen { continue }
		known |= 1 << u64(i)
		believed[i] = pos
		places = places * 31 + u64(pos.y * COLS + pos.x) + 1
	}
	key := [4]u64{u64(g.turn) << 8 | u64(g.current), known, living, places}
	t := &g.ai_threat[faction]
	if t.ready && t.key == key { return &t.mask }
	t.mask = {}
	for i in 0 ..< g.unit_count {
		if known & (1 << u64(i)) == 0 { continue }
		area := ai_enemy_reach(g, faction, i, believed[i])
		for r in 0 ..< ROWS { t.mask[r] |= area[r] }
	}
	t.key = key
	t.ready = true
	return &t.mask
}

// One enemy's share of the threat map, cached for the turn while it is
// believed to stand on the same hex (our own units moving can change its
// paths a little; that is ignored until the next turn).
Ai_Reach :: struct {
	mask: Hex_Mask,
	key:  [3]int, // turn, side to move, believed hex (as an index)
	ready: bool,
}

ai_enemy_reach :: proc(g: ^Game, faction, i: int, at: Hex) -> Hex_Mask {
	key := [3]int{g.turn, g.current, at.y * COLS + at.x}
	cache := &g.ai_reach[faction][i]
	if cache.ready && cache.key == key { return cache.mask }
	e := &g.units[i]
	et := unit_type(e)
	_, reach := unit_reach(et)
	if reach == 0 { return {} } // no weapon (a Wololo): it threatens nobody
	budget := et.move * HALVES_PER_POINT
	// plan from where we believe it is
	real := e.pos
	e.pos = at
	costs := movement_costs(g, i, faction)
	e.pos = real
	// where it can stand, grown by its reach (half again from high ground for
	// a ranged weapon)
	stand: Hex_Mask
	for row in 0 ..< ROWS {
		for col in 0 ..< COLS {
			c := costs[row][col]
			if c != UNREACHABLE && c <= budget { mask_set(&stand, Hex{col, row}) }
		}
	}
	area := mask_grow(stand, reach)
	if reach > 1 {
		high := mask_grow(mask_from(g, &stand, true), reach * 3 / 2)
		for r in 0 ..< ROWS { area[r] |= high[r] }
	}
	cache^ = {area, key, true}
	return area
}

// The hexes of m on high ground (high = true) or low ground.
mask_from :: proc(g: ^Game, m: ^Hex_Mask, high: bool) -> (out: Hex_Mask) {
	for row in 0 ..< ROWS {
		for col in 0 ..< COLS {
			h := Hex{col, row}
			if mask_has(m, h) && is_high(g, h) == high { mask_set(&out, h) }
		}
	}
	return
}

// m plus every hex within `rings` steps of a hex in m. Done on the bits: on
// this staggered map a hex's neighbours are the two beside it, and in the rows
// above and below the hex itself and the one to its left (even rows) or right
// (odd rows).
mask_grow :: proc(m: Hex_Mask, rings: int) -> Hex_Mask {
	FULL :: u32(1 << COLS) - 1
	m := m
	for _ in 0 ..< rings {
		out: Hex_Mask
		for row in 0 ..< ROWS {
			r := m[row]
			if r == 0 { continue }
			out[row] |= r | (r << 1) | (r >> 1)
			// in an odd row the hexes above and below sit at col and col+1;
			// in an even row at col-1 and col
			spread := r | (r << 1) if row % 2 == 1 else r | (r >> 1)
			if row > 0 { out[row - 1] |= spread }
			if row < ROWS - 1 { out[row + 1] |= spread }
		}
		for row in 0 ..< ROWS { out[row] &= FULL }
		m = out
	}
	return m
}

// Score of a hex for the tactical style: lower is better, compared in order.
//   [0] what the unit can do from it: 0 ranged shot with no enemy adjacent,
//       1 any attack, 2+ approach (2 + distance as in ai_hex_score), and
//       HOLD_PENALTY more for an approach hex inside the threat map while
//       holding back
//   [1] minus its terrain bonus (safe 4, high ground 2, forest 1)
//   [2] movement cost
HOLD_PENALTY :: 1000

ai_tactical_score :: proc(g: ^Game, faction: int, ut: ^Unit_Type, h: Hex, view: ^Ai_View, threat: ^Hex_Mask, hold: bool) -> [2]int {
	what := ai_hex_score(g, faction, ut, h, view)
	unsafe := mask_has(threat, h)
	if what >= 2 && unsafe && hold { what += HOLD_PENALTY }
	// a scout in forest sees out but is hidden beyond FOREST_SIGHT: worth a
	// little ground. Not for the hex it already stands on, or a scout held back
	// by its leash could stay in a wood for ever (seen in tools/sim.sh 2h2x
	// 2h2a, seed 1034: both sides stood still from turn 20 on)
	if what >= 2 && view.spot_count == 0 && view.is_scout && h != view.scout_pos && terrain_at(g, h) == .Forest { what -= SCOUT_COVER }
	bonus := 0
	// stepping next to a pike that has not struck yet this turn draws its blow
	if h != view.self_pos {
		for p in view.pikes[:view.pike_count] { if hex_distance(h, p) == 1 { bonus -= PIKE_DREAD } }
	}
	if !unsafe { bonus += 4 }
	if is_high(g, h) { bonus += 2 }
	if terrain_at(g, h) == .Forest { bonus += 1 }
	return {what, -bonus}
}

ai_tactical_unit :: proc(g: ^Game, unit: int) {
	u := &g.units[unit]
	ut := unit_type(u)
	f := u.faction
	view := ai_view(g, unit)
	threat := ai_threat_map(g, f)
	// hold back only from enemies it knows of, before the fighting starts (once
	// it has, holding back would leave the units in it to fight alone), and
	// not for ever
	in_contact := g.contact_turn > 0 && g.turn - g.contact_turn <= 1
	hold := view.spot_count > 0 && !in_contact && g.ai_held[f] < HOLD_TURNS
	costs := movement_costs(g, unit)
	best := u.pos
	s := ai_tactical_score(g, f, ut, u.pos, &view, threat, hold)
	best_score := [3]int{s.x, s.y, 0}
	closest_unsafe := max(int) // nearest approach hex given up for safety
	for row in 0 ..< ROWS {
		for col in 0 ..< COLS {
			h := Hex{col, row}
			if !can_move(g, unit, h, &costs) { continue }
			s = ai_tactical_score(g, f, ut, h, &view, threat, hold)
			if s.x >= HOLD_PENALTY { closest_unsafe = min(closest_unsafe, s.x - HOLD_PENALTY) }
			score := [3]int{s.x, s.y, costs[row][col]}
			if score.x < best_score.x || (score.x == best_score.x && (score.y < best_score.y || (score.y == best_score.y && score.z < best_score.z))) {
				best = h
				best_score = score
			}
		}
	}
	if best_score.x >= 2 && best_score.x < HOLD_PENALTY && closest_unsafe < best_score.x {
		g.ai_holding[f] = true // it could have gone closer, but waited
	}
	// cannot attack and cannot get out of reach: dig in
	if best_score.x >= HOLD_PENALTY || (best_score.x >= 2 && !hold && mask_has(threat, best)) {
		if can_fortify(g, unit) && ai_threatened(g, unit) {
			fortify(g, unit)
			return
		}
	}
	if best != u.pos { move_unit(g, unit, best) }
	if t := ai_tactical_target(g, unit); t >= 0 { attack(g, unit, t) }
}

// The target the unit is likeliest to hurt (see ai_tactical_unit), or -1.
ai_tactical_target :: proc(g: ^Game, unit: int) -> int {
	a := &g.units[unit]
	best, best_score := -1, min(int)
	for i in 0 ..< g.unit_count {
		w, ok := attack_weapon(g, unit, i)
		if !ok { continue }
		t := &g.units[i]
		atk_adv, def_adv := combat_advantage(g, a.pos, t.pos, t.fortified)
		score := dice_strength(WEAPONS[w].attack) * 4 - dice_strength(defence_against(unit_type(t), w)) * 4 - t.body * 8
		if def_adv { score -= 3 }
		if atk_adv { score += 2 }
		switch t.boon {
		case .Cursed:  score += 3 // it defends with disadvantage
		case .Blessed: score -= 3
		case .None:
		}
		_, reach := unit_reach(unit_type(t))
		if reach > 1 { score += 1 } // ranged enemies first
		if score > best_score {
			best = i
			best_score = score
		}
	}
	return best
}

// ---------------------------------------------------------------- Wololo

// How much a blessing or curse on unit t is worth to faction f now (0: none).
// A friend that can strike this turn gains most (its attack is next); one in
// an enemy's reach gains on defence. An enemy within our units' reach loses
// most. Worth more on units worth more points.
ai_chant_value :: proc(g: ^Game, f: int, t: int, threat: ^Hex_Mask) -> int {
	u := &g.units[t]
	if !u.alive || u.boon != .None { return 0 }
	weight := unit_type(u).points
	if u.faction == f {
		strike := !u.done && !u.attacked
		if strike {
			for i in 0 ..< g.unit_count {
				if can_attack(g, t, i) { return 3 * weight }
			}
		}
		if mask_has(threat, u.pos) { return 2 * weight }
		return 0
	}
	if !unit_visible(g, t, f) { return 0 }
	// an enemy our units could reach: it will roll when we attack it, or when
	// it attacks us
	for i in 0 ..< g.unit_count {
		o := &g.units[i]
		if !o.alive || o.faction != f || i == t { continue }
		_, reach := unit_reach(unit_type(o))
		if reach > 0 && hex_distance(o.pos, u.pos) <= reach + unit_type(o).move { return 2 * weight }
	}
	return 0
}

// The best target for the Wololo standing on `from` (ignoring that it may not
// be there yet), and what it is worth.
ai_best_chant :: proc(g: ^Game, caster: int, from: Hex, threat: ^Hex_Mask) -> (best, value: int) {
	c := &g.units[caster]
	best = -1
	for i in 0 ..< g.unit_count {
		t := &g.units[i]
		if i == caster || !t.alive || !unit_visible(g, i, c.faction) { continue }
		d := hex_distance(from, t.pos)
		if d > CHANT_RANGE || (d > 1 && !line_of_sight(g, from, t.pos, c.faction)) { continue }
		if v := ai_chant_value(g, c.faction, i, threat); v > value {
			best = i
			value = v
		}
	}
	return
}

// A Wololo moves to where its best chant is worth most, keeping out of the
// enemy's reach if it can, then chants. With nothing worth chanting it
// approaches like any unit, staying CHANT_RANGE back from the nearest enemy.
ai_chanter_unit :: proc(g: ^Game, unit: int) {
	u := &g.units[unit]
	f := u.faction
	view := ai_view(g, unit)
	threat := ai_threat_map(g, f)
	costs := movement_costs(g, unit)
	score :: proc(g: ^Game, unit: int, h: Hex, view: ^Ai_View, threat: ^Hex_Mask) -> [2]int {
		_, value := ai_best_chant(g, unit, h, threat)
		unsafe := 1 if mask_has(threat, h) else 0
		approach := 0
		if value == 0 {
			if view.spot_count == 0 {
				approach = hex_distance(h, view.scout_pos) // follow the scout
			} else {
				nearest := max(int)
				for p in view.spots[:view.spot_count] { nearest = min(nearest, hex_distance(h, p)) }
				approach = abs(nearest - CHANT_RANGE)
			}
		}
		return {-value * 4 + unsafe * 40 + approach, 0}
	}
	best := u.pos
	best_score := score(g, unit, u.pos, &view, threat)
	for row in 0 ..< ROWS {
		for col in 0 ..< COLS {
			h := Hex{col, row}
			if !can_move(g, unit, h, &costs) { continue }
			sc := score(g, unit, h, &view, threat)
			sc.y = costs[row][col]
			if sc.x < best_score.x || (sc.x == best_score.x && sc.y < best_score.y) {
				best = h
				best_score = sc
			}
		}
	}
	if best != u.pos { move_unit(g, unit, best) }
	if !u.alive { return } // a pike may have struck it on the way
	if t, value := ai_best_chant(g, unit, u.pos, threat); value > 0 {
		chant(g, unit, t)
	} else if can_fortify(g, unit) && mask_has(threat, u.pos) && ai_threatened(g, unit) {
		fortify(g, unit)
	}
}
