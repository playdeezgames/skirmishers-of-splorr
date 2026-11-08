package game

// Water and walls for generated maps. Both are laid after the road and the
// armies (so they never cover either: a road over water is a bridge, and a
// road through a wall is its gate) and before forest and hills.

Water_Level :: enum u8 {
	None,
	Stream, // a shallow stream across the middle of the map
	River, // a deep river with shallow fords
	Ponds, // deep ponds with shallow edges
}

WATER_LEVELS := [Water_Level]string {
	.None   = "none",
	.Stream = "a stream",
	.River  = "a river with fords",
	.Ponds  = "ponds",
}

Wall_Level :: enum u8 {
	None,
	Some, // one walled farmstead and a couple of field walls
	Many,
}

WALL_LEVELS := [Wall_Level]string {
	.None = "none",
	.Some = "some",
	.Many = "many",
}

// Can water or a wall go here? On grass or forest (clearing it), not on the
// road, not under a unit, not on water or a wall already.
free_for_feature :: proc(g: ^Game, h: Hex) -> bool {
	if !in_bounds(h) || unit_at(g, h) >= 0 { return false }
	t := g.terrain[h.y][h.x]
	return t == .Grass || t == .Forest
}

generate_water :: proc(g: ^Game, level: Water_Level) {
	switch level {
	case .None:
	case .Stream: generate_river(g, false)
	case .River:  generate_river(g, true)
	case .Ponds:  generate_ponds(g)
	}
}

// A river from the top edge to the bottom, wandering through the middle
// columns between the armies. Each row's hex touches the one above it, so the
// band has no gaps. A stream is one hex of shallow water; a river is two hexes
// of deep water with two or three shallow fords (and the road, if it crosses,
// is a bridge).
generate_river :: proc(g: ^Game, deep: bool) {
	LO :: 7
	HI :: 11 // leftmost column of the band; with the river's second hex, 12
	x := LO + rng_int(&g.rng, HI - LO + 1)
	fords: [ROWS]bool
	if deep {
		// spread out: one in each third of the map, the middle one maybe not
		thirds := [3]int{2, 8, 14}
		for t, i in thirds {
			if i == 1 && rng_int(&g.rng, 2) == 0 { continue }
			fords[t + rng_int(&g.rng, 4)] = true
		}
	}
	for row in 0 ..< ROWS {
		width := 2 if deep else 1
		for k in 0 ..< width {
			h := Hex{x + k, row}
			if !free_for_feature(g, h) { continue }
			g.terrain[h.y][h.x] = .Shallow if !deep || fords[row] else .Deep
		}
		// the next row's hex must touch this one: on an even row the hexes
		// below are x-1 and x, on an odd row x and x+1 ("odd-r" layout)
		step := rng_int(&g.rng, 2)
		x += step - 1 if row % 2 == 0 else step
		x = clamp(x, LO, HI)
	}
}

// Two or three ponds of deep water, each ringed by shallows.
generate_ponds :: proc(g: ^Game) {
	ponds := 2 + rng_int(&g.rng, 2)
	for _ in 0 ..< ponds {
		seed := Hex{-1, -1}
		for _ in 0 ..< 200 {
			h := Hex{5 + rng_int(&g.rng, COLS - 10), 1 + rng_int(&g.rng, ROWS - 2)}
			if free_for_feature(g, h) { seed = h; break }
		}
		if seed.x < 0 { continue }
		cells: [10]Hex
		size := 3 + rng_int(&g.rng, len(cells) - 2)
		cells[0] = seed
		n := 1
		g.terrain[seed.y][seed.x] = .Deep
		for tries := 0; n < size && tries < 60; tries += 1 {
			nbs, nn := neighbours(cells[rng_int(&g.rng, n)])
			nb := nbs[rng_int(&g.rng, nn)]
			if !free_for_feature(g, nb) { continue }
			g.terrain[nb.y][nb.x] = .Deep
			cells[n] = nb
			n += 1
		}
		for c in cells[:n] {
			nbs, nn := neighbours(c)
			for nb in nbs[:nn] {
				if free_for_feature(g, nb) { g.terrain[nb.y][nb.x] = .Shallow }
			}
		}
	}
}

