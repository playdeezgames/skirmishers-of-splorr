package game

import "core:fmt"

// ---------------------------------------------------------------- terrain

Terrain :: enum u8 {
	Grass,
	Forest,
	Road,
}

TERRAIN_NAMES := [Terrain]string {
	.Grass  = "Grass",
	.Forest = "Forest",
	.Road   = "Road",
}

// Movement points spent to enter a hex of this terrain. Moving from road to
// road is cheaper still (ROAD_TO_ROAD_HALVES); leaving a road onto other terrain
// costs that terrain's full amount.
TERRAIN_MOVE_COST := [Terrain]int {
	.Grass  = 1,
	.Forest = 2,
	.Road   = 1,
}

// Movement is counted in half points so a road step can cost 1/2.
HALVES_PER_POINT :: 2
ROAD_TO_ROAD_HALVES :: 1

// Cost in half points of stepping from one hex into a neighbouring one.
step_cost :: proc(from, to: Terrain) -> int {
	if from == .Road && to == .Road { return ROAD_TO_ROAD_HALVES }
	return TERRAIN_MOVE_COST[to] * HALVES_PER_POINT
}

// ---------------------------------------------------------------- dice

// Combat dice. A die "scores" with the chance below: on an attack die a score is
// a hit, on a defence die it is a block.
Die :: enum u8 {
	White,
	Red,
	Black,
}

DIE_NAMES := [Die]string {
	.White = "white",
	.Red   = "red",
	.Black = "black",
}

// Chance of scoring, in sixths: white 1/3, red 1/2, black 2/3.
DIE_SCORE_SIXTHS := [Die]int {
	.White = 2,
	.Red   = 3,
	.Black = 4,
}

// A handful of dice: how many of each colour.
Dice :: [Die]int

roll_die :: proc(r: ^Rng, d: Die) -> bool {
	return rng_int(r, 6) < DIE_SCORE_SIXTHS[d]
}

// Rolls every die in the handful and counts the scores.
roll_dice :: proc(r: ^Rng, dice: Dice) -> int {
	score := 0
	for count, d in dice {
		for _ in 0 ..< count {
			if roll_die(r, d) { score += 1 }
		}
	}
	return score
}

// ---------------------------------------------------------------- units

Unit_Kind :: enum u8 {
	Kobold,
}

Unit_Type :: struct {
	name:      string,
	attack:    Dice,
	defense:   Dice,
	body:      int, // body points; the unit dies at 0
	move:      int, // movement points per turn
	min_range: int, // attack range in hexes; 1..1 is melee only
	max_range: int,
}

UNIT_TYPES := [Unit_Kind]Unit_Type {
	.Kobold = {
		name = "Kobold",
		attack = {.White = 1, .Red = 0, .Black = 0},
		defense = {.White = 1, .Red = 0, .Black = 0},
		body = 1,
		move = 4,
		min_range = 1,
		max_range = 1,
	},
}

Unit :: struct {
	kind:       Unit_Kind,
	faction:    int,
	pos:        Hex,
	body:       int,
	alive:      bool,
	moves_left: int, // in half points (HALVES_PER_POINT)
	attacked:   bool, // has made its attack this turn
	done:       bool, // the computer has finished with it this turn
}

unit_type :: proc(u: ^Unit) -> ^Unit_Type {
	return &UNIT_TYPES[u.kind]
}

// ---------------------------------------------------------------- factions

Controller :: enum u8 {
	Human,
	Computer,
}

Faction :: struct {
	name:       string,
	controller: Controller,
	color:      [3]f32,
}

// ---------------------------------------------------------------- game state

MAX_UNITS :: 64
MAX_FACTIONS :: 4
LOG_LINES :: 12
LOG_WIDTH :: 96

Log_Line :: struct {
	buf: [LOG_WIDTH]u8,
	len: int,
}

Game :: struct {
	terrain:       [ROWS][COLS]Terrain,
	units:         [MAX_UNITS]Unit,
	unit_count:    int,
	factions:      [MAX_FACTIONS]Faction,
	faction_count: int,
	current:       int, // faction whose turn it is
	turn:          int, // round number, from 1
	winner:        int, // faction index, or -1 while the game goes on
	rng:           Rng,
	log:           [LOG_LINES]Log_Line, // ring buffer, newest at log_next-1
	log_next:      int,
	log_count:     int,
}

add_log :: proc(g: ^Game, format: string, args: ..any) {
	line := &g.log[g.log_next]
	s := fmt.bprintf(line.buf[:], format, ..args)
	line.len = len(s)
	g.log_next = (g.log_next + 1) % LOG_LINES
	g.log_count = min(g.log_count + 1, LOG_LINES)
}

