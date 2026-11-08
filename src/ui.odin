#+build js
package main

// Menus and input. Everything is driven by seven buttons, the same on every
// device (see press): a keyboard (arrows or WASD, Space or Enter, Esc), a
// gamepad (D-pad or left stick, A, B, Start; polled in web/index.html) and the
// mouse (pointing moves the cursor or the menu highlight, a click is OK).
//
// Screens are a stack of menus over the map. With no menu open you are
// playing: a hex cursor moves over the map, OK acts on the hex under it and
// Cancel backs out (leaving chant mode, dropping the selection, then opening
// the pause menu). The title screen is a menu over a computer-vs-computer
// game that keeps playing behind it.

import "core:fmt"
import "core:sys/wasm/js"
import "game"

Input :: enum i32 {
	Up,
	Down,
	Left,
	Right,
	Ok,
	Cancel,
	Menu,
}

Menu_Id :: enum {
	Title,
	Scenarios,
	Options,
	Help,
	Pause,
	Unit,
	Confirm,
	Game_Over,
	Custom, // set up a custom battle
	Army, // buy units for one side's custom army
}

Action :: enum {
	None,
	Open_Scenarios,
	Open_Options,
	Open_Help,
	Start, // arg: scenario index
	Back,
	Resume,
	Auto_Resolve,
	Take_Back,
	End_Turn,
	Restart,
	Quit,
	Auto_End,
	Sound,
	Speed,
	View,
	Fortify,
	Finish,
	Chant,
	Yes,
	No,
	Look,
	Open_Custom,
	Forest, // the custom battle's settings (Left / Right step through them)
	Road,
	Hills,
	Water,
	Walls,
	Budget,
	Watch,
	Pick_Army, // arg: side
	Build_Army, // arg: side
	Buy, // arg: unit kind (Left sells)
	Clear_Army,
	Start_Custom,
}

Item :: struct {
	label:   string,
	action:  Action,
	arg:     int,
	enabled: bool,
	value:   string, // drawn on the right (unit prices)
}

MAX_ITEMS :: 16
menu_stack: [8]Menu_Id
menu_depth := 0
menu_sel: [Menu_Id]int
menu_hover := -1 // item under the mouse
confirm_for: Action // what Yes does on the Confirm menu (Restart or Quit)
menu_dir := 1 // which way a setting steps: Left -1, Right or OK +1

// ---------------------------------------------------------------- options

// Kept in the browser (load_option / save_option in web/index.html).
Option :: enum i32 {
	Auto_End, // 1 (default): the turn ends by itself once no unit can act
	Speed, // 0 normal, 1 fast
}

auto_end := true
fast := false

load_options :: proc() {
	auto_end = load_option(i32(Option.Auto_End)) != 0 // -1 when never saved: on
	fast = load_option(i32(Option.Speed)) == 1
}

// The custom battle last set up, kept in the browser too: keys from
// CUSTOM_KEY on, the counts of each side's bought army from CUSTOM_COUNTS_KEY.
custom := game.DEFAULT_CUSTOM
building_side := 0 // whose army the Army menu buys
CUSTOM_KEY :: 100
CUSTOM_COUNTS_KEY :: 120 // + side * 16 + unit kind
#assert(len(game.Unit_Kind) <= 16)

save_custom :: proc() {
	values := [9]int {
		int(custom.forest), 1 if custom.road else 0, int(custom.hills), custom.budget,
		1 if custom.watch else 0, custom.sides[0].choice, custom.sides[1].choice,
		int(custom.water), int(custom.walls),
	}
	for v, i in values { save_option(i32(CUSTOM_KEY + i), i32(v)) }
	for side in 0 ..< 2 {
		for count, k in custom.sides[side].custom { save_option(i32(CUSTOM_COUNTS_KEY + side * 16 + int(k)), i32(count)) }
	}
}

