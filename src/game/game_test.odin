#+build !js
package game

import "core:strings"
import "core:testing"

// A blank all-grass map with two factions and no units.
blank_game :: proc(g: ^Game, seed: u64 = 1) {
	g^ = {}
	g.winner = -1
	g.turn = 1
	g.rng = {seed}
	add_faction(g, "Red", .Human, RED)
	add_faction(g, "Blue", .Computer, BLUE)
}

@(test)
test_neighbours_are_distance_one :: proc(t: ^testing.T) {
	for h in ([]Hex{{5, 5}, {5, 6}, {0, 0}, {19, 19}, {0, 7}}) {
		nbs, n := neighbours(h)
		for nb in nbs[:n] {
			testing.expect_value(t, hex_distance(h, nb), 1)
		}
	}
	_, n := neighbours({5, 5})
	testing.expect_value(t, n, 6)
	_, corner := neighbours({0, 0})
	testing.expect_value(t, corner, 2)
}

@(test)
test_distance_on_staggered_rows :: proc(t: ^testing.T) {
	testing.expect_value(t, hex_distance({0, 0}, {5, 0}), 5)
	testing.expect_value(t, hex_distance({0, 0}, {0, 2}), 2)
	// odd row is shifted right, so {0,1} touches {0,0} and {1,0}
	testing.expect_value(t, hex_distance({0, 1}, {1, 0}), 1)
	testing.expect_value(t, hex_distance({1, 1}, {0, 0}), 2)
}

@(test)
test_pixel_round_trip :: proc(t: ^testing.T) {
	for row in 0 ..< ROWS {
		for col in 0 ..< COLS {
			h := Hex{col, row}
			p := hex_to_pixel(h, 18)
			testing.expect_value(t, pixel_to_hex(p, 18), h)
			testing.expect_value(t, pixel_to_hex(p + {6, -5}, 18), h)
		}
	}
}

@(test)
test_dice_odds :: proc(t: ^testing.T) {
	r := Rng{42}
	N :: 60000
	for d in Die {
		scores := 0
		for _ in 0 ..< N {
			if roll_die(&r, d) { scores += 1 }
		}
		want := N * DIE_SCORE_SIXTHS[d] / 6
		testing.expectf(t, abs(scores - want) < N / 100, "%v die: %d scores, expected about %d", d, scores, want)
	}
}

@(test)
test_forest_costs_two :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	k := add_unit(&g, .Kobold, 0, {5, 5})
	g.terrain[5][6] = .Forest
	costs := movement_costs(&g, k)
	H :: HALVES_PER_POINT
	testing.expect_value(t, costs[5][6], 2 * H)
	testing.expect_value(t, costs[5][4], 1 * H)
	testing.expect_value(t, costs[5][8], 4 * H) // forest 2, then two grass
	testing.expect_value(t, costs[5][9], 5 * H) // through or around the forest
	testing.expect(t, can_move(&g, k, {8, 5}, &costs))
	testing.expect(t, !can_move(&g, k, {9, 5}, &costs))
}

@(test)
test_move_spends_points :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	k := add_unit(&g, .Kobold, 0, {5, 5})
	g.terrain[5][6] = .Forest
	testing.expect(t, move_unit(&g, k, {6, 5}))
	testing.expect_value(t, g.units[k].moves_left, 2 * HALVES_PER_POINT)
	testing.expect(t, move_unit(&g, k, {8, 5}))
	testing.expect_value(t, g.units[k].moves_left, 0)
	testing.expect(t, !move_unit(&g, k, {9, 5}))
}

@(test)
test_enemies_block_friends_do_not :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	k := add_unit(&g, .Kobold, 0, {0, 0})
	// a corridor along row 0: forest everywhere else nearby is too costly
	for row in 1 ..< ROWS { for col in 0 ..< COLS { g.terrain[row][col] = .Forest } }
	add_unit(&g, .Kobold, 0, {1, 0})
	costs := movement_costs(&g, k)
	testing.expect_value(t, costs[0][2], 2 * HALVES_PER_POINT) // through the friend
	testing.expect(t, !can_move(&g, k, {1, 0}, &costs)) // but not onto it

	g.units[1].faction = 1
	costs = movement_costs(&g, k)
	testing.expect(t, costs[0][2] != 2 * HALVES_PER_POINT) // the enemy blocks the corridor
}

@(test)
test_melee_range_only :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	a := add_unit(&g, .Kobold, 0, {5, 5})
	b := add_unit(&g, .Kobold, 1, {7, 5})
	friend := add_unit(&g, .Kobold, 0, {4, 5})
	testing.expect(t, !can_attack(&g, a, b))
	testing.expect(t, !can_attack(&g, a, friend))
	g.units[b].pos = {6, 5}
	testing.expect(t, can_attack(&g, a, b))
}

@(test)
test_attack_once_per_turn_and_damage :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g, 7)
	a := add_unit(&g, .Kobold, 0, {5, 5})
	b := add_unit(&g, .Kobold, 1, {6, 5})
	res, ok := attack(&g, a, b)
	testing.expect(t, ok)
	testing.expect_value(t, res.damage, max(0, res.hits - res.blocks))
	testing.expect_value(t, res.killed, res.damage >= 1)
	testing.expect_value(t, g.units[b].alive, !res.killed)
	_, again := attack(&g, a, b)
	testing.expect(t, !again)
}

@(test)
test_kill_wins_the_game :: proc(t: ^testing.T) {
	g: Game
	// find a seed whose first attack kills
	for seed in u64(1) ..< 200 {
		blank_game(&g, seed)
		a := add_unit(&g, .Kobold, 0, {5, 5})
		b := add_unit(&g, .Kobold, 1, {6, 5})
		res, _ := attack(&g, a, b)
		if res.killed {
			testing.expect_value(t, g.winner, 0)
			return
		}
	}
	testing.fail_now(t, "no killing roll in 200 seeds")
}

@(test)
test_end_turn_resets_next_faction :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	add_unit(&g, .Kobold, 0, {2, 2})
	b := add_unit(&g, .Kobold, 1, {10, 10})
	g.units[b].moves_left = 0
	g.units[b].attacked = true
	testing.expect(t, !end_turn(&g), "red's kobold has not ended its move")
	testing.expect(t, finish_move(&g, 0))
	testing.expect(t, end_turn(&g))
	testing.expect_value(t, g.current, 1)
	testing.expect_value(t, g.units[b].moves_left, 4 * HALVES_PER_POINT)
	testing.expect(t, !g.units[b].attacked)
	testing.expect(t, !g.units[b].done)
	finish_move(&g, b)
	testing.expect(t, end_turn(&g))
	testing.expect_value(t, g.current, 0)
	testing.expect_value(t, g.turn, 2)
}

@(test)
test_scenario_setup :: proc(t: ^testing.T) {
	g: Game
	new_game(&g, 0, 12345)
	testing.expect_value(t, g.faction_count, 2)
	testing.expect_value(t, g.factions[0].controller, Controller.Human)
	testing.expect_value(t, g.factions[1].controller, Controller.Computer)
	testing.expect_value(t, living_units(&g, 0), 4)
	testing.expect_value(t, living_units(&g, 1), 4)
	forest := 0
	for row in g.terrain { for tr in row { if tr == .Forest { forest += 1 } } }
	testing.expect(t, forest > 10 && forest < ROWS * COLS / 3, "mostly grass with some forest")
	for i in 0 ..< g.unit_count {
		u := g.units[i]
		testing.expect(t, terrain_at(&g, u.pos) != .Forest, "units start in the open")
	}
}

@(test)
test_ai_closes_in :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	g.current = 1
	add_unit(&g, .Kobold, 0, {2, 10})
	b := add_unit(&g, .Kobold, 1, {17, 10})
	start_faction_turn(&g)
	before := hex_distance(g.units[0].pos, g.units[b].pos)
	ai_take_turn(&g)
	testing.expect_value(t, hex_distance(g.units[0].pos, g.units[b].pos), before - 4)
	testing.expect_value(t, g.current, 0) // handed back to the player
}

// Computer against computer must always reach a winner.
@(test)
test_watch_games_finish :: proc(t: ^testing.T) {
	g: Game
	for seed in u64(1) ..= 50 {
		new_game(&g, 1, seed)
		for steps := 0; g.winner < 0 && steps < 20000; steps += 1 {
			ai_step(&g)
		}
		testing.expectf(t, g.winner >= 0, "seed %d: no winner", seed)
		testing.expectf(t, g.turn < 60, "seed %d: took %d turns", seed, g.turn)
	}
}

@(test)
test_road_costs :: proc(t: ^testing.T) {
	H :: HALVES_PER_POINT
	testing.expect_value(t, step_cost(.Road, .Road, false, false), 1) // half a point
	testing.expect_value(t, step_cost(.Grass, .Road, false, false), 1 * H)
	testing.expect_value(t, step_cost(.Road, .Grass, false, false), 1 * H)
	testing.expect_value(t, step_cost(.Road, .Forest, false, false), 2 * H)

	g: Game
	blank_game(&g)
	for col in 0 ..< COLS { g.terrain[10][col] = .Road }
	g.terrain[10][19] = .Forest
	k := add_unit(&g, .Kobold, 0, {2, 10})
	costs := movement_costs(&g, k)
	testing.expect_value(t, costs[10][10], 8) // 8 road steps: 4 points
	testing.expect(t, can_move(&g, k, {10, 10}, &costs))
	testing.expect(t, !can_move(&g, k, {11, 10}, &costs))
	testing.expect_value(t, costs[10][19], 16 + 2 * H) // 16 road steps, then forest at full cost
	// half points are spent and left over correctly
	testing.expect(t, move_unit(&g, k, {5, 10}))
	testing.expect_value(t, g.units[k].moves_left, 5)
}

