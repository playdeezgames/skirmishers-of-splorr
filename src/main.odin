#+build js
package main

// Browser side: the frame loop, the map and the panel. Menus and input are in
// ui.odin, animation in anim.odin. All rules live in the game package; this
// layer only shows them.

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
	draw_line :: proc(x0, y0, x1, y1: f32, r, g, b: f32, width: f32) ---
	// opacity of everything drawn after it (1 = opaque)
	set_alpha :: proc(a: f32) ---
	// one of the WAVs in SOUND_FILES (web/index.html), by Sound index
	play_sound :: proc(id: i32) ---
	// sound on or off; the page remembers the choice in the browser
	toggle_mute :: proc() ---
	is_muted :: proc() -> b32 ---
	// a sprite from art.png centred on (cx, cy), at a whole-number scale
	blit :: proc(sprite: i32, cx, cy: f32, scale: f32) ---
	// settings kept in the browser; load gives -1 for one never saved
	load_option :: proc(id: i32) -> i32 ---
	save_option :: proc(id: i32, value: i32) ---
	// scale and offset for everything drawn after it (1, 0, 0 = canvas pixels)
	set_transform :: proc(scale, dx, dy: f32) ---
}

// Sprites in art.png, in the Anvil sprite-set order (assets/art/world.json).
Sprite :: enum i32 {
	Kobold,
	Slinger,
	Trees,
	Heavy,
	Champion,
	Scout,
	Archer,
	Crossbow,
	Pike,
	Wololo,
}

UNIT_SPRITES := [game.Unit_Kind]Sprite {
	.Kobold         = .Kobold,
	.Kobold_Slinger = .Slinger,
	.Heavy          = .Heavy,
	.Champion       = .Champion,
	.Scout          = .Scout,
	.Archer         = .Archer,
	.Crossbow       = .Crossbow,
	.Pike           = .Pike,
	.Wololo         = .Wololo,
}

BLESS_COLOR :: Color{1, 0.85, 0.3}
CURSE_COLOR :: Color{0.72, 0.38, 0.95}

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
	Bow,
	Crossbow,
	Chant,
}

// The sound each weapon makes when it is used.
WEAPON_SOUNDS := [game.Weapon_Kind]Sound {
	.Dagger   = .Stab,
	.Sling    = .Sling,
	.Axe      = .Stab,
	.Sword    = .Stab,
	.Bow      = .Bow,
	.Crossbow = .Crossbow,
	.Pike     = .Stab,
}

play :: proc(s: Sound) {
	play_sound(i32(s))
}

CANVAS_W :: 1060 // the landscape layout: map on the left, panel on the right
CANVAS_H :: 580
HEX_R :: f32(18)
MAP_X :: f32(12) // pixel offset of the map
MAP_Y :: f32(14)
PANEL_X :: f32(672)

// The portrait layout (phones held upright; the page picks whichever layout
// shows the map larger, see `fit` in web/index.html): the map on top, and the
// panel below it drawn PORTRAIT_PANEL_SCALE times larger, with a shorter log.
// Panel code always draws in landscape panel coordinates (x from PANEL_X);
// `panel_scale` / `panel_dx` / `panel_dy` place it on the canvas.
PORTRAIT_W :: 672
MAP_H :: f32(CANVAS_H) // the map's height on the canvas in both layouts
PORTRAIT_PANEL_SCALE :: f32(1.5)
PORTRAIT_LOG_LINES :: 6
PORTRAIT_PANEL_H :: f32(384 + PORTRAIT_LOG_LINES * 14 + 30) // in panel coordinates
PORTRAIT_UI_SCALE :: f32(1.6) // menus, at most (a wide menu is scaled to fit)
portrait := false
canvas_w := f32(CANVAS_W)
canvas_h := f32(CANVAS_H)
panel_scale := f32(1)
panel_dx := f32(0)
panel_dy := f32(0)

PORTRAIT_H :: MAP_H + PORTRAIT_PANEL_H * PORTRAIT_PANEL_SCALE // 1327

@(export)
portrait_canvas_height :: proc "c" () -> i32 {
	return i32(PORTRAIT_H)
}

// Called by the page whenever it picks a layout (and resizes the canvas).
@(export)
set_portrait :: proc "c" (on: b32) {
	portrait = bool(on)
	if portrait {
		canvas_w, canvas_h = PORTRAIT_W, PORTRAIT_H
		panel_scale = PORTRAIT_PANEL_SCALE
		panel_dx = 12 - PANEL_X * panel_scale
		panel_dy = MAP_H
	} else {
		canvas_w, canvas_h = CANVAS_W, CANVAS_H
		panel_scale, panel_dx, panel_dy = 1, 0, 0
	}
}

