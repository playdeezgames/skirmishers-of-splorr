package game

// Custom battles: the player picks the ground (how much forest, a road or not,
// how hilly) and each side's army, either a ready-made one, one bought unit by
// unit within a points budget, or a random one filled up to that budget.

Forest_Level :: enum u8 {
	None,
	Light,
	Woods,
	Heavy,
	Dense,
}

FOREST_LEVELS := [Forest_Level]struct {
	name:    string,
	percent: int,
} {
	.None  = {"none", 0},
	.Light = {"light (12%)", 12},
	.Woods = {"woods (25%)", 25},
	.Heavy = {"heavy (50%)", 50},
	.Dense = {"dense (75%)", 75},
}

Hill_Level :: enum u8 {
	Flat,
	Some,
	Hilly,
}

HILL_LEVELS := [Hill_Level]struct {
	name:    string,
	percent: int,
} {
	.Flat  = {"flat", 0},
	.Some  = {"some hills (15%)", 15},
	.Hilly = {"hilly (35%)", 35},
}

Army_Preset :: struct {
	name:  string,
	kinds: []Unit_Kind, // rear units first (see place_block)
}

ARMY_PRESETS := [?]Army_Preset {
	{"Patrol", {.Kobold, .Kobold_Slinger, .Kobold_Slinger, .Kobold}},
	{"Hunters", {.Archer, .Archer, .Kobold, .Scout, .Kobold, .Archer, .Archer}},
	{"Shield wall", {.Crossbow, .Heavy, .Pike, .Wololo, .Pike, .Heavy, .Crossbow}},
	{"Champion's guard", {.Kobold, .Heavy, .Kobold, .Wololo, .Champion, .Kobold, .Heavy, .Kobold}},
	{"Warband", {.Archer, .Heavy, .Pike, .Champion, .Wololo, .Scout, .Kobold_Slinger, .Heavy, .Crossbow}},
	{"Horde", {
		.Kobold_Slinger, .Kobold_Slinger, .Kobold_Slinger, .Kobold_Slinger, .Kobold_Slinger,
		.Kobold, .Kobold, .Kobold, .Kobold, .Kobold, .Kobold, .Kobold, .Kobold,
		.Kobold, .Kobold, .Kobold, .Kobold, .Kobold, .Kobold, .Kobold,
	}},
}

// Army choices past the presets.
ARMY_CUSTOM :: len(ARMY_PRESETS)
ARMY_RANDOM :: ARMY_CUSTOM + 1
ARMY_CHOICES :: ARMY_RANDOM + 1

MAX_ARMY :: 30 // three columns of ten (MAX_UNITS holds two of these)
#assert(2 * MAX_ARMY <= MAX_UNITS)

BUDGETS := [?]int{100, 150, 200, 250, 300}

// How many of each unit kind a bought army has.
Army_Counts :: [Unit_Kind]int

Side_Setup :: struct {
	choice: int, // index into ARMY_PRESETS, or ARMY_CUSTOM / ARMY_RANDOM
	custom: Army_Counts,
}

Custom_Battle :: struct {
	forest: Forest_Level,
	road:   bool,
	hills:  Hill_Level,
	budget: int, // for custom and random armies
	watch:  bool, // computer vs computer (else you play Red)
	sides:  [2]Side_Setup,
}

DEFAULT_CUSTOM :: Custom_Battle {
	forest = .Light,
	road = true,
	hills = .Flat,
	budget = 200,
	sides = {{choice = 4}, {choice = 4}}, // warband against warband
}

// Rear units first when a bought army is laid out (shooters and the Wololo in
// the back column once there is more than one).
REAR_ORDER := [?]Unit_Kind{.Archer, .Crossbow, .Kobold_Slinger, .Wololo, .Scout, .Kobold, .Pike, .Heavy, .Champion}
#assert(len(REAR_ORDER) == len(Unit_Kind))

preset_points :: proc(p: Army_Preset) -> int {
	n := 0
	for k in p.kinds { n += UNIT_TYPES[k].points }
	return n
}

counts_points :: proc(c: Army_Counts) -> int {
	n := 0
	for count, k in c { n += count * UNIT_TYPES[k].points }
	return n
}

counts_size :: proc(c: Army_Counts) -> int {
	n := 0
	for count in c { n += count }
	return n
}

// Can one more of this kind be bought for a custom army?
can_buy :: proc(cb: ^Custom_Battle, side: int, kind: Unit_Kind) -> bool {
	c := cb.sides[side].custom
	return counts_size(c) < MAX_ARMY && counts_points(c) + UNIT_TYPES[kind].points <= cb.budget
}

// Is this side's army good to fight with? A custom one needs a unit and must
// fit the budget (which may have been lowered after it was bought).
side_ready :: proc(cb: ^Custom_Battle, side: int) -> bool {
	s := &cb.sides[side]
	if s.choice != ARMY_CUSTOM { return true }
	return counts_size(s.custom) > 0 && counts_points(s.custom) <= cb.budget
}

custom_ready :: proc(cb: ^Custom_Battle) -> bool {
	return side_ready(cb, 0) && side_ready(cb, 1)
}

// Random units, each picked among the kinds still affordable, until nothing
// more fits the budget.
random_army :: proc(r: ^Rng, budget: int, buf: []Unit_Kind) -> []Unit_Kind {
	n := 0
	left := budget
	for n < len(buf) {
		fits: [len(Unit_Kind)]Unit_Kind
		count := 0
		for ut, k in UNIT_TYPES {
			if ut.points <= left {
				fits[count] = k
				count += 1
			}
		}
		if count == 0 { break }
		k := fits[rng_int(r, count)]
		buf[n] = k
		n += 1
		left -= UNIT_TYPES[k].points
	}
	// rear units first, as for a bought army
	counts: Army_Counts
	for k in buf[:n] { counts[k] += 1 }
	return counts_to_kinds(counts, buf)
}

counts_to_kinds :: proc(c: Army_Counts, buf: []Unit_Kind) -> []Unit_Kind {
	n := 0
	for k in REAR_ORDER {
		for _ in 0 ..< c[k] {
			if n == len(buf) { return buf[:n] }
			buf[n] = k
			n += 1
		}
	}
	return buf[:n]
}

// The units one side fields, rear units first.
side_army :: proc(g: ^Game, cb: ^Custom_Battle, side: int, buf: []Unit_Kind) -> []Unit_Kind {
	s := &cb.sides[side]
	switch s.choice {
	case ARMY_CUSTOM: return counts_to_kinds(s.custom, buf)
	case ARMY_RANDOM: return random_army(&g.rng, cb.budget, buf)
	}
	kinds := ARMY_PRESETS[s.choice].kinds
	n := copy(buf, kinds)
	return buf[:n]
}

new_custom_game :: proc(g: ^Game, cb: ^Custom_Battle, seed: u64) {
	begin_game(g, "Custom battle", seed)
	for &row in g.terrain { for &t in row { t = .Grass } }
	if cb.road { generate_road(g, Road_Direction(rng_int(&g.rng, len(Road_Direction)))) }
	red := add_faction(g, "Red", .Computer if cb.watch else .Human, RED)
	blue := add_faction(g, "Blue", .Computer, BLUE)
	buf: [MAX_ARMY]Unit_Kind
	place_block(g, red, side_army(g, cb, 0, buf[:]), true, 2)
	place_block(g, blue, side_army(g, cb, 1, buf[:]), false, 2)
	// forest after the road and units, so it grows round them
	grow_forest_to(g, FOREST_LEVELS[cb.forest].percent)
	grow_hills_to(g, HILL_LEVELS[cb.hills].percent)
	finish_setup(g)
}
