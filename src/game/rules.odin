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

// ---------------------------------------------------------------- weapons

// A weapon holds the attack: its dice and its range in hexes (1..1 is melee).
Weapon_Kind :: enum u8 {
	Dagger,
	Sling,
}

Weapon :: struct {
	name:      string,
	verb:      string, // for the log: "Red Kobold stabs Blue Kobold"
	attack:    Dice,
	min_range: int,
	max_range: int,
}

WEAPONS := [Weapon_Kind]Weapon {
	.Dagger = {name = "dagger", verb = "stabs", attack = {.White = 1, .Red = 0, .Black = 0}, min_range = 1, max_range = 1},
	.Sling  = {name = "sling", verb = "slings", attack = {.White = 1, .Red = 0, .Black = 0}, min_range = 2, max_range = 3},
}

Weapons :: bit_set[Weapon_Kind]

// Expected scores of a handful of dice, in sixths, for choosing between weapons.
dice_strength :: proc(d: Dice) -> int {
	total := 0
	for count, die in d { total += count * DIE_SCORE_SIXTHS[die] }
	return total
}

// ---------------------------------------------------------------- units

Unit_Kind :: enum u8 {
	Kobold,
	Kobold_Slinger,
}

Unit_Type :: struct {
	name:    string,
	short:   string, // for the log and the map counter
	weapons: Weapons, // carried weapons; the one used is picked by range
	defense: Dice,
	body:    int, // body points; the unit dies at 0
	move:    int, // movement points per turn
}