// Walks the road from a hex on the first edge and checks it reaches the far edge.
road_crosses :: proc(g: ^Game, dir: Road_Direction) -> bool {
	seen: [ROWS][COLS]bool
	stack: [ROWS * COLS]Hex
	top := 0
	for i in 0 ..< (ROWS if dir == .East_West else COLS) {
		h := Hex{0, i} if dir == .East_West else Hex{i, 0}
		if terrain_at(g, h) == .Road && !seen[h.y][h.x] {
			seen[h.y][h.x] = true
			stack[top] = h
			top += 1
		}
	}
	for top > 0 {
		top -= 1
		h := stack[top]
		if (dir == .East_West && h.x == COLS - 1) || (dir == .North_South && h.y == ROWS - 1) { return true }
		nbs, n := neighbours(h)
		for nb in nbs[:n] {
			if terrain_at(g, nb) == .Road && !seen[nb.y][nb.x] {
				seen[nb.y][nb.x] = true
				stack[top] = nb
				top += 1
			}
		}
	}
	return false
}

@(test)
test_road_spans_the_map :: proc(t: ^testing.T) {
	g: Game
	for seed in u64(1) ..= 100 {
		for dir in Road_Direction {
			blank_game(&g, seed)
			generate_road(&g, dir)
			testing.expectf(t, road_crosses(&g, dir), "seed %d %v: road does not cross", seed, dir)
		}
	}
}

@(test)
test_scenario_has_a_road :: proc(t: ^testing.T) {
	g: Game
	seen: [Road_Direction]bool
	for seed in u64(1) ..= 40 {
		new_game(&g, 0, seed)
		ew := road_crosses(&g, .East_West)
		ns := road_crosses(&g, .North_South)
		testing.expectf(t, ew || ns, "seed %d: no road across the map", seed)
		if ew { seen[.East_West] = true }
		if ns { seen[.North_South] = true }
	}
	testing.expect(t, seen[.East_West] && seen[.North_South], "both road directions occur")
}

@(test)
test_attack_ends_movement :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	a := add_unit(&g, .Kobold, 0, {5, 5})
	b := add_unit(&g, .Kobold, 1, {6, 5})
	testing.expect(t, !unit_finished(&g, a))
	_, ok := attack(&g, a, b)
	testing.expect(t, ok)
	testing.expect_value(t, g.units[a].moves_left, 0)
	testing.expect(t, !move_unit(&g, a, {4, 5}), "no moving after an attack")
	testing.expect(t, unit_finished(&g, a))
}

@(test)
test_moved_then_finished :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	a := add_unit(&g, .Kobold, 0, {2, 5})
	add_unit(&g, .Kobold, 1, {15, 5})
	testing.expect(t, !unit_has_moved(&g, a))
	testing.expect(t, move_unit(&g, a, {4, 5}))
	testing.expect(t, unit_has_moved(&g, a))
	testing.expect(t, !unit_finished(&g, a), "movement left")
	testing.expect(t, move_unit(&g, a, {6, 5}))
	testing.expect(t, unit_finished(&g, a), "no movement and nobody in range")

	// out of movement but next to an enemy: it may still attack
	g.units[1].pos = {7, 5}
	testing.expect(t, !unit_finished(&g, a))
}

@(test)
test_kobold_battle :: proc(t: ^testing.T) {
	g: Game
	for seed in u64(1) ..= 10 {
		new_game(&g, 2, seed)
		testing.expect_value(t, living_units(&g, 0), 20)
		testing.expect_value(t, living_units(&g, 1), 20)
		slingers: [2]int
		for i in 0 ..< g.unit_count { if g.units[i].kind == .Kobold_Slinger { slingers[g.units[i].faction] += 1 } }
		testing.expect_value(t, slingers, [2]int{5, 5})
		for steps := 0; g.winner < 0 && steps < 50000; steps += 1 {
			ai_step(&g)
		}
		testing.expectf(t, g.winner >= 0, "seed %d: no winner", seed)
		testing.expectf(t, g.turn < 100, "seed %d: took %d turns", seed, g.turn)
	}
}

@(test)
test_weapon_table :: proc(t: ^testing.T) {
	testing.expect_value(t, WEAPONS[.Dagger].attack[.White], 1)
	testing.expect_value(t, WEAPONS[.Dagger].min_range, 1)
	testing.expect_value(t, WEAPONS[.Dagger].max_range, 1)
	testing.expect_value(t, WEAPONS[.Sling].attack[.White], 1)
	testing.expect_value(t, WEAPONS[.Sling].min_range, 2)
	testing.expect_value(t, WEAPONS[.Sling].max_range, 3)
	testing.expect_value(t, UNIT_TYPES[.Kobold].weapons, Weapons{.Dagger})
	testing.expect_value(t, UNIT_TYPES[.Kobold_Slinger].weapons, Weapons{.Sling, .Dagger})
}

@(test)
test_slinger_picks_weapon_by_range :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	s := add_unit(&g, .Kobold_Slinger, 0, {5, 5})
	e := add_unit(&g, .Kobold, 1, {6, 5})
	for d in 1 ..= 5 {
		g.units[e].pos = {5 + d, 5}
		w, ok := attack_weapon(&g, s, e)
		switch d {
		case 1:
			testing.expect(t, ok && w == .Dagger, "adjacent: dagger")
		case 2, 3:
			testing.expect(t, ok && w == .Sling, "2-3 hexes: sling")
		case:
			testing.expect(t, !ok, "beyond 3: nothing")
		}
	}
	// a plain kobold only has its dagger
	k := add_unit(&g, .Kobold, 0, {5, 8})
	g.units[e].pos = {7, 8}
	testing.expect(t, !can_attack(&g, k, e))
}

@(test)
test_sling_attack_logs_weapon :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	s := add_unit(&g, .Kobold_Slinger, 0, {5, 5})
	e := add_unit(&g, .Kobold, 1, {8, 5})
	res, ok := attack(&g, s, e)
	testing.expect(t, ok)
	testing.expect_value(t, res.weapon, Weapon_Kind.Sling)
	testing.expect(t, strings.contains(log_line(&g, res.killed ? 1 : 0), "slings"), log_line(&g, 0))
}

@(test)
test_ai_slinger_keeps_distance :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	g.current = 1
	add_unit(&g, .Kobold, 0, {5, 10})
	s := add_unit(&g, .Kobold_Slinger, 1, {10, 10}) // 5 away: one move from sling range
	start_faction_turn(&g)
	ai_take_turn(&g)
	d := hex_distance(g.units[s].pos, g.units[0].pos)
	testing.expect(t, d >= 2 && d <= 3, "moves into sling range, not adjacent")
	testing.expect(t, g.units[s].attacked)
}

@(test)
test_ai_slinger_steps_back_from_melee :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	g.current = 1
	add_unit(&g, .Kobold, 0, {5, 10})
	s := add_unit(&g, .Kobold_Slinger, 1, {6, 10})
	start_faction_turn(&g)
	ai_take_turn(&g)
	d := hex_distance(g.units[s].pos, g.units[0].pos)
	testing.expect(t, d >= 2 && d <= 3, "steps back to sling")
}

@(test)
test_four_kobold_teams_have_two_slingers :: proc(t: ^testing.T) {
	g: Game
	new_game(&g, 0, 9)
	slingers: [2]int
	for i in 0 ..< g.unit_count {
		if g.units[i].kind == .Kobold_Slinger { slingers[g.units[i].faction] += 1 }
	}
	testing.expect_value(t, slingers, [2]int{2, 2})
}

@(test)
test_forest_variants :: proc(t: ^testing.T) {
	g: Game
	for pct, k in ([]int{25, 50, 75}) {
		scenario := 3 + k
		testing.expect(t, strings.contains(SCENARIOS[scenario].name, "forest"), SCENARIOS[scenario].name)
		for seed in u64(1) ..= 30 {
			new_game(&g, scenario, seed)
			testing.expectf(t, forest_count(&g) == ROWS * COLS * pct / 100, "%d%% seed %d: %d forest hexes", pct, seed, forest_count(&g))
			testing.expectf(t, road_crosses(&g, .East_West) || road_crosses(&g, .North_South), "%d%% seed %d: road broken", pct, seed)
			for i in 0 ..< g.unit_count {
				testing.expect(t, terrain_at(&g, g.units[i].pos) != .Forest, "units start in the open")
			}
			testing.expect_value(t, living_units(&g, 0), 4)
			testing.expect_value(t, g.factions[0].controller, Controller.Human)
		}
	}
}

// The computer still finishes games in dense forest.
@(test)
test_dense_forest_games_finish :: proc(t: ^testing.T) {
	g: Game
	for seed in u64(1) ..= 20 {
		new_game(&g, 5, seed)
		g.factions[0].controller = .Computer
		for steps := 0; g.winner < 0 && steps < 20000; steps += 1 { ai_step(&g) }
		testing.expectf(t, g.winner >= 0, "seed %d: no winner", seed)
	}
}

