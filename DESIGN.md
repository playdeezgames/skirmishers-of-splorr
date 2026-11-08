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

**Built November 6, 2026** (all of the below). On the hilly map slingers gain:
at equal points (5 slingers vs 6 kobolds) they win 48% flat, 50% at 15% hills
and 57% at 35% hills, from range-4 shots off high ground. Mirrored armies stay
even.

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

**Built November 6, 2026** (all of the below). Choices made while building it:
units never block sight (only forest and hills do), so a hidden unit cannot
give itself away by blocking a view; you can only attack an enemy your side can
see; a move that runs into a hidden enemy stops on the hex before it and keeps
its unspent points; a last-seen marker is cleared when your side looks at the
hex again (one of your units moves, or your turn starts) and the enemy is gone.
The scout is the unit that sees furthest; it heads for the unexplored hex
nearest by way of the map's middle, and the others follow 2 hexes behind.
Simulator, 1000 games: 5 slingers vs 6 kobolds 45.7% with fog (47.9% without);
2k2s vs 4k 55.0% (52.5% without, 200 games). `-nofog` reproduces the earlier
results exactly.

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

- **Touch:** tap a hex to inspect it (as hover does on desktop). **Built
  November 7, 2026:** a tap on a new hex moves the cursor there and the panel
  shows what is on it (hex, unit, whether a shot is blocked); a tap on your own
  unit selects it straight away; a second tap on the same hex acts (move,
  attack, chant, or the unit menu on the selected unit). Menus and buttons act
  on the first tap. Dragging a finger does not move the cursor. The hint line
  says "Tap a hex to look, again to...". The mouse still acts on the first
  click. Checked at tablet size (768 wide: the 1060x580 canvas shows at 72%,
  readable). **On a phone in portrait (375 wide) the canvas is 35% size: hexes
  about 11 px and panel text about 4 px, too small to play; landscape is
  better (about 57%). A phone layout is not done.**
- **Portrait layout (phones held upright). Built November 8, 2026:** the map
  on top at full width and the panel below it, drawn 1.5 times larger, with
  the log cut to 6 lines (a 672x1327 canvas). Menus are drawn up to 1.6 times
  larger (wide ones as large as fits). The page picks whichever layout shows
  the map larger, and portrait on a tie (within 5%), so a phone upright
  (map about 52% size, up from 35%; panel text about 9 px) and a tablet
  upright use it, while a phone sideways, a tablet sideways and a desktop
  keep the landscape layout. It switches when the phone is turned round. The
  page footer now wraps on narrow screens instead of hiding its links.
  Hexes are still small on a phone (about 17 px across); zooming or panning
  the map would be the next step if that is not enough.
- **Map zoom and pan. Built November 8, 2026** (asked for phones, works
  everywhere): pinch or the mouse wheel zooms round the fingers or pointer,
  up to 3x; a drag (more than 8 CSS pixels) pans instead of tapping or
  clicking; + / - zoom round the cursor and 0 shows the whole map again;
  the gamepad's LB / RB zoom too. The zoomed map never leaves a gap at its
  edges. Keyboard and gamepad cursor moves, selecting the next unit and each
  shown computer action scroll the view to keep them in sight (the mouse
  and taps never scroll it). A new battle starts at the whole map; menus
  and the title screen do not zoom. Mouse clicks now act on release (so a
  drag can pan), still at once for the player.
- **Animation:** units slide along their path and attacks flash, so the computer's
  turn can be followed.
- **Art and sound** made with the Anvil tools, as for other SPLORR!! games.
  **Built November 6, 2026:** units slide hex by hex (only on hexes the viewing
  side can see), a dagger lunges and a sling throws a stone, the target flashes
  red (hit) or white (blocked) with a word, and a slain unit fades. The
  computer waits for each animation, and the player's clicks wait too. Three
  16x16 Anvil sprites drawn at 2x (kobold with dagger, slinger with sling, a
  pair of trees for forest) on the faction-coloured counters, and ten Anvil
  sounds (step, stab, sling, hit, block, slain, fortify, your turn, win, lose).

## Computer player

- Improve it **after elevation and fog** (they change what good play is), using
  the simulator: hold just out of enemy reach to win the first strike, prefer
  high ground and forest. **Built November 6, 2026** as the "tactical" style;
  the old AI stays as "basic" for the simulator (`-red basic`).

What was built and what the simulator found (tactical blue vs basic red):