load_custom :: proc() {
	saved :: proc(key, lo, hi: int, v: ^int) {
		x := int(load_option(i32(key)))
		if x >= lo && x <= hi { v^ = x } // -1 when never saved: keep the default
	}
	v := game.DEFAULT_CUSTOM
	forest, road, hills, watch := int(v.forest), 1, int(v.hills), 0
	water, walls := int(v.water), int(v.walls)
	saved(CUSTOM_KEY + 7, 0, len(game.Water_Level) - 1, &water)
	saved(CUSTOM_KEY + 8, 0, len(game.Wall_Level) - 1, &walls)
	saved(CUSTOM_KEY + 0, 0, len(game.Forest_Level) - 1, &forest)
	saved(CUSTOM_KEY + 1, 0, 1, &road)
	saved(CUSTOM_KEY + 2, 0, len(game.Hill_Level) - 1, &hills)
	saved(CUSTOM_KEY + 3, 10, 1000, &v.budget)
	saved(CUSTOM_KEY + 4, 0, 1, &watch)
	for side in 0 ..< 2 {
		saved(CUSTOM_KEY + 5 + side, 0, game.ARMY_CHOICES - 1, &v.sides[side].choice)
		for &count, k in v.sides[side].custom { saved(CUSTOM_COUNTS_KEY + side * 16 + int(k), 0, game.MAX_ARMY, &count) }
	}
	v.forest = game.Forest_Level(forest)
	v.road = road == 1
	v.hills = game.Hill_Level(hills)
	v.water = game.Water_Level(water)
	v.walls = game.Wall_Level(walls)
	v.watch = watch == 1
	custom = v
}

// One step through n settings, the way menu_dir says.
cycle :: proc(v, n: int) -> int {
	return (v + menu_dir + n) % n
}

side_name :: proc(side: int) -> string {
	return "Red" if side == 0 else "Blue"
}

army_label :: proc(side: int) -> string {
	s := &custom.sides[side]
	switch s.choice {
	case game.ARMY_CUSTOM:
		return fmt.tprintf("bought (%d of %d points)", game.counts_points(s.custom), custom.budget)
	case game.ARMY_RANDOM:
		return fmt.tprintf("random (%d points)", custom.budget)
	}
	p := game.ARMY_PRESETS[s.choice]
	return fmt.tprintf("%s (%d units, %d points)", p.name, len(p.kinds), game.preset_points(p))
}

// ---------------------------------------------------------------- the stack

menu_open :: proc() -> bool {
	return menu_depth > 0
}

menu_top :: proc() -> Menu_Id {
	return menu_stack[menu_depth - 1]
}

push_menu :: proc(id: Menu_Id) {
	if menu_depth >= len(menu_stack) { return }
	menu_stack[menu_depth] = id
	menu_depth += 1
	items := menu_items(id)
	menu_sel[id] = first_enabled(items, 0)
	menu_hover = -1
}

pop_menu :: proc() {
	if menu_depth > 0 { menu_depth -= 1 }
	menu_hover = -1
}

// Back to the title screen, with a computer battle behind it.
go_title :: proc() {
	menu_depth = 0
	start_game(BACKDROP_SCENARIO)
	push_menu(.Title)
}

on_title :: proc() -> bool {
	return menu_depth > 0 && menu_stack[0] == .Title
}

first_enabled :: proc(items: []Item, from: int) -> int {
	for i in 0 ..< len(items) {
		k := (from + i) % len(items)
		if items[k].enabled { return k }
	}
	return 0
}

// The items of a menu, built from the state each time (nothing to keep in step).
item_buf: [MAX_ITEMS]Item