@(test)
test_finish_move :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	a := add_unit(&g, .Kobold, 0, {2, 5})
	b := add_unit(&g, .Kobold, 0, {2, 8})
	e := add_unit(&g, .Kobold, 1, {15, 5})
	testing.expect_value(t, units_left_to_act(&g), 2)
	testing.expect(t, move_unit(&g, a, {3, 5}))
	testing.expect(t, finish_move(&g, a))
	testing.expect(t, !finish_move(&g, a), "already ended")
	testing.expect(t, !move_unit(&g, a, {4, 5}), "no moving after ending")
	testing.expect(t, unit_finished(&g, a))
	testing.expect_value(t, units_left_to_act(&g), 1)
	testing.expect(t, !end_turn(&g), "b has not ended")
	testing.expect(t, !finish_move(&g, e), "not blue's turn")
	testing.expect(t, finish_move(&g, b))
	testing.expect(t, end_turn(&g))
	testing.expect_value(t, g.current, 1)
}

@(test)
test_attacking_ends_the_unit :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	a := add_unit(&g, .Kobold, 0, {5, 5})
	add_unit(&g, .Kobold, 1, {6, 5})
	add_unit(&g, .Kobold, 1, {15, 15}) // so one kill does not end the game
	attack(&g, a, 1)
	testing.expect(t, g.units[a].done)
	testing.expect_value(t, units_left_to_act(&g), 0)
	testing.expect(t, end_turn(&g))
}

// A unit with no movement left and nobody in reach is over without being ended.
@(test)
test_stuck_unit_counts_as_ended :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	a := add_unit(&g, .Kobold, 0, {2, 5})
	add_unit(&g, .Kobold, 1, {15, 5})
	g.units[a].moves_left = 0
	testing.expect_value(t, units_left_to_act(&g), 0)
	testing.expect(t, end_turn(&g))
}

@(test)
test_hexes_between :: proc(t: ^testing.T) {
	line, n := hexes_between({2, 5}, {6, 5}, 1)
	testing.expect_value(t, n, 3)
	for h, i in line[:n] { testing.expect_value(t, h, Hex{3 + i, 5}) }
	_, adjacent := hexes_between({2, 5}, {3, 5}, 1)
	testing.expect_value(t, adjacent, 0)
	// every step of the line is one hex from the last
	for nudge in ([]f64{1, -1}) {
		l, m := hexes_between({1, 2}, {9, 15}, nudge)
		prev := Hex{1, 2}
		for h in l[:m] {
			testing.expect_value(t, hex_distance(prev, h), 1)
			prev = h
		}
		testing.expect_value(t, hex_distance(prev, {9, 15}), 1)
	}
}

@(test)
test_forest_blocks_slings :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	s := add_unit(&g, .Kobold_Slinger, 0, {5, 5})
	e := add_unit(&g, .Kobold, 1, {8, 5})
	testing.expect(t, can_attack(&g, s, e))
	g.terrain[5][6] = .Forest // between them
	testing.expect(t, !line_of_sight(&g, {5, 5}, {8, 5}))
	testing.expect(t, !can_attack(&g, s, e), "forest in between blocks the sling")
	g.terrain[5][6] = .Grass

	// the end hexes do not block: shooting into or out of a forest is fine
	g.terrain[5][8] = .Forest
	g.terrain[5][5] = .Forest
	testing.expect(t, can_attack(&g, s, e))

	// melee ignores forest entirely
	g.units[e].pos = {6, 5}
	g.terrain[5][6] = .Forest
	w, ok := attack_weapon(&g, s, e)
	testing.expect(t, ok && w == .Dagger)
}

@(test)
test_edge_line_needs_one_clear_side :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	// two hexes apart along a cube diagonal (2,-1,-1): the line runs exactly
	// along the edge between the two hexes in the middle
	a := Hex{4, 4}
	b := from_cube(to_cube(a) + {2, -1, -1})
	testing.expect_value(t, hex_distance(a, b), 2)
	l1, _ := hexes_between(a, b, 1)
	l2, _ := hexes_between(a, b, -1)
	testing.expect(t, l1[0] != l2[0], "the line grazes an edge")
	g.terrain[l1[0].y][l1[0].x] = .Forest
	testing.expect(t, line_of_sight(&g, a, b), "one side clear")
	g.terrain[l2[0].y][l2[0].x] = .Forest
	testing.expect(t, !line_of_sight(&g, a, b), "both sides wooded")
}

@(test)
test_ai_slinger_finds_a_clear_shot :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	g.current = 1
	add_unit(&g, .Kobold, 0, {5, 10})
	s := add_unit(&g, .Kobold_Slinger, 1, {10, 10})
	// wood the whole ring at distance 1 from the target, except the far side
	nbs, n := neighbours({5, 10})
	for nb in nbs[:n] { if nb.x >= 5 { g.terrain[nb.y][nb.x] = .Forest } }
	start_faction_turn(&g)
	ai_take_turn(&g)
	u := g.units[s]
	if u.attacked {
		testing.expect(t, line_of_sight(&g, u.pos, g.units[0].pos) || hex_distance(u.pos, g.units[0].pos) == 1, "only shoots with a clear line")
	}
}

// Every pair of hexes within sling range, on a fully wooded map: no crash, and
// adjacent or edge-grazing pairs behave.
@(test)
test_line_of_sight_everywhere :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	for &row in g.terrain { for &tr in row { tr = .Forest } }
	for r1 in 0 ..< ROWS { for c1 in 0 ..< COLS {
		for r2 in max(0, r1 - 3) ..< min(ROWS, r1 + 4) { for c2 in max(0, c1 - 3) ..< min(COLS, c1 + 4) {
			a, b := Hex{c1, r1}, Hex{c2, r2}
			d := hex_distance(a, b)
			if d > 3 { continue }
			los := line_of_sight(&g, a, b)
			if d <= 1 { testing.expect(t, los, "adjacent hexes always see each other") }
			testing.expect_value(t, line_of_sight(&g, b, a), los) // symmetric
		} }
	} }
}

@(test)
test_advantage_odds :: proc(t: ^testing.T) {
	r := Rng{99}
	N :: 60000
	for d in Die {
		scores := 0
		for _ in 0 ..< N {
			one: Dice
			one[d] = 1
			scores += roll_dice(&r, one, advantage = true)
		}
		p := f64(DIE_SCORE_SIXTHS[d]) / 6
		want := int(f64(N) * (1 - (1 - p) * (1 - p))) // fail twice to fail
		testing.expectf(t, abs(scores - want) < N / 100, "%v die with advantage: %d, expected about %d", d, scores, want)
	}
}

@(test)
test_fortify_rules :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	a := add_unit(&g, .Kobold, 0, {5, 5})
	b := add_unit(&g, .Kobold, 0, {5, 8})
	e := add_unit(&g, .Kobold, 1, {6, 5})
	add_unit(&g, .Kobold, 1, {15, 15})
	testing.expect(t, fortify(&g, a))
	testing.expect(t, g.units[a].fortified)
	testing.expect(t, unit_finished(&g, a), "fortifying is the unit's turn")
	testing.expect(t, !can_attack(&g, a, e) || g.units[a].done)
	_, ok := attack(&g, a, e)
	testing.expect(t, !ok, "no attack after fortifying")
	testing.expect(t, !fortify(&g, a), "only once")
	testing.expect(t, !fortify(&g, e), "not on the enemy's turn")
	// moving first rules it out
	testing.expect(t, move_unit(&g, b, {5, 9}))
	testing.expect(t, !can_fortify(&g, b))
	finish_move(&g, b)

	// it lasts through the enemy's turn, and ends when its own side's turn starts
	testing.expect(t, end_turn(&g))
	testing.expect(t, g.units[a].fortified)
	res, hit := attack(&g, e, a)
	testing.expect(t, hit)
	testing.expect(t, res.fortified)
	finish_move(&g, 3)
	testing.expect(t, end_turn(&g))
	if g.units[a].alive {
		testing.expect(t, !g.units[a].fortified, "worn off at the start of red's turn")
	}
}

// White die kills: plain 1/3 * 2/3 = 22%; against a fortified white die,
// 1/3 * (2/3)^2 = 4/27 = 15%.
@(test)
test_fortified_units_survive_more :: proc(t: ^testing.T) {
	g: Game
	kills: [2]int
	N :: 4000
	for fort in 0 ..< 2 {
		for seed in u64(1) ..= N {
			blank_game(&g, seed + 100_000 * u64(fort))
			a := add_unit(&g, .Kobold, 0, {5, 5})
			d := add_unit(&g, .Kobold, 1, {6, 5})
			add_unit(&g, .Kobold, 1, {15, 15})
			g.units[d].fortified = fort == 1
			res, _ := attack(&g, a, d)
			if res.killed { kills[fort] += 1 }
		}
	}
	testing.expectf(t, abs(kills[0] - N * 2 / 9) < N / 40, "plain: %d kills", kills[0])
	testing.expectf(t, abs(kills[1] - N * 4 / 27) < N / 40, "fortified: %d kills", kills[1])
}

@(test)
test_ai_fortifies_when_outranged :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	g.current = 1
	add_unit(&g, .Kobold_Slinger, 0, {5, 10})
	k := add_unit(&g, .Kobold, 1, {11, 10}) // 6 away: cannot reach to stab, but the slinger can reach it
	g.factions[1].ai = .Basic // the tactical style steps out of reach instead
	start_faction_turn(&g)
	ai_take_turn(&g)
	testing.expect(t, g.units[k].fortified)
	testing.expect_value(t, g.units[k].pos, Hex{11, 10})
}

