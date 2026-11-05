package game

import "core:math"

// The map is a staggered ("odd-r") grid of pointy-topped hexes: every odd row is
// shifted half a hex to the right. Hexes are stored by offset coordinates
// {col, row}; distance and pixel maths go through cube coordinates.

ROWS :: 20
COLS :: 20

Hex :: [2]int // {col, row}

Cube :: [3]int // {q, r, s}, q + r + s == 0

in_bounds :: proc(h: Hex) -> bool {
	return h.x >= 0 && h.x < COLS && h.y >= 0 && h.y < ROWS
}

to_cube :: proc(h: Hex) -> Cube {
	q := h.x - (h.y - (h.y & 1)) / 2
	r := h.y
	return {q, r, -q - r}
}

from_cube :: proc(c: Cube) -> Hex {
	col := c.x + (c.y - (c.y & 1)) / 2
	return {col, c.y}
}

hex_distance :: proc(a, b: Hex) -> int {
	d := to_cube(a) - to_cube(b)
	return max(abs(d.x), abs(d.y), abs(d.z))
}

// Neighbour offsets differ for even and odd rows.
EVEN_ROW_NEIGHBOURS := [6]Hex{{1, 0}, {0, -1}, {-1, -1}, {-1, 0}, {-1, 1}, {0, 1}}
ODD_ROW_NEIGHBOURS := [6]Hex{{1, 0}, {1, -1}, {0, -1}, {-1, 0}, {0, 1}, {1, 1}}

// Returns the in-bounds neighbours of h and how many there are.
neighbours :: proc(h: Hex) -> (out: [6]Hex, n: int) {
	offsets := &ODD_ROW_NEIGHBOURS if h.y & 1 == 1 else &EVEN_ROW_NEIGHBOURS
	for o in offsets {
		nb := h + o
		if in_bounds(nb) {
			out[n] = nb
			n += 1
		}
	}
	return
}

SQRT3 :: 1.7320508075688772

// Centre of a hex in pixels, for hexes of the given radius (centre to corner),
// with hex {0,0} centred at (radius*sqrt3/2, radius).
hex_to_pixel :: proc(h: Hex, radius: f32) -> [2]f32 {
	x := radius * SQRT3 * (f32(h.x) + 0.5 * f32(h.y & 1)) + radius * SQRT3 / 2
	y := radius * 1.5 * f32(h.y) + radius
	return {x, y}
}

// The hex under a pixel (same frame as hex_to_pixel); may be out of bounds.
pixel_to_hex :: proc(p: [2]f32, radius: f32) -> Hex {
	x := p.x - radius * SQRT3 / 2
	y := p.y - radius
	fq := (SQRT3 / 3 * x - y / 3) / radius
	fr := (2.0 / 3.0 * y) / radius
	fs := -fq - fr
	return from_cube(cube_round({f64(fq), f64(fr), f64(fs)}))
}

// Nearest cube hex to fractional cube coordinates.
cube_round :: proc(f: [3]f64) -> Cube {
	q := math.round(f.x)
	r := math.round(f.y)
	s := math.round(f.z)
	dq := abs(q - f.x)
	dr := abs(r - f.y)
	ds := abs(s - f.z)
	if dq > dr && dq > ds {
		q = -r - s
	} else if dr > ds {
		r = -q - s
	}
	return {int(q), int(r), -int(q) - int(r)}
}

MAX_LINE :: ROWS + COLS

// The hexes strictly between a and b on the straight line joining their
// centres. `nudge` shifts the line a hair to one side, which decides hexes the
// line only grazes along an edge: +1 and -1 give the two choices.
hexes_between :: proc(a, b: Hex, nudge: f64) -> (out: [MAX_LINE]Hex, n: int) {
	ca := to_cube(a)
	cb := to_cube(b)
	steps := hex_distance(a, b)
	EPS :: 1e-6
	e := [3]f64{EPS, 2 * EPS, -3 * EPS} * nudge
	fa := [3]f64{f64(ca.x), f64(ca.y), f64(ca.z)} + e
	fb := [3]f64{f64(cb.x), f64(cb.y), f64(cb.z)} + e
	for i in 1 ..< steps {
		t := f64(i) / f64(steps)
		out[n] = from_cube(cube_round(fa + (fb - fa) * t))
		n += 1
	}
	return
}
