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
}

Action :: enum {
	None,
	Open_Scenarios,
	Open_Options,
	Open_Help,
	Start, // arg: scenario index
	Back,
	Resume,
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
}

Item :: struct {
	label:   string,
	action:  Action,
	arg:     int,
	enabled: bool,
}

MAX_ITEMS :: 16
menu_stack: [8]Menu_Id
menu_depth := 0
menu_sel: [Menu_Id]int
menu_hover := -1 // item under the mouse
confirm_for: Action // what Yes does on the Confirm menu (Restart or Quit)

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
			item_buf[n^] = {label, action, arg, enabled}
			n^ += 1
		}
	}
	switch id {
	case .Title:
		add(&n, "Play", .Open_Scenarios)
		add(&n, "Options", .Open_Options)
		add(&n, "How to play", .Open_Help)
	case .Scenarios:
		for sc, i in game.SCENARIOS { add(&n, sc.name, .Start, arg = i) }
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
			if game.unit_type(u).chants { add(&n, "Chant: bless a friend", .Chant, enabled = !u.done) }
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
		chanting = true
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
		case .Auto_End, .Sound, .Speed, .View: activate(items[sel^])
		}
	case .Ok:
		activate(items[sel^])
	case .Cancel, .Menu:
		switch id {
		case .Title:     // nowhere to go back to
		case .Confirm:   pop_menu()
		case .Game_Over: pop_menu() // look at the map
		case .Scenarios, .Options, .Help, .Pause, .Unit:
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
	if selected_chants() && other >= 0 && (chanting || g.units[other].faction != g.current) && game.can_chant(&g, selected, other) {
		game.chant(&g, selected, other) // this ends the Wololo's move
		chanting = false
		select_next_unit()
		return
	}
	chanting = false
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
	case chanting:      chanting = false
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
		if !menu_open() && selected_chants() { chanting = !chanting }
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

// Where a menu is drawn: over the map while playing, in the middle of the
// screen on the title screens.
menu_box :: proc(id: Menu_Id) -> (x, y, w, h: f32) {
	items := menu_items(id)
	extra := menu_text_lines(id)
	w = MENU_W if id != .Help else 600
	h = menu_items_top(id) + f32(extra) * 18 + f32(len(items)) * ITEM_H + 14
	cx := f32(CANVAS_W) / 2 if on_title() else (PANEL_X - 12) / 2
	if id == .Scenarios { w = 420 }
	x = cx - w / 2
	y = max(16, f32(CANVAS_H) / 2 - h / 2 + (60 if on_title() && id == .Title else 0))
	return
}

menu_item_at :: proc(x, y: f32) -> int {
	if !menu_open() { return -1 }
	id := menu_top()
	bx, by, bw, _ := menu_box(id)
	items := menu_items(id)
	top := by + menu_items_top(id) + f32(menu_text_lines(id)) * 18
	for i in 0 ..< len(items) {
		iy := top + f32(i) * ITEM_H
		if x >= bx + 12 && x < bx + bw - 12 && y >= iy && y < iy + ITEM_H - 4 { return i }
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
	if game.in_bounds(h) && x < PANEL_X - 4 {
		put_cursor(h)
		cursor_on = true
	}
}

@(export)
mouse_click :: proc "c" (x, y: f32) {
	context = ctx
	if menu_open() {
		if i := menu_item_at(x, y); i >= 0 {
			menu_sel[menu_top()] = i
			activate(menu_items(menu_top())[i])
		} else if menu_top() == .Unit {
			pop_menu() // a click away from the unit menu closes it
		}
		return
	}
	if in_button(MENU_BUTTON, x, y) {
		push_menu(.Pause)
		return
	}
	if in_button(END_TURN_BUTTON, x, y) && show_end_turn_button() {
		end_human_turn()
		return
	}
	h := screen_to_hex(x, y)
	if x >= PANEL_X - 4 || !game.in_bounds(h) { return }
	put_cursor(h)
	play_ok()
}

// ---------------------------------------------------------------- drawing

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
	}
	return 0
}

HELP := [?]string {
	"Each side takes turns. A unit may move, then attack once; attacking ends",
	"its move. HeroQuest dice: white scores 1 in 3, red 1 in 2, black 2 in 3.",
	"Each block cancels a hit; each hit left costs a body point.",
	"",
	"Cursor: arrows, WASD, D-pad or the mouse.  OK: Space, Enter, A or click.",
	"Back / menu: Esc, B (Start opens the menu too).",
	"OK on your unit selects it; OK on a yellow hex moves it there; OK on a",
	"red-ringed enemy attacks. OK on the selected unit again: fortify, finish",
	"its move, or (Wololo) bless a friend. Keyboard: F finish, C chant, M sound.",
	"",
	"Forest costs 2 and blocks shots; roads are quick; high ground helps in",
	"melee and adds sling and bow range. You see only what your units see.",
	"Armour adds defence dice; crossbows pierce it; pikes strike first.",
}

draw_menus :: proc() {
	if !menu_open() { return }
	if on_title() {
		fill_rect(0, 0, CANVAS_W, CANVAS_H, 0.05, 0.05, 0.08, 0.72)
		if menu_top() == .Title {
			text("Skirmishers of SPLORR!!", f32(CANVAS_W) / 2, 120, 44, GOLD, 1)
			text("kobolds, dice and hexes", f32(CANVAS_W) / 2, 168, 18, GREY, 1)
		}
	} else {
		fill_rect(0, 0, PANEL_X - 4, CANVAS_H, 0, 0, 0, 0.5)
	}
	id := menu_top()
	x, y, w, h := menu_box(id)
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
	}
	title := titles[id]
	if id == .Unit && selected >= 0 { title = game.unit_type(&g.units[selected]).name }
	if id == .Game_Over && g.winner >= 0 { title = fmt.tprintf("%s win!", g.factions[g.winner].name) }
	tc := GOLD
	if id == .Game_Over && g.winner >= 0 { tc = g.factions[g.winner].color }
	text(title, x + w / 2, y + 28, 18, tc, 1)
	ty := y + menu_items_top(id)
	switch id {
	case .Confirm:
		text("The battle in progress will be lost.", x + w / 2, ty + 6, 13, GREY, 1)
	case .Game_Over:
		msg := "Every enemy is down." if has_human() && g.factions[g.winner].controller == .Human else "Your band is gone."
		if !has_human() { msg = "The battle is over." }
		text(msg, x + w / 2, ty + 6, 13, GREY, 1)
	case .Help:
		for line, i in HELP { text(line, x + 20, ty + 6 + f32(i) * 18, 12, WHITE) }
	case .Title, .Scenarios, .Options, .Pause, .Unit:
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
		text(it.label, x + 40, iy + (ITEM_H - 4) / 2, 14, col, 0)
	}
	if on_title() {
		text("Arrows / WASD / D-pad to choose, Space / Enter / A to pick, Esc / B to go back", f32(CANVAS_W) / 2, f32(CANVAS_H) - 18, 12, GREY, 1)
	}
}