@(test)
test_ai_does_not_fortify_out_of_reach :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	g.current = 1
	add_unit(&g, .Kobold, 0, {2, 10})
	k := add_unit(&g, .Kobold, 1, {17, 10})
	start_faction_turn(&g)
	ai_take_turn(&g)
	testing.expect(t, !g.units[k].fortified)
	testing.expect(t, g.units[k].pos != Hex{17, 10}, "advances instead")
}

@(test)
test_enemies_block_slings_friends_do_not :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	s := add_unit(&g, .Kobold_Slinger, 0, {5, 5})
	target := add_unit(&g, .Kobold, 1, {8, 5})
	testing.expect(t, can_attack(&g, s, target))

	friend := add_unit(&g, .Kobold, 0, {6, 5}) // between them
	testing.expect(t, can_attack(&g, s, target), "own units never block")

	g.units[friend].faction = 1 // now an enemy stands in the way
	testing.expect(t, !can_attack(&g, s, target), "an enemy in between blocks")
	testing.expect(t, line_of_sight(&g, {5, 5}, {8, 5}), "terrain alone is clear")
	testing.expect(t, !line_of_sight(&g, {5, 5}, {8, 5}, 0))
	testing.expect(t, line_of_sight(&g, {5, 5}, {8, 5}, 1), "blue's own unit does not block blue")

	// the blocking enemy itself can still be attacked: it is adjacent, so the dagger
	w, ok := attack_weapon(&g, s, friend)
	testing.expect(t, ok && w == .Dagger)

	// a dead unit does not block
	g.units[friend].alive = false
	testing.expect(t, can_attack(&g, s, target))
}

@(test)
test_points :: proc(t: ^testing.T) {
	testing.expect_value(t, UNIT_TYPES[.Kobold].points, 10)
	testing.expect_value(t, UNIT_TYPES[.Kobold_Slinger].points, 12)
	g: Game
	new_game(&g, 0, 3) // two kobolds and two slingers a side
	testing.expect_value(t, army_points(&g, 0), 44)
	testing.expect_value(t, army_points(&g, 1), 44)
}

@(test)
test_climbing_costs :: proc(t: ^testing.T) {
	H :: HALVES_PER_POINT
	testing.expect_value(t, step_cost(.Grass, .Grass, false, true), 1 * H + 2) // +1 point up
	testing.expect_value(t, step_cost(.Grass, .Forest, false, true), 2 * H + 2)
	testing.expect_value(t, step_cost(.Road, .Road, false, true), 2) // 1/2 + 1/2
	testing.expect_value(t, step_cost(.Road, .Grass, false, true), 1 * H + 2) // not both road
	testing.expect_value(t, step_cost(.Grass, .Road, false, true), 1 * H + 2)
	testing.expect_value(t, step_cost(.Grass, .Grass, true, false), 1 * H) // down: no extra
	testing.expect_value(t, step_cost(.Grass, .Grass, true, true), 1 * H) // along: no extra

	g: Game
	blank_game(&g)
	k := add_unit(&g, .Kobold, 0, {5, 5})
	g.high[5][6] = true
	g.high[5][7] = true
	costs := movement_costs(&g, k)
	testing.expect_value(t, costs[5][6], 2 * H) // climb
	testing.expect_value(t, costs[5][7], 3 * H) // along the top
	testing.expect_value(t, costs[5][8], 4 * H) // down
}

// Melee from high ground has advantage, both ways; ranged does not.
@(test)
test_high_ground_melee :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	low, high, far := Hex{5, 5}, Hex{6, 5}, Hex{8, 5}
	g.high[high.y][high.x] = true
	a, d := combat_advantage(&g, high, low, false)
	testing.expect(t, a && !d, "attacking down")
	a, d = combat_advantage(&g, low, high, false)
	testing.expect(t, !a && d, "defending against an attack from below")
	a, d = combat_advantage(&g, low, low, false)
	testing.expect(t, !a && !d)
	a, d = combat_advantage(&g, high, far, false)
	testing.expect(t, !a && !d, "ranged gets no advantage")
	a, d = combat_advantage(&g, low, high, true)
	testing.expect(t, !a && d, "fortified on a hill: still just advantage")

	// statistically: a kobold stabbing down kills 5/9 * 2/3 = 37%, up 1/3 * 4/9 = 15%
	N :: 4000
	kills: [2]int
	for dir in 0 ..< 2 {
		for seed in u64(1) ..= N {
			blank_game(&g, seed + 50_000 * u64(dir))
			g.high[5][6] = true
			from := high if dir == 0 else low
			to := low if dir == 0 else high
			ak := add_unit(&g, .Kobold, 0, from)
			dk := add_unit(&g, .Kobold, 1, to)
			add_unit(&g, .Kobold, 1, {15, 15})
			res, _ := attack(&g, ak, dk)
			if res.killed { kills[dir] += 1 }
		}
	}
	testing.expectf(t, abs(kills[0] - N * 10 / 27) < N / 40, "downhill: %d kills", kills[0])
	testing.expectf(t, abs(kills[1] - N * 4 / 27) < N / 40, "uphill: %d kills", kills[1])
}

@(test)
test_sling_reach_from_high_ground :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	s := add_unit(&g, .Kobold_Slinger, 0, {5, 5})
	e := add_unit(&g, .Kobold, 1, {9, 5}) // 4 away
	testing.expect(t, !can_attack(&g, s, e), "range 3 on level ground")
	g.high[5][5] = true
	testing.expect(t, can_attack(&g, s, e), "range 4 from high ground onto low")
	g.units[e].pos = {10, 5}
	testing.expect(t, !can_attack(&g, s, e), "not 5")
	g.units[e].pos = {9, 5}
	g.high[5][9] = true
	testing.expect(t, !can_attack(&g, s, e), "no bonus against a target on high ground")
	g.high[5][9] = false
	g.units[e].pos = {6, 5}
	w, ok := attack_weapon(&g, s, e)
	testing.expect(t, ok && w == .Dagger, "minimum range unchanged")
}

@(test)
test_high_ground_line_of_sight :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	a, b, mid := Hex{5, 5}, Hex{8, 5}, Hex{6, 5}
	testing.expect(t, line_of_sight(&g, a, b))
	g.high[mid.y][mid.x] = true
	testing.expect(t, !line_of_sight(&g, a, b), "a hill between two low hexes")
	g.high[a.y][a.x] = true
	testing.expect(t, line_of_sight(&g, a, b), "seen from the hill")
	g.terrain[mid.y][mid.x] = .Forest
	testing.expect(t, !line_of_sight(&g, a, b), "forest on high ground still blocks")
	g.high[mid.y][mid.x] = false
	testing.expect(t, line_of_sight(&g, a, b), "a high shooter sees over low forest")
	g.high[a.y][a.x] = false
	g.high[b.y][b.x] = true
	testing.expect(t, line_of_sight(&g, a, b), "and so does a high target")
	g.high[b.y][b.x] = false
	testing.expect(t, !line_of_sight(&g, a, b), "low to low through forest")
	g.terrain[mid.y][mid.x] = .Grass

	// enemies follow the same rule as forest
	add_unit(&g, .Kobold, 1, mid)
	testing.expect(t, !line_of_sight(&g, a, b, 0))
	g.high[a.y][a.x] = true
	testing.expect(t, line_of_sight(&g, a, b, 0), "over a low enemy from high ground")
	g.high[mid.y][mid.x] = true
	testing.expect(t, !line_of_sight(&g, a, b, 0), "an enemy on high ground blocks")
}

@(test)
test_hill_scenarios :: proc(t: ^testing.T) {
	g: Game
	for pct, k in ([]int{15, 35}) {
		scenario := 6 + k
		testing.expect(t, strings.contains(SCENARIOS[scenario].name, "hill"), SCENARIOS[scenario].name)
		for seed in u64(1) ..= 30 {
			new_game(&g, scenario, seed)
			testing.expectf(t, high_count(&g) == ROWS * COLS * pct / 100, "%d%% seed %d: %d high hexes", pct, seed, high_count(&g))
			testing.expect_value(t, living_units(&g, 0), 4)
		}
	}
	// the older scenarios stay flat
	for scenario in 0 ..< 6 {
		new_game(&g, scenario, 5)
		testing.expect_value(t, high_count(&g), 0)
	}
}

// Computer games on hilly maps still finish.
@(test)
test_hilly_games_finish :: proc(t: ^testing.T) {
	g: Game
	for seed in u64(1) ..= 30 {
		new_game(&g, 7, seed)
		g.factions[0].controller = .Computer
		for steps := 0; g.winner < 0 && steps < 20000; steps += 1 { ai_step(&g) }
		testing.expectf(t, g.winner >= 0, "seed %d: no winner", seed)
	}
}

// ---------------------------------------------------------------- fog of war

fog_game :: proc(g: ^Game) {
	blank_game(g)
	g.fog = true
}

