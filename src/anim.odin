#+build js
package main

// Animation of what the rules report (game.Event): moving units slide hex by
// hex, attacks lunge (dagger) or throw a stone (sling) and flash the target.
// Events are shown one at a time; the computer waits for the queue to empty
// before its next action, and the player's clicks wait too. Under fog only
// what the viewing side could see is shown: a move is drawn only on hexes it
// watches, and an attack it sees no end of is skipped.

import "core:math"
import "game"

STEP_TIME :: 0.09 // seconds per hex walked
STRIKE_TIME :: 0.18 // lunge or stone in flight
FLASH_TIME :: 0.32 // target flashes; a slain unit fades
CHANT_TIME :: 0.45

Anim :: struct {
	active: bool,
	ev:     game.Event,
	t, dur: f64,
	struck: bool, // the hit or block sound has played
}

anim: Anim
events_shown: int

// Forgets everything not yet shown (new game, or the QA fast-forward).
anim_skip :: proc() {
	anim = {}
	events_shown = g.event_count
}

anim_busy :: proc() -> bool {
	return anim.active || events_shown < g.event_count
}

// Can the viewing side see something happen on this hex?
anim_sees :: proc(view: int, h: game.Hex) -> bool {
	return game.hex_watched(&g, view, h)
}

anim_duration :: proc(ev: ^game.Event, view: int) -> f64 {
	own := view == game.NO_FACTION || g.units[ev.unit].faction == view
	switch ev.kind {
	case .Move:
		if own { return STEP_TIME * f64(ev.steps) }
		seen := anim_sees(view, ev.from)
		for h in ev.path[:ev.steps] { seen = seen || anim_sees(view, h) }
		return STEP_TIME * f64(ev.steps) if seen else 0
	case .Attack:
		if own || g.units[ev.target].faction == view || anim_sees(view, ev.from) || anim_sees(view, ev.target_pos) {
			return STRIKE_TIME + FLASH_TIME
		}
	case .Fortify:
		if own || anim_sees(view, ev.from) { return 0.2 }
	case .Demolish:
		if own || anim_sees(view, ev.from) || anim_sees(view, ev.target_pos) { return STRIKE_TIME + FLASH_TIME }
	case .Chant:
		if own || anim_sees(view, ev.from) || anim_sees(view, ev.target_pos) { return CHANT_TIME }
		for i in 0 ..< g.unit_count {
			// the side being chanted on sees its own units glow
			if g.units[i].faction == view && game.hex_distance(g.units[i].pos, ev.target_pos) <= game.CHANT_RADIUS { return CHANT_TIME }
		}
	}
	return 0
}

// Advances the animation by dt and starts the next event when one ends.
anim_update :: proc(dt: f64) {
	if anim.active {
		anim.t += dt
		if anim.ev.kind == .Attack && !anim.struck && anim.t >= STRIKE_TIME {
			anim.struck = true
			r := &anim.ev.result
			play(.Slain if r.killed else (.Hit if r.damage > 0 else .Block))
		}
		if anim.t < anim.dur { return }
		anim.active = false
	}
	view := viewer()
	for !anim.active && events_shown < g.event_count {
		if g.event_count - events_shown > game.EVENT_RING { events_shown = g.event_count - game.EVENT_RING }
		ev := g.events[events_shown % game.EVENT_RING]
		events_shown += 1
		dur := anim_duration(&ev, view)
		if dur <= 0 { continue }
		anim = {active = true, ev = ev, dur = dur}
		// a zoomed-in view scrolls to show what happens
		if ev.kind == .Move && ev.steps > 0 { follow_hex(ev.path[ev.steps - 1]) } else { follow_hex(ev.target_pos if ev.kind != .Fortify else ev.from) }
		switch ev.kind {
		case .Move:    play(.Step)
		case .Attack:  play(WEAPON_SOUNDS[ev.result.weapon])
		case .Fortify: play(.Fortify)
		case .Chant:   play(.Chant)
		case .Demolish: play(.Stab)
		}
	}
}

lerp2 :: proc(a, b: [2]f32, t: f32) -> [2]f32 {
	return a + (b - a) * t
}

