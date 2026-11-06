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
	// opacity of everything drawn after it (1 = opaque)
	set_alpha :: proc(a: f32) ---
	// one of the WAVs in SOUND_FILES (web/index.html), by Sound index
	play_sound :: proc(id: i32) ---
	// a sprite from art.png centred on (cx, cy), at a whole-number scale
	blit :: proc(sprite: i32, cx, cy: f32, scale: f32) ---
}

// Sprites in art.png, in the Anvil sprite-set order (assets/art/world.json).
Sprite :: enum i32 {
	Kobold,
	Slinger,
	Trees,
}

UNIT_SPRITES := [game.Unit_Kind]Sprite {
	.Kobold         = .Kobold,
	.Kobold_Slinger = .Slinger,
}

// Order must match SOUND_FILES in web/index.html.
Sound :: enum i32 {
	Step,
	Stab,
	Sling,
	Hit,
	Block,
	Slain,
	Fortify,
	Your_Turn,
	Win,
	Lose,
}

play :: proc(s: Sound) {
	play_sound(i32(s))
}

CANVAS_W :: 1060
CANVAS_H :: 580
HEX_R :: f32(18)
MAP_X :: f32(12) // pixel offset of the map
MAP_Y :: f32(14)
PANEL_X :: f32(672)
AI_DELAY :: 0.25 // seconds between computer actions, after each one's animation

Color :: [3]f32
GRASS :: Color{0.42, 0.62, 0.3}
FOREST :: Color{0.18, 0.4, 0.2}
ROAD :: Color{0.72, 0.6, 0.4}
WHITE :: Color{1, 1, 1}
GREY :: Color{0.65, 0.65, 0.7}
GOLD :: Color{1, 0.85, 0.3}

Button :: struct {
	x, y, w, h: f32,
}
FORTIFY_BUTTON :: Button{PANEL_X, 250, 90, 34}
FINISH_MOVE_BUTTON :: Button{PANEL_X + 94, 250, 90, 34}
END_TURN_BUTTON :: Button{PANEL_X + 188, 250, 90, 34}
NEW_GAME_BUTTON :: Button{PANEL_X + 282, 250, 90, 34}
FORTIFIED_RING :: Color{0.92, 0.86, 0.7}
// scenario picker, beside the scenario name: changing scenario starts a new game
PREV_SCENARIO_BUTTON :: Button{PANEL_X, 41, 20, 18}
NEXT_SCENARIO_BUTTON :: Button{PANEL_X + 24, 41, 20, 18}

ctx: runtime.Context
g: game.Game
scenario := 0
selected := -1
hover := game.Hex{-1, -1}
ai_timer: f64
// computer-vs-computer only: whose fog the map shows (V cycles it)
View_Mode :: enum {
	Everything,
	Red,
	Blue,
}
view_mode := View_Mode.Everything

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
	anim_skip()
	last_winner = -1
	last_turn_owner = -1
}

// for the turn and game-over sounds
last_winner := -1
last_turn_owner := -1

// The page calls this for a ?scenario=N address (1-based).
@(export)
load_scenario :: proc "c" (n: i32) {
	context = ctx
	idx := int(n) - 1
	if idx >= 0 && idx < len(game.SCENARIOS) { start_game(idx) }
}

// QA hook for screenshots (?steps=N): plays up to N computer actions at once.
@(export)
debug_ai_steps :: proc "c" (n: i32) {
	context = ctx
	for _ in 0 ..< n {
		if !game.ai_step(&g) { break }
	}
	anim_skip()
}

// The side whose view the map shows: the human player's, or in a game with no
// human, the one picked with V (NO_FACTION shows everything).
viewer :: proc() -> int {
	for i in 0 ..< g.faction_count {
		if g.factions[i].controller == .Human { return i }
	}
	switch view_mode {
	case .Red:  return 0
	case .Blue: return 1 if g.faction_count > 1 else 0
	case .Everything:
	}
	return game.NO_FACTION
}

has_human :: proc() -> bool {
	for i in 0 ..< g.faction_count {
		if g.factions[i].controller == .Human { return true }
	}
	return false
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
	if in_button(PREV_SCENARIO_BUTTON, x, y) {
		cycle_scenario(-1)
		return
	}
	if in_button(NEXT_SCENARIO_BUTTON, x, y) {
		cycle_scenario(1)
		return
	}
	if !human_turn() || anim_busy() { return }
	if in_button(END_TURN_BUTTON, x, y) {
		end_human_turn()
		return
	}
	if in_button(FINISH_MOVE_BUTTON, x, y) {
		finish_selected_move()
		return
	}
	if in_button(FORTIFY_BUTTON, x, y) {
		fortify_selected()
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
			game.attack(&g, selected, other) // this ends the unit's move
			select_next_unit()
			return
		}
		if game.move_unit(&g, selected, h) { return }
	}
	selected = -1
}