@(test)
test_vision_range_by_unit_type :: proc(t: ^testing.T) {
	g: Game
	fog_game(&g)
	add_unit(&g, .Kobold, 0, {2, 10})
	add_unit(&g, .Kobold_Slinger, 1, {9, 2}) // far away, out of everyone's sight
	near := add_unit(&g, .Kobold, 1, {7, 10}) // 5 hexes from the kobold
	far := add_unit(&g, .Kobold, 1, {8, 10}) // 6 hexes
	update_vision(&g, NO_FACTION)
	testing.expect(t, unit_visible(&g, near, 0))
	testing.expect(t, !unit_visible(&g, far, 0))
	testing.expect(t, hex_seen(&g, 0, {7, 10}) && !hex_seen(&g, 0, {8, 10}))
	testing.expect(t, unit_visible(&g, 0, 0)) // its own side always sees it
	testing.expect(t, unit_visible(&g, far, NO_FACTION))

	// a slinger sees 7
	g.units[0].kind = .Kobold_Slinger
	update_vision(&g, NO_FACTION)
	testing.expect(t, unit_visible(&g, far, 0))
	testing.expect(t, !hex_seen(&g, 0, {10, 10}))
}

@(test)
test_units_in_forest_seen_only_close :: proc(t: ^testing.T) {
	g: Game
	fog_game(&g)
	s := add_unit(&g, .Kobold_Slinger, 0, {2, 10})
	e := add_unit(&g, .Kobold, 1, {5, 10})
	g.terrain[10][5] = .Forest
	update_vision(&g, NO_FACTION)
	testing.expect(t, hex_in_view(&g, 0, {5, 10})) // the forest hex is in sight...
	testing.expect(t, !unit_visible(&g, e, 0)) // ...but not the unit in it
	testing.expect(t, !can_attack(&g, s, e)) // in sling range, but unseen
	testing.expect(t, unit_visible(&g, s, 1)) // the slinger on grass is seen

	g.units[s].pos = {3, 10} // 2 hexes away: now it is seen
	update_vision(&g, NO_FACTION)
	testing.expect(t, unit_visible(&g, e, 0))
	testing.expect(t, can_attack(&g, s, e))
}

@(test)
test_move_stops_at_hidden_enemy :: proc(t: ^testing.T) {
	g: Game
	fog_game(&g)
	k := add_unit(&g, .Kobold, 0, {2, 0})
	// a corridor along row 0, with an enemy hidden in forest 3 hexes along
	for row in 1 ..< ROWS { for col in 0 ..< COLS { g.terrain[row][col] = .Forest } }
	g.terrain[0][5] = .Forest
	e := add_unit(&g, .Kobold, 1, {5, 0})
	update_vision(&g, NO_FACTION)
	testing.expect(t, !unit_visible(&g, e, 0))
	costs := movement_costs(&g, k)
	testing.expect(t, can_move(&g, k, {5, 0}, &costs)) // planning does not know of it

	testing.expect(t, move_unit(&g, k, {5, 0}))
	testing.expect_value(t, g.units[k].pos, Hex{4, 0}) // stopped short
	testing.expect_value(t, g.units[k].moves_left, 2 * HALVES_PER_POINT) // 2 of 4 points spent
	testing.expect(t, unit_visible(&g, e, 0)) // and now sees it
	testing.expect(t, can_attack(&g, k, e))
	testing.expect(t, strings.contains(log_line(&g, 0), "blocks the way"))
}

@(test)
test_last_seen_marker :: proc(t: ^testing.T) {
	g: Game
	fog_game(&g)
	add_unit(&g, .Kobold, 0, {2, 10})
	e := add_unit(&g, .Kobold, 1, {6, 10})
	update_vision(&g, NO_FACTION)
	g.current = 1
	start_faction_turn(&g)
	// Blue walks out of Red's sight: Red remembers where it last saw it
	testing.expect(t, move_unit(&g, e, {10, 10}))
	pos, ok := sighting(&g, 0, e)
	testing.expect(t, ok)
	testing.expect_value(t, pos, Hex{7, 10}) // the last hex Red could see it on

	// Red's turn: it looks again, finds the hex empty, and forgets
	g.units[e].done = true
	testing.expect(t, end_turn(&g))
	_, ok = sighting(&g, 0, e)
	testing.expect(t, !ok)
}

@(test)
test_ai_scouts_and_finds_the_enemy :: proc(t: ^testing.T) {
	g: Game
	fog_game(&g)
	g.factions[0].controller = .Computer
	add_unit(&g, .Kobold, 0, {1, 9})
	add_unit(&g, .Kobold_Slinger, 0, {1, 10})
	add_unit(&g, .Kobold, 1, {18, 10})
	update_vision(&g, NO_FACTION)
	testing.expect(t, !unit_visible(&g, 2, 0))
	for _ in 0 ..< 200 {
		if g.winner >= 0 { break }
		ai_step(&g)
	}
	testing.expect(t, g.winner >= 0) // somebody found somebody
}

@(test)
test_fog_off_sees_everything :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	add_unit(&g, .Kobold, 0, {0, 0})
	e := add_unit(&g, .Kobold, 1, {19, 19})
	testing.expect(t, unit_visible(&g, e, 0))
	testing.expect(t, hex_seen(&g, 0, {19, 19}))
}

// ---------------------------------------------------------------- tactical AI

@(test)
test_mask_grow_matches_distance :: proc(t: ^testing.T) {
	for start in ([]Hex{{0, 0}, {7, 4}, {8, 5}, {19, 19}, {10, 0}, {0, 11}}) {
		m: Hex_Mask
		mask_set(&m, start)
		for rings in 0 ..= 5 {
			grown := mask_grow(m, rings)
			for row in 0 ..< ROWS {
				for col in 0 ..< COLS {
					h := Hex{col, row}
					testing.expectf(t, mask_has(&grown, h) == (hex_distance(start, h) <= rings), "start %v rings %d hex %v", start, rings, h)
				}
			}
		}
	}
}

@(test)
test_tactical_steps_out_of_reach :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	g.current = 1
	s := add_unit(&g, .Kobold_Slinger, 0, {5, 10})
	k := add_unit(&g, .Kobold, 1, {11, 10}) // the slinger could hit it next turn
	start_faction_turn(&g)
	ai_take_turn(&g)
	testing.expect(t, !g.units[k].fortified)
	threat := ai_threat_map(&g, 1)
	testing.expect(t, !mask_has(threat, g.units[k].pos), "out of the slinger's reach")
	testing.expect(t, hex_distance(g.units[s].pos, g.units[k].pos) <= 4 + 3 + 1, "but no further than it needs")
}

@(test)
test_tactical_holds_then_advances :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	g.current = 1
	add_unit(&g, .Kobold, 0, {2, 10})
	k := add_unit(&g, .Kobold, 1, {11, 10}) // 9 away: a full move would put it in reach
	start_faction_turn(&g)
	ai_take_turn(&g)
	// it stops at the edge of the kobold's reach (move 4 + dagger 1)
	d := hex_distance(g.units[0].pos, g.units[k].pos)
	testing.expect_value(t, d, 6)
	testing.expectf(t, g.ai_held[1] == 1, "held %v holding %v pos %v", g.ai_held, g.ai_holding, g.units[k].pos)
	// after HOLD_TURNS quiet turns it gives up waiting
	for _ in 0 ..< HOLD_TURNS {
		g.units[0].done = true
		testing.expect(t, end_turn(&g)) // Red stays put
		ai_take_turn(&g)
	}
	testing.expect(t, hex_distance(g.units[0].pos, g.units[k].pos) < 6, "advances in the end")
}

@(test)
test_tactical_prefers_high_ground :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	g.current = 1
	add_unit(&g, .Kobold, 0, {5, 10})
	k := add_unit(&g, .Kobold, 1, {7, 10})
	g.high[9][5] = true // a hill beside the enemy: stab down with advantage
	start_faction_turn(&g)
	ai_take_turn(&g)
	testing.expect_value(t, g.units[k].pos, Hex{5, 9})
}

@(test)
test_tactical_target_choice :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	k := add_unit(&g, .Kobold, 0, {5, 10})
	fort := add_unit(&g, .Kobold, 1, {6, 10})
	sl := add_unit(&g, .Kobold_Slinger, 1, {4, 10})
	g.units[fort].fortified = true
	testing.expect_value(t, ai_tactical_target(&g, k), sl) // not the fortified one, and a slinger
	g.units[fort].fortified = false
	testing.expect_value(t, ai_tactical_target(&g, k), sl) // a slinger before a kobold
	g.units[sl].kind = .Kobold
	g.high[10][4] = true // now it holds the high ground
	testing.expect_value(t, ai_tactical_target(&g, k), fort)
}

// ---------------------------------------------------------------- armour and new units

@(test)
test_armour_adds_defence_dice :: proc(t: ^testing.T) {
	testing.expect_value(t, unit_defence(&UNIT_TYPES[.Kobold]), Dice{.White = 1, .Red = 0, .Black = 0})
	testing.expect_value(t, unit_defence(&UNIT_TYPES[.Heavy]), Dice{.White = 1, .Red = 1, .Black = 0})
	testing.expect_value(t, unit_defence(&UNIT_TYPES[.Champion]), Dice{.White = 1, .Red = 0, .Black = 1})
	testing.expect_value(t, UNIT_TYPES[.Heavy].body, 2)
	testing.expect_value(t, UNIT_TYPES[.Champion].body, 3)
	testing.expect_value(t, UNIT_TYPES[.Scout].move, 6)
	testing.expect_value(t, UNIT_TYPES[.Scout].vision, 8)
}

