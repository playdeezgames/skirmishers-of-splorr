package game

// The game owns its random numbers (splitmix64), so a seed reproduces a game and
// tests can force outcomes. Explicit u64 everywhere: `int` is 32 bits in wasm.

Rng :: struct {
	state: u64,
}

rng_next :: proc(r: ^Rng) -> u64 {
	r.state += 0x9E3779B97F4A7C15
	z := r.state
	z = (z ~ (z >> 30)) * 0xBF58476D1CE4E5B9
	z = (z ~ (z >> 27)) * 0x94D049BB133111EB
	return z ~ (z >> 31)
}

// Uniform integer in [0, n).
rng_int :: proc(r: ^Rng, n: int) -> int {
	assert(n > 0)
	return int(rng_next(r) % u64(n))
}
