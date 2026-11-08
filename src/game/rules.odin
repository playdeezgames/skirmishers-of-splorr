package game

import "core:fmt"

// ---------------------------------------------------------------- terrain

Terrain :: enum u8 {
	Grass,
	Forest,
	Road,
	Shallow, // shallow water: slow going
	Deep, // deep water: nobody crosses it (a road over it is a bridge)
	Wood_Wall, // a palisade
	Stone_Wall,
	Cracked_Wall, // a stone wall a sapper has struck once: still a wall
	Rubble, // what a sapper leaves of a wall: slow going, blocks nothing
}

TERRAIN_NAMES := [Terrain]string {
	.Grass      = "Grass",
	.Forest     = "Forest",
	.Road       = "Road",
	.Shallow    = "Shallow water",
	.Deep       = "Deep water",
	.Wood_Wall  = "Wooden wall",
	.Stone_Wall = "Stone wall",
	.Cracked_Wall = "Cracked stone wall",
	.Rubble     = "Rubble",
}

// Deep water and walls cannot be entered. Walls also block sight, except to
// a unit right next to them (it looks over), and give cover from shots to a
// unit right behind them (see line_of_sight and wall_cover). A sapper breaks
// a wooden wall into rubble with one blow and a stone wall with two (it
// cracks first; see demolish).
TERRAIN_PASSABLE := [Terrain]bool {
	.Grass      = true,
	.Forest     = true,
	.Road       = true,
	.Shallow    = true,
	.Deep       = false,
	.Wood_Wall  = false,
	.Stone_Wall = false,
	.Cracked_Wall = false,
	.Rubble     = true,
}

is_wall :: proc(t: Terrain) -> bool {
	return t == .Wood_Wall || t == .Stone_Wall || t == .Cracked_Wall
}

is_water :: proc(t: Terrain) -> bool {
	return t == .Shallow || t == .Deep
}

// Movement points spent to enter a hex of this terrain. Moving from road to
// road is cheaper still (ROAD_TO_ROAD_HALVES); leaving a road onto other terrain
// costs that terrain's full amount.
TERRAIN_MOVE_COST := [Terrain]int {
	.Grass      = 1,
	.Forest     = 2,
	.Road       = 1,
	.Shallow    = 2,
	.Deep       = 0, // impassable (TERRAIN_PASSABLE)
	.Wood_Wall  = 0,
	.Stone_Wall = 0,
	.Cracked_Wall = 0,
	.Rubble     = 2,
}

// Movement is counted in half points so a road step can cost 1/2.
HALVES_PER_POINT :: 2
ROAD_TO_ROAD_HALVES :: 1

// Climbing from low ground onto high ground costs extra: a whole point, or half
// a point when both hexes are road. Going down or along costs nothing extra.
CLIMB_HALVES :: 2
ROAD_CLIMB_HALVES :: 1

// Cost in half points of stepping from one hex into a neighbouring one.
step_cost :: proc(from, to: Terrain, from_high, to_high: bool) -> int {
	road := from == .Road && to == .Road
	cost := ROAD_TO_ROAD_HALVES if road else TERRAIN_MOVE_COST[to] * HALVES_PER_POINT
	if to_high && !from_high { cost += ROAD_CLIMB_HALVES if road else CLIMB_HALVES }
	return cost
}

// A sapper's price: a kobold (10) and what breaking walls is worth; see
// DESIGN.md (Sappers) for the simulator runs.
SAPPER_POINTS :: 12

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