menu_items :: proc(id: Menu_Id) -> []Item {
	n := 0
	add :: proc(n: ^int, label: string, action: Action, enabled := true, arg := 0) {
		if n^ < MAX_ITEMS {
			item_buf[n^] = {label, action, arg, enabled, ""}
			n^ += 1
		}
	}
	switch id {
	case .Custom:
		add(&n, fmt.tprintf("Forest: %s", game.FOREST_LEVELS[custom.forest].name), .Forest)
		add(&n, fmt.tprintf("Road: %s", "yes" if custom.road else "no"), .Road)
		add(&n, fmt.tprintf("Hills: %s", game.HILL_LEVELS[custom.hills].name), .Hills)
		add(&n, fmt.tprintf("Water: %s", game.WATER_LEVELS[custom.water]), .Water)
		add(&n, fmt.tprintf("Walls: %s", game.WALL_LEVELS[custom.walls]), .Walls)
		add(&n, fmt.tprintf("Sides: %s", "computer vs computer" if custom.watch else "you are Red, the computer Blue"), .Watch)
		for side in 0 ..< 2 {
			add(&n, fmt.tprintf("%s: %s", side_name(side), army_label(side)), .Pick_Army, arg = side)
			if custom.sides[side].choice == game.ARMY_CUSTOM {
				c := custom.sides[side].custom
				what := "nothing yet" if game.counts_size(c) == 0 else fmt.tprintf("%d units", game.counts_size(c))
				add(&n, fmt.tprintf("    Buy %s's units (%s)", side_name(side), what), .Build_Army, arg = side)
			}
		}
		add(&n, fmt.tprintf("Points to buy or draw armies: %d", custom.budget), .Budget)
		add(&n, "Start battle", .Start_Custom, enabled = game.custom_ready(&custom))
		add(&n, "Back", .Back)
	case .Army:
		c := custom.sides[building_side].custom
		for ut, k in game.UNIT_TYPES {
			add(&n, ut.name, .Buy, arg = int(k))
			item_buf[n - 1].value = fmt.tprintf("%d", c[k])
		}
		add(&n, "Clear", .Clear_Army, enabled = game.counts_size(c) > 0)
		add(&n, "Done", .Back)
	case .Title:
		add(&n, "Play", .Open_Scenarios)
		add(&n, "Options", .Open_Options)
		add(&n, "How to play", .Open_Help)
	case .Scenarios:
		for sc, i in game.SCENARIOS { add(&n, sc.name, .Start, arg = i) }
		add(&n, "Custom battle...", .Open_Custom)
		add(&n, "Back", .Back)
	case .Options:
		add(&n, fmt.tprintf("End turn: %s", "automatic" if auto_end else "press End turn"), .Auto_End)
		add(&n, fmt.tprintf("Sound: %s", "off" if is_muted() else "on"), .Sound)
		add(&n, fmt.tprintf("Computer speed: %s", "fast" if fast else "normal"), .Speed)
		add(&n, "Back", .Back)
	case .Help:
		add(&n, "Back", .Back)
	case .Pause:
		add(&n, "Resume", .Resume)
		if !auto_end && human_turn() { add(&n, "End turn", .End_Turn, enabled = game.units_left_to_act(&g) == 0) }
		if g.winner < 0 && has_human() { add(&n, "Let the computer finish", .Auto_Resolve) }
		if g.winner < 0 && auto_side >= 0 { add(&n, "Take back control", .Take_Back) }
		if !has_human() {
			names := [View_Mode]string{.Everything = "everything", .Red = "Red's side", .Blue = "Blue's side"}
			add(&n, fmt.tprintf("View: %s", names[view_mode]), .View)
		}
		add(&n, "Options", .Open_Options)
		add(&n, "Restart this battle", .Restart)
		add(&n, "Quit to title", .Quit)
	case .Unit:
		if selected >= 0 {
			u := &g.units[selected]
			add(&n, "Fortify", .Fortify, enabled = game.can_fortify(&g, selected))
			add(&n, "Finish move", .Finish, enabled = !game.unit_finished(&g, selected))
			if game.unit_type(u).chants {
				add(&n, "Chant: bless an area", .Chant, enabled = !u.done && !u.attacked)
				add(&n, "Chant: curse an area", .Chant, enabled = !u.done && !u.attacked, arg = 1)
			}
		}
		add(&n, "Cancel", .Back)
	case .Confirm:
		add(&n, "Yes", .Yes)
		add(&n, "No, keep playing", .No)
	case .Game_Over:
		add(&n, "Play again", .Restart)
		add(&n, "Choose a battle", .Open_Scenarios)
		add(&n, "Title screen", .Quit)
		add(&n, "Look at the map", .Look)
	}
	return item_buf[:n]
}

// ---------------------------------------------------------------- actions

