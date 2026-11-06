# Skirmishers of SPLORR!!

A hex-and-counter wargame in the browser. You command a band of kobolds against a computer army on a 20 by 20 hex map of grass, forest and road. Combat uses HeroQuest-style attack and defence dice.

**Play: https://playdeezgames.github.io/skirmishers-of-splorr/**

Made by an AI agent (Claude Code) at the direction of TheGrumpyGameDev: the code, the rules text, the screenshots and this README. See [DESIGN.md](DESIGN.md) for the designer's decisions, including what is planned but not built yet (elevation, fog of war).

## Rules

- **Dice.** Attackers roll their weapon's attack dice and defenders roll their defence dice. A white die scores on 1 in 3, a red die on 1 in 2, and a black die on 2 in 3. Each block cancels one hit, and each hit left over costs a body point. Kobolds have 1 body point.
- **Units.** A Kobold (`K`) carries a dagger (1 white die, range 1). A Kobold Slinger (`S`) carries a sling (1 white die, range 2 to 3) and a dagger, and uses whichever reaches the target. Both defend with 1 white die and move 4. A kobold is worth 10 points and a slinger 12.
- **Terrain.** Entering grass costs 1 movement point, forest 2 and road 1. A step from road to road costs 1/2. Forest or an enemy unit between a slinger and its target blocks the shot; your own units do not.
- **High ground.** Pale hexes with a dark rim are high ground. Climbing onto it costs 1 extra movement point (1/2 along a road). In melee the higher unit rolls with advantage, attacking or defending. A slinger on high ground reaches 4 hexes onto low ground. Hills block shots between two low hexes, and from high ground you can shoot over low forest and enemies.
- **Turns.** Each unit may move, then attack once. Attacking ends its move. A unit can also **Finish move** to stop early, or **Fortify** instead of moving: until your next turn, each failed defence die is rolled once more. The turn ends only when every unit has finished.
- **Winning.** Eliminate the other side.

## Controls

- **Click** one of your units to select it. Yellow hexes show where it can move and a red outline marks an enemy it can attack. Click a yellow hex to move there, or a red-outlined enemy to attack it.
- **D** fortify, **F** finish move, **Space** end turn, **Esc** deselect, **N** new game, **[ ]** change scenario. There are buttons for all of these too.
- Hover over a hex to see its terrain, movement cost and any unit on it.

## Scenarios

Kobold Skirmish (four against four, two slingers each) on a lightly wooded map, on maps that are 25, 50 or 75 percent forest, and on maps with some hills or hilly ones. Two computer-against-computer battles: four against four, and twenty against twenty (15 kobolds and 5 slingers a side).

## Build

Odin (`dev-2026-07` or newer). Python 3 with Pillow and Google Chrome are only needed for the screenshots.

```bash
./test.sh                      # rules tests, native
./build.sh                     # build/web (serve with: python3 -m http.server -d build/web 8123)
tools/sim.sh 2k2s 4k -n 1000   # balance simulator: computer against computer
tools/pages.sh                 # size build copied into docs/ for GitHub Pages
tools/shots.sh                 # assets/screenshots/ and assets/cover.png from the real build
tools/ship.sh                  # itch.io zip; pushes only with --push
```

## Credits

Cover title set in DejaVu Sans Mono (Bitstream Vera licence). No other third-party assets.

More games: https://playdeezgames.github.io/oeuvre-of-splorr/ · https://thegrumpygamedev.itch.io/