- Before contact, units hold outside the hexes any known enemy could attack
  next turn. Holding stops once anyone attacks (otherwise units already
  fighting are left alone: dense-forest games dragged to 16 turns and tactical
  lost 45%), and after 2 quiet turns, so two careful sides cannot stall.
- Ties between equally good hexes go to safe hexes, high ground, then forest.
  Targets: not fortified, not uphill, slingers first.
- With no enemy known, the scout would rather stop in forest (hidden beyond 2
  hexes) than gain 2 more hexes. Advancing at half speed when blind was tried
  and lost ground (50%).
- Results, 400 games each: 4k 54%, 2k2s 53%, 2k2s on 35% hills 55%, 2k2s in
  50% forest 54%; 15k5s about even (48%, 300 games). Tactical against itself
  stays even and every game finishes.
- **Making the first attack is worth less than expected:** one variant made
  the first attack in 74% of games and still won only 52%. A dagger blow kills
  2 times in 9, and the whole line strikes back next turn. Bigger gains would
  need new ideas (screening slingers behind kobolds, ganging up), or rules that
  make the first blow count for more.

## Release standard

- **All of it now:** a README with the AI statement, plus `ITCH_DESCRIPTION.md`,
  `assets/cover.png` (630×500), `assets/screenshots/`, `devlog/YYYYMMDD/`,
  `tools/ship.sh` and the one-line `shippit.sh` wrapper. The cover and
  screenshots use the current plain look until art arrives. Nothing ships to
  itch.io without the user saying so.

## Armour and more unit types

