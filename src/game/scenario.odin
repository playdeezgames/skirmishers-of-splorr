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
	{"Kobold Skirmish: 25% forest", setup_kobold_forest_25},
	{"Kobold Skirmish: 50% forest", setup_kobold_forest_50},
	{"Kobold Skirmish: 75% forest", setup_kobold_forest_75},
	{"Kobold Skirmish: some hills", setup_kobold_hills_15},
	{"Kobold Skirmish: hilly", setup_kobold_hills_35},
	{"Kobold Warband", setup_kobold_warband},
	{"Shield Wall vs Skirmishers", setup_shield_wall},
	{"Champion's Guard vs the Horde", setup_champions_guard},
	{"Ambush in the Woods", setup_woods_ambush},
	{"Archers on the Heights", setup_archer_heights},
	{"River Crossing", setup_river_crossing},
	{"Walled Farmsteads", setup_walled_farmsteads},
}

RED :: [3]f32{0.85, 0.25, 0.2}
BLUE :: [3]f32{0.2, 0.45, 0.9}

new_game :: proc(g: ^Game, scenario: int, seed: u64) {
	begin_game(g, SCENARIOS[scenario].name, seed)
	SCENARIOS[scenario].setup(g)
	finish_setup(g)
}

// What every new game starts from, whatever builds it.
begin_game :: proc(g: ^Game, name: string, seed: u64) {
	g^ = {}
	g.name = name
	g.winner = -1
	g.turn = 1
	g.rng = {seed}
	g.fog = true // fog of war in every battle
}