// Selects the next of the player's units whose move is not over, after the
// selected one (wrapping round), or nothing if all have ended.
select_next_unit :: proc() {
	start := max(selected, 0)
	for k in 1 ..= g.unit_count {
		i := (start + k) % g.unit_count
		u := &g.units[i]
		if u.alive && u.faction == g.current && !game.unit_finished(&g, i) {
			selected = i
			return
		}
	}
	selected = -1
}

fortify_selected :: proc() {
	if selected < 0 || !human_turn() { return }
	if game.fortify(&g, selected) { select_next_unit() }
}

finish_selected_move :: proc() {
	if selected < 0 || !human_turn() { return }
	if game.finish_move(&g, selected) { select_next_unit() }
}

cycle_scenario :: proc(step: int) {
	n := len(game.SCENARIOS)
	start_game((scenario + step + n) % n)
}

// Refused by the rules while any of the player's units has not ended its move.
end_human_turn :: proc() {
	if game.end_turn(&g) {
		selected = -1
		ai_timer = 0
	}
}

on_key :: proc(e: js.Event) {
	if e.kind != .Key_Down || e.key.repeat { return }
	if anim_busy() {
		switch e.key.key {
		case " ", "Enter", "d", "D", "f", "F": return // wait for the animation
		}
	}
	switch e.key.key {
	case " ", "Enter":
		if human_turn() { end_human_turn() }
	case "d", "D":
		fortify_selected()
	case "f", "F":
		finish_selected_move()
	case "Escape":
		selected = -1
	case "n", "N":
		start_game(scenario)
	case "v", "V":
		if has_human() { return }
		view_mode = View_Mode((int(view_mode) + 1) % len(View_Mode))
	case "[":
		cycle_scenario(-1)
	case "]":
		cycle_scenario(1)
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
	text(label, b.x + b.w / 2, b.y + b.h / 2, 13, WHITE if enabled else GREY, 1)
}

@(export)
step :: proc(dt: f64, c: runtime.Context) -> bool {
	context = ctx
	free_all(context.temp_allocator)

	anim_update(dt)
	if game.is_computer_turn(&g) && !anim_busy() {
		ai_timer += dt
		if ai_timer >= AI_DELAY {
			ai_timer = 0
			game.ai_step(&g)
			anim_update(0) // start its animation this frame
		}
	}
	turn_sounds()
	if selected >= 0 && !g.units[selected].alive { selected = -1 }

	clear_canvas(0.1, 0.1, 0.13)
	draw_map()
	draw_panel()
	return true
}

UNEXPLORED :: Color{0.07, 0.07, 0.09}

// Your turn starting, and the end of the game.
turn_sounds :: proc() {
	if anim_busy() { return }
	if g.winner >= 0 && last_winner < 0 {
		last_winner = g.winner
		lost := has_human() && g.factions[g.winner].controller != .Human
		play(.Lose if lost else .Win)
	}
	owner := g.current + g.turn * game.MAX_FACTIONS
	if human_turn() && owner != last_turn_owner {
		if last_turn_owner >= 0 { play(.Your_Turn) }
	}
	last_turn_owner = owner
}

draw_map :: proc() {
	view := viewer()
	costs: [game.ROWS][game.COLS]int
	if selected >= 0 { costs = game.movement_costs(&g, selected) }
	for row in 0 ..< game.ROWS {
		for col in 0 ..< game.COLS {
			h := game.Hex{col, row}
			p := hex_centre(h)
			if !game.hex_seen(&g, view, h) {
				// never seen: no terrain shown
				draw_hex(p.x, p.y, HEX_R, UNEXPLORED.r, UNEXPLORED.g, UNEXPLORED.b, 1, 1, 1, 1, 0.06, 1)
				continue
			}
			t := game.terrain_at(&g, h)
			fill: Color
			switch t {
			case .Grass:  fill = GRASS
			case .Forest: fill = FOREST
			case .Road:   fill = ROAD
			}
			high := game.is_high(&g, h)
			if high { fill = fill * 0.7 + Color{0.95, 0.9, 0.7} * 0.3 } // high ground: paler, with a dark rim
			draw_hex(p.x, p.y, HEX_R, fill.r, fill.g, fill.b, 1, 0, 0, 0, 0.25, 1)
			if high { draw_hex(p.x, p.y, HEX_R - 1.5, 0, 0, 0, 0, 0.35, 0.27, 0.15, 0.8, 1.5) }
			if t == .Forest { blit(i32(Sprite.Trees), p.x, p.y, 2) }
			if !game.hex_in_view(&g, view, h) {
				// explored but out of sight now: dimmed
				draw_hex(p.x, p.y, HEX_R, 0.05, 0.05, 0.08, 0.5, 0, 0, 0, 0, 0)
			}
			if selected >= 0 && !anim_busy() && game.can_move(&g, selected, h, &costs) {
				draw_hex(p.x, p.y, HEX_R - 2, 1, 1, 0.6, 0.3, 0, 0, 0, 0, 0)
			}
		}
	}
	// last-seen markers: a faded counter with a question mark
	if view != game.NO_FACTION {
		for i in 0 ..< g.unit_count {
			pos, ok := game.sighting(&g, view, i)
			if !ok { continue }
			p := hex_centre(pos)
			col := g.factions[g.units[i].faction].color * 0.35 + Color{0.25, 0.25, 0.28}
			draw_circle(p.x, p.y, HEX_R * 0.5, col.r, col.g, col.b, 0.6, 0.6, 0.65, 1)
			text("?", p.x, p.y + 1, 12, Color{0.85, 0.85, 0.88}, 1)
		}
	}
	for i in 0 ..< g.unit_count {
		u := &g.units[i]
		p := hex_centre(u.pos)
		apos, alpha, ashow, amoved := anim_unit(i, view)
		if amoved {
			if !ashow { continue }
			p = apos
		} else if !u.alive || !game.unit_visible(&g, i, view) {
			continue
		}
		set_alpha(alpha)
		defer set_alpha(1)
		col := g.factions[u.faction].color
		finished := game.unit_finished(&g, i)
		if finished {
			// greyed out: a little of the faction colour left so sides stay readable
			col = col * 0.25 + Color{0.38, 0.38, 0.4}
		}
		if u.fortified {
			// a pale ring round the counter: defends with advantage
			draw_hex(p.x, p.y, HEX_R * 0.86, 0, 0, 0, 0, FORTIFIED_RING.r, FORTIFIED_RING.g, FORTIFIED_RING.b, 1, 3)
		}
		draw_circle(p.x, p.y, HEX_R * 0.8, col.r, col.g, col.b, 0.1, 0.1, 0.1, 2)
		if finished { set_alpha(alpha * 0.55) }
		blit(i32(UNIT_SPRITES[u.kind]), p.x, p.y, 2) // the kobold's dagger or the slinger's sling
		set_alpha(alpha)
		if !finished && game.unit_has_moved(&g, i) {
			// moved but can still act: a small pip at the upper right
			draw_circle(p.x + HEX_R * 0.5, p.y - HEX_R * 0.5, 3.5, 1, 1, 1, 0.1, 0.1, 0.1, 1)
		}
		if selected >= 0 && !anim_busy() && game.can_attack(&g, selected, i) {
			draw_hex(p.x, p.y, HEX_R - 1, 0, 0, 0, 0, 1, 0.15, 0.1, 1, 3)
		}
	}
	draw_anim_effects()
	if selected >= 0 && !anim_busy() {
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
	button(PREV_SCENARIO_BUTTON, "<", true)
	button(NEXT_SCENARIO_BUTTON, ">", true)
	text(game.SCENARIOS[scenario].name, x + 52, 50, 13, GREY)
	if !has_human() {
		names := [View_Mode]string{.Everything = "everything", .Red = "Red's view", .Blue = "Blue's view"}
		text(fmt.tprintf("Map shows %s (V to change)", names[view_mode]), x, 102, 13, GREY)
	}

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
		text(fmt.tprintf("%s %s (%d points)", g.factions[u.faction].name, ut.name, ut.points), x, y, 15)
		text(fmt.tprintf("Defence %s   Body %d/%d   Move %s/%d   Sight %d", dice_text(ut.defense), u.body, ut.body, points_text(u.moves_left), ut.move, ut.vision), x, y + 20, 13, GREY)
		wy := y + 38
		for w in ut.weapons {
			wp := &game.WEAPONS[w]
			reach := fmt.tprintf("range %d", wp.max_range) if wp.min_range == wp.max_range else fmt.tprintf("range %d-%d", wp.min_range, wp.max_range)
			text(fmt.tprintf("%s: %s, %s", wp.name, dice_text(wp.attack), reach), x, wy, 13, GREY)
			wy += 18
		}
		state := "may attack"
		if u.fortified {
			state = "fortified: defends with advantage"
		} else if u.attacked {
			state = "attacked: done for this turn"
		} else if u.done {
			state = "move finished"
		} else if game.unit_finished(&g, selected) {
			state = "no moves left and nobody in range"
		}
		text(state, x, wy, 13, GREY)
	} else if human_turn() {
		text("Click one of your units to select it.", x, y, 13, GREY)
		text("Yellow: moves. Red: targets. ?: last seen.", x, y + 16, 13, GREY)
		text("Kobolds carry daggers; slingers whirl slings.", x, y + 32, 13, GREY)
		text("Pip: moved. Grey: done. Pale ring: fortified.", x, y + 48, 13, GREY)
		text("D: fortify (before moving). F: finish move.", x, y + 64, 13, GREY)
		text("Space: end turn. N: new game. [ ]: scenario.", x, y + 80, 13, GREY)
	}
	view := viewer()
	if hover.x >= 0 && !game.hex_seen(&g, view, hover) {
		text(fmt.tprintf("Hex %d,%d: unexplored", hover.x, hover.y), x, 210, 13, GREY)
	} else if hover.x >= 0 {
		t := game.terrain_at(&g, hover)
		cost := fmt.tprintf("move cost %d", game.TERRAIN_MOVE_COST[t])
		if t == .Road { cost = fmt.tprintf("%s, %s from road", cost, points_text(game.step_cost(.Road, .Road, false, false))) }
		text(fmt.tprintf("Hex %d,%d: %s%s (%s)", hover.x, hover.y, game.is_high(&g, hover) ? "high " : "", game.TERRAIN_NAMES[t], cost), x, 210, 13, GREY)
		if hu := game.unit_at(&g, hover); hu >= 0 && game.unit_visible(&g, hu, view) {
			u := &g.units[hu]
			label := fmt.tprintf("%s %s, body %d%s", g.factions[u.faction].name, game.unit_type(u).name, u.body, ", fortified" if u.fortified else "")
			// explain a shot the selected unit cannot take because of forest
			if selected >= 0 && u.faction != g.units[selected].faction {
				d := game.hex_distance(g.units[selected].pos, u.pos)
				_, in_range := game.weapon_in_range(&g, game.unit_type(&g.units[selected]), g.units[selected].pos, u.pos)
				if game.needs_line_of_sight(d) && in_range && !game.line_of_sight(&g, g.units[selected].pos, u.pos, g.units[selected].faction) {
					label = fmt.tprintf("%s: shot blocked", label)
				}
			}
			text(label, x, 228, 13, g.factions[u.faction].color)
		} else if view != game.NO_FACTION {
			for i in 0 ..< g.unit_count {
				if pos, ok := game.sighting(&g, view, i); ok && pos == hover {
					fc := &g.factions[g.units[i].faction]
					text(fmt.tprintf("%s %s last seen here", fc.name, game.unit_type(&g.units[i]).name), x, 228, 13, fc.color)
					break
				}
			}
			if !game.hex_in_view(&g, view, hover) { text("out of sight", x + 260, 228, 11, GREY) }
		}
	}

	left := game.units_left_to_act(&g) if human_turn() else 0
	button(FORTIFY_BUTTON, "Fortify", human_turn() && selected >= 0 && game.can_fortify(&g, selected))
	button(FINISH_MOVE_BUTTON, "Finish move", human_turn() && selected >= 0 && !game.unit_finished(&g, selected))
	button(END_TURN_BUTTON, "End turn", human_turn() && left == 0)
	button(NEW_GAME_BUTTON, "New game", true)
	if left > 0 {
		text(fmt.tprintf("%d unit%s still to move", left, "" if left == 1 else "s"), x + 188, 292, 11, GREY)
	}

	for i in 0 ..< g.faction_count {
		fc := &g.factions[i]
		who := "you" if fc.controller == .Human else "computer"
		text(fmt.tprintf("%s (%s): %d units, %d points", fc.name, who, game.living_units(&g, i), game.army_points(&g, i)), x, 306 + f32(i) * 18, 13, fc.color)
	}

	text("Log", x, 356, 14, GOLD)
	for i in 0 ..< g.log_count {
		shade := 1 - f32(i) * 0.06
		text(game.log_line(&g, i), x, 376 + f32(i) * 15, 11, WHITE * shade)
	}
}
