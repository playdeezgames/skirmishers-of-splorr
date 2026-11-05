# Skirmishers of SPLORR!! — design decisions

The user's answers to the open questions, November 5, 2026. Items marked **built**
are in the game; the rest are decided but not built yet. `CLAUDE.md` describes
the code as it is.

## Line of sight

- Forest on a hex between shooter and target blocks the shot. **Built.**
- **Enemy units between shooter and target block the shot; friendly units do
  not.** **Built.**

## Weapons and units

- Weapon switching stays **free and automatic**: the distance picks the weapon
  (sling at 2–3, dagger at 1). **Built.**
- **Points cost per unit type: kobold 10, slinger 12.** **Built.** The user first
  set kobold = 2, but the simulator found a slinger worth about 1.2 kobolds (4
  slingers ≈ 4.6 kobolds, 8 ≈ 9.6), which no whole number fits at that scale; the
  user chose 10 and 12. Equal points then fight about even (5 slingers vs 6
  kobolds: slingers win 48%; 10 vs 12: 47%).
- The 20-vs-20 computer battle is **15 kobolds and 5 slingers** per side (210
  points each; red wins 53% over 300 games). **Built.**

## Elevation

- **Two levels per hex: low (0) and high (1)**, independent of terrain (a forest
  or road can be on high ground).
- **Movement:** stepping from low to high costs **+1**, or **+½ if both hexes
  are road** (so an uphill road-to-road step costs 1 in all). Going down or
  along costs nothing extra.
- **Melee:** the unit on higher ground has **advantage**, whether it attacks down
  or defends against an attack from below (a failed die is rolled once more).
- **Ranged:** a shooter on high ground shooting at a target on low ground has its
  **maximum range raised by 50%, rounded down** (sling 3 → 4). Minimum range is
  unchanged.
- **Advantage does not stack:** one re-roll per failed die however many sources
  (fortify, high ground).
- **Line of sight:** high ground between two low hexes blocks. A shooter or target
  on high ground sees over low-ground forest and enemies; forest or enemies on
  high ground still block.
- **Scenarios:** current scenarios stay flat. Add two skirmishes: **"some hills"
  (~15%)** and **"hilly" (~35%)**, grown as clumps.

## Fog of war

- **Vision per unit type**, using line of sight: kobold 5 hexes, slinger 7.
- A unit **in forest is only seen by enemies within 2 hexes** (still needing
  line of sight).
- **Terrain is explored:** hidden until one of your units has seen it, then it
  stays revealed. Enemies that go out of sight leave a **"last seen"** marker
  until that hex is seen again.
- **The computer only uses what its own units have seen.** With no enemy in
  sight it **scouts then advances**: one unit goes ahead to find the enemy while
  the rest follow, then it attacks.
- **Computer-vs-computer view:** everything by default, with a key to toggle
  Red's view, Blue's view and everything.
- **Fog is on in every scenario.** `tools/sim.sh` gets `-nofog` for comparing with
  earlier results.

## Interface and presentation

- **Touch:** tap a hex to inspect it (as hover does on desktop).
- **Animation:** units slide along their path and attacks flash, so the computer's
  turn can be followed.
- **Art and sound** made with the Anvil tools, as for other SPLORR!! games.

## Computer player

- Improve it **after elevation and fog** (they change what good play is), using
  the simulator: hold just out of enemy reach to win the first strike, prefer
  high ground and forest.

## Release standard

- **All of it now:** a README with the AI statement, plus `ITCH_DESCRIPTION.md`,
  `assets/cover.png` (630×500), `assets/screenshots/`, `devlog/YYYYMMDD/`,
  `tools/ship.sh` and the one-line `shippit.sh` wrapper. The cover and
  screenshots use the current plain look until art arrives. Nothing ships to
  itch.io without the user saying so.

## Suggested order

1. README and release-standard files. **Done November 5, 2026.**
2. Enemies block line of sight; 15k5s battle; points cost (simulator). **Done November 5, 2026.**
3. Elevation.
4. Fog of war.
5. Computer player improvements.
6. Move animation; Anvil art and sound.
7. Tap to inspect (check on a touch-size screen).
