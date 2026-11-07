# Skirmishers of SPLORR!!

A hex-and-counter wargame in the browser. You command a band of kobolds against a computer army on a 20 by 20 hex map of grass, forest and road. Combat uses HeroQuest-style attack and defence dice.

**Play: https://playdeezgames.github.io/skirmishers-of-splorr/**

Made by an AI agent (Claude Code) at the direction of TheGrumpyGameDev: the code, the rules text, the pixel art and sounds (made in the Anvil, the author's art and sound tool), the screenshots and this README. See [DESIGN.md](DESIGN.md) for the designer's decisions, including what is planned but not built yet (tap to inspect on touch screens).

## Rules

- **Dice.** Attackers roll their weapon's attack dice and defenders roll their defence dice. A white die scores on 1 in 3, a red die on 1 in 2, and a black die on 2 in 3. Each block cancels one hit, and each hit left over costs a body point. Kobolds have 1 body point.
- **Units.** A Kobold (`K`) carries a dagger (1 white die, range 1). A Kobold Slinger (`S`) carries a sling (1 white die, range 2 to 3) and a dagger, and uses whichever reaches the target. Both defend with 1 white die and move 4. A kobold is worth 10 points and a slinger 12. A **Heavy Kobold** chops with an axe (1 red die), wears chain (defends with 1 white and 1 red), has 2 body points and moves 3 (25 points). A **Kobold Champion** has a sword (1 white and 1 red), plate (1 white and 1 black) and 3 body points (55 points). A **Kobold Scout** fights like a kobold but moves 6 and sees 8 hexes (11 points). A **Kobold Archer** shoots a bow (1 white die, range 2 to 5; 14 points). A **Kobold Crossbow** wears leather and shoots a crossbow (1 white die, range 2 to 4) that **pierces armour**: the target rolls without its best defence die (16 points). A **Kobold Pike** wears leather and carries a pike (1 red die, range 1) that **strikes first**: when an enemy steps next to it, the pike attacks at once, before the enemy can (once each enemy turn; 20 points). Hover an enemy pike to see whether it is still ready. A **Kobold Wololo** has no weapon: instead of attacking it chants on a hex in sight within 3 hexes, and the chant lands on that hex and the six around it: it **blesses** every friend there (advantage on its next roll, a gold badge) or **curses** every enemy there you can see (disadvantage on its next roll: each die that scores is rolled again and counts only if it scores twice; a purple badge). The Wololo never blesses itself. Click an enemy to curse around it; press **C** once to aim a blessing or twice to aim a curse (or use the unit menu), and the area under the cursor lights up. An unused blessing or curse fades when the Wololo's side's next turn starts (20 points). Wounds stay: pips on a counter show the body points left.
- **Armour** adds defence dice: leather 1 white, chain 1 red, plate 1 black, on top of a kobold's own hide (1 white).
- **Terrain.** Entering grass costs 1 movement point, forest 2 and road 1. A step from road to road costs 1/2. Forest or an enemy unit between a slinger and its target blocks the shot; your own units do not.
- **High ground.** Pale hexes with a dark rim are high ground. Climbing onto it costs 1 extra movement point (1/2 along a road). In melee the higher unit rolls with advantage, attacking or defending. A slinger on high ground reaches 4 hexes onto low ground. Hills block shots between two low hexes, and from high ground you can shoot over low forest and enemies.
- **Fog of war.** You see only what your units see: a kobold 5 hexes and a slinger 7, where nothing blocks the view (forest and hills do; units do not). A unit in forest is only spotted from 2 hexes away. Ground you have never seen is dark, ground you have seen but cannot see now is dimmed, and an enemy that slips out of sight leaves a **?** where you last saw it. You can only attack enemies you can see, and a move that runs into a hidden enemy stops in front of it. The computer plays by the same rules: it knows only what its own units have seen.
- **Turns.** Each unit may move, then attack once. Attacking ends its move. A unit can also **Finish move** to stop early, or **Fortify** instead of moving: until your next turn, each failed defence die is rolled once more. The turn ends only when every unit has finished.
- **Winning.** Eliminate the other side.

## Controls

The game starts on a title screen (Play, Options, How to play); Play lists the battles. Everything works with six buttons, on any of:

| | Keyboard | Gamepad | Mouse |
|---|---|---|---|
| Move the cursor or the menu highlight | arrows or WASD | D-pad or left stick | point |
| OK | Space or Enter | A | click |
| Cancel / back | Esc or Backspace | B | the Menu button |
| Menu | Tab or P (Esc with nothing selected) | Start or Select | the Menu button |

- When your turn starts, your first unit is selected and the cursor is on it. Yellow hexes show where it can move and a red ring marks an enemy it can attack: OK on either does it. After a unit acts, the next one is selected for you.
- OK on another of your units selects it. OK on the selected unit again opens its menu: **Fortify**, **Finish move**, and for a Wololo **Chant** (bless a friend).
- Cancel drops the selection; with nothing selected it opens the menu (Resume, Options, Restart this battle, Quit to title). Restarting or quitting a battle in progress asks first.
- **The turn ends by itself** once none of your units can do anything more. **Options** can make you press **End turn** instead (in the menu, the panel button or **E**); there you also turn **sound** on or off and choose the **computer speed**. Options are remembered in your browser.
- Keyboard shortcuts: **F** finish move, **C** chant mode (Wololo), **M** sound, **E** end turn, **V** switch whose view a computer-against-computer battle shows (also in the menu).

## Scenarios

Kobold Skirmish (four against four, two slingers each) on a lightly wooded map, on maps that are 25, 50 or 75 percent forest, and on maps with some hills or hilly ones. The Kobold Warband: nine a side with a champion, two heavies, a pike, a slinger, an archer, a crossbow, a scout and a Wololo. Two computer-against-computer battles: four against four, and twenty against twenty (15 kobolds and 5 slingers a side). Four mixed-band battles where unlike armies meet: Shield Wall vs Skirmishers, Champion's Guard vs the Horde, Ambush in the Woods (half the map forest) and Archers on the Heights (hilly).

**Custom battle:** choose how much forest, whether there is a road, and how hilly the ground is; give each side a ready-made army, a random one, or one you buy unit by unit within a points budget; and play Red against the computer or watch the computer fight itself.

## Build

Odin (`dev-2026-07` or newer) and Python 3 (the build packs the sprites with `tools/gen_atlas.py`, standard library only). Pillow and Google Chrome are only needed for the screenshots.

```bash
./test.sh                      # rules tests, native
./build.sh                     # build/web (serve with: python3 -m http.server -d build/web 8123)
tools/sim.sh 2k2s 4k -n 1000   # balance simulator: computer against computer (letters k s h c r a x p w; -nofog to turn fog off)
tools/pages.sh                 # size build copied into docs/ for GitHub Pages
tools/shots.sh                 # assets/screenshots/ and assets/cover.png from the real build
tools/ship.sh                  # itch.io zip; pushes only with --push
```

## Credits

Cover title set in DejaVu Sans Mono (Bitstream Vera licence). No other third-party assets.

More games: https://playdeezgames.github.io/oeuvre-of-splorr/ · https://thegrumpygamedev.itch.io/