UNIT_TYPES := [Unit_Kind]Unit_Type {
	.Kobold = {
		name = "Kobold",
		short = "Kobold",
		weapons = {.Dagger},
		defense = {.White = 1, .Red = 0, .Black = 0},
		body = 1,
		move = 4,
	},
	.Kobold_Slinger = {
		name = "Kobold Slinger",
		short = "Slinger",
		weapons = {.Sling, .Dagger},
		defense = {.White = 1, .Red = 0, .Black = 0},
		body = 1,
		move = 4,
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
	done:       bool, // has ended its move this turn (by choice, or by attacking)
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
	// per faction and weapon, for balance tools
	attacks:       [MAX_FACTIONS][Weapon_Kind]int,
	kills:         [MAX_FACTIONS][Weapon_Kind]int,
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
	if !u.alive || u.done || !in_bounds(dest) || dest == u.pos { return false }
	if unit_at(g, dest) >= 0 { return false }
	c := costs[dest.y][dest.x]
	return c != UNREACHABLE && c <= u.moves_left
}

move_unit :: proc(g: ^Game, unit: int, dest: Hex) -> bool {
	if g.winner >= 0 || g.units[unit].faction != g.current || g.units[unit].done { return false }
	costs := movement_costs(g, unit)
	if !can_move(g, unit, dest, &costs) { return false }
	u := &g.units[unit]
	u.moves_left -= costs[dest.y][dest.x]
	u.pos = dest
	return true
}

// ---------------------------------------------------------------- combat

weapon_reaches :: proc(w: Weapon_Kind, distance: int) -> bool {
	return distance >= WEAPONS[w].min_range && distance <= WEAPONS[w].max_range
}

// Line of sight between two hexes: blocked if forest stands on a hex strictly
// between them (the two end hexes never block, so a unit in a forest can see and
// be seen from outside it). A line that runs exactly along hex edges is clear if
// either side of the edge is clear.
line_of_sight :: proc(g: ^Game, a, b: Hex) -> bool {
	clear_side :: proc(g: ^Game, a, b: Hex, nudge: f64) -> bool {
		line, n := hexes_between(a, b, nudge)
		for h in line[:n] {
			// on a staggered map a line between edge hexes can graze just off
			// the map; nothing grows there
			if in_bounds(h) && terrain_at(g, h) == .Forest { return false }
		}
		return true
	}
	return clear_side(g, a, b, 1) || clear_side(g, a, b, -1)
}

// Ranged attacks (beyond 1 hex) need line of sight; melee never does.
needs_line_of_sight :: proc(distance: int) -> bool {
	return distance > 1
}

// The weapon a unit standing on `from` would use against a target on `to`: of
// the weapons that reach (and, at range, can see), the one with the strongest
// dice (the first listed on a tie).
weapon_for :: proc(g: ^Game, ut: ^Unit_Type, from, to: Hex) -> (best: Weapon_Kind, ok: bool) {
	distance := hex_distance(from, to)
	for w in ut.weapons {
		if !weapon_reaches(w, distance) { continue }
		if !ok || dice_strength(WEAPONS[w].attack) > dice_strength(WEAPONS[best].attack) {
			best = w
			ok = true
		}
	}
	// trace the line only when something reaches (it is the costly part)
	if ok && needs_line_of_sight(distance) && !line_of_sight(g, from, to) { ok = false }
	return
}

// The weapon the attacker would use on the target, if it can attack it now.
attack_weapon :: proc(g: ^Game, attacker, target: int) -> (w: Weapon_Kind, ok: bool) {
	a := &g.units[attacker]
	t := &g.units[target]
	if !a.alive || !t.alive || a.attacked || a.faction == t.faction { return }
	return weapon_for(g, unit_type(a), a.pos, t.pos)
}

can_attack :: proc(g: ^Game, attacker, target: int) -> bool {
	_, ok := attack_weapon(g, attacker, target)
	return ok
}

// Shortest and longest reach over all of a unit type's weapons.
unit_reach :: proc(ut: ^Unit_Type) -> (lo, hi: int) {
	lo = max(int)
	for w in ut.weapons {
		lo = min(lo, WEAPONS[w].min_range)
		hi = max(hi, WEAPONS[w].max_range)
	}
	return
}

Attack_Result :: struct {
	weapon: Weapon_Kind,
	hits:   int, // scores on the attack dice
	blocks: int, // scores on the defence dice
	damage: int, // body points lost
	killed: bool,
}

// Attacking also ends the attacker's movement for the turn.
// The attacker rolls its weapon's attack dice (the weapon is picked by range),
// the target rolls its defence dice; each block cancels one hit, and every hit
// left costs the target a body point.
attack :: proc(g: ^Game, attacker, target: int) -> (res: Attack_Result, ok: bool) {
	if g.winner >= 0 || g.units[attacker].faction != g.current || g.units[attacker].done { return }
	weapon := attack_weapon(g, attacker, target) or_return
	a := &g.units[attacker]
	t := &g.units[target]
	res.weapon = weapon
	res.hits = roll_dice(&g.rng, WEAPONS[weapon].attack)
	res.blocks = roll_dice(&g.rng, unit_type(t).defense)
	res.damage = max(0, res.hits - res.blocks)
	a.attacked = true
	a.moves_left = 0 // attacking ends the unit's movement
	a.done = true
	g.attacks[a.faction][weapon] += 1
	t.body -= res.damage
	if t.body <= 0 {
		t.body = 0
		t.alive = false
		res.killed = true
		g.kills[a.faction][weapon] += 1
	}
	aname := g.factions[a.faction].name
	tname := g.factions[t.faction].name
	// "Red Slinger slings Blue Kobold: 1 hit 0 block, slain"
	add_log(g, "%s %s %s %s %s: %d hit %d block, %s", aname, unit_type(a).short, WEAPONS[weapon].verb,
		tname, unit_type(t).short, res.hits, res.blocks, "slain" if res.killed else "no harm")
	check_winner(g)
	return res, true
}

// Finishes a unit's move for this turn (the player's "Finish move"): it may not
// move or attack again until its side's next turn. Returns false if it is not
// that side's turn or the unit has already finished.
finish_move :: proc(g: ^Game, unit: int) -> bool {
	u := &g.units[unit]
	if g.winner >= 0 || !u.alive || u.faction != g.current || u.done { return false }
	u.done = true
	return true
}

// True when the unit's move is over for this turn: it was ended, it has
// attacked (which ends it), or it has no movement left and no enemy in range.
unit_finished :: proc(g: ^Game, unit: int) -> bool {
	u := &g.units[unit]
	if u.faction != g.current { return false }
	if u.done || u.attacked { return true }
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

// Living units of the side to move whose move is not over yet.
units_left_to_act :: proc(g: ^Game) -> int {
	n := 0
	for i in 0 ..< g.unit_count {
		if g.units[i].alive && g.units[i].faction == g.current && !unit_finished(g, i) { n += 1 }
	}
	return n
}

// Passes play to the next faction that still has units. Refused (false) while
// any unit of the side to move has not ended its move.
end_turn :: proc(g: ^Game) -> bool {
	if g.winner >= 0 || units_left_to_act(g) > 0 { return false }
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
	return true
}
