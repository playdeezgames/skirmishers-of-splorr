#+build js
package main

// Browser side: mouse and key input, canvas drawing and the frame loop.
// All rules live in the game package; this file only shows them.

import "base:runtime"
import "core:fmt"
import "core:sys/wasm/js"
import "core:time"
import "game"

// Implemented in web/index.html (2D canvas, pixels, y down).
foreign import canvas "canvas"
@(default_calling_convention = "contextless")
foreign canvas {
	clear_canvas :: proc(r, g, b: f32) ---
	fill_rect :: proc(x, y, w, h: f32, r, g, b, a: f32) ---
	// pointy-topped hex; a stroke alpha of 0 skips the outline
	draw_hex :: proc(cx, cy, radius: f32, fr, fg, fb, fa: f32, sr, sg, sb, sa: f32, line: f32) ---
	draw_circle :: proc(cx, cy, radius: f32, fr, fg, fb: f32, sr, sg, sb: f32, line: f32) ---
	// align: 0 left, 1 centre, 2 right; y is the text's middle
	draw_text :: proc(s: [^]u8, n: i32, x, y, size: f32, r, g, b: f32, align: i32) ---
}

CANVAS_W :: 1020
CANVAS_H :: 580
HEX_R :: f32(18)
MAP_X :: f32(12) // pixel offset of the map
MAP_Y :: f32(14)
PANEL_X :: f32(672)
AI_DELAY :: 0.35 // seconds between computer actions

Color :: [3]f32
GRASS :: Color{0.42, 0.62, 0.3}
FOREST :: Color{0.18, 0.4, 0.2}
ROAD :: Color{0.72, 0.6, 0.4}
TREE :: Color{0.08, 0.24, 0.1}
WHITE :: Color{1, 1, 1}
GREY :: Color{0.65, 0.65, 0.7}
GOLD :: Color{1, 0.85, 0.3}

Button :: struct {
	x, y, w, h: f32,
}
END_TURN_BUTTON :: Button{PANEL_X, 250, 150, 34}
NEW_GAME_BUTTON :: Button{PANEL_X + 166, 250, 150, 34}

ctx: runtime.Context
g: game.Game
scenario := 0
selected := -1
hover := game.Hex{-1, -1}
ai_timer: f64

main :: proc() {
	ctx = context
	js.add_window_event_listener(.Key_Down, nil, on_key)
	start_game(0)
}

start_game :: proc(n: int) {
	scenario = n
	game.new_game(&g, n, u64(time.now()._nsec))
	selected = -1
	ai_timer = 0
}

// The page calls this for a ?scenario=N address (1-based).
@(export)
load_scenario :: proc "c" (n: i32) {
	context = ctx
	idx := int(n) - 1
	if idx >= 0 && idx < len(game.SCENARIOS) { start_game(idx) }
}

human_turn :: proc() -> bool {
	return g.winner < 0 && g.factions[g.current].controller == .Human
}

in_button :: proc(b: Button, x, y: f32) -> bool {
	return x >= b.x && x < b.x + b.w && y >= b.y && y < b.y + b.h
}

screen_to_hex :: proc(x, y: f32) -> game.Hex {
	return game.pixel_to_hex({x - MAP_X, y - MAP_Y}, HEX_R)
}

hex_centre :: proc(h: game.Hex) -> [2]f32 {
	return game.hex_to_pixel(h, HEX_R) + {MAP_X, MAP_Y}
}

@(export)
mouse_move :: proc "c" (x, y: f32) {
	context = ctx
	h := screen_to_hex(x, y)
	hover = h if game.in_bounds(h) && x < PANEL_X - 4 else {-1, -1}
}

@(export)
mouse_click :: proc "c" (x, y: f32) {
	context = ctx
	if in_button(NEW_GAME_BUTTON, x, y) {
		start_game(scenario)
		return
	}
	if !human_turn() { return }
	if in_button(END_TURN_BUTTON, x, y) {
		end_human_turn()
		return
	}
	h := screen_to_hex(x, y)
	if x >= PANEL_X - 4 || !game.in_bounds(h) {
		selected = -1
		return
	}
	other := game.unit_at(&g, h)
	if other >= 0 && g.units[other].faction == g.current {
		selected = other
		return
	}
	if selected >= 0 {
		if other >= 0 && game.can_attack(&g, selected, other) {
			game.attack(&g, selected, other)
			return
		}
		if game.move_unit(&g, selected, h) { return }
	}
	selected = -1
}