activate :: proc(it: Item) {
	if !it.enabled { return }
	switch it.action {
	case .None:
	case .Open_Scenarios: push_menu(.Scenarios)
	case .Open_Options:   push_menu(.Options)
	case .Open_Help:      push_menu(.Help)
	case .Start:
		menu_depth = 0
		start_game(it.arg)
	case .Back, .Resume, .Look:
		pop_menu()
	case .End_Turn:
		pop_menu()
		end_human_turn()
	case .Auto_Resolve:
		pop_menu()
		auto_resolve()
	case .Take_Back:
		pop_menu()
		take_back_control()
	case .Restart:
		if g.winner >= 0 {
			menu_depth = 0
			start_game(scenario)
		} else {
			confirm_for = .Restart
			push_menu(.Confirm)
		}
	case .Quit:
		if g.winner >= 0 {
			go_title()
		} else {
			confirm_for = .Quit
			push_menu(.Confirm)
		}
	case .Yes:
		menu_depth = 0
		if confirm_for == .Restart { start_game(scenario) } else { go_title() }
	case .No:
		pop_menu()
	case .Open_Custom:
		push_menu(.Custom)
	case .Forest:
		custom.forest = game.Forest_Level(cycle(int(custom.forest), len(game.Forest_Level)))
	case .Road:
		custom.road = !custom.road
	case .Hills:
		custom.hills = game.Hill_Level(cycle(int(custom.hills), len(game.Hill_Level)))
	case .Water:
		custom.water = game.Water_Level(cycle(int(custom.water), len(game.Water_Level)))
	case .Walls:
		custom.walls = game.Wall_Level(cycle(int(custom.walls), len(game.Wall_Level)))
	case .Budget:
		i := 0
		for b, k in game.BUDGETS { if b == custom.budget { i = k } }
		custom.budget = game.BUDGETS[cycle(i, len(game.BUDGETS))]
	case .Watch:
		custom.watch = !custom.watch
	case .Pick_Army:
		s := &custom.sides[it.arg]
		s.choice = cycle(s.choice, game.ARMY_CHOICES)
	case .Build_Army:
		building_side = it.arg
		push_menu(.Army)
	case .Buy:
		c := &custom.sides[building_side].custom
		k := game.Unit_Kind(it.arg)
		if menu_dir < 0 {
			if c[k] > 0 { c[k] -= 1 }
		} else if game.can_buy(&custom, building_side, k) {
			c[k] += 1
		}
	case .Clear_Army:
		custom.sides[building_side].custom = {}
	case .Start_Custom:
		menu_depth = 0
		start_game(CUSTOM_SCENARIO)
	case .Auto_End:
		auto_end = !auto_end
		save_option(i32(Option.Auto_End), 1 if auto_end else 0)
	case .Sound:
		toggle_mute()
	case .Speed:
		fast = !fast
		save_option(i32(Option.Speed), 1 if fast else 0)
	case .View:
		view_mode = View_Mode((int(view_mode) + 1) % len(View_Mode))
	case .Fortify:
		pop_menu()
		fortify_selected()
	case .Finish:
		pop_menu()
		finish_selected_move()
	case .Chant:
		pop_menu()
		chant_mode = .Bless if it.arg == 0 else .Curse
		cursor_on = true
	}
	#partial switch it.action {
	case .Forest, .Road, .Hills, .Water, .Walls, .Budget, .Watch, .Pick_Army, .Buy, .Clear_Army: save_custom()
	}
}

menu_input :: proc(btn: Input) {
	id := menu_top()
	items := menu_items(id)
	if len(items) == 0 { return }
	sel := &menu_sel[id]
	sel^ = clamp(sel^, 0, len(items) - 1)
	switch btn {
	case .Up, .Down:
		step := -1 if btn == .Up else 1
		for _ in 0 ..< len(items) {
			sel^ = (sel^ + step + len(items)) % len(items)
			if items[sel^].enabled { break }
		}
	case .Left, .Right:
		// settings flip either way
		#partial switch items[sel^].action {
		case .Auto_End, .Sound, .Speed, .View, .Forest, .Road, .Hills, .Water, .Walls, .Budget, .Watch, .Pick_Army, .Buy:
			menu_dir = -1 if btn == .Left else 1
			activate(items[sel^])
			menu_dir = 1
		}
	case .Ok:
		activate(items[sel^])
	case .Cancel, .Menu:
		switch id {
		case .Title:     // nowhere to go back to
		case .Confirm:   pop_menu()
		case .Game_Over: pop_menu() // look at the map
		case .Scenarios, .Options, .Help, .Pause, .Unit, .Custom, .Army:
			pop_menu()
		}
	}
}