@(test)
test_armour_blocks_more :: proc(t: ^testing.T) {
	// a champion's sword (white + red) against a kobold's hide and against plate
	blocks := [2]int{}
	N :: 4000
	for kind, k in ([]Unit_Kind{.Kobold, .Champion}) {
		for seed in u64(1) ..= N {
			g: Game
			blank_game(&g, seed)
			a := add_unit(&g, .Champion, 0, {5, 5})
			d := add_unit(&g, kind, 1, {6, 5})
			res, ok := attack(&g, a, d)
			testing.expect(t, ok)
			blocks[k] += res.blocks
		}
	}
	// hide: 1/3 a roll; hide and plate: 1/3 + 2/3 = 1 a roll
	testing.expectf(t, abs(f64(blocks[0]) / N - 1.0 / 3) < 0.03, "hide blocks %v", f64(blocks[0]) / N)
	testing.expectf(t, abs(f64(blocks[1]) / N - 1.0) < 0.05, "plate blocks %v", f64(blocks[1]) / N)
}

@(test)
test_wounds_stay_until_dead :: proc(t: ^testing.T) {
	g: Game
	for seed in u64(1) ..< 500 {
		blank_game(&g, seed)
		a := add_unit(&g, .Champion, 0, {5, 5})
		h := add_unit(&g, .Heavy, 1, {6, 5})
		res, _ := attack(&g, a, h)
		if res.damage == 1 {
			testing.expect_value(t, g.units[h].body, 1)
			testing.expect(t, g.units[h].alive)
			testing.expect(t, strings.contains(log_line(&g, 0), "wounded"))
			return
		}
	}
	testing.fail_now(t, "no seed gave exactly one wound")
}

@(test)
test_mixed_band_games_finish :: proc(t: ^testing.T) {
	kinds := []Unit_Kind{.Kobold_Slinger, .Kobold_Slinger, .Scout, .Kobold, .Kobold, .Champion, .Heavy, .Heavy}
	for seed in u64(1) ..= 5 {
		g: Game
		g.winner = -1
		g.turn = 1
		g.rng = {seed}
		g.fog = true
		add_faction(&g, "Red", .Computer, RED)
		add_faction(&g, "Blue", .Computer, BLUE)
		place_block(&g, 0, kinds, true)
		place_block(&g, 1, kinds, false)
		start_faction_turn(&g)
		update_vision(&g, NO_FACTION)
		for steps := 0; g.winner < 0 && steps < 50000; steps += 1 { ai_step(&g) }
		testing.expectf(t, g.winner >= 0, "seed %d: no winner", seed)
	}
}

@(test)
test_warband_scenario :: proc(t: ^testing.T) {
	g: Game
	testing.expect_value(t, SCENARIOS[8].name, "Kobold Warband")
	new_game(&g, 8, 3)
	testing.expect_value(t, army_points(&g, 0), 204)
	testing.expect_value(t, army_points(&g, 1), 204)
	testing.expect_value(t, living_units(&g, 0), 9)
}

// ---------------------------------------------------------------- bow and crossbow

@(test)
test_pierce_takes_the_best_die :: proc(t: ^testing.T) {
	testing.expect_value(t, defence_against(&UNIT_TYPES[.Champion], .Crossbow), Dice{.White = 1, .Red = 0, .Black = 0})
	testing.expect_value(t, defence_against(&UNIT_TYPES[.Heavy], .Crossbow), Dice{.White = 1, .Red = 0, .Black = 0})
	testing.expect_value(t, defence_against(&UNIT_TYPES[.Crossbow], .Crossbow), Dice{.White = 1, .Red = 0, .Black = 0})
	// one die is always kept
	testing.expect_value(t, defence_against(&UNIT_TYPES[.Kobold], .Crossbow), Dice{.White = 1, .Red = 0, .Black = 0})
	// other weapons do not pierce
	testing.expect_value(t, defence_against(&UNIT_TYPES[.Champion], .Bow), unit_defence(&UNIT_TYPES[.Champion]))
}

@(test)
test_bow_and_crossbow_ranges :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	a := add_unit(&g, .Archer, 0, {2, 10})
	x := add_unit(&g, .Crossbow, 0, {2, 12})
	e := add_unit(&g, .Kobold, 1, {7, 10}) // 5 from the archer
	f := add_unit(&g, .Kobold, 1, {7, 12}) // 5 from the crossbow
	w, ok := attack_weapon(&g, a, e)
	testing.expect(t, ok && w == .Bow)
	testing.expect(t, !can_attack(&g, x, f), "a crossbow reaches 4")
	g.units[f].pos = {6, 12}
	w, ok = attack_weapon(&g, x, f)
	testing.expect(t, ok && w == .Crossbow)
	g.units[e].pos = {3, 10}
	w, ok = attack_weapon(&g, a, e)
	testing.expect(t, ok && w == .Dagger, "an archer falls back on its dagger")
}

// ---------------------------------------------------------------- pike

@(test)
test_pike_strikes_first :: proc(t: ^testing.T) {
	// find a seed where the pike's strike kills, and one where it does not
	killed_once, survived_once := false, false
	for seed in u64(1) ..= 200 {
		g: Game
		blank_game(&g, seed)
		k := add_unit(&g, .Kobold, 0, {3, 10})
		p := add_unit(&g, .Pike, 1, {6, 10})
		testing.expect(t, move_unit(&g, k, {4, 10})) // 2 from the pike: not next to it
		testing.expect(t, !g.units[p].reacted, "not next to the pike yet")
		testing.expect(t, move_unit(&g, k, {5, 10})) // steps next to the pike
		testing.expect(t, g.units[p].reacted)
		testing.expect(t, strings.contains(log_line(&g, 0), "strikes first") || strings.contains(log_line(&g, 1), "strikes first"))
		if !g.units[k].alive {
			killed_once = true
			testing.expect_value(t, g.units[k].pos, Hex{5, 10})
		} else {
			survived_once = true
			// another step next to the same pike: it has struck this turn already
			count := g.event_count
			testing.expect(t, move_unit(&g, k, {5, 9})) // one step, still next to the pike
			testing.expect_value(t, g.event_count - count, 1) // only the move
		}
		if killed_once && survived_once { break }
	}
	testing.expect(t, killed_once && survived_once)
}

@(test)
test_pike_strikes_again_next_turn :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g, 3)
	g.factions[0].controller = .Human
	add_unit(&g, .Pike, 1, {6, 10})
	g.units[0].reacted = true
	g.current = 1
	start_faction_turn(&g)
	testing.expect(t, !g.units[0].reacted, "cleared when a turn starts")
}

@(test)
test_pike_move_events_are_split :: proc(t: ^testing.T) {
	for seed in u64(1) ..= 200 {
		g: Game
		blank_game(&g, seed)
		// a grass corridor along row 10, forest all round, so the way is fixed
		for row in 0 ..< ROWS { for col in 0 ..< COLS { if row != 10 { g.terrain[row][col] = .Forest } } }
		k := add_unit(&g, .Kobold, 0, {1, 10})
		add_unit(&g, .Pike, 1, {3, 9}) // next to 3,10 and 4,10
		before := g.event_count
		testing.expect(t, move_unit(&g, k, {5, 10}))
		if !g.units[k].alive { continue }
		// the move up to the pike, the pike's attack, the rest of the move
		testing.expect_value(t, g.event_count - before, 3)
		first := g.events[before % EVENT_RING]
		testing.expect_value(t, first.kind, Event_Kind.Move)
		testing.expect_value(t, first.path[first.steps - 1], Hex{3, 10})
		testing.expect_value(t, g.events[(before + 1) % EVENT_RING].kind, Event_Kind.Attack)
		testing.expect(t, g.events[(before + 1) % EVENT_RING].result.first_strike)
		last := g.events[(before + 2) % EVENT_RING]
		testing.expect_value(t, last.kind, Event_Kind.Move)
		testing.expect_value(t, last.from, Hex{3, 10})
		testing.expect_value(t, g.units[k].pos, Hex{5, 10})
		return
	}
	testing.fail_now(t, "the kobold never survived")
}

// ---------------------------------------------------------------- Wololo

@(test)
test_disadvantage_odds :: proc(t: ^testing.T) {
	r := Rng{42}
	one := Dice{.White = 1, .Red = 0, .Black = 0}
	N :: 30000
	scores, both := 0, 0
	for _ in 0 ..< N {
		scores += roll_dice(&r, one, disadvantage = true)
		both += roll_dice(&r, one, advantage = true, disadvantage = true)
	}
	// white scores 1/3; with disadvantage it must score twice: 1/9
	testing.expectf(t, abs(f64(scores) / N - 1.0 / 9) < 0.01, "disadvantage %v", f64(scores) / N)
	testing.expectf(t, abs(f64(both) / N - 1.0 / 3) < 0.015, "both cancel %v", f64(both) / N)
}

@(test)
test_chant_bless_and_curse :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	w := add_unit(&g, .Wololo, 0, {5, 10})
	k := add_unit(&g, .Kobold, 0, {6, 10})
	e := add_unit(&g, .Kobold, 1, {8, 10}) // 3 away
	far := add_unit(&g, .Kobold, 1, {9, 12})
	testing.expect(t, !can_attack(&g, w, e), "a Wololo has no attack")
	testing.expect(t, !can_chant(&g, w, far), "out of range")
	testing.expect(t, can_chant(&g, w, k) && can_chant(&g, w, e))
	testing.expect(t, chant(&g, w, e))
	testing.expect_value(t, g.units[e].boon, Boon.Cursed)
	testing.expect(t, g.units[w].done, "chanting ends its move")
	testing.expect(t, !can_chant(&g, w, k), "once a turn")
	testing.expect(t, strings.contains(log_line(&g, 0), "curses"))
	// the curse is spent on the cursed unit's next roll
	res, ok := attack(&g, k, e)
	_ = ok
	testing.expect(t, !ok, "not adjacent yet") // 2 away: kobold cannot reach
	g.units[k].pos = {7, 10}
	res, ok = attack(&g, k, e)
	testing.expect(t, ok)
	testing.expect_value(t, res.defence_boon, Boon.Cursed)
	testing.expect_value(t, g.units[e].boon, Boon.None)
}

