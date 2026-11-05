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
	testing.expect_value(t, step_cost(.Road, .Road), 1) // half a point
	testing.expect_value(t, step_cost(.Grass, .Road), 1 * H)
	testing.expect_value(t, step_cost(.Road, .Grass), 1 * H)
	testing.expect_value(t, step_cost(.Road, .Forest), 2 * H)

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