// ---------------------------------------------------------------- input

// One button press from any device (the gamepad's come from the page).
@(export)
press :: proc "c" (btn: Input) {
	context = ctx
	on_input(btn)
}

on_input :: proc(btn: Input) {
	touched = false // keys and the gamepad get their own hints
	if menu_open() {
		menu_input(btn)
		return
	}
	switch btn {
	case .Up, .Down, .Left, .Right: move_cursor(btn)
	case .Ok:                       play_ok()
	case .Cancel:                   play_cancel()
	case .Menu:                     push_menu(.Pause)
	}
}

// The cursor moves one hex. Up and down pick the hex in the next row nearest
// to where the cursor has been heading across, so going straight up does not
// drift on the staggered rows.
move_cursor :: proc(btn: Input) {
	c := cursor
	switch btn {
	case .Left:  c.x -= 1
	case .Right: c.x += 1
	case .Up, .Down:
		c.y += -1 if btn == .Up else 1
		best := c
		best_d := max(f32)
		for dx in -1 ..= 1 {
			h := game.Hex{cursor.x + dx, c.y}
			if !game.in_bounds(h) { continue }
			if d := abs(hex_centre(h).x - cursor_pref_x); d < best_d {
				best = h
				best_d = d
			}
		}
		c = best
	case .Ok, .Cancel, .Menu:
	}
	if !game.in_bounds(c) { return }
	cursor = c
	if btn == .Left || btn == .Right { cursor_pref_x = hex_centre(c).x }
	cursor_on = true
	follow_hex(c)
}

put_cursor :: proc(h: game.Hex) {
	cursor = h
	cursor_pref_x = hex_centre(h).x
}

// OK on the hex under the cursor: what a click on the map does.
play_ok :: proc() {
	if !human_turn() || anim_busy() { return }
	h := cursor
	other := game.unit_at(&g, h)
	if other >= 0 && !game.unit_visible(&g, other, g.current) { other = -1 }
	if selected_chants() && chant_mode != .Off {
		// aimed at the hex under the cursor; nothing happens where it cannot go
		if game.chant_at(&g, selected, h, chant_mode == .Bless) { // this ends the Wololo's move
			chant_mode = .Off
			select_next_unit()
		}
		return
	}
	if selected_chants() && other >= 0 && g.units[other].faction != g.current && game.can_chant(&g, selected, other) {
		game.chant(&g, selected, other) // curses round that enemy
		select_next_unit()
		return
	}
	if other >= 0 && other == selected {
		push_menu(.Unit) // fortify, finish move, chant
		return
	}
	if other >= 0 && g.units[other].faction == g.current {
		selected = other
		return
	}
	if selected >= 0 {
		if other >= 0 && game.can_attack(&g, selected, other) {
			game.attack(&g, selected, other) // this ends the unit's move
			select_next_unit()
			return
		}
		if game.move_unit(&g, selected, h) { return }
	}
	selected = -1
}

play_cancel :: proc() {
	switch {
	case chant_mode != .Off: chant_mode = .Off
	case selected >= 0: selected = -1
	case:               push_menu(.Pause)
	}
}

