# Anno M36

A Warhammer 40,000 hive-city economic builder in Godot. Build a military-industrial hive that meets the Imperial tithe, while keeping four castes of citizens fed, comforted, devout or policed.

This is a playable prototype with placeholder visuals: placement, production chains, districts, three transport networks, building modules, crowds and the tithe loop. See the design document for the full vision.

![Prototype screenshot](docs/screenshot.png)

## Running it

1. Install [Godot 4.4](https://godotengine.org/download) or newer (standard build, not .NET).
2. Open Godot, choose **Import**, and select `project.godot` in this folder.
3. Press **F5** to play.

Each run picks a random map seed. Set `world_seed` on the World node in `scenes/main.tscn` to replay a map.

## Controls

| Input | Action |
| --- | --- |
| WASD / arrow keys, middle-drag | Pan |
| Mouse wheel | Zoom |
| Q / E | Rotate the view 90° |
| Left click | Place building, or select a building, deposit or district |
| Left drag | Lay walkway, road or rail (L-shaped line); bulldoze or paint districts (rectangle) |
| R | Rotate the building being placed |
| Right click / Esc | Leave the current tool or deselect |
| Tab | Show district borders |
| Delete or X | Demolish selected (50% refund) |
| U | Upgrade selected housing |
| Space, 1, 2, 3 | Pause, normal, x2, x4 speed |

Bindings can be remapped in Project Settings > Input Map; anything defined there overrides the defaults in `scripts/core/input_setup.gd`.

## How the prototype plays

**Getting started.** You begin with the Bastion, a ring road, the gold Bastion Ward district and the Founding Charter: slum stacks, food and water, and the steel and ferrocrete to build more housing. Build slums beside a road or walkway, then mines on the deposits nearby (click a deposit to see what it is) with a road back to the Bastion. Every production building needs its drive modules beside it before it will run. Hover any build button for costs, workers and recipes.

- **Founding.** No tithe is levied until the hive houses 2,500 citizens. Reaching it founds the hive and grants the first charter.
- **Tithe.** From then on, every 8 minutes the Administratum takes its quota from the **Bastion Ward's** stockpile. The first is always steel; later cycles grow and rotate between the tithe goods the hive is permitted to make (steel, promethium, plasteel, lasguns, power packs, autogun rounds, flak armour). Full delivery raises favour and grants 2 charters, 75% or more grants 1, less lowers favour and grants none.
- **Charters.** Everything beyond the founding set is unlocked by spending charters in the Charters tab: 28 charters over three tiers, each with prerequisites (Cargo Rail, Workshops, Promethium Rights, Plasteel Foundries, Lasgun Pattern and so on). Quotas only ask for goods your unlocked buildings can make, so unlocking a new tithe good also adds it to the Imperium's demands.
- **Placement.** Buildings are polyominoes (rectangles, L, T and S shapes, never with holes). Blue markers are input ports, orange are outputs.
- **Districts.** Every building sits wholly inside one painted district. Each district has its own stockpile, held at its depot (the Bastion, or a District Depot), plus its own needs and morale. Charter and paint new districts from the Districts tab (up to 8).
- **Transport networks.**
  - *Walkways* carry people only. Housing needs a walkway or road to its depot to get food and water, and workers walk to jobs along them.
  - *Roads* carry haulers between buildings and their district depot, and people too. A building with no road to its depot can only trade through direct port links. Haulage per district comes from its depots (Bastion 12/s, District Depot 6/s).
  - *Cargo rail* links districts. Districts whose road-connected Cargo Stations share a rail line trade at 12/s per station. Without rail, depots on a shared road trade at 3/s, which also eats both districts' haulage. Rail can cross roads and walkways.
- **Freight.** Each district keeps about a minute of what its buildings and citizens use. Surplus goes to districts that are short, and anything left drains to the Bastion Ward, the hive's central store. Construction draws on every district's stock, its own first.
- **Commuting.** Workers walk up to 60 tiles to a job, across district lines if need be; long commutes lose efficiency. So a housing district can feed an industrial one, but the walk has to exist.
- **Direct links.** When an output port faces another building's input port, goods pass straight across for free, road or not. Tight, linked layouts beat sprawl.
- **Modules.** Place a module touching a host. Production buildings have 3 slots when small, 4 medium and 5 large, and modules take space beside the host (and may block its ports):
  - **Drive modules** are required. Each production building has its own (a mine needs Grinder Rigs, a furnace Bellows Houses, a ration press a Press Line, and so on). With none it sits idle and hires nobody; each one adds 50% speed, so two run it at full rate and more push it past that. They grow with the host: 1x1 for small buildings, 1x2 for medium, 2x2 for large. The inspector has an "Add" button for the right one.
  - **Warehouse** fits any production building and doubles its buffers.
  - Specialist modules come with charters: Machine-Spirit Shrine (decay x0.4, burns sacred unguents), Servitor Bay (40% fewer workers, uses machine parts), Overclock Coils (speed x1.3, decay x2, uses power cells), Deep Bore Drill (mine output x1.5).
  - Onsite processors that skip a production step: Fungal Mill (Ration Press works raw biomass), Polymer Still (Plasteel Foundry uses crude promethium), Nickel Crucible (Alloy Forge takes raw nickel ore).
  - A module whose upkeep isn't met switches off until it is.
- **Crowds.** Worker gangs walk the real route from their housing to their workplace, work a shift out of sight and walk home, on staggered shifts and coloured by caste. Trucks shuttle between depots and busy buildings, and trains run along active rail links. The crowds are a view of the simulation, never an input to it.
- **Deposits are finite.** Mines must sit on a matching deposit; output scales with how much of the footprint covers it, and deposits run dry.
- **Workers and needs.** Production buildings need large crews (a Deep Ore Mine employs 150 menials, a slum stack houses 100), so even a single steel chain needs a street of housing. The crew scale is one setting, `WORKER_SCALE` in `tools/gen_data.py`. Housing holds one caste. Upgrades keep the footprint and add capacity (a slum becomes a block of flats); castes never turn into each other. Unmet basic needs shrink the workforce.
- **Deposits.** Click a deposit tile to see what it is, how much is left and what mines it; its outline lights up on the map.
- **Morale.** Per district: Comfort goods, Fervour (Shrines using devotional icons) and Order (Enforcer Precincts using kits) each raise it, and it scales the speed of every building in the district.
- **Maintenance.** Buildings lose condition and slow down below 60%. They repair themselves with machine parts from their district depot.

## Project layout

```
data/            Generated .tres definitions (items, recipes, buildings, castes)
tools/gen_data.py  Source of truth for all game data; regenerates data/
scripts/data/    Resource classes and the Database autoload
scripts/grid/    Footprint rotation, the placement grid and module attachment
scripts/transport/  The three transport networks: tiles, connectivity, paths
scripts/sim/     Economy (per-district stockpiles), labour, freight, tithe
scripts/world/   Terrain, deposits, districts, main World node
scripts/view/    Camera, placement tools, building and network visuals, crowds
scripts/ui/      HUD, built in code
tests/           Headless test suite and a screenshot helper
```

## Changing game data

All items, recipes, buildings and castes live in `tools/gen_data.py`, so balancing happens in one readable file. After editing it:

```
python3 tools/gen_data.py
```

This checks references (unknown items, ports facing inwards, upgrades that change footprint) and rewrites `data/`. Don't edit the `.tres` files by hand; they are overwritten.

The current set is 41 goods (12 raw, 14 refined, 5 components and 10 finished: 4 tithe goods and 6 civic goods), 50 recipes, 97 buildings (including 37 drive modules and 8 other modules), 4 castes and 29 charters. The generator also checks that every production building has a drive module and that every building belongs to exactly one charter.

## Tests

```
godot --headless --path . res://tests/test_runner.tscn
```

28 tests covering data integrity, footprints, placement and districts, port links, transport rules and paths, road and market access, commuting range, freight by road and rail, modules (attachment, slots, effects, recipes, upkeep), drive modules, the worker scale, charters and unlocks, the founding threshold, tithe quotas, the production chain, depletion, maintenance and terrain generation. Exits non-zero on failure.

`tests/screenshot.tscn` builds a sample two-district hive and saves a screenshot, which is handy for checking visuals.

## Not built yet

Mapped against the design document, these are stand-ins or still to do:

- **Freight is one hop.** Goods move only between districts that are directly linked; there's no routing through a middle district yet.
- **No congestion per road tile.** Road load is measured per district (haulage), not per segment.
- **Passenger transit.** Workers only walk; there's no tram or passenger rail to stretch commutes.
- **Charter balance.** Charter costs, prerequisites and the 2,500 founding threshold are first guesses and need playtesting.
- **Pressure events** (accidents, plague, warp storms, audits, cults), pollution and population drift.
- **Win and loss conditions**, still open in the design doc.
- **Menus**: production statistics, in-game wiki, settings, objectives. Save and load.