// The i-th most recent log line (0 is the newest).
log_line :: proc(g: ^Game, i: int) -> string {
	idx := (g.log_next - 1 - i + 2 * LOG_LINES) % LOG_LINES
	return string(g.log[idx].buf[:g.log[idx].len])
}

terrain_at :: proc(g: ^Game, h: Hex) -> Terrain {
	return g.terrain[h.y][h.x]
}

// Index of the living unit on h, or -1.
unit_at :: proc(g: ^Game, h: Hex) -> int {
	for i in 0 ..< g.unit_count {
		u := &g.units[i]
		if u.alive && u.pos == h { return i }
	}
	return -1
}

add_unit :: proc(g: ^Game, kind: Unit_Kind, faction: int, pos: Hex) -> int {
	assert(g.unit_count < MAX_UNITS)
	assert(unit_at(g, pos) < 0)
	t := &UNIT_TYPES[kind]
	idx := g.unit_count
	g.units[idx] = {
		kind       = kind,
		faction    = faction,
		pos        = pos,
		body       = t.body,
		alive      = true,
		moves_left = t.move * HALVES_PER_POINT,
	}
	g.unit_count += 1
	return idx
}

add_faction :: proc(g: ^Game, name: string, controller: Controller, color: [3]f32) -> int {
	assert(g.faction_count < MAX_FACTIONS)
	g.factions[g.faction_count] = {name, controller, color}
	g.faction_count += 1
	return g.faction_count - 1
}

living_units :: proc(g: ^Game, faction: int) -> int {
	n := 0
	for i in 0 ..< g.unit_count {
		if g.units[i].alive && g.units[i].faction == faction { n += 1 }
	}
	return n
}

// ---------------------------------------------------------------- movement

UNREACHABLE :: -1

// Cheapest movement cost, in half points, from the unit's hex to every hex, ignoring its
// remaining points (UNREACHABLE where there is no way in). Units may pass through
// friends but not enemies; whether a hex can be stopped on is can_move's job.
movement_costs :: proc(g: ^Game, unit: int) -> (cost: [ROWS][COLS]int) {
	u := &g.units[unit]
	for &row in cost { for &c in row { c = UNREACHABLE } }
	// who stands where, so the search does not rescan the unit list
	blocked: [ROWS][COLS]bool
	for i in 0 ..< g.unit_count {
		o := &g.units[i]
		if o.alive && o.faction != u.faction { blocked[o.pos.y][o.pos.x] = true }
	}
	heap: Cost_Heap
	cost[u.pos.y][u.pos.x] = 0
	heap_push(&heap, {0, u.pos})
	for heap.count > 0 {
		e := heap_pop(&heap)
		if e.cost > cost[e.hex.y][e.hex.x] { continue } // stale entry
		from := terrain_at(g, e.hex)
		nbs, n := neighbours(e.hex)
		for nb in nbs[:n] {
			if blocked[nb.y][nb.x] { continue }
			c := e.cost + step_cost(from, terrain_at(g, nb))
			old := cost[nb.y][nb.x]
			if old == UNREACHABLE || c < old {
				cost[nb.y][nb.x] = c
				heap_push(&heap, {c, nb})
			}
		}
	}
	return
}

// A fixed-size min-heap for movement_costs; each hex is pushed at most once per
// improvement, and there are at most 6 improvements per hex.
Cost_Entry :: struct {
	cost: int,
	hex:  Hex,
}

Cost_Heap :: struct {
	items: [ROWS * COLS * 6 + 1]Cost_Entry,
	count: int,
}

heap_push :: proc(h: ^Cost_Heap, e: Cost_Entry) {
	i := h.count
	h.items[i] = e
	h.count += 1
	for i > 0 {
		parent := (i - 1) / 2
		if h.items[parent].cost <= h.items[i].cost { break }
		h.items[parent], h.items[i] = h.items[i], h.items[parent]
		i = parent
	}
}

heap_pop :: proc(h: ^Cost_Heap) -> Cost_Entry {
	top := h.items[0]
	h.count -= 1
	h.items[0] = h.items[h.count]
	i := 0
	for {
		l := 2 * i + 1
		r := l + 1
		m := i
		if l < h.count && h.items[l].cost < h.items[m].cost { m = l }
		if r < h.count && h.items[r].cost < h.items[m].cost { m = r }
		if m == i { break }
		h.items[m], h.items[i] = h.items[i], h.items[m]
		i = m
	}
	return top
}