// After the map and units are in place: the first turn starts.
finish_setup :: proc(g: ^Game) {
	start_faction_turn(g)
	update_vision(g, NO_FACTION)
	add_log(g, "%s: turn 1", g.name)
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

forest_count :: proc(g: ^Game) -> int {
	n := 0
	for row in g.terrain { for t in row { if t == .Forest { n += 1 } } }
	return n
}

// Grows forest clumps on open grass until `percent` of the map is forest. Road
// and hexes with units are left alone, so call it after the road and the units.
// Each clump starts on a random grass hex and grows to 3..12 hexes by spreading
// to random neighbours.
grow_forest_to :: proc(g: ^Game, percent: int) {
	target := ROWS * COLS * percent / 100
	open :: proc(g: ^Game, h: Hex) -> bool {
		return g.terrain[h.y][h.x] == .Grass && unit_at(g, h) < 0
	}
	count := forest_count(g)
	for count < target {
		// a random open hex to start the clump (give up if there are none)
		seed := Hex{-1, -1}
		for _ in 0 ..< 1000 {
			h := Hex{rng_int(&g.rng, COLS), rng_int(&g.rng, ROWS)}
			if open(g, h) { seed = h; break }
		}
		if seed.x < 0 { break }
		cells: [12]Hex
		size := 3 + rng_int(&g.rng, len(cells) - 2)
		cells[0] = seed
		n := 1
		g.terrain[seed.y][seed.x] = .Forest
		count += 1
		for tries := 0; n < size && count < target && tries < 100; tries += 1 {
			nbs, nn := neighbours(cells[rng_int(&g.rng, n)])
			nb := nbs[rng_int(&g.rng, nn)]
			if !open(g, nb) { continue }
			g.terrain[nb.y][nb.x] = .Forest
			cells[n] = nb
			n += 1
			count += 1
		}
	}
}

high_count :: proc(g: ^Game) -> int {
	n := 0
	for row in g.high { for h in row { if h { n += 1 } } }
	return n
}

// Raises clumps of high ground until `percent` of the map is high. Height is
// separate from terrain, so hills can carry forest, road, walls or units, but
// never water.
grow_hills_to :: proc(g: ^Game, percent: int) {
	target := ROWS * COLS * percent / 100
	count := high_count(g)
	for count < target {
		seed := Hex{-1, -1}
		for _ in 0 ..< 1000 {
			h := Hex{rng_int(&g.rng, COLS), rng_int(&g.rng, ROWS)}
			if !is_high(g, h) && !is_water(terrain_at(g, h)) { seed = h; break }
		}
		if seed.x < 0 { break }
		cells: [16]Hex
		size := 4 + rng_int(&g.rng, len(cells) - 3)
		cells[0] = seed
		n := 1
		g.high[seed.y][seed.x] = true
		count += 1
		for tries := 0; n < size && count < target && tries < 100; tries += 1 {
			nbs, nn := neighbours(cells[rng_int(&g.rng, n)])
			nb := nbs[rng_int(&g.rng, nn)]
			if is_high(g, nb) || is_water(terrain_at(g, nb)) { continue } // water lies low
			g.high[nb.y][nb.x] = true
			cells[n] = nb
			n += 1
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
	// 15 kobolds and 5 slingers a side; rear units first, so the slingers stand
	// in the back column behind ten kobolds
	kinds: [20]Unit_Kind
	for i in 0 ..< 5 { kinds[i] = .Kobold_Slinger }
	place_block(g, red, kinds[:], true)
	place_block(g, blue, kinds[:], false)
}

// The four-kobold skirmish on a map that is `percent` forest: road first, then
// the armies on open ground, then forest clumps until the share is reached.
setup_kobold_forest :: proc(g: ^Game, percent: int) {
	for &row in g.terrain { for &t in row { t = .Grass } }
	generate_road(g, Road_Direction(rng_int(&g.rng, len(Road_Direction))))
	red := add_faction(g, "Red", .Human, RED)
	blue := add_faction(g, "Blue", .Computer, BLUE)
	place_kobold_armies(g, red, blue)
	grow_forest_to(g, percent)
}

setup_kobold_forest_25 :: proc(g: ^Game) { setup_kobold_forest(g, 25) }
setup_kobold_forest_50 :: proc(g: ^Game) { setup_kobold_forest(g, 50) }
setup_kobold_forest_75 :: proc(g: ^Game) { setup_kobold_forest(g, 75) }

// The four-kobold skirmish on the usual light woods and road, with `percent` of
// the map raised as high ground.
setup_kobold_hills :: proc(g: ^Game, percent: int) {
	setup_kobold_skirmish(g)
	grow_hills_to(g, percent)
}

setup_kobold_hills_15 :: proc(g: ^Game) { setup_kobold_hills(g, 15) }
setup_kobold_hills_35 :: proc(g: ^Game) { setup_kobold_hills(g, 35) }

// Nine a side, 204 points each: a champion, two heavies, a pike, a slinger,
// an archer, a crossbow, a scout and a Wololo, on the usual light woods and
// road.
setup_kobold_warband :: proc(g: ^Game) {
	generate_clumped_forest(g, 9, 3, 9)
	generate_road(g, Road_Direction(rng_int(&g.rng, len(Road_Direction))))
	red := add_faction(g, "Red", .Human, RED)
	blue := add_faction(g, "Blue", .Computer, BLUE)
	// rear units first (place_block fills the column nearest the edge first)
	kinds := [?]Unit_Kind{.Archer, .Heavy, .Pike, .Champion, .Wololo, .Scout, .Kobold_Slinger, .Heavy, .Crossbow}
	place_block(g, red, kinds[:], true, 2)
	place_block(g, blue, kinds[:], false, 2)
}

// Mixed bands: two different armies, Red (you) against Blue, balanced with
// tools/sim.sh at -inset 2 (win rates in the comments are computer vs
// computer, red first). `forest` < 0 means the usual light clumps; otherwise
// that share of the map grows round the armies. Kinds are rear units first.
setup_bands :: proc(g: ^Game, forest, hills: int, red_kinds, blue_kinds: []Unit_Kind, water := Water_Level.None, walls := Wall_Level.None) {
	if forest < 0 {
		generate_clumped_forest(g, 9, 3, 9)
	} else {
		for &row in g.terrain { for &t in row { t = .Grass } }
	}
	generate_road(g, Road_Direction(rng_int(&g.rng, len(Road_Direction))))
	red := add_faction(g, "Red", .Human, RED)
	blue := add_faction(g, "Blue", .Computer, BLUE)
	place_block(g, red, red_kinds, true, 2)
	place_block(g, blue, blue_kinds, false, 2)
	generate_water(g, water)
	generate_walls(g, walls)
	ensure_connected(g)
	if forest >= 0 { grow_forest_to(g, forest) }
	grow_hills_to(g, hills)
}

// Heavies, pikes, crossbows and a Wololo (142 points) against archers, a scout
// and a crowd of kobolds (141): 50% to 49%.
setup_shield_wall :: proc(g: ^Game) {
	red := [?]Unit_Kind{.Crossbow, .Heavy, .Pike, .Wololo, .Pike, .Heavy, .Crossbow}
	blue := [?]Unit_Kind{.Archer, .Kobold, .Archer, .Kobold, .Scout, .Kobold, .Archer, .Kobold, .Kobold, .Kobold, .Kobold}
	setup_bands(g, -1, 0, red[:], blue[:])
}

// A champion, two heavies, a Wololo and four kobolds (165 points) against
// thirteen kobolds and three slingers (166): 53% to 47%.
setup_champions_guard :: proc(g: ^Game) {
	red := [?]Unit_Kind{.Kobold, .Heavy, .Kobold, .Wololo, .Champion, .Kobold, .Heavy, .Kobold}
	blue := [?]Unit_Kind {
		.Kobold_Slinger, .Kobold, .Kobold, .Kobold, .Kobold_Slinger, .Kobold, .Kobold, .Kobold, .Kobold_Slinger, .Kobold,
		.Kobold, .Kobold, .Kobold, .Kobold, .Kobold, .Kobold,
	}
	setup_bands(g, -1, 0, red[:], blue[:])
}

// Half the map is forest, where bows see little: archers, a scout and kobolds
// (161 points) against heavies, a pike, crossbows and a Wololo (122): 51% to 48%.
// The archers' points overstate them here: forest is where bows are weakest.
setup_woods_ambush :: proc(g: ^Game) {
	red := [?]Unit_Kind{.Archer, .Kobold, .Archer, .Kobold, .Scout, .Kobold, .Archer, .Kobold, .Archer, .Kobold, .Kobold, .Kobold}
	blue := [?]Unit_Kind{.Crossbow, .Heavy, .Pike, .Wololo, .Heavy, .Crossbow}
	setup_bands(g, 50, 0, red[:], blue[:])
}

// Hilly ground, where bows shoot half as far again from high ground: four
// archers and two heavies (130 points) against a shield wall with two kobolds
// (162): 47% to 53%.
setup_archer_heights :: proc(g: ^Game) {
	red := [?]Unit_Kind{.Archer, .Heavy, .Archer, .Archer, .Heavy, .Archer}
	blue := [?]Unit_Kind{.Crossbow, .Kobold, .Heavy, .Pike, .Wololo, .Pike, .Heavy, .Kobold, .Crossbow}
	setup_bands(g, -1, 35, red[:], blue[:])
}

WARBAND := [?]Unit_Kind{.Archer, .Heavy, .Pike, .Champion, .Wololo, .Scout, .Kobold_Slinger, .Heavy, .Crossbow}

// The warband against itself (204 points a side) with a deep river between
// them, crossed only at two or three shallow fords (and by the road's bridge,
// if it crosses): 51% to 47% (400 games, 9 unfinished).
setup_river_crossing :: proc(g: ^Game) {
	setup_bands(g, -1, 0, WARBAND[:], WARBAND[:], water = .River)
}

// The warband against itself among walled farmsteads and field walls, with a
// stream across the middle: 52.5% to 46% (400 games).
setup_walled_farmsteads :: proc(g: ^Game) {
	setup_bands(g, -1, 0, WARBAND[:], WARBAND[:], water = .Stream, walls = .Many)
}