// A canvas point in panel coordinates (where the panel's buttons are).
to_panel :: proc(x, y: f32) -> (f32, f32) {
	return (x - panel_dx) / panel_scale, (y - panel_dy) / panel_scale
}

// Is a canvas point over the map (not the panel)?
on_map :: proc(x, y: f32) -> bool {
	return y < MAP_H - 4 if portrait else x < PANEL_X - 4
}

panel_height :: proc() -> f32 {
	return PORTRAIT_PANEL_H if portrait else CANVAS_H
}
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
FORTIFIED_RING :: Color{0.92, 0.86, 0.7}
MENU_BUTTON :: Button{PANEL_X + 292, 12, 84, 24} // for the mouse; Esc, B or Start do the same
END_TURN_BUTTON :: Button{PANEL_X, 282, 120, 30} // only while you must end turns yourself (Options)
AUTO_END_DELAY :: 0.5 // seconds to see your last action before the turn ends by itself
BACKDROP_SCENARIO :: 1 // the computer battle behind the title screen
CUSTOM_SCENARIO :: -1 // `scenario` for a custom battle (set up from `custom`)

// With a Wololo selected, chant mode aims a blessing or a curse at the hex
// under the cursor and the six round it (C, or the unit menu). Outside it, OK
// on an enemy in range curses round that enemy.
Chant_Mode :: enum {
	Off,
	Bless,
	Curse,
}
chant_mode := Chant_Mode.Off

ctx: runtime.Context
g: game.Game
scenario := 0
selected := -1
cursor := game.Hex{10, 10}
cursor_pref_x: f32 // where up and down aim across the staggered rows
cursor_on := false // drawn once the player has moved it (or a unit was selected)
ai_timer: f64
auto_end_timer: f64
game_over_shown := false
backdrop_timer: f64
// computer-vs-computer only: whose fog the map shows (View in the pause menu, or V)
View_Mode :: enum {
	Everything,
	Red,
	Blue,
}
view_mode := View_Mode.Everything

main :: proc() {
	ctx = context
	js.add_window_event_listener(.Key_Down, nil, on_key)
	load_options()
	load_custom()
	go_title()
}

start_game :: proc(n: int) {
	scenario = n
	seed := u64(time.now()._nsec)
	if n == CUSTOM_SCENARIO { game.new_custom_game(&g, &custom, seed) } else { game.new_game(&g, n, seed) }
	selected = -1
	chant_mode = .Off
	cursor_on = false
	put_cursor({game.COLS / 2, game.ROWS / 2})
	ai_timer = 0
	auto_end_timer = 0
	backdrop_timer = 0
	game_over_shown = false
	anim_skip()
	last_winner = -1
	last_turn_owner = -1
}

// for the turn and game-over sounds
last_winner := -1
last_turn_owner := -1