on_key :: proc(e: js.Event) {
	if e.kind != .Key_Down { return }
	btn: Input
	nav := true
	switch e.key.key {
	case "ArrowUp", "w", "W":           btn = .Up
	case "ArrowDown", "s", "S":         btn = .Down
	case "ArrowLeft", "a", "A":         btn = .Left
	case "ArrowRight", "d", "D":        btn = .Right
	case " ", "Enter":                  btn = .Ok
	case "Escape", "Backspace":         btn = .Cancel
	case "Tab", "p", "P":               btn = .Menu
	case:                               nav = false
	}
	if nav {
		// holding a direction repeats; holding OK or Cancel does not
		if !e.key.repeat || btn <= .Right { on_input(btn) }
		js.event_prevent_default()
		return
	}
	if e.key.repeat { return }
	// a few shortcuts for the keyboard (all are in the menus too)
	switch e.key.key {
	case "m", "M":
		toggle_mute()
	case "f", "F":
		if !menu_open() && !anim_busy() { finish_selected_move() }
	case "c", "C":
		if !menu_open() && selected_chants() {
			chant_mode = Chant_Mode((int(chant_mode) + 1) % len(Chant_Mode)) // off, bless, curse
			cursor_on = true
		}
	case "+", "=":
		if can_zoom() { zoom_step(1) }
	case "-", "_":
		if can_zoom() { zoom_step(-1) }
	case "0":
		if can_zoom() { zoom_step(0) }
	case "e", "E":
		if !menu_open() && !anim_busy() && human_turn() { end_human_turn() }
	case "v", "V":
		if !has_human() { view_mode = View_Mode((int(view_mode) + 1) % len(View_Mode)) }
	case:
		return
	}
	js.event_prevent_default()
}

// ---------------------------------------------------------------- mouse

MENU_W :: f32(340)
ITEM_H :: f32(30)

// How much larger than canvas pixels menus are drawn: 1 in the landscape
// layout; in portrait as large as fits, up to PORTRAIT_UI_SCALE.
menu_scale :: proc(id: Menu_Id) -> f32 {
	if !portrait { return 1 }
	return min(PORTRAIT_UI_SCALE, (canvas_w - 16) / menu_width(id))
}

menu_width :: proc(id: Menu_Id) -> f32 {
	#partial switch id {
	case .Help:             return 600
	case .Scenarios, .Army: return 420
	case .Custom:           return 480
	}
	return MENU_W
}

// Where a menu is drawn, in menu coordinates (canvas pixels / menu_scale):
// over the map while playing, in the middle of the screen on the title screens.
menu_box :: proc(id: Menu_Id) -> (x, y, w, h: f32) {
	items := menu_items(id)
	extra := menu_text_lines(id)
	s := menu_scale(id)
	w = menu_width(id)
	h = menu_items_top(id) + f32(extra) * 18 + f32(len(items)) * ITEM_H + 14
	cx := canvas_w / 2 if on_title() || portrait else (PANEL_X - 12) / 2
	cy := canvas_h / 2 if on_title() else MAP_H / 2
	x = cx / s - w / 2
	y = max(16, cy / s - h / 2 + (60 if on_title() && id == .Title else 0))
	return
}

menu_item_at :: proc(x, y: f32) -> int {
	if !menu_open() { return -1 }
	id := menu_top()
	s := menu_scale(id)
	mx, my := x / s, y / s
	bx, by, bw, _ := menu_box(id)
	items := menu_items(id)
	top := by + menu_items_top(id) + f32(menu_text_lines(id)) * 18
	for i in 0 ..< len(items) {
		iy := top + f32(i) * ITEM_H
		if mx >= bx + 12 && mx < bx + bw - 12 && my >= iy && my < iy + ITEM_H - 4 { return i }
	}
	return -1
}

@(export)
mouse_move :: proc "c" (x, y: f32) {
	context = ctx
	if menu_open() {
		menu_hover = menu_item_at(x, y)
		if menu_hover >= 0 && menu_items(menu_top())[menu_hover].enabled { menu_sel[menu_top()] = menu_hover }
		return
	}
	h := screen_to_hex(x, y)
	if game.in_bounds(h) && on_map(x, y) {
		put_cursor(h)
		cursor_on = true
	}
}

@(export)
mouse_click :: proc "c" (x, y: f32) {
	context = ctx
	touched = false
	click(x, y, false)
}

// A tap on a touch screen. There is no hovering, so a tap on a new hex only
// moves the cursor there to inspect it (the panel shows what is on it), or
// selects your own unit there; a tap on the hex the cursor is already on acts,
// as OK does. Menus and buttons act at once.
@(export)
touch_tap :: proc "c" (x, y: f32) {
	context = ctx
	touched = true
	click(x, y, true)
}

touched := false // the last press was a tap (the hints say so)