end_human_turn :: proc() {
	selected = -1
	game.end_turn(&g)
	ai_timer = 0
}

on_key :: proc(e: js.Event) {
	if e.kind != .Key_Down || e.key.repeat { return }
	switch e.key.key {
	case " ", "Enter", "e", "E":
		if human_turn() { end_human_turn() }
	case "Escape":
		selected = -1
	case "n", "N":
		start_game(scenario)
	case:
		return
	}
	js.event_prevent_default()
}

text :: proc(s: string, x, y: f32, size: f32 = 14, color := WHITE, align: i32 = 0) {
	str := s
	draw_text(raw_data(str), i32(len(str)), x, y, size, color.r, color.g, color.b, align)
}

dice_text :: proc(d: game.Dice) -> string {
	out := ""
	for count, die in d {
		if count == 0 { continue }
		part := fmt.tprintf("%d %s", count, game.DIE_NAMES[die])
		out = part if out == "" else fmt.tprintf("%s, %s", out, part)
	}
	return out if out != "" else "none"
}

// Half points as text: 7 -> "3.5", 8 -> "4".
points_text :: proc(halves: int) -> string {
	whole := halves / game.HALVES_PER_POINT
	if halves % game.HALVES_PER_POINT == 0 { return fmt.tprintf("%d", whole) }
	return fmt.tprintf("%d.5", whole)
}

button :: proc(b: Button, label: string, enabled: bool) {
	bg := Color{0.25, 0.3, 0.42} if enabled else Color{0.18, 0.18, 0.22}
	fill_rect(b.x, b.y, b.w, b.h, bg.r, bg.g, bg.b, 1)
	text(label, b.x + b.w / 2, b.y + b.h / 2, 15, WHITE if enabled else GREY, 1)
}

@(export)
step :: proc(dt: f64, c: runtime.Context) -> bool {
	context = ctx
	free_all(context.temp_allocator)

	if game.is_computer_turn(&g) {
		ai_timer += dt
		if ai_timer >= AI_DELAY {
			ai_timer = 0
			game.ai_step(&g)
		}
	}
	if selected >= 0 && !g.units[selected].alive { selected = -1 }

	clear_canvas(0.1, 0.1, 0.13)
	draw_map()
	draw_panel()
	return true
}

draw_map :: proc() {
	costs: [game.ROWS][game.COLS]int
	if selected >= 0 { costs = game.movement_costs(&g, selected) }
	for row in 0 ..< game.ROWS {
		for col in 0 ..< game.COLS {
			h := game.Hex{col, row}
			p := hex_centre(h)
			t := game.terrain_at(&g, h)
			fill: Color
			switch t {
			case .Grass:  fill = GRASS
			case .Forest: fill = FOREST
			case .Road:   fill = ROAD
			}
			draw_hex(p.x, p.y, HEX_R, fill.r, fill.g, fill.b, 1, 0, 0, 0, 0.25, 1)
			if t == .Forest {
				text("♣", p.x - 5, p.y - 3, 11, TREE, 1)
				text("♣", p.x + 5, p.y + 5, 11, TREE, 1)
			}
			if selected >= 0 && game.can_move(&g, selected, h, &costs) {
				draw_hex(p.x, p.y, HEX_R - 2, 1, 1, 0.6, 0.3, 0, 0, 0, 0, 0)
			}
		}
	}
	for i in 0 ..< g.unit_count {
		u := &g.units[i]
		if !u.alive { continue }
		p := hex_centre(u.pos)
		col := g.factions[u.faction].color
		finished := game.unit_finished(&g, i)
		letter := WHITE
		if finished {
			// greyed out: a little of the faction colour left so sides stay readable
			col = col * 0.25 + Color{0.38, 0.38, 0.4}
			letter = Color{0.75, 0.75, 0.78}
		}
		draw_circle(p.x, p.y, HEX_R * 0.62, col.r, col.g, col.b, 0.1, 0.1, 0.1, 2)
		text("K", p.x, p.y + 1, 13, letter, 1)
		if !finished && game.unit_has_moved(&g, i) {
			// moved but can still act: a small pip at the upper right
			draw_circle(p.x + HEX_R * 0.5, p.y - HEX_R * 0.5, 3.5, 1, 1, 1, 0.1, 0.1, 0.1, 1)
		}
		if selected >= 0 && game.can_attack(&g, selected, i) {
			draw_hex(p.x, p.y, HEX_R - 1, 0, 0, 0, 0, 1, 0.15, 0.1, 1, 3)
		}
	}
	if selected >= 0 {
		p := hex_centre(g.units[selected].pos)
		draw_hex(p.x, p.y, HEX_R - 1, 0, 0, 0, 0, 1, 1, 1, 1, 3)
	}
	if hover.x >= 0 {
		p := hex_centre(hover)
		draw_hex(p.x, p.y, HEX_R - 1, 0, 0, 0, 0, GOLD.r, GOLD.g, GOLD.b, 0.9, 2)
	}
}