Decided November 6, 2026 (the user's answers). Nothing here is built yet. The
numbers in the table are a **draft**, to be tuned with the simulator.

- **Armour is extra defence dice.** It is gear, like weapons: every kobold has
  its hide (1 white die), and armour adds to it: **leather +1 white, chain +1
  red, plate +1 black.**
- **All new units are kobolds**, so mirrored armies stay easy to balance.
- **Gear is fixed per unit type** (as the slinger's sling and dagger are now);
  no buying gear per unit.
- **Champion:** an elite kobold, **just stronger** (more body points, a better
  weapon, plate); no special rule.
- **Kobold shaman, called a Wololo: blesses and curses.** No attack of its own.
  Its action (ending its move, as an attack does) targets a unit in sight
  within 3 hexes: a friend is **blessed** (advantage on its next roll, attack
  or defence), an enemy is **cursed** (disadvantage on its next roll).
- **Heavy infantry:** armoured, slower, harder-hitting melee.
- **Pike: strikes first.** When an enemy moves next to a pike, the pike makes a
  free attack before that enemy can attack.
- **Two shooters:** a **bow** (range 2-5, outranges the sling) and a
  **crossbow** (range 2-4, **pierces armour**: the target rolls one fewer
  defence die).
- **Fast scout:** high movement and long sight, weak in a fight.

Draft unit table (move, sight and body as now; defence is hide plus armour;
points to be set by the simulator so equal points fight about even):

| Unit | Weapons | Armour (defence) | Body | Move | Sight |
|---|---|---|---|---|---|
| Kobold | dagger (1 white, 1) | none (1 white) | 1 | 4 | 5 |
| Slinger | sling (1 white, 2-3), dagger | none (1 white) | 1 | 4 | 7 |
| Pike | pike (1 red, 1), strikes first | leather (2 white) | 1 | 3 | 5 |
| Heavy | axe (1 red, 1) | chain (1 white, 1 red) | 2 | 3 | 5 |
| Archer | bow (1 white, 2-5), dagger | none (1 white) | 1 | 4 | 7 |
| Crossbow | crossbow (1 white, 2-4, pierces), dagger | leather (2 white) | 1 | 3 | 6 |
| Scout | dagger | none (1 white) | 1 | 6 | 8 |
| Champion | sword (1 red, 1 white, 1) | plate (1 white, 1 black) | 3 | 4 | 6 |
| Wololo | none: bless or curse, range 3 | none (1 white) | 1 | 4 | 6 |

Proposed rule details (Claude's proposals, to confirm):

- **Disadvantage** mirrors advantage: each die that scores is rolled once more
  and counts only if it scores again. Advantage and disadvantage cancel;
  neither stacks (one blessing, however many sources).
- A blessing or curse lasts for **one roll**, or until the Wololo's side's next
  turn starts, whichever comes first. A unit holds one at a time; a new one
  replaces it.
- **Strikes first:** once per enemy turn, when an enemy steps into a hex next
  to the pike, the pike attacks it at once (its normal pike dice). If the
  enemy dies, its move ends there. The pike can still act normally on its own
  turn.
- **Pierce:** the crossbow removes the target's best defence die (black, then
  red, then white); a target with one die still rolls it.
- **Units with more than 1 body point** keep their damage; no healing. The map
  shows their body points as pips on the counter.
- Each new type gets an Anvil sprite (counter art) and sounds where new
  (bow, crossbow, chant).

Suggested order inside this step, each priced with the simulator before the
next:

1. Armour as gear, units with more than 1 body point (pips on the map), and
   the three plain units: heavy infantry, champion, scout. **Built November
   6, 2026** with the draft stats, plus the "Kobold Warband" scenario (160
   points a side). Simulator prices: **heavy 25** (2.85 kobolds in all-heavy
   armies but 2.5 among kobolds: 4h vs 11k 56%, 2h4k vs 9k 48%), **champion
   55** (1c vs 6k 51%; 1c4k vs 10k 46%), **scout 11** (fights as a kobold;
   swapping one for a kobold comes out even once the computer keeps its scout
   within 4 hexes of a friend; before that leash it ran ahead alone and lost
   44%). Worth depends on the mix: many cheap units get more attacks a turn.
2. Bow and crossbow (the pierce rule). **Built November 6, 2026** with the
   draft stats; the warband now has an archer and a crossbow (168 points a
   side). Prices: **archer 14** (4a vs 4s 60%, vs 5s 42%; 2a2k vs 2s3k 41%),
   **crossbow 16** (as good as an archer against bare hide, 4x vs 6k 50%, but
   much better against armour: 4x vs 2h 75%, 2h2x vs 2h3k 76%, 1c4x vs 1c4a
   71%). Found on the way: a scout in forest could stand still for ever (its
   forest bonus matched the ground its leash let it gain); it now gets the
   bonus only for a hex it moves to.
3. Pike (the strikes-first reaction, the first rule that acts on the other
   side's turn; the computer must plan around it). **Built November 6, 2026**
   as proposed: every ready pike next to the hex an enemy steps onto strikes
   (once per pike per enemy turn), a kill ends the move, a survivor walks on.
   The computer avoids stepping next to a ready pike it can see, when it has
   an equally good hex. **Pike 20 points**: much stronger than the draft
   guessed (4p vs 6k 77%, vs 8k 51%, vs 9k 35%; 2p4k vs 9k 30%). The warband's
   kobold is now a pike (178 points a side).
4. Wololo: disadvantage, blessing and cursing, and when the computer casts.
   **Built November 6, 2026** as proposed (disadvantage, one roll, fades on
   the caster's next turn, one at a time). It cannot bless itself. The
   computer plays its Wololos first each turn, so a blessing can go on an
   attack the same turn; it blesses a friend that can strike now (else one in
   the enemy's reach) and curses an enemy its units can reach, weighting by
   points. **Wololo 12 points** (20 from November 7, 2026: see Area chants): about a kobold beside kobolds (1w4k vs 5k
   45%), worth more beside big units (1w2h2k vs 1k2h2k 55%, 1w1c3k vs 1c4k
   61%). The warband has one (nine a side, 190 points).
5. Sprites and sounds for the new types; scenarios with mixed bands. **Done
   November 7, 2026.** Sprites and sounds came with parts 1-4. Four
   scenarios pit different bands against each other, Red (you) against Blue,
   balanced with the simulator at `-inset 2` (computer vs computer, Red's win
   rate first):
   - Shield Wall vs Skirmishers: 2 heavies, 2 pikes, 2 crossbows, a Wololo
     (134) vs 3 archers, a scout, 6 kobolds (113), light woods: 48% / 51%.
   - Champion's Guard vs the Horde: champion, 2 heavies, a Wololo, 4 kobolds
     (157) vs 12 kobolds, 3 slingers (156): 55% / 45%.
   - Ambush in the Woods (50% forest): 4 archers, a scout, 6 kobolds (127) vs
     2 heavies, a pike, 2 crossbows, a Wololo (114): 48% / 50%.
   - Archers on the Heights (35% hills): 4 archers, 2 heavies (106) vs 2
     heavies, 2 pikes, 2 crossbows, a Wololo, 2 kobolds (154): 55% / 44%.
   Finding: terrain swings these matchups hard. Archers are cheap on open and
   hilly ground (4a2h 106 points beat 2h2p2x1w 134 points 68% on 35% hills;
   4a1r6k 127 beats it 66% on the usual map) and weak in forest (27% at 50%
   forest). Their price (14) may want raising; not changed yet.

## Interface overhaul (November 7, 2026)

The user's direction: the interface has grown "it works" clunky. Wanted:

- **Menus** for starting a game (choose a scenario) and leaving one, instead
  of buttons and hotkeys scattered over the panel.
- **One control scheme:** up / down / left / right / OK / cancel, the same on
  a gamepad (D-pad, A, B) and a keyboard (arrows or WASD, Space or Enter,
  Esc). The mouse keeps working (pointing moves the cursor, a click is OK).
- **Ending the turn is automatic by default:** when none of your units can do
  anything more, the turn ends by itself. Requiring the End turn press stays
  as an option.

**Built November 7, 2026:** a title screen over a computer battle (Play,
Options, How to play), the battle list, a pause menu (Resume, End turn when
you must press it, View in computer battles, Options, Restart, Quit), a unit
menu (OK on the selected unit: Fortify, Finish move, Chant), a game-over menu
(Play again, Choose a battle, Title, Look at the map), and confirmation before
throwing a battle away. Controls are a hex cursor and six buttons on keyboard,
gamepad and mouse; your first unit is selected when your turn starts, and the
next after each action. Options (end turn, sound, computer speed) are kept in
the browser. The old panel buttons and the N and [ ] keys are gone.

## Custom battles (November 7, 2026)

The user asked for a "custom" battle type: pick the ground and the armies.
Built as **Play > Custom battle...**, a settings menu (Left / Right or OK step
each setting):

- **Forest:** none, light (12%), woods (25%), heavy (50%), dense (75%).
- **Road:** yes or no.
- **Hills:** flat, some hills (15%), hilly (35%).
- **Sides:** you play Red against the computer, or computer vs computer.
- **Each side's army:** a ready-made one (Patrol 44 points, Hunters 87,
  Shield wall 142, Champion's guard 165, Warband 204, Horde 210; prices as of
  the archer's 20 points), one bought
  unit by unit, or a random one filled up to the budget.
- **Points to buy or draw armies:** 100, 150, 200, 250 or 300 (for bought and
  random armies; at most 30 units a side).

Buying opens the side's army menu: every unit type with its price and count
(Right or OK buys, Left sells; the mouse has - and + boxes). The battle cannot
start with an empty bought army or one over the budget. The last setup is
kept in the browser. Rules side: `src/game/custom.odin` (`Custom_Battle`,
`new_custom_game`); armies stand in a block two columns in from each edge,
shooters and the Wololo in the back column, and forest grows round them.

## Area chants (November 7, 2026)

The user's direction: the Wololo's chant should be an area effect, "a center
hex and all the hexes adjacent to it". Built as: the Wololo aims at a hex in
view within 3 (line of sight beyond 1); a blessing lands on every friend on
that hex and the six around it, a curse on every enemy there that its side
can see. Choices made without asking: one chant blesses or curses, not both;
hidden enemies are not cursed (no fog leaks in the log); the Wololo never
blesses itself, so a lone Wololo still finishes its move. On the page, OK on
an enemy in range still curses round it; C (or the unit menu) aims a
blessing, then a curse, at the cursor, lighting the seven hexes and ringing
the units it would touch.

Price: 12 to **20 points** (simulator: 1w10k v 12k 50%, 1w2h2k v 2k2h2k 57%,
1w1c3k v 1c5k 51%; at 12 it won 59-70% against a kobold in its place). The
mixed-band scenarios were re-balanced: Blue's skirmishers get a kobold (123),
the horde a kobold (166), the woodland archers a kobold (137); the heights
stay (Red 106 v Blue 162, 47% / 53%).

## Archer price (November 7, 2026)

The user asked for a better archer price. Their worth depends on what they
face (simulator, 400 games each):

- Plain kobolds: about 13-14 points (5a v 7k 53%, 8k 44%; 1c4a v 1c5k 54%).
- Behind a heavy and pike screen: about 22 (2h2p4a v 2h2p4s4k 50%, v 2h2p8k
  80%, v 2h2p12k 50%).
- Slow heavies: far more (5a v 3h 92%, v 5h 86%): move 3 cannot close on
  range 5.
- Terrain: hills multiply them (5a v 7k 80% on 15% hills, 92% on 35%:
  bow range 5 becomes 7 from high ground); forest halves them (28% at 50%).

Set to **20 points** (from 14), close to the mixed-army value. A single price
cannot cover hills or slow heavies; if those stay lopsided, the fix is in the
rules, e.g. the high-ground range bonus as +1 hex instead of x1.5 for the bow,
or heavies that can double-move.

**Decided November 8, 2026: archers being overpowered on hills is by
design.** Holding high ground with bows is meant to pay off; it will matter
more in a campaign of several battles, where choosing (or being denied) the
ground is part of the war. Keep the x1.5 range rule and the 20-point price.

## Walls and water (November 8, 2026)

The user asked for walls and water from the roadmap list. Their exact rules
were not specified; these are Claude's defaults, easy to change:

- **Shallow water** costs 2 to enter (like forest) but blocks no view and
  hides nobody. **Deep water** cannot be entered and blocks no view (you can
  shoot across a river). A road over water is a bridge. Water is never high
  ground.
- **Wooden and stone walls** are map tiles that cannot be entered. A wall
  blocks line of sight and shots like forest, except when either end is
  right next to it: a unit at a wall looks and shoots over it, and can be
  seen and shot over it. Seen from high ground, low walls block nothing, as
  with low forest.
- **Cover:** a shot across a wall hex right next to the target (on either
  traced line) lets the target defend with advantage, logged "(cover)".
  Not from high ground over a low wall. Advantage never stacks (fortified,
  holding high ground, cover). Melee never crosses a wall (the wall hex is
  between).
- Wooden and stone walls play the same for now; siege machinery is where
  they will differ (wood can be burned or broken more easily).
- **Maps:** water and walls are laid after the road and the armies (never on
  either; the road becomes a bridge or a gate) and before forest and hills.
  Water: a stream (one shallow hex wide), a river (two deep hexes wide with
  two or three shallow fords, one per third of the map) running north-south
  through the middle columns, each row's hex touching the last so there is
  no gap, or two or three ponds (deep, ringed by shallows). Walls: "some"
  is one walled farmstead (a ring of 12 wall hexes round a yard, with two
  gates opposite each other) and two field walls (3 to 6 hexes, sometimes
  bending), "many" is two farmsteads and five field walls; each is wooden
  or stone at random. If anything is shut in, walls and then deep water give
  way until every unit can walk to every other (`ensure_connected`).
- **Computer player:** it measures how far it is from what it heads for by
  walking distance (round water and walls), not as the crow flies, so it
  finds fords and gates; on open maps this is the same as before. It likes
  hexes next to a wall (cover) a little, as it likes forest.
- **Custom battles** gain Water (none, a stream, a river with fords, ponds)
  and Walls (none, some, many). **Scenarios:** River Crossing (the warband
  against itself across a river: 51% to 47% over 400 games) and Walled
  Farmsteads (many walls and a stream: 52.5% to 46%). Battles take a few more
  turns (about 20 to 23 instead of 14); unfinished games stay rare (6 to 9
  in 400).
- Drawn without new sprites for now: water in two blues with wave marks,
  stone walls as grey courses of stone, palisades as brown pointed stakes.

## Sappers (November 8, 2026)

Watching Walled Farmsteads, the user saw the need for an engineer or sapper
that turns walls into rubble. Claude's defaults, easy to change:

- **Kobold Sapper:** fights like a kobold (a pick: 1 white die, range 1),
  defends with 1 white, body 1, move 4, sight 5, 12 points. Its own sprite
  (an iron cap and a pick). Letter `e` in `tools/sim.sh`.
- **Breaking a wall** instead of attacking, on a wall hex next to it: a
  wooden wall (or a cracked stone wall) becomes **rubble**; a stone wall
  first **cracks** (still a wall in every way) and falls to a second blow on a
  later turn. This is where wooden and stone walls finally differ. Like an
  attack it ends the sapper's move; it can move first. On the page, walls it
  can break get an orange ring and OK on one breaks it; the log says
  "Red Sapper breaks the wooden wall into rubble" / "cracks the stone wall",
  with a swing and a puff of dust.
- **Rubble** costs 2 to enter (like forest and shallow water), blocks no
  sight and gives no cover. The view cache and the computer's reach maps are
  cleared when a wall falls (the map changed).
- **Computer:** a sapper with nobody to strike breaks the wall next to it
  that is worth most: the steps going through would save on its walk (round
  the wall otherwise), plus 3 for each enemy in sight sheltering right behind
  it; stone counts half (two blows); at least 3 to bother. It likes ending
  its move where such a breach is open.
- **Price:** in the simulator a sapper is worth exactly a kobold (1e9k v 10k
  49% open, 51% among many walls, 47.5% with walls and a stream; warband +
  sapper v warband + kobold 49-50%): the computer strikes only about 0.1
  walls a game, since farmsteads have gates and field walls are short.
  Priced at 12 for what a player can do with it that the computer hardly
  does (opening a farmstead's far side, taking cover away from shooters).
- **Walled Farmsteads** now gives each warband a sapper (216 points a side:
  47.5% to 52% over 400 games).

## Fortifying under shooters (November 8, 2026)

The user saw a lone pike keep fortifying against a lone archer until the
archer got lucky. The computer fortified whenever it could not attack this
turn but could be attacked next; against an enemy that outranges it that is
only waiting to be shot. Now it does not fortify while an enemy in sight
with a longer reach is near enough to shoot it next turn (`ai_outranged`); it
advances instead, which drives a kiting shooter back to the map edge.

- Lone duels: pike v archer 41% -> 56% (8 turns instead of 13), heavy v
  archer 46% -> 85% (12 turns instead of 33; it had fortified 26 times a
  game).
- Armies built round archers lost most: Shield Wall vs Skirmishers went
  50/49 -> 74/24 and Archers on the Heights 47/53 -> 19/80. Rebalanced by
  composition: the skirmishers get two more kobolds (142 v 161: 53% to 47%),
  and the Heights' shield wall drops a heavy and its two kobolds (130 v
  117: about 50/50). Warband mirror 50/48.5, Champion's Guard 54/46 and
  Ambush in the Woods 48/51 stayed in balance.
- **Archers are now overpriced at 20 in open fights**: 5a v 7k went 53% ->
  32%, 2h2p4a v 2h2p4s4k 50% -> 28%. Their old value leaned on the computer
  sitting still under arrows. A new price is for the user to decide (hills
  stay strong by design).

## Roadmap ideas (not decided in detail; November 7, 2026)

The user's list of what the game still needs, to be planned one at a time:

- **New races:** goblins, orcs, gnolls (each with its own roster).
- **Mounted units.**
- **Walls:** wooden walls and stone walls as map tiles. **Built November 8,
  2026** (see Walls and water).
- **Water:** shallow water slows units down; deep water cannot be crossed.
  **Built November 8, 2026.**
- **Watercraft** to carry units over deep water, perhaps fighting other boats
  and attacking fortifications.
- **Siege machinery.**
- **A campaign:** a larger world map of battles, where the player raises
  armies with money from taxes and tribute and goes to war with larger
  enemies.
- **Veteran units:** units that gain some benefit from experience (added
  November 7, 2026).
- **Morale** (added November 8, 2026): units that can waver, rout or rally,
  not decided in detail.
- **Auto-resolve:** in a game with a human player, a way to hand the battle to
  the computer to finish, switching straight to fast speed (added November 7,
  2026). **Built November 8, 2026:** "Let the computer
  finish" in the pause menu hands your side to the computer, which plays it at
  fast speed whatever the speed option says (the option itself is untouched),
  keeping your side's view (V still switches it). The panel says "The
  computer is finishing for you" and your army line "you, by computer".
  "Take back control" in the same menu returns it, even in the middle of your
  turn. The end screen still counts the result as your win or loss. A new
  battle or a restart always starts with you in control.

## Suggested order

1. README and release-standard files. **Done November 5, 2026.**
2. Enemies block line of sight; 15k5s battle; points cost (simulator). **Done November 5, 2026.**
3. Elevation. **Done November 6, 2026.**
4. Fog of war. **Done November 6, 2026.**
5. Computer player improvements. **Done November 6, 2026.**
6. Move animation; Anvil art and sound. **Done November 6, 2026.**
7. Tap to inspect (check on a touch-size screen). **Done November 7, 2026**
   (tablet size works); portrait layout for phones November 8, 2026.
8. Armour and more unit types (see that section); parts 1-4 done November 6,
   2026, part 5 (mixed-band scenarios) November 7, 2026. **Done.**
9. Interface overhaul: menus, one control scheme for gamepad and keyboard,
   automatic end of turn (see that section). **Done November 7, 2026.**
10. Custom battles (see that section). **Done November 7, 2026.**
11. Then the roadmap ideas, in an order still to agree.