@(test)
test_blessing_fades_on_casters_turn :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	g.factions[1].controller = .Human
	w := add_unit(&g, .Wololo, 0, {5, 10})
	k := add_unit(&g, .Kobold, 0, {6, 10})
	add_unit(&g, .Kobold, 1, {15, 10})
	testing.expect(t, chant(&g, w, k))
	testing.expect_value(t, g.units[k].boon, Boon.Blessed)
	g.units[k].done = true
	testing.expect(t, end_turn(&g)) // Blue's turn: still blessed (for defence)
	testing.expect_value(t, g.units[k].boon, Boon.Blessed)
	g.units[2].done = true
	testing.expect(t, end_turn(&g)) // Red's turn again: unused, it fades
	testing.expect_value(t, g.units[k].boon, Boon.None)
}

@(test)
test_wololo_games_finish :: proc(t: ^testing.T) {
	kinds := []Unit_Kind{.Wololo, .Kobold_Slinger, .Kobold, .Kobold, .Heavy}
	for seed in u64(1) ..= 5 {
		g: Game
		g.winner = -1
		g.turn = 1
		g.rng = {seed}
		g.fog = true
		add_faction(&g, "Red", .Computer, RED)
		add_faction(&g, "Blue", .Computer, BLUE)
		place_block(&g, 0, kinds, true)
		place_block(&g, 1, kinds, false)
		start_faction_turn(&g)
		update_vision(&g, NO_FACTION)
		chants := 0
		for steps := 0; g.winner < 0 && steps < 50000; steps += 1 {
			before := g.event_count
			ai_step(&g)
			for e in before ..< g.event_count { if g.events[e % EVENT_RING].kind == .Chant { chants += 1 } }
		}
		testing.expectf(t, g.winner >= 0, "seed %d: no winner", seed)
		testing.expectf(t, chants > 0, "seed %d: the Wololos never chanted", seed)
	}
}

@(test)
test_custom_battle :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	cb := DEFAULT_CUSTOM
	cb.forest = .Heavy
	cb.road = false
	cb.hills = .Some
	cb.sides[0].choice = ARMY_CUSTOM
	cb.sides[0].custom[.Champion] = 2
	cb.sides[0].custom[.Archer] = 3
	cb.sides[1].choice = 0 // patrol
	testing.expect(t, custom_ready(&cb))
	new_custom_game(g, &cb, 7)
	testing.expect_value(t, g.name, "Custom battle")
	testing.expect_value(t, army_points(g, 0), 2 * 55 + 3 * 20)
	testing.expect_value(t, army_points(g, 1), 44)
	testing.expect_value(t, g.factions[0].controller, Controller.Human)
	testing.expect_value(t, forest_count(g), ROWS * COLS * 50 / 100)
	testing.expect_value(t, high_count(g), ROWS * COLS * 15 / 100)
	roads := 0
	for row in g.terrain { for tr in row { if tr == .Road { roads += 1 } } }
	testing.expect_value(t, roads, 0)
	for i in 0 ..< g.unit_count { testing.expect(t, g.terrain[g.units[i].pos.y][g.units[i].pos.x] != .Forest) }

	cb.road = true
	cb.watch = true
	new_custom_game(g, &cb, 8)
	testing.expect_value(t, g.factions[0].controller, Controller.Computer)
	roads = 0
	for row in g.terrain { for tr in row { if tr == .Road { roads += 1 } } }
	testing.expect(t, roads >= COLS)
}

@(test)
test_custom_budget :: proc(t: ^testing.T) {
	cb := DEFAULT_CUSTOM
	cb.budget = 100
	cb.sides[0].choice = ARMY_CUSTOM
	testing.expect(t, !side_ready(&cb, 0)) // nothing bought yet
	cb.sides[0].custom[.Champion] = 1
	testing.expect(t, can_buy(&cb, 0, .Heavy)) // 55 + 25
	cb.sides[0].custom[.Heavy] = 1
	testing.expect(t, !can_buy(&cb, 0, .Heavy)) // 80 + 25 > 100
	testing.expect(t, can_buy(&cb, 0, .Scout)) // 80 + 11
	testing.expect(t, side_ready(&cb, 0))
	cb.budget = 50 // lowered after buying
	testing.expect(t, !side_ready(&cb, 0))
	testing.expect(t, !custom_ready(&cb))

	// random armies use the budget up (less than the cheapest unit left) and fit it
	r := Rng{3}
	for budget in BUDGETS {
		for _ in 0 ..< 50 {
			buf: [MAX_ARMY]Unit_Kind
			army := random_army(&r, budget, buf[:])
			pts := 0
			for k in army { pts += UNIT_TYPES[k].points }
			testing.expect(t, pts <= budget && pts > budget - 10)
		}
	}
	// every preset fits in one side's share of the map
	for p in ARMY_PRESETS { testing.expect(t, len(p.kinds) <= MAX_ARMY) }
}

@(test)
test_mixed_band_scenarios :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	Want :: struct {
		name:      string,
		red, blue: int, // points
		forest:    int, // percent, or -1 for the usual clumps
		hills:     int,
	}
	wants := [?]Want {
		{"Shield Wall vs Skirmishers", 142, 141, -1, 0},
		{"Champion's Guard vs the Horde", 165, 166, -1, 0},
		{"Ambush in the Woods", 161, 122, 50, 0},
		{"Archers on the Heights", 130, 162, -1, 35},
	}
	for w in wants {
		idx := -1
		for sc, i in SCENARIOS { if sc.name == w.name { idx = i } }
		testing.expectf(t, idx >= 0, "no scenario %s", w.name)
		if idx < 0 { continue }
		new_game(g, idx, 11)
		testing.expect_value(t, army_points(g, 0), w.red)
		testing.expect_value(t, army_points(g, 1), w.blue)
		testing.expect_value(t, g.factions[0].controller, Controller.Human)
		testing.expect_value(t, high_count(g), ROWS * COLS * w.hills / 100)
		if w.forest >= 0 { testing.expect_value(t, forest_count(g), ROWS * COLS * w.forest / 100) }
		for i in 0 ..< g.unit_count { testing.expect(t, g.terrain[g.units[i].pos.y][g.units[i].pos.x] != .Forest) }
	}
}

@(test)
test_chant_area :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	w := add_unit(&g, .Wololo, 0, {5, 10})
	center := Hex{8, 10}
	nbs, _ := neighbours(center)
	a := add_unit(&g, .Kobold, 0, center)
	b := add_unit(&g, .Heavy, 0, nbs[0] if nbs[0] != Hex{9, 10} else nbs[1])
	c := add_unit(&g, .Kobold, 0, {10, 10}) // two from the centre
	far_side := Hex{9, 10} // an enemy beside the centre, not in the line of sight
	testing.expect_value(t, hex_distance(center, far_side), 1)
	d := add_unit(&g, .Kobold, 1, far_side)
	testing.expect_value(t, hex_distance(center, g.units[c].pos), 2)
	testing.expect(t, chant_at(&g, w, center, true))
	testing.expect_value(t, g.units[a].boon, Boon.Blessed)
	testing.expect_value(t, g.units[b].boon, Boon.Blessed)
	testing.expect_value(t, g.units[c].boon, Boon.None)
	testing.expect_value(t, g.units[d].boon, Boon.None) // a blessing skips enemies
	testing.expect(t, strings.contains(log_line(&g, 0), "blesses Red"))

	// a curse on an empty hex catches every enemy round it, but never the
	// Wololo's own side, and the Wololo never blesses itself
	blank_game(&g)
	w = add_unit(&g, .Wololo, 0, {5, 10})
	e1 := add_unit(&g, .Kobold, 1, {7, 9})
	e2 := add_unit(&g, .Kobold, 1, {7, 11})
	f := add_unit(&g, .Kobold, 0, {6, 10})
	empty := Hex{7, 10}
	testing.expect(t, hex_distance(empty, g.units[e1].pos) == 1 && hex_distance(empty, g.units[e2].pos) == 1)
	testing.expect(t, !can_chant_at(&g, w, {1, 10}, false), "nobody to curse there")
	testing.expect(t, chant_at(&g, w, empty, false))
	testing.expect_value(t, g.units[e1].boon, Boon.Cursed)
	testing.expect_value(t, g.units[e2].boon, Boon.Cursed)
	testing.expect_value(t, g.units[f].boon, Boon.None)
	testing.expect_value(t, g.units[w].boon, Boon.None)

	// alone, a Wololo has nobody to chant on: out of moves, it is finished
	blank_game(&g)
	w = add_unit(&g, .Wololo, 0, {5, 10})
	add_unit(&g, .Kobold, 1, {15, 10})
	testing.expect(t, !can_chant_at(&g, w, {5, 10}, true), "no blessing itself")
	g.units[w].moves_left = 0
	testing.expect(t, unit_finished(&g, w))
}