// Rolls every die in the handful and counts the scores. With advantage, each
// die that fails is rolled once more; with disadvantage, each die that scores
// is rolled once more and counts only if it scores again. Having both is
// neither.
roll_dice :: proc(r: ^Rng, dice: Dice, advantage := false, disadvantage := false) -> int {
	adv := advantage && !disadvantage
	dis := disadvantage && !advantage
	score := 0
	for count, d in dice {
		for _ in 0 ..< count {
			hit := roll_die(r, d)
			if adv && !hit { hit = roll_die(r, d) }
			if dis && hit { hit = roll_die(r, d) }
			if hit { score += 1 }
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
	Axe,
	Sword,
	Bow,
	Crossbow,
	Pike,
	Pick,
}

Weapon :: struct {
	name:      string,
	verb:      string, // for the log: "Red Kobold stabs Blue Kobold"
	attack:    Dice,
	min_range: int,
	max_range: int,
	pierce:    bool, // the target rolls without its best defence die (see defence_against)
	first_strike: bool, // strikes an enemy that steps next to it, on the enemy's turn (move_unit)
}

WEAPONS := [Weapon_Kind]Weapon {
	.Dagger = {name = "dagger", verb = "stabs", attack = {.White = 1, .Red = 0, .Black = 0}, min_range = 1, max_range = 1},
	.Sling  = {name = "sling", verb = "slings", attack = {.White = 1, .Red = 0, .Black = 0}, min_range = 2, max_range = 3},
	.Axe    = {name = "axe", verb = "chops", attack = {.White = 0, .Red = 1, .Black = 0}, min_range = 1, max_range = 1},
	.Sword  = {name = "sword", verb = "cuts", attack = {.White = 1, .Red = 1, .Black = 0}, min_range = 1, max_range = 1},
	.Bow    = {name = "bow", verb = "shoots", attack = {.White = 1, .Red = 0, .Black = 0}, min_range = 2, max_range = 5},
	.Crossbow = {name = "crossbow", verb = "bolts", attack = {.White = 1, .Red = 0, .Black = 0}, min_range = 2, max_range = 4, pierce = true},
	.Pike   = {name = "pike", verb = "skewers", attack = {.White = 0, .Red = 1, .Black = 0}, min_range = 1, max_range = 1, first_strike = true},
	.Pick   = {name = "pick", verb = "hacks", attack = {.White = 1, .Red = 0, .Black = 0}, min_range = 1, max_range = 1},
}

// ---------------------------------------------------------------- armour

// Armour adds defence dice to a kobold's own hide (Unit_Type.defense).
Armour_Kind :: enum u8 {
	None,
	Leather,
	Chain,
	Plate,
}

Armour :: struct {
	name: string,
	dice: Dice,
}

ARMOURS := [Armour_Kind]Armour {
	.None    = {name = "none", dice = {}},
	.Leather = {name = "leather", dice = {.White = 1, .Red = 0, .Black = 0}},
	.Chain   = {name = "chain", dice = {.White = 0, .Red = 1, .Black = 0}},
	.Plate   = {name = "plate", dice = {.White = 0, .Red = 0, .Black = 1}},
}

// Every defence die a unit of this type rolls: its hide plus its armour.
unit_defence :: proc(ut: ^Unit_Type) -> Dice {
	return ut.defense + ARMOURS[ut.armour].dice
}

// The defence dice a unit of this type rolls against weapon w. A piercing
// weapon (the crossbow) takes away the best die (black, then red, then white),
// but a unit with only one die still rolls it.
defence_against :: proc(ut: ^Unit_Type, w: Weapon_Kind) -> Dice {
	d := unit_defence(ut)
	if !WEAPONS[w].pierce { return d }
	total := d[.White] + d[.Red] + d[.Black]
	if total <= 1 { return d }
	for die in ([]Die{.Black, .Red, .White}) {
		if d[die] > 0 {
			d[die] -= 1
			break
		}
	}
	return d
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
	Heavy,
	Champion,
	Scout,
	Archer,
	Crossbow,
	Pike,
	Wololo,
	Sapper,
}

Unit_Type :: struct {
	name:    string,
	short:   string, // for the log and the map counter
	weapons: Weapons, // carried weapons; the one used is picked by range
	defense: Dice, // its own hide; armour adds to it (unit_defence)
	armour:  Armour_Kind,
	body:    int, // body points; the unit dies at 0
	move:    int, // movement points per turn
	points:  int, // army-building cost; set with tools/sim.sh so equal points fight about even
	vision:  int, // hexes it sees under fog of war (fog.odin)
	chants:  bool, // may bless a friend or curse an enemy (chant)
	sapper:  bool, // may break a wall next to it (demolish)
}

UNIT_TYPES := [Unit_Kind]Unit_Type {
	.Kobold = {
		name = "Kobold",
		short = "Kobold",
		weapons = {.Dagger},
		defense = {.White = 1, .Red = 0, .Black = 0},
		body = 1,
		move = 4,
		points = 10,
		vision = 5,
	},
	.Kobold_Slinger = {
		name = "Kobold Slinger",
		short = "Slinger",
		weapons = {.Sling, .Dagger},
		defense = {.White = 1, .Red = 0, .Black = 0},
		body = 1,
		move = 4,
		points = 12, // worth about 1.2 kobolds (simulator, November 5, 2026)
		vision = 7,
	},
	.Heavy = {
		name = "Heavy Kobold",
		short = "Heavy",
		weapons = {.Axe},
		defense = {.White = 1, .Red = 0, .Black = 0},
		armour = .Chain,
		body = 2,
		move = 3,
		points = 25, // 2.85 kobolds in all-heavy armies, 2.5 among kobolds (simulator, November 6, 2026)
		vision = 5,
	},
	.Champion = {
		name = "Kobold Champion",
		short = "Champion",
		weapons = {.Sword},
		defense = {.White = 1, .Red = 0, .Black = 0},
		armour = .Plate,
		body = 3,
		move = 4,
		points = 55, // 6 kobolds alone, a little less in a mixed band (simulator)
		vision = 6,
	},
	.Scout = {
		name = "Kobold Scout",
		short = "Scout",
		weapons = {.Dagger},
		defense = {.White = 1, .Red = 0, .Black = 0},
		body = 1,
		move = 6,
		points = 11, // fights as a kobold; speed and sight are worth a little (simulator: about even)
		vision = 8,
	},
	.Archer = {
		name = "Kobold Archer",
		short = "Archer",
		weapons = {.Bow, .Dagger},
		defense = {.White = 1, .Red = 0, .Black = 0},
		body = 1,
		move = 4,
		points = 20, // was 14 (fair against kobolds: 5a v 7k 53%); in mixed armies 4a = 4s4k (2h2p4a v 2h2p4s4k 50%), and slow heavies cannot catch them (5a v 5h 86%) (simulator, November 7, 2026)
		vision = 7,
	},
	.Crossbow = {
		name = "Kobold Crossbow",
		short = "Crossbow",
		weapons = {.Crossbow, .Dagger},
		defense = {.White = 1, .Red = 0, .Black = 0},
		armour = .Leather,
		body = 1,
		move = 3,
		points = 16, // an archer's worth against bare hide, much more against armour (simulator, November 6, 2026)
		vision = 6,
	},
	.Pike = {
		name = "Kobold Pike",
		short = "Pike",
		weapons = {.Pike},
		defense = {.White = 1, .Red = 0, .Black = 0},
		armour = .Leather,
		body = 1,
		move = 3,
		points = 20, // 4 pikes match 8 kobolds (51%); the first strike is worth a lot (simulator, November 6, 2026)
		vision = 5,
	},
	.Wololo = {
		name = "Kobold Wololo",
		short = "Wololo",
		weapons = {}, // no attack: it chants
		defense = {.White = 1, .Red = 0, .Black = 0},
		body = 1,
		move = 4,
		points = 20, // area chants (November 7, 2026): two kobolds beside kobolds (1w10k v 12k 50%), more beside heavies (1w2h2k v 2k2h2k 57%) and champions (1w1c3k v 1c5k 51%)
		vision = 6,
		chants = true,
	},
	.Sapper = {
		name = "Kobold Sapper",
		short = "Sapper",
		weapons = {.Pick}, // fights like a kobold's dagger
		defense = {.White = 1, .Red = 0, .Black = 0},
		body = 1,
		move = 4,
		points = SAPPER_POINTS,
		vision = 5,
		sapper = true,
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
	fortified:  bool, // defends with advantage until its side's next turn starts
	reacted:    bool, // has struck first this turn (pikes; cleared whenever a turn starts)
	boon:       Boon, // blessed or cursed by a Wololo, for its next roll
	boon_by:    int, // the faction that chanted it; it fades when that side's turn starts
}

// A Wololo's blessing (advantage) or curse (disadvantage) on a unit's next
// roll, attacking or defending.
Boon :: enum u8 {
	None,
	Blessed,
	Cursed,
}

CHANT_RANGE :: 3

unit_type :: proc(u: ^Unit) -> ^Unit_Type {
	return &UNIT_TYPES[u.kind]
}

// ---------------------------------------------------------------- factions

Controller :: enum u8 {
	Human,
	Computer,
}

// How a computer faction plays (ai.odin). Tactical is the default; Basic is
// the first computer player, kept so tools/sim.sh can measure against it.
Ai_Style :: enum u8 {
	Tactical,
	Basic,
}

Faction :: struct {
	name:       string,
	controller: Controller,
	color:      [3]f32,
	ai:         Ai_Style,
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

// What just happened, for the page to animate and play sounds for. The rules
// push one Event per move, attack and fortify into a ring; the page keeps its
// own count of how many it has shown (`event_count` only grows).
EVENT_RING :: 32
MAX_EVENT_PATH :: 16

Event_Kind :: enum u8 {
	Move,
	Attack,
	Fortify,
	Chant,
	Demolish,
}

Event :: struct {
	kind:       Event_Kind,
	unit:       int, // the mover, attacker or fortifier
	target:     int, // attacks only
	from:       Hex, // where the unit started
	path:       [MAX_EVENT_PATH]Hex, // moves: the hexes walked, ending where it stopped
	steps:      int,
	target_pos: Hex, // attacks: where the target stood; chants: the centre hex
	result:     Attack_Result,
	bless:      bool, // chants: a blessing (else a curse)
	rubble:     bool, // demolish: the wall fell (else a stone wall cracked)
}

push_event :: proc(g: ^Game, e: Event) {
	g.events[g.event_count % EVENT_RING] = e
	g.event_count += 1
}

Game :: struct {
	name:          string, // the scenario's, or "Custom battle"
	terrain:       [ROWS][COLS]Terrain,
	high:          [ROWS][COLS]bool, // elevation: high ground (true) or low ground
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
	fortifies:     [MAX_FACTIONS]int,
	demolished:    [MAX_FACTIONS]int, // walls broken or cracked by sappers (tools/sim.sh)
	// fog of war (fog.odin); off unless new_game or the simulator turns it on
	fog:           bool,
	seen:          [MAX_FACTIONS]Hex_Mask, // explored
	in_view:       [MAX_FACTIONS]Hex_Mask, // in sight now
	watched:       [MAX_FACTIONS]Hex_Mask, // a unit here would be seen now
	last_seen:     [MAX_FACTIONS][MAX_UNITS]Sighting,
	// tactical computer player (ai.odin)
	ai_held:       [MAX_FACTIONS]int, // turns in a row it held back from the enemy's reach
	contact_turn:  int, // round of the latest attack by anyone (0: none yet)
	ai_holding:    [MAX_FACTIONS]bool, // some unit held back this turn
	ai_threat:     [MAX_FACTIONS]Ai_Threat, // cached threat maps
	ai_reach:      [MAX_FACTIONS][MAX_UNITS]Ai_Reach, // cached per enemy
	events:        [EVENT_RING]Event, // see push_event
	event_count:   int,
	view_cache:    [VIEW_SLOTS][ROWS][COLS]Hex_Mask, // hexes in sight, per sight range and hex (fog.odin)
	view_ready:    [VIEW_SLOTS]Hex_Mask, // which hexes of each table are filled in
	view_slots:    [VIEW_SLOTS]int, // the sight range each slot holds (0: free)
	open_mask:     Hex_Mask, // hexes that are not forest
	open_ready:    bool,
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

is_high :: proc(g: ^Game, h: Hex) -> bool {
	return g.high[h.y][h.x]
}

terrain_at :: proc(g: ^Game, h: Hex) -> Terrain {
	return g.terrain[h.y][h.x]
}

passable :: proc(g: ^Game, h: Hex) -> bool {
	return TERRAIN_PASSABLE[g.terrain[h.y][h.x]]
}

// Steps from the nearest of `from` to every hex, walking over passable
// terrain and ignoring units (UNREACHABLE where no walk gets there). The
// sources themselves count even when impassable, so a walk can head for the
// bank of a lake. On open ground it equals the hex distance.
walk_distances :: proc(g: ^Game, from: []Hex) -> (d: [ROWS][COLS]i32) {
	for &row in d { for &c in row { c = UNREACHABLE } }
	queue: [ROWS * COLS]Hex
	head, tail := 0, 0
	for h in from {
		if !in_bounds(h) || d[h.y][h.x] == 0 { continue }
		d[h.y][h.x] = 0
		queue[tail] = h
		tail += 1
	}
	for head < tail {
		h := queue[head]
		head += 1
		nbs, n := neighbours(h)
		for nb in nbs[:n] {
			if d[nb.y][nb.x] != UNREACHABLE || !passable(g, nb) { continue }
			d[nb.y][nb.x] = d[h.y][h.x] + 1
			queue[tail] = nb
			tail += 1
		}
	}
	return
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

add_faction :: proc(g: ^Game, name: string, controller: Controller, color: [3]f32, ai := Ai_Style.Tactical) -> int {
	assert(g.faction_count < MAX_FACTIONS)
	g.factions[g.faction_count] = {name, controller, color, ai}
	g.faction_count += 1
	return g.faction_count - 1
}

// Total points of a faction's living units.
army_points :: proc(g: ^Game, faction: int) -> int {
	n := 0
	for i in 0 ..< g.unit_count {
		u := &g.units[i]
		if u.alive && u.faction == faction { n += unit_type(u).points }
	}
	return n
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

OWN_VIEW :: -2

// Cheapest movement cost, in half points, from the unit's hex to every hex, ignoring its
// remaining points (UNREACHABLE where there is no way in). Units may pass through
// friends but not enemies; whether a hex can be stopped on is can_move's job.
// Under fog only the enemies `viewer` can see block the search (OWN_VIEW: the
// unit's own side), so planning never uses hidden units; move_unit stops a move
// that runs into one.
movement_costs :: proc(g: ^Game, unit: int, viewer := OWN_VIEW) -> (cost: [ROWS][COLS]int) {
	u := &g.units[unit]
	who := u.faction if viewer == OWN_VIEW else viewer
	for &row in cost { for &c in row { c = UNREACHABLE } }
	// who stands where, so the search does not rescan the unit list
	blocked: [ROWS][COLS]bool
	for i in 0 ..< g.unit_count {
		o := &g.units[i]
		if o.alive && o.faction != u.faction && unit_visible(g, i, who) { blocked[o.pos.y][o.pos.x] = true }
	}
	heap: Cost_Heap
	cost[u.pos.y][u.pos.x] = 0
	heap_push(&heap, {0, u.pos})
	for heap.count > 0 {
		e := heap_pop(&heap)
		if e.cost > cost[e.hex.y][e.hex.x] { continue } // stale entry
		from := terrain_at(g, e.hex)
		from_high := is_high(g, e.hex)
		nbs, n := neighbours(e.hex)
		for nb in nbs[:n] {
			if blocked[nb.y][nb.x] || !passable(g, nb) { continue }
			c := e.cost + step_cost(from, terrain_at(g, nb), from_high, is_high(g, nb))
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
	if o := unit_at(g, dest); o >= 0 && unit_visible(g, o, u.faction) { return false }
	c := costs[dest.y][dest.x]
	return c != UNREACHABLE && c <= u.moves_left
}

MAX_PATH :: 64

// The cheapest path to dest found by movement_costs, without the start hex.
path_to :: proc(g: ^Game, start, dest: Hex, costs: ^[ROWS][COLS]int) -> (path: [MAX_PATH]Hex, n: int) {
	back: [MAX_PATH]Hex
	cur := dest
	for cur != start && n < MAX_PATH {
		back[n] = cur
		n += 1
		nbs, k := neighbours(cur)
		for nb in nbs[:k] {
			c := costs[nb.y][nb.x]
			if c != UNREACHABLE && c + step_cost(terrain_at(g, nb), terrain_at(g, cur), is_high(g, nb), is_high(g, cur)) == costs[cur.y][cur.x] {
				cur = nb
				break
			}
		}
	}
	for i in 0 ..< n { path[i] = back[n - 1 - i] }
	return
}

push_move_event :: proc(g: ^Game, unit: int, from: Hex, steps: []Hex) {
	if len(steps) == 0 { return }
	ev := Event{kind = .Move, unit = unit, from = from}
	for h in steps[:min(len(steps), MAX_EVENT_PATH)] {
		ev.path[ev.steps] = h
		ev.steps += 1
	}
	push_event(g, ev)
}

// An enemy pike that strikes the unit as it steps onto h: next to h, alive,
// and not yet used this turn. -1 if none.
first_striker :: proc(g: ^Game, unit: int, h: Hex) -> int {
	u := &g.units[unit]
	for i in 0 ..< g.unit_count {
		p := &g.units[i]
		if !p.alive || p.faction == u.faction || p.reacted || .Pike not_in unit_type(p).weapons { continue }
		if hex_distance(p.pos, h) == 1 { return i }
	}
	return -1
}

// Moves the unit to dest one hex at a time. A pike strikes first when the
// unit steps next to it (once per pike per turn); if that kills the unit its
// move ends there, otherwise it walks on. Under fog the way can run into an
// enemy the side could not see: the unit then stops short (on the last hex of
// the way it may stand on), keeps the points it has not spent, and now sees the
// enemy. Returns false only if the move was refused.
move_unit :: proc(g: ^Game, unit: int, dest: Hex) -> bool {
	if g.winner >= 0 || g.units[unit].faction != g.current || g.units[unit].done { return false }
	costs := movement_costs(g, unit)
	if !can_move(g, unit, dest, &costs) { return false }
	u := &g.units[unit]
	start := u.pos
	path, n := path_to(g, start, dest, &costs)
	reached := -1 // index into path of the furthest hex walked; -1 is the start
	bumped := false
	// the move is told as Move events split around any pike's strike, so the
	// page shows them in order
	seg_from, seg_first := start, 0
	for i in 0 ..< n {
		h := path[i]
		if o := unit_at(g, h); o >= 0 && g.units[o].faction != u.faction {
			bumped = true
			break
		}
		reached = i
		// every pike it steps next to strikes, one after another
		for pike := first_striker(g, unit, h); pike >= 0; pike = first_striker(g, unit, h) {
			if seg_first <= i {
				push_move_event(g, unit, seg_from, path[seg_first:i + 1])
				seg_from, seg_first = h, i + 1
			}
			u.pos = h // it is struck where it stands
			res := resolve_attack(g, pike, unit, .Pike, first_strike = true)
			g.units[pike].reacted = true
			u.pos = start
			if res.killed {
				u.pos = h
				u.moves_left -= costs[h.y][h.x]
				update_vision(g, u.faction)
				return true
			}
		}
		if g.fog {
			// what the unit sees on the way, and who sees it pass
			look_from(g, u.faction, u.kind, h)
			record_sightings(g, u.faction)
			for f in 0 ..< g.faction_count {
				if f != u.faction && mask_has(&g.watched[f], h) { g.last_seen[f][unit] = {h, true} }
			}
		}
	}
	// cannot stop on a friend: fall back along the way to a free hex
	for reached >= 0 && unit_at(g, path[reached]) >= 0 { reached -= 1 }
	stop := start if reached < 0 else path[reached]
	u.moves_left -= costs[stop.y][stop.x]
	u.pos = stop
	if reached >= seg_first {
		push_move_event(g, unit, seg_from, path[seg_first:reached + 1])
	} else if stop != seg_from {
		one := [1]Hex{stop} // backed off a friend to before the last strike
		push_move_event(g, unit, seg_from, one[:])
	}
	if bumped { add_log(g, "%s %s stops: an enemy blocks the way", g.factions[u.faction].name, unit_type(u).short) }
	update_vision(g, u.faction)
	return true
}

// ---------------------------------------------------------------- combat

// A weapon's longest reach from one hex to another: shooting from high ground
// down onto low ground adds half again, rounded down (sling 3 -> 4). Melee
// weapons (range 1) are unchanged.
weapon_max_range :: proc(g: ^Game, w: Weapon_Kind, from, to: Hex) -> int {
	r := WEAPONS[w].max_range
	if r > 1 && is_high(g, from) && !is_high(g, to) { r = r * 3 / 2 }
	return r
}

weapon_reaches :: proc(g: ^Game, w: Weapon_Kind, from, to: Hex) -> bool {
	d := hex_distance(from, to)
	return d >= WEAPONS[w].min_range && d <= weapon_max_range(g, w, from, to)
}

NO_FACTION :: -1

// Line of sight between two hexes, as seen by `viewer` (a faction). For each hex
// strictly between them:
//   - an obstacle is forest, a wall (unless either end is right next to it:
//     a unit at a wall looks over it, and can be seen over it), or a living
//     unit of a faction other than the
//     viewer's (the viewer's own side never blocks; with NO_FACTION only terrain
//     counts);
//   - when both ends are on low ground, high ground in between blocks, and so
//     does any obstacle;
//   - when either end is on high ground, it sees over low ground (obstacles
//     there do not block), but an obstacle on high ground still blocks.
// The two end hexes never block, so a unit in a forest can see and be seen from
// outside it. A line that runs exactly along hex edges is clear if either side
// of the edge is clear.
line_of_sight :: proc(g: ^Game, a, b: Hex, viewer := NO_FACTION) -> bool {
	clear_side :: proc(g: ^Game, a, b: Hex, viewer: int, nudge: f64) -> bool {
		ends_high := is_high(g, a) || is_high(g, b)
		line, n := hexes_between(a, b, nudge)
		for h in line[:n] {
			// on a staggered map a line between edge hexes can graze just off
			// the map; nothing grows there, and nobody stands there
			if !in_bounds(h) { continue }
			high := is_high(g, h)
			if high && !ends_high { return false } // a hill between two low hexes
			if !high && ends_high { continue } // seen over from above
			t := terrain_at(g, h)
			if t == .Forest { return false }
			// a wall blocks, unless one end stands right next to it and looks over
			if is_wall(t) && hex_distance(h, a) > 1 && hex_distance(h, b) > 1 { return false }
			if viewer != NO_FACTION {
				if o := unit_at(g, h); o >= 0 && g.units[o].faction != viewer { return false }
			}
		}
		return true
	}
	return clear_side(g, a, b, viewer, 1) || clear_side(g, a, b, viewer, -1)
}

// Ranged attacks (beyond 1 hex) need line of sight; melee never does.
needs_line_of_sight :: proc(distance: int) -> bool {
	return distance > 1
}

// The weapon a unit of `faction` standing on `from` would use against a target
// on `to`: of the weapons that reach (and, at range, can see past forest and
// enemies), the one with the strongest dice (the first listed on a tie).
weapon_for :: proc(g: ^Game, ut: ^Unit_Type, faction: int, from, to: Hex) -> (best: Weapon_Kind, ok: bool) {
	best, ok = weapon_in_range(g, ut, from, to)
	// trace the line only when something reaches (it is the costly part)
	if ok && needs_line_of_sight(hex_distance(from, to)) && !line_of_sight(g, from, to, faction) { ok = false }
	return
}

// Like weapon_for, but ignoring line of sight.
weapon_in_range :: proc(g: ^Game, ut: ^Unit_Type, from, to: Hex) -> (best: Weapon_Kind, ok: bool) {
	for w in ut.weapons {
		if !weapon_reaches(g, w, from, to) { continue }
		if !ok || dice_strength(WEAPONS[w].attack) > dice_strength(WEAPONS[best].attack) {
			best = w
			ok = true
		}
	}
	return
}

// The weapon the attacker would use on the target, if it can attack it now.
attack_weapon :: proc(g: ^Game, attacker, target: int) -> (w: Weapon_Kind, ok: bool) {
	a := &g.units[attacker]
	t := &g.units[target]
	if !a.alive || !t.alive || a.attacked || a.faction == t.faction { return }
	if !unit_visible(g, target, a.faction) { return } // fog: only what the side can see
	return weapon_for(g, unit_type(a), a.faction, a.pos, t.pos)
}

can_attack :: proc(g: ^Game, attacker, target: int) -> bool {
	_, ok := attack_weapon(g, attacker, target)
	return ok
}

// Shortest and longest reach over all of a unit type's weapons, on level ground
// (high ground can add to the longest; see weapon_max_range).
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
	fortified: bool, // the target was fortified
	first_strike: bool, // a pike struck an enemy stepping next to it
	attack_advantage:  bool, // melee from high ground down onto low ground
	defence_advantage: bool, // fortified, or holding high ground against melee from below
	attack_boon:       Boon, // the attacker was blessed or cursed (used up by this roll)
	defence_boon:      Boon, // the target was
}

// High ground in melee: the higher unit has advantage, attacking down or
// defending against an attack from below. Ranged attacks get longer reach from
// high ground instead (weapon_max_range). Advantage never stacks: fortified on
// a hill is still one re-roll per failed die.
combat_advantage :: proc(g: ^Game, attacker, target: Hex, fortified: bool) -> (attack_adv, defence_adv: bool) {
	melee := hex_distance(attacker, target) == 1
	a_high := is_high(g, attacker)
	t_high := is_high(g, target)
	attack_adv = melee && a_high && !t_high
	defence_adv = fortified || (melee && t_high && !a_high) || wall_cover(g, attacker, target)
	return
}

// A shot at a unit right behind a wall: the line passes over a wall hex next
// to the target, which then defends with advantage. A shooter on high ground
// shooting over a low wall gets no such trouble (it sees over it).
wall_cover :: proc(g: ^Game, attacker, target: Hex) -> bool {
	if hex_distance(attacker, target) <= 1 { return false }
	a_high := is_high(g, attacker)
	for nudge in ([2]f64{1, -1}) {
		line, n := hexes_between(attacker, target, nudge)
		for h in line[:n] {
			if !in_bounds(h) || !is_wall(terrain_at(g, h)) || hex_distance(h, target) != 1 { continue }
			if a_high && !is_high(g, h) { continue }
			return true
		}
	}
	return false
}

// Attacking also ends the attacker's movement for the turn.
// The attacker rolls its weapon's attack dice (the weapon is picked by range),
// the target rolls its defence dice; each block cancels one hit, and every hit
// left costs the target a body point.
attack :: proc(g: ^Game, attacker, target: int) -> (res: Attack_Result, ok: bool) {
	if g.winner >= 0 || g.units[attacker].faction != g.current || g.units[attacker].done { return }
	weapon := attack_weapon(g, attacker, target) or_return
	a := &g.units[attacker]
	a.attacked = true
	a.moves_left = 0 // attacking ends the unit's movement
	a.done = true
	return resolve_attack(g, attacker, target, weapon), true
}

// Rolls one attack and applies it: shared by attack and a pike striking first
// (which costs the pike nothing on its own turn).
resolve_attack :: proc(g: ^Game, attacker, target: int, weapon: Weapon_Kind, first_strike := false) -> (res: Attack_Result) {
	a := &g.units[attacker]
	t := &g.units[target]
	res.weapon = weapon
	res.first_strike = first_strike
	res.fortified = t.fortified
	res.attack_advantage, res.defence_advantage = combat_advantage(g, a.pos, t.pos, t.fortified)
	// a blessing or curse is spent on the unit's next roll
	res.attack_boon, a.boon = a.boon, .None
	res.defence_boon, t.boon = t.boon, .None
	res.hits = roll_dice(&g.rng, WEAPONS[weapon].attack, advantage = res.attack_advantage || res.attack_boon == .Blessed, disadvantage = res.attack_boon == .Cursed)
	res.blocks = roll_dice(&g.rng, defence_against(unit_type(t), weapon), advantage = res.defence_advantage || res.defence_boon == .Blessed, disadvantage = res.defence_boon == .Cursed)
	res.damage = max(0, res.hits - res.blocks)
	g.ai_held = {} // contact: nobody is holding back any more
	g.contact_turn = g.turn
	g.attacks[a.faction][weapon] += 1
	t.body -= res.damage
	if t.body <= 0 {
		t.body = 0
		t.alive = false
		res.killed = true
		g.kills[a.faction][weapon] += 1
		update_vision(g, a.faction)
	}
	push_event(g, {kind = .Attack, unit = attacker, target = target, from = a.pos, target_pos = t.pos, result = res})
	aname := g.factions[a.faction].name
	tname := g.factions[t.faction].name
	// "Red Kobold (high) stabs Blue Kobold (fort): 1 hit 0 block, slain"; the tags
	// say why a side rolled with advantage
	def_tag := ""
	if res.defence_advantage {
		held_high := hex_distance(a.pos, t.pos) == 1 && is_high(g, t.pos) && !is_high(g, a.pos)
		tags := ""
		if res.fortified { tags = "fort" }
		if held_high { tags = "high" if tags == "" else fmt.tprintf("%s, high", tags) }
		if wall_cover(g, a.pos, t.pos) { tags = "cover" if tags == "" else fmt.tprintf("%s, cover", tags) }
		def_tag = fmt.tprintf(" (%s)", tags)
	}
	atk_tag := " (high)" if res.attack_advantage else ""
	if res.attack_boon != .None { atk_tag = fmt.tprintf("%s (%s)", atk_tag, "blessed" if res.attack_boon == .Blessed else "cursed") }
	if first_strike { atk_tag = fmt.tprintf("%s strikes first and", atk_tag) }
	if res.defence_boon != .None { def_tag = fmt.tprintf("%s (%s)", def_tag, "blessed" if res.defence_boon == .Blessed else "cursed") }
	add_log(g, "%s %s%s %s %s %s%s: %d hit %d block, %s", aname, unit_type(a).short, atk_tag,
		WEAPONS[weapon].verb, tname, unit_type(t).short, def_tag, res.hits, res.blocks, "slain" if res.killed else ("wounded" if res.damage > 0 else "no harm"))
	check_winner(g)
	return res
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

// A unit may fortify instead of doing anything else this turn: only before it
// has moved or attacked.
can_fortify :: proc(g: ^Game, unit: int) -> bool {
	u := &g.units[unit]
	return g.winner < 0 && u.alive && u.faction == g.current && !u.done && !u.attacked &&
		u.moves_left == unit_type(u).move * HALVES_PER_POINT
}

// Fortifying is the unit's whole turn: it stays put, does not attack, and
// defends with advantage (each failed defence die is rolled again) until its
// side's next turn starts.
fortify :: proc(g: ^Game, unit: int) -> bool {
	if !can_fortify(g, unit) { return false }
	u := &g.units[unit]
	u.fortified = true
	u.done = true
	u.moves_left = 0
	g.fortifies[u.faction] += 1
	push_event(g, {kind = .Fortify, unit = unit, from = u.pos})
	add_log(g, "%s %s fortifies", g.factions[u.faction].name, unit_type(u).short)
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
	return !can_chant_anywhere(g, unit) && !can_demolish_anywhere(g, unit)
}

// ---------------------------------------------------------------- demolishing

// A sapper breaks a wall next to it instead of attacking: a wooden wall or a
// cracked stone wall becomes rubble, a stone wall cracks (so stone takes two
// blows, on two turns). Like an attack, it ends the sapper's move.
can_demolish :: proc(g: ^Game, unit: int, h: Hex) -> bool {
	u := &g.units[unit]
	if g.winner >= 0 || !u.alive || u.faction != g.current || u.done || u.attacked || !unit_type(u).sapper { return false }
	return in_bounds(h) && hex_distance(u.pos, h) == 1 && is_wall(terrain_at(g, h))
}

can_demolish_anywhere :: proc(g: ^Game, unit: int) -> bool {
	if !unit_type(&g.units[unit]).sapper { return false }
	nbs, n := neighbours(g.units[unit].pos)
	for nb in nbs[:n] {
		if can_demolish(g, unit, nb) { return true }
	}
	return false
}

demolish :: proc(g: ^Game, unit: int, h: Hex) -> bool {
	if !can_demolish(g, unit, h) { return false }
	u := &g.units[unit]
	u.attacked = true
	u.moves_left = 0
	u.done = true
	old := terrain_at(g, h)
	rubble := old != .Stone_Wall
	g.terrain[h.y][h.x] = .Rubble if rubble else .Cracked_Wall
	// the map changed: sight lines and the computer's reach maps with it
	clear_view_cache(g)
	g.ai_threat = {}
	g.ai_reach = {}
	g.demolished[u.faction] += 1
	push_event(g, {kind = .Demolish, unit = unit, from = u.pos, target_pos = h, rubble = rubble})
	name := g.factions[u.faction].name
	if rubble {
		add_log(g, "%s %s breaks the %s into rubble", name, unit_type(u).short, "wooden wall" if old == .Wood_Wall else "stone wall")
	} else {
		add_log(g, "%s %s cracks the stone wall", name, unit_type(u).short)
	}
	update_vision(g, u.faction)
	return true
}

// ---------------------------------------------------------------- chanting

// A chant lands on a hex and the six around it (CHANT_RADIUS): a blessing on
// every friend there, a curse on every enemy there that the caster's side can
// see. The Wololo never blesses itself.
CHANT_RADIUS :: 1

// Would a chant centred on `center` touch this unit?
chant_hits :: proc(g: ^Game, caster: int, center: Hex, bless: bool, unit: int) -> bool {
	c := &g.units[caster]
	u := &g.units[unit]
	if unit == caster || !u.alive || hex_distance(center, u.pos) > CHANT_RADIUS { return false }
	if bless { return u.faction == c.faction }
	return u.faction != c.faction && unit_visible(g, unit, c.faction)
}

// Can this Wololo chant on that hex now? It must not have acted; the hex is in
// its side's sight, within CHANT_RANGE, with line of sight beyond 1 hex, and
// the chant would touch somebody.
can_chant_at :: proc(g: ^Game, caster: int, center: Hex, bless: bool) -> bool {
	c := &g.units[caster]
	if g.winner >= 0 || !c.alive || c.done || c.attacked || !unit_type(c).chants || c.faction != g.current { return false }
	if !in_bounds(center) || !hex_in_view(g, c.faction, center) { return false }
	d := hex_distance(c.pos, center)
	if d > CHANT_RANGE || (d > 1 && !line_of_sight(g, c.pos, center, c.faction)) { return false }
	for i in 0 ..< g.unit_count {
		if chant_hits(g, caster, center, bless, i) { return true }
	}
	return false
}

// A chant centred on a unit: blesses round a friend, curses round an enemy.
can_chant :: proc(g: ^Game, caster, target: int) -> bool {
	t := &g.units[target]
	return t.alive && can_chant_at(g, caster, t.pos, t.faction == g.units[caster].faction)
}

// Is there any hex this Wololo could chant on now?
can_chant_anywhere :: proc(g: ^Game, caster: int) -> bool {
	c := &g.units[caster]
	if c.done || c.attacked || !unit_type(c).chants { return false }
	for row in max(0, c.pos.y - CHANT_RANGE) ..= min(ROWS - 1, c.pos.y + CHANT_RANGE) {
		for col in max(0, c.pos.x - CHANT_RANGE - 1) ..= min(COLS - 1, c.pos.x + CHANT_RANGE + 1) {
			h := Hex{col, row}
			if can_chant_at(g, caster, h, true) || can_chant_at(g, caster, h, false) { return true }
		}
	}
	return false
}

// The Wololo blesses (advantage on the next roll) or curses (disadvantage)
// every unit the chant touches. Like an attack, it ends the Wololo's move. A
// unit holds one blessing or curse at a time; a new one replaces it.
chant_at :: proc(g: ^Game, caster: int, center: Hex, bless: bool) -> bool {
	if !can_chant_at(g, caster, center, bless) { return false }
	c := &g.units[caster]
	names: [dynamic]string
	names.allocator = context.temp_allocator
	other := c.faction
	for i in 0 ..< g.unit_count {
		if !chant_hits(g, caster, center, bless, i) { continue }
		u := &g.units[i]
		u.boon = .Blessed if bless else .Cursed
		u.boon_by = c.faction
		other = u.faction
		append(&names, unit_type(u).short)
	}
	c.attacked = true
	c.moves_left = 0
	c.done = true
	push_event(g, {kind = .Chant, unit = caster, target = -1, from = c.pos, target_pos = center, bless = bless})
	list := ""
	for n, i in names {
		sep := "" if i == 0 else (" and " if i == len(names) - 1 else ", ")
		list = fmt.tprintf("%s%s%s", list, sep, n)
	}
	add_log(g, "%s %s %s %s %s", g.factions[c.faction].name, unit_type(c).short,
		"blesses" if bless else "curses", g.factions[other].name, list)
	return true
}

// A chant centred on a unit (see can_chant).
chant :: proc(g: ^Game, caster, target: int) -> bool {
	t := &g.units[target]
	return t.alive && chant_at(g, caster, t.pos, t.faction == g.units[caster].faction)
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
			u.fortified = false // fortifying lasts only through the enemy's turn
		}
		u.reacted = false // a pike may strike first once in every turn
		if u.boon != .None && u.boon_by == g.current { u.boon = .None } // unused blessings fade
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
	update_vision(g, g.current) // the side to move looks round again
	add_log(g, "Turn %d: %s to move", g.turn, g.factions[g.current].name)
	return true
}
