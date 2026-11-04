# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What the game is

A single-player hex-and-counter wargame in the browser. Each scenario sets up the factions and says whether each one is human- or computer-controlled.

- **Combat is HeroQuest-style dice**: the attacker rolls its attack dice and the target rolls its defence dice. Each die scores with a chance set by its colour: white 1/3, red 1/2, black 2/3. Each block cancels one hit, every hit left costs one body point, and a unit at 0 body points dies.
- **Units** have attack dice, defence dice, body points, movement points and a min/max attack range in hexes. Range 1–1 means melee only. Each unit can move (spending points over several moves) and attack once per turn, in either order.
- **Terrain sets the movement cost**: grass costs 1, forest 2. Units can pass through friendly units but not enemies, and cannot stop on an occupied hex.
- **Map**: 20×20 staggered ("odd-r") grid of pointy-topped hexes, where odd rows are shifted half a hex to the right.
- **Not built yet:** ranged unit types, elevation, and fog of war. When fog of war is added, the AI must only see what its own side can see, not the hidden state.

## Commands

```bash
./build.sh                      # odin -> build/web/game.wasm (+ index.html, odin.js); OPT=size for shipping
./test.sh                       # native tests of src/game
./test.sh -define:ODIN_TEST_NAMES=game.test_dice_odds   # one test
python3 -m http.server -d build/web 8123                # serve (wasm needs http, not file://)
```

`.claude/launch.json` defines the `skirmishers` preview server on port 8123. `?scenario=2` loads the computer-vs-computer scenario, which is useful for watching the AI and combat. Both scripts run with `-vet -strict-style`.

## Architecture

- `src/game/`: package `game`, all of the rules, with **no browser imports**, so it builds and tests natively.
  - `hex.odin`: offset↔cube conversion, neighbours (different offsets for even and odd rows), distance, and hex↔pixel conversion.
  - `rules.odin`: terrain and dice tables, `UNIT_TYPES` (indexed by `Unit_Kind`), the `Game` struct (fixed-size arrays and a ring-buffer log, no allocation), Dijkstra `movement_costs`, `move_unit`, `attack`, `end_turn`, and win checks. `move_unit` and `attack` refuse units that are not on the current faction's side.
  - `scenario.odin`: the `SCENARIOS` table (name + setup proc). `new_game(g, scenario, seed)` resets everything. Forest is grown in clumps from random seed hexes, and deployment hexes are forced to grass.
  - `ai.odin`: `ai_step` plays one computer unit per call (or ends the turn), so the page can show each action. `ai_take_turn` runs a whole turn, for tests.
  - `game_test.odin`: has `#+build !js`, which is required because Odin otherwise compiles `_test` files into the wasm build and fails on `core:os`.
- **Randomness belongs to the game** (`Rng`, splitmix64 in `g.rng`) and is seeded by `new_game`. Use explicit `u64` because `int` is 32 bits on `js_wasm32`. Tests pick seeds to force outcomes.
- `src/main.odin` (`#+build js`): the web layer. It owns the UI state (selection, hover, AI timer), calls `ai_step` every `AI_DELAY` seconds on computer turns, and draws everything each frame. Drawing goes through a few `foreign import canvas` procs in canvas pixels. Input arrives as `proc "c"` exports (`mouse_move`, `mouse_click`, `load_scenario`), plus a key listener.
- `web/index.html`: the 2D-canvas shim (hexes, circles, text via `memory.loadString`) and pointer → canvas-pixel mapping. If you add an import, add it to both the Odin `foreign` block and the `imports.canvas` object.

## House conventions (from the user's vault)

The user's knowledge vault is `/home/yermom/git/bok-of-splorr` (Obsidian, `splorr/`). `splorr/Tech/Odin wasm recipe.md` and `splorr/Gotchas.md` cover the toolchain and its traps: WebGL fails on the user's Chrome, so use only the 2D canvas; the browser pane caches the wasm and throttles frames while hidden. `splorr/Home.md` and `splorr/Tech/Release standard.md` hold the standing rules:

- Never `git push` or ship to itch.io (`shippit.sh --push`, `butler push`) unless the user says so. "Push" means `git push`; "ship" means itch.io.
- New games start on GitHub Pages; making the repo public or enabling Pages is the user's call.
- The page footer must keep the AI statement and the back links.
- When the game is added to the vault, create `splorr/Games/Skirmishers of SPLORR!!.md` and link it from `splorr/Home.md`.
