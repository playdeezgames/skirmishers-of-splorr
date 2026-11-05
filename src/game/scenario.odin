package game

// A scenario builds the map, the factions (and who controls each) and the units.

Scenario :: struct {
	name:  string,
	setup: proc(g: ^Game),
}

SCENARIOS := [?]Scenario {
	{"Kobold Skirmish", setup_kobold_skirmish},
	{"Kobold Skirmish (computer vs computer)", setup_kobold_watch},
	{"Kobold Battle: 20 vs 20", setup_kobold_battle},
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

Road_Direction :: enum u8 {
	East_West,
	North_South,
}

// Lays a road from one edge of the map to the opposite edge. Each step moves to
// a neighbour that is closer to the far end, picked at random among those, so
// the road wanders but always connects. Road replaces whatever was there.
generate_road :: proc(g: ^Game, dir: Road_Direction) -> (start, end: Hex) {
	// keep the ends away from the corners
	lo := 4
	switch dir {
	case .East_West:
		start = {0, lo + rng_int(&g.rng, ROWS - 2 * lo)}
		end = {COLS - 1, lo + rng_int(&g.rng, ROWS - 2 * lo)}
	case .North_South:
		start = {lo + rng_int(&g.rng, COLS - 2 * lo), 0}
		end = {lo + rng_int(&g.rng, COLS - 2 * lo), ROWS - 1}
	}
	h := start
	g.terrain[h.y][h.x] = .Road
	for h != end {
		nbs, n := neighbours(h)
		closer: [6]Hex
		count := 0
		d := hex_distance(h, end)
		for nb in nbs[:n] {
			if hex_distance(nb, end) < d {
				closer[count] = nb
				count += 1
			}
		}
		h = closer[rng_int(&g.rng, count)]
		g.terrain[h.y][h.x] = .Road
	}
	return
}

// Two lines of four kobolds facing each other across the map: daggers on the
// flanks, slingers in the middle.
place_kobold_armies :: proc(g: ^Game, red, blue: int) {
	rows := [4]int{6, 8, 11, 13}
	kinds := [4]Unit_Kind{.Kobold, .Kobold_Slinger, .Kobold_Slinger, .Kobold}
	for r, i in rows {
		left := Hex{2, r}
		right := Hex{COLS - 3, r}
		if g.terrain[left.y][left.x] == .Forest { g.terrain[left.y][left.x] = .Grass }
		if g.terrain[right.y][right.x] == .Forest { g.terrain[right.y][right.x] = .Grass }
		add_unit(g, kinds[i], red, left)
		add_unit(g, kinds[i], blue, right)
	}
}

setup_kobold_skirmish :: proc(g: ^Game) {
	generate_clumped_forest(g, 9, 3, 9)
	generate_road(g, Road_Direction(rng_int(&g.rng, len(Road_Direction))))
	red := add_faction(g, "Red", .Human, RED)
	blue := add_faction(g, "Blue", .Computer, BLUE)
	place_kobold_armies(g, red, blue)
}

setup_kobold_watch :: proc(g: ^Game) {
	generate_clumped_forest(g, 9, 3, 9)
	generate_road(g, Road_Direction(rng_int(&g.rng, len(Road_Direction))))
	red := add_faction(g, "Red", .Computer, RED)
	blue := add_faction(g, "Blue", .Computer, BLUE)
	place_kobold_armies(g, red, blue)
}

// A block of units in columns of up to 10 rows across the middle of the map,
// starting `inset` columns in from the faction's edge (left or right). The first
// units fill the column nearest the edge, so list rear units first.
place_block :: proc(g: ^Game, faction: int, kinds: []Unit_Kind, left: bool, inset := 1) {
	BLOCK_ROWS :: 10
	first_row := (ROWS - BLOCK_ROWS) / 2
	for kind, i in kinds {
		col := inset + i / BLOCK_ROWS
		row := first_row + i % BLOCK_ROWS
		h := Hex{col, row} if left else Hex{COLS - 1 - col, row}
		if g.terrain[h.y][h.x] == .Forest { g.terrain[h.y][h.x] = .Grass }
		add_unit(g, kind, faction, h)
	}
}

setup_kobold_battle :: proc(g: ^Game) {
	generate_clumped_forest(g, 9, 3, 9)
	generate_road(g, Road_Direction(rng_int(&g.rng, len(Road_Direction))))
	red := add_faction(g, "Red", .Computer, RED)
	blue := add_faction(g, "Blue", .Computer, BLUE)
	kinds: [20]Unit_Kind // all daggers
	place_block(g, red, kinds[:], true)
	place_block(g, blue, kinds[:], false)
}