// Walled farmsteads (a ring of wall round a yard, with two gates on opposite
// sides) and short field walls, wooden or stone at random.
generate_walls :: proc(g: ^Game, level: Wall_Level) {
	farms, lines := 0, 0
	switch level {
	case .None: return
	case .Some: farms, lines = 1, 2
	case .Many: farms, lines = 2, 5
	}
	for _ in 0 ..< farms { generate_farmstead(g) }
	for _ in 0 ..< lines { generate_field_wall(g) }
}

wall_kind :: proc(g: ^Game) -> Terrain {
	return .Stone_Wall if rng_int(&g.rng, 2) == 0 else .Wood_Wall
}

// The six hexes round `c`, `r` steps out, walked in order (a hex ring).
ring_hexes :: proc(c: Hex, r: int) -> (out: [36]Hex, n: int) {
	// walk r steps in one direction, then r along each of the six sides
	h := c
	for _ in 0 ..< r { h = neighbour_dir(h, 4) }
	for side in 0 ..< 6 {
		for _ in 0 ..< r {
			out[n] = h
			n += 1
			h = neighbour_dir(h, side)
		}
	}
	return
}

generate_farmstead :: proc(g: ^Game) {
	for _ in 0 ..< 40 {
		c := Hex{6 + rng_int(&g.rng, COLS - 12), 3 + rng_int(&g.rng, ROWS - 6)}
		ring, n := ring_hexes(c, 2)
		ok := true
		for h in ring[:n] {
			if !in_bounds(h) || is_water(terrain_at(g, h)) || is_wall(terrain_at(g, h)) { ok = false; break }
		}
		if !ok { continue }
		kind := wall_kind(g)
		gate := rng_int(&g.rng, n / 2)
		for h, i in ring[:n] {
			if i == gate || i == gate + n / 2 { continue } // two gates, opposite
			if free_for_feature(g, h) { g.terrain[h.y][h.x] = kind }
		}
		return
	}
}

generate_field_wall :: proc(g: ^Game) {
	for _ in 0 ..< 40 {
		h := Hex{5 + rng_int(&g.rng, COLS - 10), 1 + rng_int(&g.rng, ROWS - 2)}
		if !free_for_feature(g, h) { continue }
		dir := rng_int(&g.rng, 6)
		length := 3 + rng_int(&g.rng, 4)
		kind := wall_kind(g)
		for _ in 0 ..< length {
			if !free_for_feature(g, h) { break }
			g.terrain[h.y][h.x] = kind
			// wander a little: mostly straight on, sometimes a bend
			if rng_int(&g.rng, 4) == 0 { dir = (dir + 5 + 2 * rng_int(&g.rng, 2)) % 6 }
			h = neighbour_dir(h, dir)
		}
		return
	}
}

// Every unit must be able to walk to every enemy. If water and walls have
// shut anyone in, walls give way to grass and deep water to shallows until
// they can.
ensure_connected :: proc(g: ^Game) {
	if armies_connected(g) { return }
	for &row in g.terrain {
		for &t in row {
			if is_wall(t) { t = .Grass }
		}
	}
	if armies_connected(g) { return }
	for &row in g.terrain {
		for &t in row {
			if t == .Deep { t = .Shallow }
		}
	}
}

armies_connected :: proc(g: ^Game) -> bool {
	if g.unit_count == 0 { return true }
	start := [1]Hex{g.units[0].pos}
	d := walk_distances(g, start[:])
	for i in 0 ..< g.unit_count {
		p := g.units[i].pos
		if d[p.y][p.x] == UNREACHABLE { return false }
	}
	return true
}