draw_panel :: proc() {
	x := PANEL_X
	text("Skirmishers of SPLORR!!", x, 24, 20, GOLD)
	text(game.SCENARIOS[scenario].name, x, 50, 13, GREY)

	f := &g.factions[g.current]
	status: string
	switch {
	case g.winner >= 0:
		status = fmt.tprintf("%s win!", g.factions[g.winner].name)
	case f.controller == .Human:
		status = fmt.tprintf("Turn %d: your move (%s)", g.turn, f.name)
	case:
		status = fmt.tprintf("Turn %d: %s is thinking...", g.turn, f.name)
	}
	text(status, x, 80, 16, f.color if g.winner < 0 else g.factions[g.winner].color)

	y := f32(110)
	if selected >= 0 {
		u := &g.units[selected]
		ut := game.unit_type(u)
		text(fmt.tprintf("%s %s", g.factions[u.faction].name, ut.name), x, y, 15)
		text(fmt.tprintf("Attack %s   Defence %s", dice_text(ut.attack), dice_text(ut.defense)), x, y + 20, 13, GREY)
		text(fmt.tprintf("Body %d/%d   Move %s/%d   Range %d-%d", u.body, ut.body, points_text(u.moves_left), ut.move, ut.min_range, ut.max_range), x, y + 38, 13, GREY)
		state := "may attack"
		if u.attacked {
			state = "attacked: done for this turn"
		} else if game.unit_finished(&g, selected) {
			state = "no moves left and nobody in range"
		}
		text(state, x, y + 56, 13, GREY)
	} else if human_turn() {
		text("Click one of your units to select it.", x, y, 13, GREY)
		text("Yellow hexes: where it can move.", x, y + 18, 13, GREY)
		text("Red outline: an enemy it can attack.", x, y + 36, 13, GREY)
		text("White pip: moved. Grey: done for the turn.", x, y + 54, 13, GREY)
		text("Space ends the turn, N starts a new game.", x, y + 72, 13, GREY)
	}
	if hover.x >= 0 {
		t := game.terrain_at(&g, hover)
		cost := fmt.tprintf("move cost %d", game.TERRAIN_MOVE_COST[t])
		if t == .Road { cost = fmt.tprintf("%s, %s from road", cost, points_text(game.step_cost(.Road, .Road))) }
		text(fmt.tprintf("Hex %d,%d: %s (%s)", hover.x, hover.y, game.TERRAIN_NAMES[t], cost), x, 200, 13, GREY)
		if hu := game.unit_at(&g, hover); hu >= 0 {
			u := &g.units[hu]
			text(fmt.tprintf("%s %s, body %d", g.factions[u.faction].name, game.unit_type(u).name, u.body), x, 218, 13, g.factions[u.faction].color)
		}
	}

	button(END_TURN_BUTTON, "End turn", human_turn())
	button(NEW_GAME_BUTTON, "New game", true)

	for i in 0 ..< g.faction_count {
		fc := &g.factions[i]
		who := "you" if fc.controller == .Human else "computer"
		text(fmt.tprintf("%s (%s): %d kobolds", fc.name, who, game.living_units(&g, i)), x, 306 + f32(i) * 18, 13, fc.color)
	}

	text("Log", x, 356, 14, GOLD)
	for i in 0 ..< g.log_count {
		shade := 1 - f32(i) * 0.06
		text(game.log_line(&g, i), x, 376 + f32(i) * 15, 11, WHITE * shade)
	}
}