click :: proc(x, y: f32, tap: bool) {
	if menu_open() {
		if i := menu_item_at(x, y); i >= 0 {
			menu_sel[menu_top()] = i
			it := menu_items(menu_top())[i]
			bx, _, bw, _ := menu_box(menu_top())
			mx := x / menu_scale(menu_top())
			if it.action == .Buy && mx >= sell_x(bx, bw) - 4 && mx < sell_x(bx, bw) + 24 { menu_dir = -1 }
			activate(it)
			menu_dir = 1
		} else if menu_top() == .Unit {
			pop_menu() // a click away from the unit menu closes it
		}
		return
	}
	px, py := to_panel(x, y)
	if in_button(MENU_BUTTON, px, py) {
		push_menu(.Pause)
		return
	}
	if in_button(END_TURN_BUTTON, px, py) && show_end_turn_button() {
		end_human_turn()
		return
	}
	h := screen_to_hex(x, y)
	if !on_map(x, y) || !game.in_bounds(h) { return }
	if tap && !(cursor_on && h == cursor) {
		put_cursor(h) // look first
		cursor_on = true
		// one of your own units is selected at once (selecting does nothing
		// that cannot be undone); moves, attacks and chants wait for a second tap
		u := game.unit_at(&g, h)
		if u >= 0 && u != selected && chant_mode == .Off && human_turn() && g.units[u].faction == g.current { play_ok() }
		return
	}
	put_cursor(h)
	play_ok()
}

// ---------------------------------------------------------------- drawing

// The - and + boxes on an Army menu row.
sell_x :: proc(x, w: f32) -> f32 { return x + w - 120 }
buy_x :: proc(x, w: f32) -> f32 { return x + w - 52 }

// Where a menu's text starts below its top edge (menus with a heading leave
// room for it).
menu_items_top :: proc(id: Menu_Id) -> f32 {
	return 18 if id == .Title else 50
}

// Lines of text a menu shows above its items.
menu_text_lines :: proc(id: Menu_Id) -> int {
	#partial switch id {
	case .Confirm:   return 1
	case .Game_Over: return 1
	case .Help:      return len(HELP)
	case .Army:      return 2
	}
	return 0
}

HELP := [?]string {
	"Each side takes turns. A unit may move, then attack once; attacking ends",
	"its move. HeroQuest dice: white scores 1 in 3, red 1 in 2, black 2 in 3.",
	"Each block cancels a hit; each hit left costs a body point.",
	"",
	"Cursor: arrows, WASD, D-pad or the mouse.  OK: Space, Enter, A or click.",
	"Touch: tap a hex to look at it, tap it again to act there.",
	"Zoom: pinch, mouse wheel, + / - (0 whole map), LB / RB. Drag to pan.",
	"Back / menu: Esc, B (Start opens the menu too).",
	"OK on your unit selects it; OK on a yellow hex moves it there; OK on a",
	"red-ringed enemy attacks. OK on the selected unit again: fortify, finish",
	"its move, or (Wololo) chant. Keyboard: F finish, C chant, M sound.",
	"",
	"Forest costs 2 and blocks shots; roads are quick; high ground helps in",
	"melee and adds sling and bow range. You see only what your units see.",
	"Shallow water costs 2; deep water and walls cannot be crossed. A wall",
	"blocks shots unless a unit stands right at it, and gives that unit cover.",
	"Armour adds defence dice; crossbows pierce it; pikes strike first.",
	"A Wololo's chant blesses every friend, or curses every enemy, on a hex",
	"and the six round it.",
}

