package game

// Fog of war. Each side sees what its living units can see:
//   - a unit sees every hex within its type's `vision` that it has line of
//     sight to (terrain and elevation only: units do not block sight);
//   - a unit standing in forest is only seen by enemies within FOREST_SIGHT
//     hexes (still needing line of sight);
//   - hexes a side has ever seen stay explored (`seen`); hexes in sight right
//     now are `in_view`; hexes where a unit would be seen are `watched`;
//   - an enemy that goes out of sight leaves a `last_seen` marker where it was
//     last seen. The marker goes when that side looks at the hex again (one of
//     its units moves, or its turn starts) and finds the enemy gone.
// With `g.fog` false every side sees everything (old tests, tools/sim.sh -nofog).

FOREST_SIGHT :: 2

Sighting :: struct {
	pos:   Hex,
	valid: bool,
}

// One bit per hex: bit `col` of row `row`.
Hex_Mask :: [ROWS]u32
#assert(COLS <= 32)

mask_has :: proc(m: ^Hex_Mask, h: Hex) -> bool {
	return m[h.y] & (1 << u32(h.x)) != 0
}

mask_set :: proc(m: ^Hex_Mask, h: Hex) {
	m[h.y] |= 1 << u32(h.x)
}

// What a unit of one kind sees from one hex. Terrain and elevation never change
// during a game, so each is worked out once (call clear_view_cache after
// changing the map under units that have already looked). The cache keeps one
// table per sight range in use; a fifth range is worked out each time instead
// (slower, never wrong). Only the hexes in sight are kept: which of them would
// show a unit (`watched`) follows from the forest and the distance.
VIEW_SLOTS :: 4

clear_view_cache :: proc(g: ^Game) {
	g.view_cache = {}
	g.view_ready = {}
	g.view_slots = {}
	g.open_ready = false
}

view_from :: proc(g: ^Game, kind: Unit_Kind, from: Hex) -> Hex_Mask {
	vision := UNIT_TYPES[kind].vision
	slot := -1
	for &v, i in g.view_slots {
		if v == 0 { v = vision }
		if v == vision {
			slot = i
			break
		}
	}
	if slot >= 0 && mask_has(&g.view_ready[slot], from) { return g.view_cache[slot][from.y][from.x] }
	seen: Hex_Mask
	for row in max(0, from.y - vision) ..= min(ROWS - 1, from.y + vision) {
		for col in max(0, from.x - vision - 1) ..= min(COLS - 1, from.x + vision + 1) {
			h := Hex{col, row}
			d := hex_distance(from, h)
			if d > vision || (d > 1 && !line_of_sight(g, from, h)) { continue }
			mask_set(&seen, h)
		}
	}
	if slot >= 0 {
		g.view_cache[slot][from.y][from.x] = seen
		mask_set(&g.view_ready[slot], from)
	}
	return seen
}

// Hexes that are not forest: a unit there is seen from anywhere in sight.
open_ground :: proc(g: ^Game) -> ^Hex_Mask {
	if !g.open_ready {
		g.open_mask = {}
		for row in 0 ..< ROWS {
			for col in 0 ..< COLS {
				if g.terrain[row][col] != .Forest { mask_set(&g.open_mask, Hex{col, row}) }
			}
		}
		g.open_ready = true
	}
	return &g.open_mask
}

// Adds what a unit of this kind sees from `from` to faction f's view.
look_from :: proc(g: ^Game, f: int, kind: Unit_Kind, from: Hex) {
	seen := view_from(g, kind, from)
	here: Hex_Mask
	mask_set(&here, from)
	near := mask_grow(here, FOREST_SIGHT)
	open := open_ground(g)
	for row in 0 ..< ROWS {
		g.seen[f][row] |= seen[row]
		g.in_view[f][row] |= seen[row]
		g.watched[f][row] |= seen[row] & (open[row] | near[row])
	}
}

// Notes the position of every enemy faction f can see now.
record_sightings :: proc(g: ^Game, f: int) {
	for i in 0 ..< g.unit_count {
		e := &g.units[i]
		if e.alive && e.faction != f && mask_has(&g.watched[f], e.pos) { g.last_seen[f][i] = {e.pos, true} }
	}
}

// Recomputes what every side sees from where its units stand now. Markers of
// faction `looking` (NO_FACTION: none) are dropped where it can see the
// hex again and the enemy is not there; markers of dead units always go.
update_vision :: proc(g: ^Game, looking: int) {
	if !g.fog { return }
	for f in 0 ..< g.faction_count {
		g.in_view[f] = {}
		g.watched[f] = {}
	}
	for i in 0 ..< g.unit_count {
		u := &g.units[i]
		if u.alive { look_from(g, u.faction, u.kind, u.pos) }
	}
	for f in 0 ..< g.faction_count {
		record_sightings(g, f)
		for i in 0 ..< g.unit_count {
			s := &g.last_seen[f][i]
			if !s.valid { continue }
			gone := g.units[i].pos != s.pos
			if !g.units[i].alive || (f == looking && gone && mask_has(&g.watched[f], s.pos)) { s.valid = false }
		}
	}
}

// Can faction f see this unit? Its own side always can; NO_FACTION sees all.
unit_visible :: proc(g: ^Game, unit: int, f: int) -> bool {
	u := &g.units[unit]
	return !g.fog || f == NO_FACTION || u.faction == f || mask_has(&g.watched[f], u.pos)
}

// Would a unit standing on h be seen by faction f now?
hex_watched :: proc(g: ^Game, f: int, h: Hex) -> bool {
	return !g.fog || f == NO_FACTION || mask_has(&g.watched[f], h)
}

// Has faction f ever seen this hex?
hex_seen :: proc(g: ^Game, f: int, h: Hex) -> bool {
	return !g.fog || f == NO_FACTION || mask_has(&g.seen[f], h)
}

// Is this hex in faction f's sight now?
hex_in_view :: proc(g: ^Game, f: int, h: Hex) -> bool {
	return !g.fog || f == NO_FACTION || mask_has(&g.in_view[f], h)
}

// Where faction f last saw an enemy unit it cannot see now, if it remembers.
sighting :: proc(g: ^Game, f: int, unit: int) -> (Hex, bool) {
	if !g.fog || f == NO_FACTION || !g.units[unit].alive || unit_visible(g, unit, f) { return {}, false }
	s := g.last_seen[f][unit]
	return s.pos, s.valid
}