// The page calls this for a ?scenario=N address (1-based): straight into it.
@(export)
load_scenario :: proc "c" (n: i32) {
	context = ctx
	idx := int(n) - 1
	if idx >= 0 && idx < len(game.SCENARIOS) {
		menu_depth = 0
		start_game(idx)
	}
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

// QA hook for screenshots (?watch=1): the computer plays every side.
@(export)
debug_watch :: proc "c" () {
	context = ctx
	for i in 0 ..< g.faction_count { g.factions[i].controller = .Computer }
	selected = -1
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

// Selects the next of the player's units whose move is not over, after the
// selected one (wrapping round), or nothing if all have ended; the cursor
// follows it.
select_next_unit :: proc() {
	n := g.unit_count
	for k in 1 ..= n {
		i := ((selected + k) % n + n) % n
		u := &g.units[i]
		if u.alive && u.faction == g.current && !game.unit_finished(&g, i) {
			selected = i
			put_cursor(u.pos)
			cursor_on = true
			return
		}
	}
	selected = -1
}

selected_chants :: proc() -> bool {
	return selected >= 0 && game.unit_type(&g.units[selected]).chants && human_turn()
}

fortify_selected :: proc() {
	if selected < 0 || !human_turn() { return }
	if game.fortify(&g, selected) { select_next_unit() }
}

finish_selected_move :: proc() {
	if selected < 0 || !human_turn() { return }
	if game.finish_move(&g, selected) { select_next_unit() }
}

// Refused by the rules while any of the player's units has not ended its move.
end_human_turn :: proc() {
	if game.end_turn(&g) {
		selected = -1
		chant_mode = .Off
		ai_timer = 0
	}
}

show_end_turn_button :: proc() -> bool {
	return !auto_end && human_turn()
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

	sdt := dt * 2 if fast else dt // Options: computer speed
	anim_update(sdt)
	// the computer plays while no menu is open (the title screen's battle
	// plays on behind it)
	if game.is_computer_turn(&g) && !anim_busy() && (!menu_open() || on_title()) {
		ai_timer += sdt
		if ai_timer >= AI_DELAY {
			ai_timer = 0
			game.ai_step(&g)
			anim_update(0) // start its animation this frame
		}
	}
	// the turn ends by itself once none of your units can do anything more
	if auto_end && human_turn() && !menu_open() && !anim_busy() && game.units_left_to_act(&g) == 0 {
		auto_end_timer += dt
		if auto_end_timer >= AUTO_END_DELAY { end_human_turn() }
	} else {
		auto_end_timer = 0
	}
	if g.winner >= 0 && !anim_busy() {
		if on_title() {
			// the backdrop battle starts over after a moment
			backdrop_timer += dt
			if backdrop_timer > 2 {
				game.new_game(&g, BACKDROP_SCENARIO, u64(time.now()._nsec))
				anim_skip()
				backdrop_timer = 0
			}
		} else if !game_over_shown {
			game_over_shown = true
			push_menu(.Game_Over)
		}
	}
	if !on_title() { turn_sounds() }
	if selected >= 0 && !g.units[selected].alive { selected = -1 }

	clear_canvas(0.1, 0.1, 0.13)
	draw_map()
	if !on_title() { draw_panel() }
	draw_menus()
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
		// your turn: the first unit able to act is selected, the cursor on it
		selected = -1
		select_next_unit()
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
		if u.boon != .None {
			// blessed (+) or cursed (-): a small badge at the upper left
			bc := BLESS_COLOR if u.boon == .Blessed else CURSE_COLOR
			draw_circle(p.x - HEX_R * 0.55, p.y - HEX_R * 0.5, 5, bc.r, bc.g, bc.b, 0.1, 0.1, 0.1, 1)
			text("+" if u.boon == .Blessed else "-", p.x - HEX_R * 0.55, p.y - HEX_R * 0.5 + 1, 10, Color{0.1, 0.1, 0.1}, 1)
		}
		if most := game.unit_type(u).body; most > 1 {
			// body points: a pip each along the bottom of the counter, dark once lost
			for b in 0 ..< most {
				px := p.x + (f32(b) - f32(most - 1) / 2) * 5
				lit := b < u.body
				draw_circle(px, p.y + HEX_R * 0.6, 2.2, 1 if lit else 0.25, 1 if lit else 0.2, 1 if lit else 0.2, 0.1, 0.1, 0.1, 1)
			}
		}
		if !finished && game.unit_has_moved(&g, i) {
			// moved but can still act: a small pip at the upper right
			draw_circle(p.x + HEX_R * 0.5, p.y - HEX_R * 0.5, 3.5, 1, 1, 1, 0.1, 0.1, 0.1, 1)
		}
		if selected >= 0 && !anim_busy() && game.can_attack(&g, selected, i) {
			draw_hex(p.x, p.y, HEX_R - 1, 0, 0, 0, 0, 1, 0.15, 0.1, 1, 3)
		}
		if selected_chants() && chant_mode == .Off && !anim_busy() && u.faction != g.current && game.can_chant(&g, selected, i) {
			// enemies the Wololo can curse round (purple)
			draw_hex(p.x, p.y, HEX_R - 1, 0, 0, 0, 0, CURSE_COLOR.r, CURSE_COLOR.g, CURSE_COLOR.b, 1, 3)
		}
	}
	draw_chant_area()
	draw_anim_effects()
	if selected >= 0 && !anim_busy() {
		p := hex_centre(g.units[selected].pos)
		draw_hex(p.x, p.y, HEX_R - 1, 0, 0, 0, 0, 1, 1, 1, 1, 3)
	}
	if cursor_on && !menu_open() {
		p := hex_centre(cursor)
		draw_hex(p.x, p.y, HEX_R - 1, 0, 0, 0, 0, GOLD.r, GOLD.g, GOLD.b, 0.95, 2.5)
	}
}

// In chant mode, the hexes a chant on the cursor would cover: tinted when it
// can go there, a faint outline when it cannot.
draw_chant_area :: proc() {
	if chant_mode == .Off || !selected_chants() || anim_busy() || menu_open() { return }
	bless := chant_mode == .Bless
	ok := game.can_chant_at(&g, selected, cursor, bless)
	col := BLESS_COLOR if bless else CURSE_COLOR
	nbs, n := game.neighbours(cursor)
	area: [7]game.Hex
	area[0] = cursor
	copy(area[1:], nbs[:n])
	for h in area[:n + 1] {
		p := hex_centre(h)
		if ok {
			draw_hex(p.x, p.y, HEX_R - 1, col.r, col.g, col.b, 0.28, col.r, col.g, col.b, 0.9, 2)
		} else {
			draw_hex(p.x, p.y, HEX_R - 1, 0, 0, 0, 0, col.r, col.g, col.b, 0.35, 1.5)
		}
	}
	for i in 0 ..< g.unit_count {
		if ok && game.chant_hits(&g, selected, cursor, bless, i) {
			p := hex_centre(g.units[i].pos)
			draw_hex(p.x, p.y, HEX_R - 1, 0, 0, 0, 0, col.r, col.g, col.b, 1, 3)
		}
	}
}

draw_panel :: proc() {
	set_transform(panel_scale, panel_dx, panel_dy)
	defer set_transform(1, 0, 0)
	x := PANEL_X
	text("Skirmishers of SPLORR!!", x, 24, 20, GOLD)
	if !on_title() { button(MENU_BUTTON, "Menu (Esc)", !menu_open()) }
	text(g.name, x, 50, 13, GREY)

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
	text(status, x, 76, 16, f.color if g.winner < 0 else g.factions[g.winner].color)
	if !has_human() {
		names := [View_Mode]string{.Everything = "everything", .Red = "Red's side", .Blue = "Blue's side"}
		text(fmt.tprintf("Showing %s (View in the menu)", names[view_mode]), x, 96, 12, GREY)
	}

	// the selected unit, or else the one under the cursor
	view := viewer()
	shown := selected
	if shown < 0 {
		if hu := game.unit_at(&g, cursor); hu >= 0 && cursor_on && game.unit_visible(&g, hu, view) { shown = hu }
	}
	y := f32(116)
	if shown >= 0 {
		draw_unit_card(shown, x, y)
	} else if human_turn() {
		text("Choose one of your units (OK on it).", x, y, 13, GREY)
	}
	draw_hex_info(x, 240, view)

	if show_end_turn_button() {
		left := game.units_left_to_act(&g)
		button(END_TURN_BUTTON, "End turn (E)", left == 0 && !anim_busy())
		if left > 0 { text(fmt.tprintf("%d unit%s still to act", left, "" if left == 1 else "s"), x + 130, 297, 12, GREY) }
	} else if human_turn() {
		left := game.units_left_to_act(&g)
		msg := "the turn ends by itself" if left == 0 else fmt.tprintf("%d unit%s still to act", left, "" if left == 1 else "s")
		text(msg, x, 297, 12, GREY)
	}

	for i in 0 ..< g.faction_count {
		fc := &g.factions[i]
		who := "you" if fc.controller == .Human else "computer"
		text(fmt.tprintf("%s (%s): %d units, %d points", fc.name, who, game.living_units(&g, i), game.army_points(&g, i)), x, 324 + f32(i) * 18, 13, fc.color)
	}

	text("Log", x, 366, 14, GOLD)
	for i in 0 ..< (min(g.log_count, PORTRAIT_LOG_LINES) if portrait else g.log_count) {
		shade := 1 - f32(i) * 0.06
		text(game.log_line(&g, i), x, 384 + f32(i) * 14, 11, WHITE * shade)
	}
	text(control_hint(), x, panel_height() - 12, 11, Color{0.75, 0.75, 0.55})
}

// What OK and Cancel do right now, at the foot of the panel.
control_hint :: proc() -> string {
	switch {
	case menu_open():
		return "Tap to choose" if touched else "Up/Down choose   OK pick   Cancel back"
	case !human_turn():
		return "Cancel: menu"
	case touched && chant_mode == .Bless:
		return "Tap a hex to aim, again to bless round it"
	case touched && chant_mode == .Curse:
		return "Tap a hex to aim, again to curse round it"
	case touched && selected >= 0:
		return "Tap a hex to look, again to move or attack there"
	case touched:
		return "Tap your unit to select it; tap a hex to look"
	case chant_mode == .Bless:
		return "OK: bless friends on and round the cursor   Cancel: stop"
	case chant_mode == .Curse:
		return "OK: curse foes on and round the cursor   Cancel: stop"
	case selected >= 0:
		return "OK: move/attack   OK on it: more   Cancel: drop"
	}
	return "Arrows/D-pad: cursor   OK: choose unit   Cancel: menu"
}

draw_unit_card :: proc(i: int, x, y: f32) {
	u := &g.units[i]
	ut := game.unit_type(u)
	text(fmt.tprintf("%s %s (%d points)", g.factions[u.faction].name, ut.name, ut.points), x, y, 15, g.factions[u.faction].color)
	armour := "" if ut.armour == .None else fmt.tprintf(" (%s)", game.ARMOURS[ut.armour].name)
	text(fmt.tprintf("Body %d/%d   Move %s/%d   Sight %d", u.body, ut.body, points_text(u.moves_left), ut.move, ut.vision), x, y + 18, 13, GREY)
	text(fmt.tprintf("Defence %s%s", dice_text(game.unit_defence(ut)), armour), x, y + 34, 13, GREY)
	wy := y + 50
	for w in ut.weapons {
		wp := &game.WEAPONS[w]
		reach := fmt.tprintf("range %d", wp.max_range) if wp.min_range == wp.max_range else fmt.tprintf("range %d-%d", wp.min_range, wp.max_range)
		note := ", pierces armour" if wp.pierce else (", strikes first" if wp.first_strike else "")
		text(fmt.tprintf("%s: %s, %s%s", wp.name, dice_text(wp.attack), reach, note), x, wy, 13, GREY)
		wy += 16
	}
	if ut.chants {
		text(fmt.tprintf("chant: bless or curse a hex and round it, range %d", game.CHANT_RANGE), x, wy, 13, GREY)
		wy += 16
	}
	if i != selected || u.faction != g.current { return }
	state := "may chant" if ut.chants else "may attack"
	if ut.chants && chant_mode == .Bless { state = "chant mode: bless (C switches to curse)" }
	if ut.chants && chant_mode == .Curse { state = "chant mode: curse (C stops)" }
	if u.boon != .None { state = fmt.tprintf("%s; %s", state, "blessed" if u.boon == .Blessed else "cursed") }
	if u.fortified {
		state = "fortified: defends with advantage"
	} else if u.attacked {
		state = "acted: done for this turn"
	} else if u.done {
		state = "move finished"
	} else if game.unit_finished(&g, i) {
		state = "no moves left and nobody in range"
	}
	text(state, x, wy, 13, GOLD)
}

// The hex under the cursor: its terrain, and who is on it or was last seen there.
draw_hex_info :: proc(x, y: f32, view: int) {
	if !cursor_on { return }
	h := cursor
	if !game.hex_seen(&g, view, h) {
		text(fmt.tprintf("Hex %d,%d: unexplored", h.x, h.y), x, y, 13, GREY)
		return
	}
	t := game.terrain_at(&g, h)
	cost := fmt.tprintf("move cost %d", game.TERRAIN_MOVE_COST[t])
	if t == .Road { cost = fmt.tprintf("%s, %s from road", cost, points_text(game.step_cost(.Road, .Road, false, false))) }
	text(fmt.tprintf("Hex %d,%d: %s%s (%s)", h.x, h.y, game.is_high(&g, h) ? "high " : "", game.TERRAIN_NAMES[t], cost), x, y, 13, GREY)
	if hu := game.unit_at(&g, h); hu >= 0 && game.unit_visible(&g, hu, view) {
		u := &g.units[hu]
		label := fmt.tprintf("%s %s, body %d%s", g.factions[u.faction].name, game.unit_type(u).name, u.body, ", fortified" if u.fortified else "")
		if u.boon != .None { label = fmt.tprintf("%s, %s", label, "blessed" if u.boon == .Blessed else "cursed") }
		if .Pike in game.unit_type(u).weapons && u.faction != g.current {
			label = fmt.tprintf("%s, %s", label, "has struck first" if u.reacted else "ready to strike first")
		}
		// explain a shot the selected unit cannot take because something is in the way
		if selected >= 0 && u.faction != g.units[selected].faction {
			d := game.hex_distance(g.units[selected].pos, u.pos)
			_, in_range := game.weapon_in_range(&g, game.unit_type(&g.units[selected]), g.units[selected].pos, u.pos)
			if game.needs_line_of_sight(d) && in_range && !game.line_of_sight(&g, g.units[selected].pos, u.pos, g.units[selected].faction) {
				label = fmt.tprintf("%s: shot blocked", label)
			}
		}
		text(label, x, y + 18, 13, g.factions[u.faction].color)
	} else if view != game.NO_FACTION {
		for i in 0 ..< g.unit_count {
			if pos, ok := game.sighting(&g, view, i); ok && pos == h {
				fc := &g.factions[g.units[i].faction]
				text(fmt.tprintf("%s %s last seen here", fc.name, game.unit_type(&g.units[i]).name), x, y + 18, 13, fc.color)
				break
			}
		}
		if !game.hex_in_view(&g, view, h) { text("out of sight", x + 260, y + 18, 11, GREY) }
	}
}