can_move :: proc(g: ^Game, unit: int, dest: Hex, costs: ^[ROWS][COLS]int) -> bool {
	u := &g.units[unit]
	if !u.alive || !in_bounds(dest) || dest == u.pos { return false }
	if unit_at(g, dest) >= 0 { return false }
	c := costs[dest.y][dest.x]
	return c != UNREACHABLE && c <= u.moves_left
}

move_unit :: proc(g: ^Game, unit: int, dest: Hex) -> bool {
	if g.winner >= 0 || g.units[unit].faction != g.current { return false }
	costs := movement_costs(g, unit)
	if !can_move(g, unit, dest, &costs) { return false }
	u := &g.units[unit]
	u.moves_left -= costs[dest.y][dest.x]
	u.pos = dest
	return true
}

// ---------------------------------------------------------------- combat

can_attack :: proc(g: ^Game, attacker, target: int) -> bool {
	a := &g.units[attacker]
	t := &g.units[target]
	if !a.alive || !t.alive || a.attacked || a.faction == t.faction { return false }
	d := hex_distance(a.pos, t.pos)
	at := unit_type(a)
	return d >= at.min_range && d <= at.max_range
}

Attack_Result :: struct {
	hits:   int, // scores on the attack dice
	blocks: int, // scores on the defence dice
	damage: int, // body points lost
	killed: bool,
}

// Attacking also ends the attacker's movement for the turn.
// Attacker rolls its attack dice, the target rolls its defence dice; each block
// cancels one hit, and every hit left costs the target a body point.
attack :: proc(g: ^Game, attacker, target: int) -> (res: Attack_Result, ok: bool) {
	if g.winner >= 0 || g.units[attacker].faction != g.current { return }
	if !can_attack(g, attacker, target) { return }
	a := &g.units[attacker]
	t := &g.units[target]
	res.hits = roll_dice(&g.rng, unit_type(a).attack)
	res.blocks = roll_dice(&g.rng, unit_type(t).defense)
	res.damage = max(0, res.hits - res.blocks)
	a.attacked = true
	a.moves_left = 0 // attacking ends the unit's movement
	t.body -= res.damage
	if t.body <= 0 {
		t.body = 0
		t.alive = false
		res.killed = true
	}
	aname := g.factions[a.faction].name
	tname := g.factions[t.faction].name
	if res.killed {
		add_log(g, "%s %s hits %d, blocks %d: %s %s slain", aname, unit_type(a).name, res.hits, res.blocks, tname, unit_type(t).name)
	} else {
		add_log(g, "%s %s hits %d, blocks %d: no harm", aname, unit_type(a).name, res.hits, res.blocks)
	}
	check_winner(g)
	return res, true
}

// True when the unit can do nothing more this turn: it has attacked (which also
// ends movement), or it has no movement left and no enemy in range.
unit_finished :: proc(g: ^Game, unit: int) -> bool {
	u := &g.units[unit]
	if u.faction != g.current { return false }
	if u.attacked { return true }
	if u.moves_left > 0 { return false }
	for i in 0 ..< g.unit_count {
		if can_attack(g, unit, i) { return false }
	}
	return true
}

// True when the unit has spent any movement this turn.
unit_has_moved :: proc(g: ^Game, unit: int) -> bool {
	u := &g.units[unit]
	return u.faction == g.current && u.moves_left < unit_type(u).move * HALVES_PER_POINT
}

check_winner :: proc(g: ^Game) {
	alive_faction := -1
	for f in 0 ..< g.faction_count {
		if living_units(g, f) > 0 {
			if alive_faction >= 0 { return }
			alive_faction = f
		}
	}
	if alive_faction >= 0 {
		g.winner = alive_faction
		add_log(g, "%s win!", g.factions[alive_faction].name)
	}
}

// ---------------------------------------------------------------- turns

start_faction_turn :: proc(g: ^Game) {
	for i in 0 ..< g.unit_count {
		u := &g.units[i]
		if u.faction == g.current {
			u.moves_left = unit_type(u).move * HALVES_PER_POINT
			u.attacked = false
			u.done = false
		}
	}
}

// Passes play to the next faction that still has units.
end_turn :: proc(g: ^Game) {
	if g.winner >= 0 { return }
	for _ in 0 ..< g.faction_count {
		g.current += 1
		if g.current >= g.faction_count {
			g.current = 0
			g.turn += 1
		}
		if living_units(g, g.current) > 0 { break }
	}
	start_faction_turn(g)
	add_log(g, "Turn %d: %s to move", g.turn, g.factions[g.current].name)
}