// Where to draw unit i now, how opaque, and whether to draw it at all;
// `moved` says the animation decides (otherwise draw it where it stands).
anim_unit :: proc(i: int, view: int) -> (pos: [2]f32, alpha: f32, show, moved: bool) {
	alpha = 1
	// a unit slain by an attack not shown yet stays on the map until then
	if !g.units[i].alive {
		for k in events_shown ..< g.event_count {
			ev := &g.events[k % game.EVENT_RING]
			if ev.kind == .Attack && ev.target == i && ev.result.killed {
				return hex_centre(ev.target_pos), 1, true, true
			}
		}
	}
	if !anim.active { return }
	ev := &anim.ev
	t := f32(anim.t)
	switch ev.kind {
	case .Move:
		if ev.unit != i { return }
		moved = true
		s := t / STEP_TIME
		k := min(int(s), ev.steps - 1)
		a := ev.from if k == 0 else ev.path[k - 1]
		b := ev.path[k]
		f := min(s - f32(k), 1)
		pos = lerp2(hex_centre(a), hex_centre(b), f)
		near := a if f < 0.5 else b
		own := view == game.NO_FACTION || g.units[i].faction == view
		show = own || anim_sees(view, near)
	case .Attack:
		if ev.unit == i && game.WEAPONS[ev.result.weapon].max_range == 1 && t < STRIKE_TIME {
			// lunge a third of the way and back
			lunge := math.sin(t / STRIKE_TIME * math.PI) * 0.35
			return lerp2(hex_centre(ev.from), hex_centre(ev.target_pos), lunge), 1, true, true
		}
		if ev.target == i && ev.result.killed {
			fade := 1 - max(0, t - STRIKE_TIME) / FLASH_TIME
			return hex_centre(ev.target_pos), fade, fade > 0, true
		}
	case .Demolish:
		if ev.unit == i && t < STRIKE_TIME {
			// the sapper swings at the wall
			lunge := math.sin(t / STRIKE_TIME * math.PI) * 0.35
			return lerp2(hex_centre(ev.from), hex_centre(ev.target_pos), lunge), 1, true, true
		}
	case .Fortify, .Chant:
	}
	return
}

// Effects over the units: the sling stone, the flash on the target and a word
// saying what happened.
draw_anim_effects :: proc() {
	if anim.active && anim.ev.kind == .Chant {
		// the area glows and a ring widens over it, gold for a blessing,
		// purple for a curse
		ev := &anim.ev
		f := f32(anim.t / CHANT_TIME)
		col := BLESS_COLOR if ev.bless else CURSE_COLOR
		b := hex_centre(ev.target_pos)
		set_alpha(1 - f)
		nbs, n := game.neighbours(ev.target_pos)
		draw_hex(b.x, b.y, HEX_R - 1, col.r, col.g, col.b, 0.35, col.r, col.g, col.b, 1, 2)
		for h in nbs[:n] {
			p := hex_centre(h)
			draw_hex(p.x, p.y, HEX_R - 1, col.r, col.g, col.b, 0.35, col.r, col.g, col.b, 1, 2)
		}
		draw_hex(b.x, b.y, HEX_R * (1.2 + f * 1.4), 0, 0, 0, 0, col.r, col.g, col.b, 1, 3)
		text("blessed!" if ev.bless else "cursed!", b.x, b.y - HEX_R * 2 - 4 - f * 8, 13, col, 1)
		set_alpha(1)
		return
	}
	if anim.active && anim.ev.kind == .Demolish && anim.t >= STRIKE_TIME {
		// a puff of dust over the wall
		ev := &anim.ev
		f := f32((anim.t - STRIKE_TIME) / FLASH_TIME)
		b := hex_centre(ev.target_pos)
		set_alpha(1 - f)
		for k in 0 ..< 6 {
			a := f32(k) * math.PI / 3 + 0.4
			r := HEX_R * (0.3 + f * 0.8)
			draw_circle(b.x + math.cos(a) * r, b.y + math.sin(a) * r * 0.7, 3 + f * 4, 0.7, 0.62, 0.5, 0, 0, 0, 0)
		}
		text("rubble!" if ev.rubble else "cracked", b.x, b.y - HEX_R - 4 - f * 8, 13, Color{0.95, 0.85, 0.6}, 1)
		set_alpha(1)
		return
	}
	if !anim.active || anim.ev.kind != .Attack { return }
	ev := &anim.ev
	t := f32(anim.t)
	a := hex_centre(ev.from)
	b := hex_centre(ev.target_pos)
	if t < STRIKE_TIME {
		f := t / STRIKE_TIME
		#partial switch ev.result.weapon {
		case .Sling:
			// a stone lobbed in an arc
			p := lerp2(a, b, f)
			draw_circle(p.x, p.y - math.sin(f * math.PI) * 10, 3, 0.85, 0.8, 0.7, 0.2, 0.2, 0.2, 1)
		case .Bow, .Crossbow:
			// an arrow or bolt in a straight line (the bow's a little higher)
			lift := math.sin(f * math.PI) * (6 if ev.result.weapon == .Bow else 2)
			tail := lerp2(a, b, max(0, f - 0.12))
			head := lerp2(a, b, f)
			draw_line(tail.x, tail.y - lift, head.x, head.y - lift, 0.95, 0.92, 0.85, 2)
		}
		return
	}
	f := (t - STRIKE_TIME) / FLASH_TIME
	r := &ev.result
	col := Color{1, 0.2, 0.1} if r.damage > 0 else Color{0.95, 0.95, 1}
	set_alpha(1 - f)
	draw_hex(b.x, b.y, HEX_R - 1, col.r, col.g, col.b, 0.35, col.r, col.g, col.b, 1, 3)
	word := "slain!" if r.killed else ("hit" if r.damage > 0 else ("blocked" if r.hits > 0 else "miss"))
	text(word, b.x, b.y - HEX_R - 4 - f * 8, 13, col, 1)
	set_alpha(1)
}