draw_menus :: proc() {
	if !menu_open() { return }
	id := menu_top()
	x, y, w, h := menu_box(id)
	ms := menu_scale(id)
	if on_title() {
		fill_rect(0, 0, canvas_w, canvas_h, 0.05, 0.05, 0.08, 0.72)
		if id == .Title {
			// above the menu, in canvas pixels (too wide to scale up in portrait)
			text("Skirmishers of SPLORR!!", canvas_w / 2, y * ms - 154, 44, GOLD, 1)
			text("kobolds, dice and hexes", canvas_w / 2, y * ms - 106, 18, GREY, 1)
		}
		hint := "Tap to choose" if touched else "Arrows / WASD / D-pad to choose, Space / Enter / A to pick, Esc / B to go back"
		text(hint, canvas_w / 2, canvas_h - 18, 12, GREY, 1)
	} else if portrait {
		fill_rect(0, 0, canvas_w, MAP_H - 4, 0, 0, 0, 0.5)
	} else {
		fill_rect(0, 0, PANEL_X - 4, CANVAS_H, 0, 0, 0, 0.5)
	}
	set_transform(ms, 0, 0)
	defer set_transform(1, 0, 0)
	fill_rect(x, y, w, h, 0.13, 0.14, 0.19, 0.97)
	fill_rect(x, y, w, 3, GOLD.r, GOLD.g, GOLD.b, 1)
	titles := [Menu_Id]string {
		.Title     = "",
		.Scenarios = "Choose a battle",
		.Options   = "Options",
		.Help      = "How to play",
		.Pause     = "Paused",
		.Unit      = "",
		.Confirm   = "Restart this battle?" if confirm_for == .Restart else "Quit to the title screen?",
		.Game_Over = "",
		.Custom    = "Custom battle",
		.Army      = "",
	}
	title := titles[id]
	if id == .Unit && selected >= 0 { title = game.unit_type(&g.units[selected]).name }
	if id == .Game_Over && g.winner >= 0 { title = fmt.tprintf("%s win!", g.factions[g.winner].name) }
	if id == .Army { title = fmt.tprintf("%s's army", side_name(building_side)) }
	tc := GOLD
	if id == .Game_Over && g.winner >= 0 { tc = g.factions[g.winner].color }
	text(title, x + w / 2, y + 28, 18, tc, 1)
	ty := y + menu_items_top(id)
	switch id {
	case .Confirm:
		text("The battle in progress will be lost.", x + w / 2, ty + 6, 13, GREY, 1)
	case .Game_Over:
		msg := "Every enemy is down." if g.winner == player_side() else "Your band is gone."
		if player_side() < 0 { msg = "The battle is over." }
		text(msg, x + w / 2, ty + 6, 13, GREY, 1)
	case .Help:
		for line, i in HELP { text(line, x + 20, ty + 6 + f32(i) * 18, 12, WHITE) }
	case .Army:
		c := custom.sides[building_side].custom
		pts := game.counts_points(c)
		text(fmt.tprintf("%d of %d points spent, %d left; %d of %d units", pts, custom.budget, custom.budget - pts, game.counts_size(c), game.MAX_ARMY), x + w / 2, ty + 6, 13, WHITE, 1)
		text("Right or OK buys one, Left sells one", x + w / 2, ty + 24, 12, GREY, 1)
	case .Title, .Scenarios, .Options, .Pause, .Unit, .Custom:
	}
	ty += f32(menu_text_lines(id)) * 18
	items := menu_items(id)
	sel := menu_sel[id]
	for it, i in items {
		iy := ty + f32(i) * ITEM_H
		if i == sel {
			fill_rect(x + 12, iy, w - 24, ITEM_H - 4, 0.28, 0.33, 0.48, 1)
			text(">", x + 22, iy + (ITEM_H - 4) / 2, 14, GOLD, 0)
		}
		col := WHITE if it.enabled else Color{0.4, 0.4, 0.45}
		mid := iy + (ITEM_H - 4) / 2
		text(it.label, x + 40, mid, 14, col, 0)
		if it.action == .Buy {
			// price, then  - count +  (the mouse clicks - to sell)
			k := game.Unit_Kind(it.arg)
			price := game.UNIT_TYPES[k].points
			afford := game.can_buy(&custom, building_side, k)
			text(fmt.tprintf("%d pts", price), x + w - 140, mid, 13, GREY if afford else Color{0.5, 0.3, 0.3}, 2)
			sx, px := sell_x(x, w), buy_x(x, w)
			fill_rect(sx, iy + 3, 20, ITEM_H - 10, 0.2, 0.22, 0.3, 1)
			fill_rect(px, iy + 3, 20, ITEM_H - 10, 0.2, 0.22, 0.3, 1)
			text("-", sx + 10, mid, 14, WHITE, 1)
			text("+", px + 10, mid, 14, WHITE if afford else Color{0.4, 0.4, 0.45}, 1)
			text(it.value, (sx + 20 + px) / 2, mid, 14, GOLD, 1)
		}
	}
}