@(test)
test_chant_curses_only_seen_enemies :: proc(t: ^testing.T) {
	g: Game
	blank_game(&g)
	g.fog = true
	w := add_unit(&g, .Wololo, 0, {5, 10})
	seen := add_unit(&g, .Kobold, 1, {7, 10}) // 2 away on grass
	g.terrain[10][8] = .Forest
	hidden := add_unit(&g, .Kobold, 1, {8, 10}) // 3 away in forest: unseen
	update_vision(&g, NO_FACTION)
	testing.expect(t, !unit_visible(&g, hidden, 0))
	testing.expect(t, chant_at(&g, w, {7, 10}, false))
	testing.expect_value(t, g.units[seen].boon, Boon.Cursed)
	testing.expect_value(t, g.units[hidden].boon, Boon.None)
}

@(test)
test_water_and_walls_block_movement :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	blank_game(g)
	k := add_unit(g, .Kobold, 0, {5, 10})
	g.terrain[10][6] = .Deep
	g.terrain[10][4] = .Stone_Wall
	g.terrain[9][5] = .Shallow
	costs := movement_costs(g, k)
	testing.expect_value(t, costs[10][6], UNREACHABLE)
	testing.expect_value(t, costs[10][4], UNREACHABLE)
	testing.expect_value(t, costs[9][5], 2 * HALVES_PER_POINT) // shallow water costs 2
	// the hex beyond the deep water is reached the long way round
	testing.expect(t, costs[10][7] > 2 * HALVES_PER_POINT)
	testing.expect(t, !move_unit(g, k, {6, 10}))
}

@(test)
test_wall_sight_and_cover :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	blank_game(g)
	// a wall two hexes from each end blocks the line
	g.terrain[10][8] = .Wood_Wall
	testing.expect(t, !line_of_sight(g, {6, 10}, {10, 10}))
	// right next to the wall, a unit looks over it, and is seen over it
	testing.expect(t, line_of_sight(g, {7, 10}, {10, 10}))
	testing.expect(t, line_of_sight(g, {6, 10}, {9, 10}))
	// a shot at a unit right behind the wall: cover, which is defence advantage
	testing.expect(t, wall_cover(g, {6, 10}, {9, 10}))
	_, def := combat_advantage(g, {6, 10}, {9, 10}, false)
	testing.expect(t, def)
	// the unit behind the wall shooting out: its target has no cover
	testing.expect(t, !wall_cover(g, {9, 10}, {6, 10}))
	// shooting down from high ground over a low wall: no cover
	g.high[10][6] = true
	testing.expect(t, !wall_cover(g, {6, 10}, {9, 10}))
	// deep water blocks nothing
	g.high[10][6] = false
	g.terrain[10][8] = .Deep
	testing.expect(t, line_of_sight(g, {5, 10}, {11, 10}))

	// cover is tagged in the log
	blank_game(g)
	g.terrain[10][8] = .Stone_Wall
	a := add_unit(g, .Archer, 0, {5, 10})
	add_unit(g, .Kobold, 1, {9, 10})
	testing.expect(t, can_attack(g, a, 1))
	attack(g, a, 1)
	testing.expect(t, strings.contains(log_line(g, 0), "(cover)"))
}

@(test)
test_walk_distances :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	blank_game(g)
	from := [1]Hex{{3, 3}}
	d := walk_distances(g, from[:])
	for row in 0 ..< ROWS {
		for col in 0 ..< COLS {
			testing.expect_value(t, int(d[row][col]), hex_distance({3, 3}, {col, row}))
		}
	}
	// a wall across the map, open at the bottom: the walk goes round it
	for row in 0 ..< ROWS - 1 { g.terrain[row][8] = .Stone_Wall }
	from[0] = {6, 0}
	d = walk_distances(g, from[:])
	testing.expect(t, int(d[0][10]) > hex_distance({6, 0}, {10, 0}) + 10)
	testing.expect_value(t, d[0][8], UNREACHABLE)
}

@(test)
test_custom_water_and_walls :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	cb := DEFAULT_CUSTOM
	for water in Water_Level {
		for walls in Wall_Level {
			cb.water = water
			cb.walls = walls
			for seed in u64(1) ..= 5 {
				new_custom_game(g, &cb, seed)
				testing.expect(t, armies_connected(g), "every unit can reach every other")
				deep, shallow, wall := 0, 0, 0
				for row in 0 ..< ROWS {
					for col in 0 ..< COLS {
						tr := g.terrain[row][col]
						if tr == .Deep { deep += 1 }
						if tr == .Shallow { shallow += 1 }
						if is_wall(tr) { wall += 1 }
						if is_water(tr) { testing.expect(t, !g.high[row][col], "water lies low") }
					}
				}
				for i in 0 ..< g.unit_count { testing.expect(t, passable(g, g.units[i].pos)) }
				switch water {
				case .None:   testing.expect_value(t, deep + shallow, 0)
				case .Stream: testing.expect(t, deep == 0 && shallow >= ROWS - 4)
				case .River:  testing.expect(t, deep >= ROWS && shallow >= 2)
				case .Ponds:  testing.expect(t, deep > 0 && shallow > 0)
				}
				if walls == .None { testing.expect_value(t, wall, 0) } else { testing.expect(t, wall > 0) }
			}
		}
	}
}

@(test)
test_water_and_wall_scenarios :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	for name, i in SCENARIOS {
		if name.name != "River Crossing" && name.name != "Walled Farmsteads" { continue }
		new_game(g, i, 3)
		testing.expect(t, armies_connected(g))
		pts := 204 if name.name == "River Crossing" else 204 + SAPPER_POINTS
		testing.expect_value(t, army_points(g, 0), pts)
		testing.expect_value(t, army_points(g, 1), pts)
		deep, wall := 0, 0
		for row in g.terrain {
			for tr in row {
				if tr == .Deep { deep += 1 }
				if is_wall(tr) { wall += 1 }
			}
		}
		if name.name == "River Crossing" { testing.expect(t, deep >= ROWS) } else { testing.expect(t, wall > 0) }
	}
}

@(test)
test_sapper_demolish :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	blank_game(g)
	s := add_unit(g, .Sapper, 0, {5, 10})
	k := add_unit(g, .Kobold, 0, {3, 10})
	add_unit(g, .Kobold, 1, {15, 2}) // so the game is not over
	start_faction_turn(g)
	g.terrain[10][6] = .Wood_Wall
	g.terrain[10][4] = .Stone_Wall
	g.terrain[10][8] = .Stone_Wall
	testing.expect(t, !can_demolish(g, s, {8, 10}), "not next to it")
	testing.expect(t, !can_demolish(g, k, {4, 10}), "only sappers")
	testing.expect(t, !can_demolish(g, s, {5, 9}), "not a wall")
	testing.expect(t, can_demolish_anywhere(g, s))
	// a wooden wall falls at once, and that is the sapper's turn
	testing.expect(t, demolish(g, s, {6, 10}))
	testing.expect_value(t, g.terrain[10][6], Terrain.Rubble)
	testing.expect(t, unit_finished(g, s))
	testing.expect(t, !demolish(g, s, {4, 10}), "one wall a turn")
	testing.expect(t, strings.contains(log_line(g, 0), "breaks the wooden wall"))
	// rubble: passable at 2, blocks no sight
	testing.expect(t, passable(g, {6, 10}))
	g.terrain[2][6] = .Rubble
	testing.expect(t, line_of_sight(g, {3, 2}, {9, 2}), "rubble blocks no sight")
	// a stone wall takes two blows, on two turns
	g.units[s].attacked, g.units[s].done = false, false
	g.units[s].moves_left = 0
	testing.expect(t, !unit_finished(g, s), "a wall to break is still something to do")
	testing.expect(t, demolish(g, s, {4, 10}))
	testing.expect_value(t, g.terrain[10][4], Terrain.Cracked_Wall)
	testing.expect(t, !passable(g, {4, 10}))
	testing.expect(t, strings.contains(log_line(g, 0), "cracks the stone wall"))
	g.units[s].attacked, g.units[s].done = false, false
	testing.expect(t, demolish(g, s, {4, 10}))
	testing.expect_value(t, g.terrain[10][4], Terrain.Rubble)
	costs := movement_costs(g, k)
	testing.expect_value(t, costs[10][4], 2 * HALVES_PER_POINT)
}

@(test)
test_ai_sapper_breaches :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	blank_game(g)
	g.factions[0].controller = .Computer
	// a wall the length of the map but for one gap at the bottom
	for row in 0 ..< ROWS - 1 { g.terrain[row][10] = .Wood_Wall }
	s := add_unit(g, .Sapper, 0, {9, 5})
	add_unit(g, .Kobold, 1, {13, 5})
	start_faction_turn(g)
	update_vision(g, NO_FACTION)
	ai_tactical_unit(g, s)
	broken := 0
	for row in 0 ..< ROWS - 1 { if g.terrain[row][10] == .Rubble { broken += 1 } }
	testing.expect_value(t, broken, 1)
	// with the gap right beside it, it walks instead
	blank_game(g)
	g.factions[0].controller = .Computer
	for row in 0 ..< 6 { g.terrain[row][10] = .Wood_Wall }
	s = add_unit(g, .Sapper, 0, {9, 5})
	add_unit(g, .Kobold, 1, {13, 5})
	start_faction_turn(g)
	update_vision(g, NO_FACTION)
	ai_tactical_unit(g, s)
	broken = 0
	for row in 0 ..< 6 { if g.terrain[row][10] == .Rubble { broken += 1 } }
	testing.expect_value(t, broken, 0)
}
