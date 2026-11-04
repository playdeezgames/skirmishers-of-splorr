package game

// A scenario builds the map, the factions (and who controls each) and the units.

Scenario :: struct {
	name:  string,
	setup: proc(g: ^Game),
}

SCENARIOS := [?]Scenario {
	{"Kobold Skirmish", setup_kobold_skirmish},
	{"Kobold Skirmish (computer vs computer)", setup_kobold_watch},
}

RED :: [3]f32{0.85, 0.25, 0.2}
BLUE :: [3]f32{0.2, 0.45, 0.9}

new_game :: proc(g: ^Game, scenario: int, seed: u64) {
	g^ = {}
	g.winner = -1
	g.turn = 1
	g.rng = {seed}
	SCENARIOS[scenario].setup(g)
	start_faction_turn(g)
	add_log(g, "%s: turn 1", SCENARIOS[scenario].name)
}

// Mostly grass, with clumps of forest grown from random seeds.
generate_clumped_forest :: proc(g: ^Game, clumps, min_size, max_size: int) {
	for &row in g.terrain { for &t in row { t = .Grass } }
	for _ in 0 ..< clumps {
		size := min_size + rng_int(&g.rng, max_size - min_size + 1)
		cells: [32]Hex
		count := 1
		cells[0] = {rng_int(&g.rng, COLS), rng_int(&g.rng, ROWS)}
		g.terrain[cells[0].y][cells[0].x] = .Forest
		for tries := 0; count < min(size, len(cells)) && tries < 200; tries += 1 {
			from := cells[rng_int(&g.rng, count)]
			nbs, n := neighbours(from)
			nb := nbs[rng_int(&g.rng, n)]
			if g.terrain[nb.y][nb.x] == .Forest { continue }
			g.terrain[nb.y][nb.x] = .Forest
			cells[count] = nb
			count += 1
		}
	}
}

// Two lines of four kobolds facing each other across the map.
place_kobold_armies :: proc(g: ^Game, red, blue: int) {
	rows := [4]int{6, 8, 11, 13}
	for r in rows {
		left := Hex{2, r}
		right := Hex{COLS - 3, r}
		g.terrain[left.y][left.x] = .Grass
		g.terrain[right.y][right.x] = .Grass
		add_unit(g, .Kobold, red, left)
		add_unit(g, .Kobold, blue, right)
	}
}

setup_kobold_skirmish :: proc(g: ^Game) {
	generate_clumped_forest(g, 9, 3, 9)
	red := add_faction(g, "Red", .Human, RED)
	blue := add_faction(g, "Blue", .Computer, BLUE)
	place_kobold_armies(g, red, blue)
}

setup_kobold_watch :: proc(g: ^Game) {
	generate_clumped_forest(g, 9, 3, 9)
	red := add_faction(g, "Red", .Computer, RED)
	blue := add_faction(g, "Blue", .Computer, BLUE)
	place_kobold_armies(g, red, blue)
}
