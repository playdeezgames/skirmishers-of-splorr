#+build !js
package game

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
	end_turn(&g)
	testing.expect_value(t, g.current, 1)
	testing.expect_value(t, g.units[b].moves_left, 4 * HALVES_PER_POINT)
	testing.expect(t, !g.units[b].attacked)
	end_turn(&g)
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
