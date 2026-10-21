#!/usr/bin/env python3
"""
Anno M36 game data generator.

This file is the single source of truth for items, recipes, buildings and
castes. Edit the tables below, then run:

    python3 tools/gen_data.py

It rewrites every .tres file under data/ (items, recipes, buildings, castes).
Do not hand-edit the generated .tres files; changes there are overwritten.

Conventions
-----------
Grid coordinates: x grows east (+X in the world), y grows south (+Z).
Footprints are drawn as ASCII rows, "X" = occupied cell, "." = empty.
Footprints must be a single connected shape with no enclosed holes
(design rule: no dead space inside a building). tests/run_tests.gd enforces it.

Ports: (x, y, side, kind) where side is N/E/S/W and kind is "in" or "out".
An output port on building A links to an input port on building B when B's
port cell is the neighbour of A's port cell on that side and faces back.
Linked ports hand goods over directly and skip the logistics network.
"""

from __future__ import annotations

import os
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")

# ---------------------------------------------------------------------------
# Items: 12 raw, 14 refined, 5 components, 10 finished (41 total)
# tier: 0 raw, 1 refined, 2 component, 3 finished
# tithe_base: base quota per tithe cycle; 0 means the Imperium never asks for it
# ---------------------------------------------------------------------------
ITEMS = [
    # id, name, tier, category, tithe_base, colour, description
    ("iron_ore", "Iron Ore", 0, "raw", 0, "#7a4b3a", "Mined from deep seams below the hive foundations."),
    ("coal", "Coal", 0, "raw", 0, "#2b2b2b", "Fuel for furnaces and feedstock for chemicals."),
    ("nickel_ore", "Nickel Ore", 0, "raw", 0, "#8f9a7a", "Alloying metal. Scarcer than iron."),
    ("copper_ore", "Copper Ore", 0, "raw", 0, "#b8733f", "Drawn into wire for every machine in the hive."),
    ("silica_sand", "Silica Sand", 0, "raw", 0, "#d8c89a", "Ash-waste sand, fused into glass and crystal."),
    ("limestone", "Limestone", 0, "raw", 0, "#c9c3b0", "Quarried for ferrocrete."),
    ("sulphur", "Sulphur", 0, "raw", 0, "#d9c43a", "Reeking yellow deposits for propellant."),
    ("crude_promethium", "Crude Promethium", 0, "raw", 0, "#5a3d6b", "Unrefined fuel pumped from the deep wells."),
    ("rare_earths", "Rare Earths", 0, "raw", 0, "#3f8f8a", "Trace metals for crystals, cells and cogitators."),
    ("sump_water", "Sump Water", 0, "raw", 0, "#3d5a5a", "Recycled, filthy, everywhere."),
    ("fungal_biomass", "Fungal Biomass", 0, "raw", 0, "#6b7a3a", "Grown in vats on sump water."),
    ("salvage_scrap", "Salvage Scrap", 0, "raw", 0, "#6e6258", "Picked from old ruins. Cheap, finite."),

    ("steel", "Steel", 1, "industrial", 120, "#8c939a", "The hive's basic building metal."),
    ("nickel_matte", "Nickel Matte", 1, "industrial", 0, "#a3ad8c", "Smelted nickel, ready for alloying."),
    ("steel_alloy", "Steel Alloy", 1, "industrial", 0, "#a7b3bf", "Dense alloy billets, rolled into far more steel."),
    ("copper_wire", "Copper Wire", 1, "industrial", 0, "#d08a4a", "Spooled conductor."),
    ("glass", "Glass", 1, "industrial", 0, "#9fc4c9", "For pict-screens, lenses and windows."),
    ("ferrocrete", "Ferrocrete", 1, "construction", 0, "#7f7a70", "Reinforced concrete. Housing is made of it."),
    ("purified_water", "Purified Water", 1, "civic", 0, "#5b8fb0", "Filtered sump water. Every caste needs it."),
    ("promethium_fuel", "Promethium Fuel", 1, "industrial", 80, "#8a4fb3", "Refined fuel. Also a tithe staple."),
    ("polymer", "Polymer", 1, "industrial", 0, "#4f6a8a", "Plastics from promethium."),
    ("plasteel", "Plasteel", 1, "industrial", 60, "#b6c2cc", "Steel bonded with polymer. Light and strong."),
    ("propellant", "Propellant", 1, "industrial", 0, "#b35a2a", "Explosive charge for munitions."),
    ("focusing_crystal", "Focusing Crystal", 1, "industrial", 0, "#c43a3a", "Ground lens crystal for lasguns."),
    ("nutrient_slurry", "Nutrient Slurry", 1, "civic", 0, "#8a8a4a", "Processed biomass paste."),
    ("sacred_unguents", "Sacred Unguents", 1, "industrial", 0, "#c9a03a", "Blessed oils. Machines fail without them."),

    ("machine_parts", "Machine Parts", 2, "industrial", 0, "#9a8a6a", "Spare parts. Consumed by maintenance."),
    ("cogitator_circuits", "Cogitator Circuits", 2, "industrial", 0, "#3a8a5a", "Logic boards for thinking machines."),
    ("power_cells", "Power Cells", 2, "industrial", 0, "#3a6ab3", "Stored charge."),
    ("shell_casings", "Shell Casings", 2, "industrial", 0, "#b39a3a", "Stamped brass-steel cases."),
    ("ceramite", "Ceramite", 2, "construction", 0, "#e0ddd0", "Heat-proof ceramic plate for advanced buildings."),

    ("lasgun", "Lasgun", 3, "tithe", 20, "#a33a2a", "The Imperial Guard's rifle. The tithe's centrepiece."),
    ("las_power_pack", "Las Power Pack", 3, "tithe", 40, "#2a5aa3", "Lasgun ammunition."),
    ("autogun_rounds", "Autogun Rounds", 3, "tithe", 60, "#a38a2a", "Crated solid-shot ammunition."),
    ("flak_armour", "Flak Armour", 3, "tithe", 25, "#5a6a4a", "Layered infantry armour."),
    ("ration_bricks", "Ration Bricks", 3, "civic", 0, "#9a8a5a", "Basic food for every caste."),
    ("recaf", "Recaf", 3, "civic", 0, "#5a3a2a", "Stimulant drink. Comfort for workers."),
    ("amasec", "Amasec", 3, "civic", 0, "#a35a3a", "Spirits. Comfort for the upper castes."),
    ("pict_screens", "Pict Screens", 3, "civic", 0, "#3a3a5a", "Entertainment and propaganda feeds."),
    ("devotional_icons", "Devotional Icons", 3, "civic", 0, "#c9b03a", "Aquilas and saints for shrines."),
    ("enforcer_kit", "Enforcer Kit", 3, "civic", 0, "#2a2a3a", "Shotguns, shields and mauls for the precincts."),
]

# ---------------------------------------------------------------------------
# Recipes: inputs / outputs per cycle, duration in seconds at full speed.
# deposit: extraction recipes only; the building must sit on that deposit.
# The steel ladder follows the brief: basic (1 step) vs alloy (3 steps, ~3x).
# ---------------------------------------------------------------------------
RECIPES = [
    # id, name, inputs, outputs, duration, deposit
    # Extraction
    ("extract_iron_ore", "Mine Iron Ore", {}, {"iron_ore": 1}, 2.0, "iron_ore"),
    ("extract_coal", "Mine Coal", {}, {"coal": 1}, 2.0, "coal"),
    ("extract_nickel_ore", "Mine Nickel Ore", {}, {"nickel_ore": 1}, 3.0, "nickel_ore"),
    ("extract_copper_ore", "Mine Copper Ore", {}, {"copper_ore": 1}, 2.5, "copper_ore"),
    ("extract_rare_earths", "Mine Rare Earths", {}, {"rare_earths": 1}, 4.0, "rare_earths"),
    ("extract_sulphur", "Mine Sulphur", {}, {"sulphur": 1}, 3.0, "sulphur"),
    ("extract_silica_sand", "Dig Silica Sand", {}, {"silica_sand": 1}, 1.5, "silica_sand"),
    ("extract_limestone", "Quarry Limestone", {}, {"limestone": 1}, 2.0, "limestone"),
    ("extract_crude_promethium", "Pump Crude Promethium", {}, {"crude_promethium": 1}, 2.0, "crude_promethium"),
    ("extract_salvage_scrap", "Scavenge Scrap", {}, {"salvage_scrap": 1}, 2.0, "salvage_scrap"),
    ("pump_sump_water", "Pump Sump Water", {}, {"sump_water": 2}, 2.0, ""),
    ("grow_biomass", "Grow Biomass", {"sump_water": 1}, {"fungal_biomass": 2}, 4.0, ""),

    # Metals
    ("smelt_steel", "Smelt Steel (basic)", {"iron_ore": 2, "coal": 1}, {"steel": 1}, 4.0, ""),
    ("smelt_scrap", "Smelt Scrap", {"salvage_scrap": 2}, {"steel": 1}, 3.0, ""),
    ("smelt_nickel_matte", "Smelt Nickel Matte", {"nickel_ore": 2, "coal": 1}, {"nickel_matte": 2}, 3.0, ""),
    ("forge_steel_alloy", "Forge Steel Alloy", {"iron_ore": 2, "coal": 1, "nickel_matte": 1}, {"steel_alloy": 1}, 4.0, ""),
    ("roll_alloy", "Roll Alloy into Steel", {"steel_alloy": 1}, {"steel": 3}, 2.0, ""),
    ("draw_wire", "Draw Copper Wire", {"copper_ore": 1}, {"copper_wire": 2}, 2.0, ""),

    # Minerals and construction
    ("fuse_glass", "Fuse Glass", {"silica_sand": 2, "coal": 1}, {"glass": 1}, 3.0, ""),
    ("mix_ferrocrete", "Mix Ferrocrete", {"limestone": 2, "silica_sand": 1, "sump_water": 1}, {"ferrocrete": 2}, 3.0, ""),
    ("filter_water", "Filter Water", {"sump_water": 2}, {"purified_water": 1}, 2.0, ""),

    # Promethium
    ("refine_promethium", "Refine Promethium", {"crude_promethium": 2}, {"promethium_fuel": 1}, 3.0, ""),
    ("make_polymer", "Make Polymer", {"crude_promethium": 1, "coal": 1}, {"polymer": 1}, 3.0, ""),
    ("crack_promethium", "Crack Promethium", {"crude_promethium": 3, "sump_water": 1}, {"promethium_fuel": 2, "polymer": 2}, 5.0, ""),

    # Advanced refined
    ("bond_plasteel", "Bond Plasteel", {"steel": 2, "polymer": 1}, {"plasteel": 1}, 4.0, ""),
    ("mix_propellant", "Mix Propellant", {"sulphur": 1, "coal": 1}, {"propellant": 2}, 3.0, ""),
    ("grind_crystal", "Grind Focusing Crystal", {"silica_sand": 2, "rare_earths": 1}, {"focusing_crystal": 1}, 5.0, ""),
    ("render_slurry", "Render Nutrient Slurry", {"fungal_biomass": 2, "purified_water": 1}, {"nutrient_slurry": 2}, 3.0, ""),
    ("bless_unguents", "Bless Unguents", {"promethium_fuel": 1, "fungal_biomass": 1}, {"sacred_unguents": 2}, 4.0, ""),

    # Components
    ("make_machine_parts", "Make Machine Parts", {"steel": 1, "copper_wire": 1}, {"machine_parts": 1}, 4.0, ""),
    ("etch_circuits", "Etch Cogitator Circuits", {"copper_wire": 2, "glass": 1, "rare_earths": 1}, {"cogitator_circuits": 1}, 6.0, ""),
    ("charge_cells", "Charge Power Cells", {"rare_earths": 1, "copper_wire": 2, "promethium_fuel": 1}, {"power_cells": 2}, 5.0, ""),
    ("press_casings", "Press Shell Casings", {"steel": 1}, {"shell_casings": 4}, 3.0, ""),
    ("fire_ceramite", "Fire Ceramite", {"silica_sand": 2, "rare_earths": 1, "promethium_fuel": 1}, {"ceramite": 1}, 6.0, ""),

    # Tithe goods
    ("assemble_lasgun", "Assemble Lasgun", {"plasteel": 1, "focusing_crystal": 1, "power_cells": 1}, {"lasgun": 1}, 8.0, ""),
    ("fill_power_packs", "Fill Las Power Packs", {"power_cells": 2, "polymer": 1}, {"las_power_pack": 2}, 5.0, ""),
    ("load_rounds", "Load Autogun Rounds", {"shell_casings": 4, "propellant": 2}, {"autogun_rounds": 4}, 5.0, ""),
    ("stitch_flak", "Stitch Flak Armour", {"polymer": 2, "steel": 1}, {"flak_armour": 1}, 6.0, ""),

    # Civic goods
    ("press_rations", "Press Ration Bricks", {"nutrient_slurry": 2}, {"ration_bricks": 2}, 3.0, ""),
    ("roast_recaf", "Roast Recaf", {"fungal_biomass": 1, "purified_water": 1}, {"recaf": 2}, 4.0, ""),
    ("distil_amasec", "Distil Amasec", {"fungal_biomass": 2, "purified_water": 1, "glass": 1}, {"amasec": 1}, 8.0, ""),
    ("build_pict_screens", "Build Pict Screens", {"glass": 1, "cogitator_circuits": 1, "polymer": 1}, {"pict_screens": 1}, 8.0, ""),
    ("cast_icons_scrap", "Cast Icons (scrap)", {"salvage_scrap": 1}, {"devotional_icons": 2}, 4.0, ""),
    ("cast_icons_steel", "Cast Icons (steel)", {"steel": 1}, {"devotional_icons": 2}, 4.0, ""),
    ("issue_enforcer_kit", "Issue Enforcer Kits", {"steel": 1, "polymer": 1, "power_cells": 1}, {"enforcer_kit": 1}, 8.0, ""),

    # Module-unlocked recipes: an onsite processor skips a whole production step
    ("press_rations_direct", "Press Rations (onsite mill)", {"fungal_biomass": 3, "purified_water": 1}, {"ration_bricks": 2}, 4.0, ""),
    ("bond_plasteel_integrated", "Bond Plasteel (onsite still)", {"steel": 2, "crude_promethium": 1, "coal": 1}, {"plasteel": 1}, 5.0, ""),
    ("forge_alloy_integrated", "Forge Alloy (onsite crucible)", {"iron_ore": 2, "coal": 2, "nickel_ore": 1}, {"steel_alloy": 1}, 5.0, ""),

    # Services (consume goods, produce district coverage instead of items)
    ("hold_mass", "Hold Mass", {"devotional_icons": 1}, {}, 30.0, ""),
    ("patrol_district", "Patrol District", {"enforcer_kit": 1}, {}, 60.0, ""),
]

# ---------------------------------------------------------------------------
# Castes: needs are units per 100 citizens per minute.
# Basic needs gate the workforce; comfort feeds morale.
# ---------------------------------------------------------------------------
CASTES = [
    ("menial", "Menials", "#8a7a6a",
     {"ration_bricks": 2.0, "purified_water": 2.0}, {"recaf": 1.0}),
    ("hiver", "Hivers", "#6a8aa3",
     {"ration_bricks": 3.0, "purified_water": 3.0}, {"recaf": 1.0, "pict_screens": 0.2}),
    ("scribe", "Scribes", "#a3906a",
     {"ration_bricks": 3.0, "purified_water": 3.0}, {"amasec": 0.5, "pict_screens": 0.5}),
    ("adept", "Adepts", "#a33a2a",
     {"purified_water": 2.0, "sacred_unguents": 2.0, "nutrient_slurry": 1.0}, {}),
]

# ---------------------------------------------------------------------------
# Footprints
# ---------------------------------------------------------------------------
SHAPES = {
    "1x1": ["X"],
    "1x2": ["X", "X"],
    "2x1": ["XX"],
    "3x1": ["XXX"],
    "2x2": ["XX", "XX"],
    "2x3": ["XX", "XX", "XX"],
    "3x2": ["XXX", "XXX"],
    "3x3": ["XXX", "XXX", "XXX"],
    "L5": ["XXX", "X.."],          # L-shaped 3x2, five cells
    "L3": ["XX", "X."],            # small L, three cells
    "T": ["XXX", ".X."],
    "S": [".XX", "XX."],
    "BIG_L": ["XXX", "XXX", "X.."],
}


def shape_cells(name: str) -> list[tuple[int, int]]:
    rows = SHAPES[name]
    return [(x, y) for y, row in enumerate(rows) for x, ch in enumerate(row) if ch == "X"]


def default_ports(cells, inputs: bool, outputs: bool):
    """Inputs on the westmost cells facing west, outputs on the eastmost facing east."""
    ports = []
    xs = [c[0] for c in cells]
    min_x, max_x = min(xs), max(xs)
    if inputs:
        for (x, y) in cells:
            if x == min_x:
                ports.append((x, y, "W", "in"))
    if outputs:
        for (x, y) in cells:
            if x == max_x:
                ports.append((x, y, "E", "out"))
    return ports


# ---------------------------------------------------------------------------
# Buildings
# category: core, transport, housing, extraction, industry, civic, service, module
# workers: {caste: count}
# ports: None = default (in on west, out on east); [] = no ports; or explicit list
# module_slots: None = automatic from size and category (see auto_slots)
# Modules: module_hosts lists host categories or building ids. module_effects
# multiply the host: speed, output, decay, workers, buffer. module_upkeep is
# units per minute from the district stockpile; unpaid upkeep switches the
# module off. module_recipes are extra recipes the host can then select.
# ---------------------------------------------------------------------------
B = []


# Every production building needs this many times its listed crew. Kept as one
# knob so the hive-to-hamlet balance can be tuned in one place.
WORKER_SCALE = 5
PRODUCTION = ("extraction", "industry", "civic")


def building(id, name, category, shape, recipes=(), cost=None, workers=None,
             ports=None, colour="#777777", height=1.0, buffer=8,
             housing_caste="", housing_capacity=0, upgrade_to="", upgrade_cost=None,
             logistics=0.0, decay=1.0, service_kind="", service_capacity=0,
             needs_deposit=False, description="", module_slots=None, module_hosts=(),
             module_effects=None, module_upkeep=None, module_recipes=(), is_depot=False,
             station_capacity=0.0):
    cells = shape_cells(shape)
    if module_slots is None:
        module_slots = auto_slots(category, len(cells))
    if category in PRODUCTION and workers:
        workers = {k: v * WORKER_SCALE for k, v in workers.items()}
    if ports is None:
        has_inputs = any(r for r in recipes if RECIPE_BY_ID[r][2])
        has_outputs = any(r for r in recipes if RECIPE_BY_ID[r][3])
        ports = default_ports(cells, has_inputs, has_outputs)
    B.append(dict(
        id=id, name=name, category=category, cells=cells, ports=ports,
        recipes=list(recipes), cost=cost or {}, workers=workers or {},
        colour=colour, height=height, buffer=buffer,
        housing_caste=housing_caste, housing_capacity=housing_capacity,
        upgrade_to=upgrade_to, upgrade_cost=upgrade_cost or {},
        logistics=logistics, decay=decay, service_kind=service_kind,
        service_capacity=service_capacity, needs_deposit=needs_deposit,
        description=description, module_slots=module_slots, module_hosts=list(module_hosts),
        module_effects=module_effects or {}, module_upkeep=module_upkeep or {},
        module_recipes=list(module_recipes), is_depot=is_depot,
        station_capacity=station_capacity, drive_module="",
    ))


def auto_slots(category: str, cells: int) -> int:
    """Production buildings get module slots by size; everything else none.
    Room for at least two drive modules plus a warehouse on the smallest."""
    if category not in PRODUCTION:
        return 0
    return 3 if cells <= 2 else (4 if cells <= 5 else 5)


RECIPE_BY_ID = {r[0]: r for r in RECIPES}

# Core and transport
building("administratum_bastion", "Administratum Bastion", "core", "3x3",
         cost={}, workers={}, ports=[], colour="#4a3f5a", height=3.0,
         logistics=12.0, decay=0.0, is_depot=True,
         description="Seat of the governor's office. Acts as its district's depot. The tithe is collected from this district's stockpile.")
building("district_depot", "District Depot", "transport", "2x2",
         cost={"steel": 15, "ferrocrete": 10}, workers={"menial": 10}, ports=[],
         colour="#5a5a3f", height=1.2, logistics=6.0, is_depot=True, decay=0.5,
         description="Holds a district's stockpile and adds 6/s haulage. Buildings trade with it over roads; housing shops at it over walkways or roads.")
building("cargo_station", "Cargo Station", "transport", "3x1",
         cost={"steel": 30, "ferrocrete": 20}, workers={"menial": 15}, ports=[],
         colour="#4a4a5a", height=1.4, station_capacity=12.0, decay=0.5,
         description="Loads freight trains. Place next to cargo rail and connect to the district depot by road. Districts with stations on the same rail line trade at 12/s per station.")

# Housing: upgrades keep the same footprint (a slum becomes a block of flats)
building("slum_stack", "Slum Stack", "housing", "2x2", ports=[],
         cost={"steel": 5, "ferrocrete": 10}, colour="#5a4a3f", height=1.5,
         housing_caste="menial", housing_capacity=100,
         upgrade_to="ferrocrete_block", upgrade_cost={"ferrocrete": 25, "steel": 10}, decay=0.5)
building("ferrocrete_block", "Ferrocrete Block", "housing", "2x2", ports=[],
         cost={"steel": 15, "ferrocrete": 35}, colour="#6a5a4a", height=2.5,
         housing_caste="menial", housing_capacity=200,
         upgrade_to="hab_stack", upgrade_cost={"ferrocrete": 40, "plasteel": 10, "glass": 10}, decay=0.5)
building("hab_stack", "Hab Stack", "housing", "2x2", ports=[],
         cost={"steel": 15, "ferrocrete": 75, "plasteel": 10, "glass": 10}, colour="#7a6a5a", height=3.5,
         housing_caste="menial", housing_capacity=300, decay=0.5)

building("hiver_tenement", "Hiver Tenement", "housing", "2x3", ports=[],
         cost={"steel": 15, "ferrocrete": 20, "glass": 5}, colour="#4a5a6a", height=1.5,
         housing_caste="hiver", housing_capacity=60,
         upgrade_to="hiver_block", upgrade_cost={"ferrocrete": 30, "glass": 10, "steel": 10}, decay=0.5)
building("hiver_block", "Hiver Block", "housing", "2x3", ports=[],
         cost={"steel": 25, "ferrocrete": 50, "glass": 15}, colour="#5a6a7a", height=2.5,
         housing_caste="hiver", housing_capacity=120,
         upgrade_to="hiver_spire", upgrade_cost={"ferrocrete": 40, "plasteel": 15, "glass": 15}, decay=0.5)
building("hiver_spire", "Hiver Spire", "housing", "2x3", ports=[],
         cost={"steel": 25, "ferrocrete": 90, "glass": 30, "plasteel": 15}, colour="#6a7a8a", height=3.5,
         housing_caste="hiver", housing_capacity=180, decay=0.5)

building("scribe_quarters", "Scribe Quarters", "housing", "3x2", ports=[],
         cost={"steel": 20, "ferrocrete": 25, "glass": 15}, colour="#6a5a3a", height=1.8,
         housing_caste="scribe", housing_capacity=40,
         upgrade_to="scribe_manse", upgrade_cost={"ferrocrete": 30, "glass": 20, "plasteel": 10}, decay=0.5)
building("scribe_manse", "Scribe Manse", "housing", "3x2", ports=[],
         cost={"steel": 20, "ferrocrete": 55, "glass": 35, "plasteel": 10}, colour="#7a6a4a", height=2.8,
         housing_caste="scribe", housing_capacity=80, decay=0.5)

building("forge_cloister", "Forge Cloister", "housing", "2x2", ports=[],
         cost={"steel": 30, "ferrocrete": 20, "machine_parts": 10}, colour="#6a2a2a", height=2.0,
         housing_caste="adept", housing_capacity=20,
         upgrade_to="forge_sanctum", upgrade_cost={"plasteel": 20, "ceramite": 10, "machine_parts": 10}, decay=0.5)
building("forge_sanctum", "Forge Sanctum", "housing", "2x2", ports=[],
         cost={"steel": 30, "ferrocrete": 20, "machine_parts": 20, "plasteel": 20, "ceramite": 10},
         colour="#7a3a3a", height=3.0, housing_caste="adept", housing_capacity=40, decay=0.5)

# Extraction
building("deep_ore_mine", "Deep Ore Mine", "extraction", "2x2",
         recipes=["extract_iron_ore", "extract_coal", "extract_nickel_ore", "extract_copper_ore",
                  "extract_rare_earths", "extract_sulphur"],
         cost={"steel": 15}, workers={"menial": 30}, colour="#5a4030", height=1.4, needs_deposit=True,
         description="Place over an ore deposit. Output scales with how many cells cover the deposit.")
building("open_quarry", "Open Quarry", "extraction", "3x2",
         recipes=["extract_limestone", "extract_silica_sand"],
         cost={"steel": 10}, workers={"menial": 30}, colour="#8a8070", height=0.6, needs_deposit=True,
         description="Place over limestone or silica sand.")
building("promethium_derrick", "Promethium Derrick", "extraction", "1x1",
         recipes=["extract_crude_promethium"], cost={"steel": 12},
         workers={"menial": 10}, colour="#3a2a4a", height=2.4, needs_deposit=True)
building("scavenger_post", "Scavenger Post", "extraction", "1x2",
         recipes=["extract_salvage_scrap"], cost={"steel": 5},
         workers={"menial": 20}, colour="#6a5a4a", height=0.8, needs_deposit=True,
         description="Strips scrap fields. They run out quickly.")
building("sump_pump", "Sump Pump", "extraction", "1x1",
         recipes=["pump_sump_water"], cost={"steel": 8},
         workers={"menial": 10}, colour="#2a4a4a", height=1.0)
building("fungal_vats", "Fungal Vats", "extraction", "2x2",
         recipes=["grow_biomass"], cost={"steel": 10, "ferrocrete": 10},
         workers={"menial": 25}, colour="#4a5a2a", height=1.0)

# Industry
building("blast_furnace", "Blast Furnace", "industry", "2x2",
         recipes=["smelt_steel", "smelt_scrap"], cost={"steel": 20, "ferrocrete": 10},
         workers={"menial": 30}, colour="#6a3a2a", height=2.0)
building("matte_smelter", "Matte Smelter", "industry", "2x1",
         recipes=["smelt_nickel_matte"], cost={"steel": 20, "ferrocrete": 10},
         workers={"hiver": 15}, colour="#5a6a4a", height=1.6)
building("alloy_forge", "Alloy Forge", "industry", "L5",
         recipes=["forge_steel_alloy"], cost={"steel": 40, "ferrocrete": 20, "machine_parts": 5},
         workers={"hiver": 30}, colour="#7a4a3a", height=2.2,
         ports=[(0, 0, "W", "in"), (0, 1, "W", "in"), (0, 1, "S", "in"), (2, 0, "E", "out")],
         description="The advanced steel route, step 2 of 3. Feed it nickel matte.")
building("rolling_mill", "Rolling Mill", "industry", "3x1",
         recipes=["roll_alloy"], cost={"steel": 30, "machine_parts": 5},
         workers={"hiver": 15}, colour="#8a8a8a", height=1.2,
         description="Rolls one alloy billet into three steel. Step 3 of 3.")
building("wire_drawer", "Wire Drawer", "industry", "2x1",
         recipes=["draw_wire"], cost={"steel": 15}, workers={"hiver": 10}, colour="#8a5a2a", height=1.2)
building("glassworks", "Glassworks", "industry", "2x2",
         recipes=["fuse_glass"], cost={"steel": 15, "ferrocrete": 10},
         workers={"menial": 20}, colour="#5a8a8a", height=1.6)
building("ferrocrete_mixer", "Ferrocrete Mixer", "industry", "2x1",
         recipes=["mix_ferrocrete"], cost={"steel": 12},
         workers={"menial": 20}, colour="#7a7a6a", height=1.4)
building("water_filter", "Water Filter", "industry", "1x2",
         recipes=["filter_water"], cost={"steel": 10},
         workers={"menial": 10}, colour="#3a6a8a", height=1.2)
building("promethium_refinery", "Promethium Refinery", "industry", "T",
         recipes=["refine_promethium"], cost={"steel": 25, "ferrocrete": 15},
         workers={"hiver": 20}, colour="#5a3a6a", height=2.4,
         ports=[(0, 0, "W", "in"), (1, 1, "S", "in"), (2, 0, "E", "out")])
building("polymer_plant", "Polymer Plant", "industry", "2x2",
         recipes=["make_polymer"], cost={"steel": 25, "ferrocrete": 10},
         workers={"hiver": 20}, colour="#3a4a6a", height=1.8)
building("cracking_tower", "Cracking Tower", "industry", "3x3",
         recipes=["crack_promethium"], cost={"steel": 60, "ferrocrete": 40, "machine_parts": 10, "ceramite": 5},
         workers={"hiver": 30, "adept": 5}, colour="#6a4a8a", height=4.0, buffer=12,
         ports=[(0, 0, "W", "in"), (0, 1, "W", "in"), (0, 2, "W", "in"),
                (2, 0, "E", "out"), (2, 2, "E", "out"), (1, 2, "S", "out")],
         description="Splits crude into fuel and polymer at once. Big, efficient, needs Adepts.")
building("plasteel_foundry", "Plasteel Foundry", "industry", "3x2",
         recipes=["bond_plasteel"], cost={"steel": 40, "ferrocrete": 20, "machine_parts": 5},
         workers={"hiver": 30}, colour="#9aa3aa", height=2.2)
building("propellant_works", "Propellant Works", "industry", "2x2",
         recipes=["mix_propellant"], cost={"steel": 25, "ferrocrete": 15},
         workers={"hiver": 20}, colour="#8a4a2a", height=1.6)
building("crystal_grinder", "Crystal Grinder", "industry", "2x1",
         recipes=["grind_crystal"], cost={"steel": 20, "machine_parts": 5},
         workers={"adept": 5, "hiver": 10}, colour="#8a2a2a", height=1.4)
building("slurry_vat", "Slurry Vat", "industry", "2x1",
         recipes=["render_slurry"], cost={"steel": 10, "ferrocrete": 5},
         workers={"menial": 15}, colour="#6a6a3a", height=1.2)
building("unguent_chapel", "Unguent Chapel", "industry", "2x1",
         recipes=["bless_unguents"], cost={"steel": 15, "glass": 5},
         workers={"adept": 5}, colour="#a3803a", height=1.8)
building("machine_shop", "Machine Shop", "industry", "2x2",
         recipes=["make_machine_parts"], cost={"steel": 30},
         workers={"hiver": 20}, colour="#7a6a4a", height=1.6,
         description="Spare parts keep every other building from decaying.")
building("cogitator_lab", "Cogitator Lab", "industry", "S",
         recipes=["etch_circuits"], cost={"steel": 30, "glass": 15, "machine_parts": 10},
         workers={"adept": 10}, colour="#2a6a4a", height=1.8,
         ports=[(1, 0, "N", "in"), (0, 1, "W", "in"), (2, 0, "E", "out")])
building("cell_plant", "Cell Plant", "industry", "2x2",
         recipes=["charge_cells"], cost={"steel": 30, "machine_parts": 5},
         workers={"hiver": 20}, colour="#2a4a8a", height=1.6)
building("casing_press", "Casing Press", "industry", "2x1",
         recipes=["press_casings"], cost={"steel": 20}, workers={"menial": 15}, colour="#8a7a2a", height=1.2)
building("ceramite_kiln", "Ceramite Kiln", "industry", "2x2",
         recipes=["fire_ceramite"], cost={"steel": 40, "ferrocrete": 30, "machine_parts": 10},
         workers={"adept": 10}, colour="#c9c3b0", height=2.0)

# Tithe manufactoria
building("lasgun_manufactorum", "Lasgun Manufactorum", "industry", "BIG_L",
         recipes=["assemble_lasgun"], cost={"steel": 60, "ferrocrete": 30, "machine_parts": 15, "plasteel": 10},
         workers={"hiver": 40, "adept": 5}, colour="#8a2a1a", height=2.6, buffer=12,
         ports=[(0, 0, "W", "in"), (0, 1, "W", "in"), (0, 2, "W", "in"), (0, 2, "S", "in"), (2, 1, "E", "out")])
building("power_pack_line", "Power Pack Line", "industry", "3x1",
         recipes=["fill_power_packs"], cost={"steel": 30, "machine_parts": 5},
         workers={"hiver": 20}, colour="#2a3a8a", height=1.4)
building("munitions_works", "Munitions Works", "industry", "2x3",
         recipes=["load_rounds"], cost={"steel": 40, "ferrocrete": 20},
         workers={"menial": 30, "hiver": 10}, colour="#8a6a1a", height=1.8)
building("flak_tailory", "Flak Tailory", "industry", "2x2",
         recipes=["stitch_flak"], cost={"steel": 25, "ferrocrete": 10},
         workers={"menial": 30}, colour="#4a5a3a", height=1.4)

# Civic goods
building("ration_press", "Ration Press", "civic", "2x1",
         recipes=["press_rations"], cost={"steel": 10},
         workers={"menial": 10}, colour="#8a7a4a", height=1.2)
building("recaf_roastery", "Recaf Roastery", "civic", "1x2",
         recipes=["roast_recaf"], cost={"steel": 10, "ferrocrete": 5},
         workers={"menial": 10}, colour="#4a2a1a", height=1.2)
building("amasec_distillery", "Amasec Distillery", "civic", "2x2",
         recipes=["distil_amasec"], cost={"steel": 20, "glass": 10},
         workers={"hiver": 15}, colour="#8a4a2a", height=1.8)
building("pict_workshop", "Pict Workshop", "civic", "2x2",
         recipes=["build_pict_screens"], cost={"steel": 25, "glass": 10, "machine_parts": 5},
         workers={"hiver": 15, "adept": 2}, colour="#2a2a4a", height=1.6)
building("icon_workshop", "Icon Workshop", "civic", "1x2",
         recipes=["cast_icons_scrap", "cast_icons_steel"], cost={"steel": 10},
         workers={"menial": 10}, colour="#a3903a", height=1.2)
building("enforcer_armoury", "Enforcer Armoury", "civic", "2x2",
         recipes=["issue_enforcer_kit"], cost={"steel": 30, "ferrocrete": 20},
         workers={"hiver": 15}, colour="#1a1a2a", height=1.6)

# Modules: placed touching a host, they use up space next to it (and can
# block its ports) in exchange for a bonus or an extra recipe.
building("machine_spirit_shrine", "Machine-Spirit Shrine", "module", "1x1", ports=[],
         cost={"steel": 5, "glass": 5}, colour="#c9a03a", height=1.6, decay=0.0,
         module_hosts=["industry", "extraction"], module_effects={"decay": 0.4},
         module_upkeep={"sacred_unguents": 0.5},
         description="Placates the host's machine spirit: decay x0.4. Burns sacred unguents.")
building("servitor_bay", "Servitor Bay", "module", "1x2", ports=[],
         cost={"steel": 20, "machine_parts": 5}, colour="#6a6a6a", height=1.0, decay=0.0,
         module_hosts=["industry", "extraction", "civic"], module_effects={"workers": 0.6},
         module_upkeep={"machine_parts": 0.5},
         description="Servitors replace 40% of the host's workers. Needs machine parts.")
building("overclock_coils", "Overclock Coils", "module", "1x1", ports=[],
         cost={"steel": 15, "copper_wire": 10}, colour="#3a6ab3", height=1.8, decay=0.0,
         module_hosts=["industry"], module_effects={"speed": 1.3, "decay": 2.0},
         module_upkeep={"power_cells": 0.5},
         description="Speed x1.3, decay x2. Drinks power cells.")
building("deep_bore_drill", "Deep Bore Drill", "module", "1x2", ports=[],
         cost={"steel": 25, "machine_parts": 5}, colour="#5a4030", height=2.2, decay=0.0,
         module_hosts=["deep_ore_mine", "open_quarry"], module_effects={"output": 1.5, "decay": 1.5},
         description="Mine output x1.5. Empties the deposit faster.")
building("warehouse", "Warehouse", "module", "1x2", ports=[],
         cost={"steel": 6, "ferrocrete": 10}, colour="#5a5a4a", height=1.0, decay=0.0,
         module_hosts=["industry", "extraction", "civic"], module_effects={"buffer": 2.0},
         description="Doubles the host's input and output buffers, so it rides out supply gaps. Fits any production building.")
building("fungal_mill", "Fungal Mill", "module", "1x2", ports=[],
         cost={"steel": 10, "ferrocrete": 5}, colour="#6a7a3a", height=1.2, decay=0.0,
         module_hosts=["ration_press"], module_recipes=["press_rations_direct"],
         description="Lets a Ration Press work raw biomass, skipping the Slurry Vat.")
building("polymer_still", "Polymer Still", "module", "2x1", ports=[],
         cost={"steel": 20, "ferrocrete": 10}, colour="#3a4a6a", height=1.8, decay=0.0,
         module_hosts=["plasteel_foundry"], module_recipes=["bond_plasteel_integrated"],
         description="Lets a Plasteel Foundry use crude promethium and coal instead of polymer.")
building("nickel_crucible", "Nickel Crucible", "module", "1x2", ports=[],
         cost={"steel": 20, "ferrocrete": 10, "machine_parts": 5}, colour="#a3ad8c", height=1.6, decay=0.0,
         module_hosts=["alloy_forge"], module_recipes=["forge_alloy_integrated"],
         description="Lets an Alloy Forge take raw nickel ore, skipping the Matte Smelter.")

# Drive modules. Every production building has its own, and runs only while at
# least one is attached. Each adds DRIVE_PER_MODULE to the building's speed, so
# two run it at full rate and more push it past that, up to its slot count.
# Module size grows with the host, so big industry sprawls like Anno farmland.
DRIVE_PER_MODULE = 0.5
DRIVE_MODULES = {
    # host id: (module id, name, description)
    "deep_ore_mine": ("grinder_rig", "Grinder Rig", "Crushing rig that drives the mine's bore."),
    "open_quarry": ("quarry_grinder", "Quarry Grinder", "Breaks quarried rock down for haulage."),
    "promethium_derrick": ("pump_jack", "Pump Jack", "Draws crude up the well."),
    "scavenger_post": ("salvage_sorter", "Salvage Sorter", "Sorting floor where scrap gangs strip the ruins."),
    "sump_pump": ("pump_turbine", "Pump Turbine", "Lifts sump water to the surface."),
    "fungal_vats": ("spore_tank", "Spore Tank", "Seeds and feeds the fungal culture."),
    "blast_furnace": ("bellows_house", "Bellows House", "Forces air into the furnace."),
    "matte_smelter": ("matte_converter", "Matte Converter", "Blows impurities out of the nickel melt."),
    "alloy_forge": ("forge_hammer", "Forge Hammer", "Steam hammer that works the alloy billets."),
    "rolling_mill": ("roller_stand", "Roller Stand", "A stand of rollers for the mill train."),
    "wire_drawer": ("drawing_bench", "Drawing Bench", "Pulls copper through the dies."),
    "glassworks": ("glass_furnace", "Glass Furnace", "Melts the batch for blowing and casting."),
    "ferrocrete_mixer": ("cement_drum", "Cement Drum", "Turns the aggregate and binder."),
    "water_filter": ("filter_bed", "Filter Bed", "Layers of charcoal and sand."),
    "promethium_refinery": ("fractionating_column", "Fractionating Column", "Separates the crude by weight."),
    "polymer_plant": ("reactor_vessel", "Reactor Vessel", "Pressure vessel for polymerisation."),
    "cracking_tower": ("catalyst_stack", "Catalyst Stack", "Catalyst beds that split the crude."),
    "plasteel_foundry": ("bonding_press", "Bonding Press", "Presses polymer into the hot steel."),
    "propellant_works": ("mixing_vat", "Mixing Vat", "Blends sulphur and coal."),
    "crystal_grinder": ("lapping_wheel", "Lapping Wheel", "Grinds focusing crystals to shape."),
    "slurry_vat": ("rendering_tank", "Rendering Tank", "Breaks biomass down to paste."),
    "unguent_chapel": ("blessing_font", "Blessing Font", "Where the oils are blessed in batches."),
    "machine_shop": ("lathe_bay", "Lathe Bay", "A bay of lathes and mills."),
    "cogitator_lab": ("etching_bath", "Etching Bath", "Acid baths for circuit plates."),
    "cell_plant": ("charge_rack", "Charge Rack", "Racks where cells take their charge."),
    "casing_press": ("stamping_press", "Stamping Press", "Stamps casings from steel strip."),
    "ceramite_kiln": ("kiln_chamber", "Kiln Chamber", "A firing chamber for ceramite plate."),
    "lasgun_manufactorum": ("assembly_line", "Assembly Line", "A line of benches and servitor arms."),
    "power_pack_line": ("cell_filler", "Cell Filler", "Seals cells into power-pack casings."),
    "munitions_works": ("loading_line", "Loading Line", "Fills and crimps the rounds."),
    "flak_tailory": ("stitching_floor", "Stitching Floor", "Rows of machinists layering flak."),
    "ration_press": ("press_line", "Press Line", "Moulds slurry into bricks."),
    "recaf_roastery": ("roasting_drum", "Roasting Drum", "Roasts the recaf beans."),
    "amasec_distillery": ("still_house", "Still House", "Copper stills for the spirit."),
    "pict_workshop": ("tube_bench", "Tube Bench", "Assembles screens and cathode tubes."),
    "icon_workshop": ("casting_pit", "Casting Pit", "Sand moulds for aquilas and saints."),
    "enforcer_armoury": ("armourers_bench", "Armourer's Bench", "Fits and tests enforcer kit."),
}


def add_drive_modules() -> None:
    for host_id, (mid, name, desc) in DRIVE_MODULES.items():
        host = next(b for b in B if b["id"] == host_id)
        n = len(host["cells"])
        shape = "1x1" if n <= 2 else ("1x2" if n <= 5 else "2x2")
        steel = max(4, int(host["cost"].get("steel", 0)) // 3)
        cost = {"steel": steel}
        if host["cost"].get("ferrocrete"):
            cost["ferrocrete"] = max(2, int(host["cost"]["ferrocrete"]) // 3)
        if host["cost"].get("machine_parts"):
            cost["machine_parts"] = max(1, int(host["cost"]["machine_parts"]) // 3)
        r, g, b_ = (int(host["colour"].lstrip("#")[i:i + 2], 16) for i in (0, 2, 4))
        colour = "#%02x%02x%02x" % (int(r * 0.75), int(g * 0.75), int(b_ * 0.75))
        building(mid, name, "module", shape, ports=[], cost=cost, colour=colour,
                 height=round(host["height"] * 0.65, 2), decay=0.0,
                 module_hosts=[host_id], module_effects={"drive": DRIVE_PER_MODULE},
                 description=f"{desc} Required by the {host['name']}: each one adds "
                             f"{int(DRIVE_PER_MODULE * 100)}% speed, two run it at full rate.")
        host["drive_module"] = mid


add_drive_modules()

# Services: the Fervour and Order levers (Comfort comes from caste comfort needs)
building("shrine", "Shrine", "service", "1x1",
         recipes=["hold_mass"], cost={"steel": 5, "ferrocrete": 10}, ports=[],
         workers={"menial": 2}, colour="#c9a03a", height=2.2,
         service_kind="fervour", service_capacity=300,
         description="Fervour: cheap and steady. Covers 300 citizens while supplied with icons.")
building("enforcer_precinct", "Enforcer Precinct", "service", "2x2",
         recipes=["patrol_district"], cost={"steel": 25, "ferrocrete": 30}, ports=[],
         workers={"hiver": 10}, colour="#2a2a3a", height=2.0,
         service_kind="order", service_capacity=500,
         description="Order: fast and reliable. Covers 500 citizens while supplied with kits.")


# ---------------------------------------------------------------------------
# Charters: what the Administratum permits the hive to build.
# The founding charter (cost 0) is owned from the start. Every other charter is
# bought with charters earned from tithes (two for full delivery, one for 75%+)
# and needs its prerequisites first. A production building's drive module comes
# with it automatically. networks: "walk", "road", "rail".
# ---------------------------------------------------------------------------
CHARTERS = [
    # id, name, tier, cost, prerequisites, buildings, networks, description
    ("founding", "Founding Charter", 0, 0, [],
     ["administratum_bastion", "district_depot", "slum_stack", "sump_pump", "water_filter",
      "fungal_vats", "slurry_vat", "ration_press", "deep_ore_mine", "blast_furnace",
      "scavenger_post", "open_quarry", "ferrocrete_mixer", "warehouse"],
     ["walk", "road"],
     "Housing, food, water, and the steel and ferrocrete to build more of them."),

    ("ferrocrete_housing", "Ferrocrete Housing", 1, 1, [], ["ferrocrete_block"], [],
     "Upgrade slum stacks into ferrocrete blocks that house twice as many."),
    ("devotion", "Ecclesiarchy Writ", 1, 1, [], ["icon_workshop", "shrine"], [],
     "Shrines and the icon workshops that supply them: the Fervour lever."),
    ("recaf", "Recaf Licence", 1, 1, [], ["recaf_roastery"], [],
     "Recaf, the first comfort good for menials and hivers."),
    ("glass", "Glassworking", 1, 1, [], ["glassworks"], [],
     "Glass for windows, lenses and screens."),
    ("hiver_quarters", "Hiver Quarters", 1, 1, [], ["hiver_tenement"], [],
     "Housing for hivers, the skilled caste most factories need."),
    ("cargo_rail", "Cargo Rail", 1, 1, [], ["cargo_station"], ["rail"],
     "Cargo rail and stations for fast freight between districts."),
    ("workshops", "Workshops", 1, 1, ["hiver_quarters"], ["machine_shop", "wire_drawer"], [],
     "Machine parts for repairs, and copper wire."),
    ("promethium", "Promethium Rights", 1, 1, ["hiver_quarters"],
     ["promethium_derrick", "promethium_refinery"], [],
     "Pump and refine promethium, a tithe staple."),

    ("integrated_milling", "Integrated Milling", 2, 1, [], ["fungal_mill"], [],
     "A mill module that lets a ration press work raw biomass."),
    ("polymers", "Polymer Chemistry", 2, 2, ["promethium"], ["polymer_plant"], [],
     "Plastics from promethium and coal."),
    ("plasteel", "Plasteel Foundries", 2, 2, ["polymers", "ferrocrete_housing"],
     ["plasteel_foundry", "hab_stack"], [],
     "Plasteel, a tithe good, and the hab stacks built from it."),
    ("hiver_blocks", "Hiver Blocks", 2, 2, ["hiver_quarters", "glass"], ["hiver_block"], [],
     "Upgrade hiver tenements into blocks of 120."),
    ("advanced_steel", "Advanced Metallurgy", 2, 2, ["workshops"],
     ["matte_smelter", "alloy_forge", "rolling_mill"], [],
     "The three-step alloy route: three times the steel per ore."),
    ("munitions", "Munitions", 2, 2, ["hiver_quarters"],
     ["casing_press", "propellant_works", "munitions_works"], [],
     "Autogun rounds for the tithe."),
    ("flak", "Flak Armour", 2, 2, ["polymers"], ["flak_tailory"], [],
     "Layered flak armour for the tithe."),
    ("power_cells", "Power Cells", 2, 2, ["workshops", "promethium"], ["cell_plant"], [],
     "Charged cells for weapons, kits and coils."),
    ("scribes", "Scriptorium", 2, 2, ["glass"], ["scribe_quarters"], [],
     "Housing for scribes, the clerical caste."),
    ("servitors", "Servitor Licence", 2, 2, ["workshops"], ["servitor_bay", "deep_bore_drill"], [],
     "Servitor bays that cut crews, and deep bore drills for mines."),
    ("amasec", "Amasec Distilling", 2, 2, ["glass", "scribes"], ["amasec_distillery"], [],
     "Amasec, a comfort good for the upper castes."),
    ("onsite_crucibles", "Onsite Crucibles", 2, 2, ["advanced_steel"], ["nickel_crucible"], [],
     "A crucible module that lets an alloy forge take raw nickel ore."),
    ("overclocking", "Overclocking", 2, 2, ["power_cells"], ["overclock_coils"], [],
     "Coils that run industry faster and harder."),

    ("enforcers", "Arbites Mandate", 3, 3, ["power_cells"], ["enforcer_armoury", "enforcer_precinct"], [],
     "Enforcer precincts and the armouries that kit them: the Order lever."),
    ("cogitators", "Cogitator Engines", 3, 3, ["glass", "workshops", "scribes"],
     ["cogitator_lab", "pict_workshop"], [],
     "Logic boards, and the pict screens built from them."),
    ("lasguns", "Lasgun Pattern", 3, 3, ["power_cells", "plasteel"],
     ["crystal_grinder", "power_pack_line", "lasgun_manufactorum"], [],
     "Lasguns and power packs, the heart of the tithe."),
    ("mechanicus", "Mechanicus Enclave", 3, 3, ["workshops", "promethium"],
     ["forge_cloister", "forge_sanctum", "unguent_chapel", "ceramite_kiln", "machine_spirit_shrine"], [],
     "Adept housing, sacred unguents, ceramite and machine-spirit shrines."),
    ("integrated_plasteel", "Integrated Plasteel", 3, 2, ["plasteel"], ["polymer_still"], [],
     "A still module that lets a plasteel foundry skip the polymer plant."),
    ("spire_housing", "Spire Housing", 3, 3, ["plasteel", "hiver_blocks", "scribes"],
     ["hiver_spire", "scribe_manse"], [],
     "The top housing tiers for hivers and scribes."),
    ("cracking", "Catalytic Cracking", 3, 3, ["polymers", "mechanicus"], ["cracking_tower"], [],
     "Split crude into fuel and polymer at once."),
]


def write_charters(out: str) -> None:
    for i, (cid, name, tier, cost, pre, blds, nets, desc) in enumerate(CHARTERS):
        text = header("CharterDef", "res://scripts/data/charter_def.gd")
        text += f"id = {gd_sname(cid)}\n"
        text += f"display_name = {gd_str(name)}\n"
        text += f"tier = {tier}\n"
        text += f"cost = {cost}\n"
        text += f"sort_order = {i}\n"
        text += "prerequisites = Array[StringName]([" + ", ".join(gd_sname(x) for x in pre) + "])\n"
        all_b = list(blds)
        for bid in blds:
            host = next(b for b in B if b["id"] == bid)
            if host["drive_module"]:
                all_b.append(host["drive_module"])
        text += "buildings = Array[StringName]([" + ", ".join(gd_sname(x) for x in all_b) + "])\n"
        text += "networks = Array[StringName]([" + ", ".join(gd_sname(x) for x in nets) + "])\n"
        text += f"description = {gd_str(desc)}\n"
        write(os.path.join(out, f"{cid}.tres"), text)


def check_charters() -> None:
    ids = [c[0] for c in CHARTERS]
    assert len(ids) == len(set(ids)), "duplicate charter id"
    assert [c for c in CHARTERS if c[3] == 0] == [CHARTERS[0]], "only the founding charter may be free"
    drive_ids = {b["drive_module"] for b in B if b["drive_module"]}
    seen = {}
    for cid, name, tier, cost, pre, blds, nets, desc in CHARTERS:
        for p_ in pre:
            assert p_ in ids and ids.index(p_) < ids.index(cid), f"charter {cid}: bad prerequisite {p_}"
        for bid in blds:
            assert any(b["id"] == bid for b in B), f"charter {cid}: unknown building {bid}"
            assert bid not in drive_ids, f"charter {cid}: list the host, not its drive module {bid}"
            assert bid not in seen, f"{bid} is in both {seen.get(bid)} and {cid}"
            seen[bid] = cid
        for n in nets:
            assert n in ("walk", "road", "rail"), f"charter {cid}: unknown network {n}"
    for b in B:
        if b["id"] not in drive_ids:
            assert b["id"] in seen, f"building {b['id']} is in no charter"


# ---------------------------------------------------------------------------
# .tres writers
# ---------------------------------------------------------------------------
SIDE = {"N": (0, -1), "E": (1, 0), "S": (0, 1), "W": (-1, 0)}


def gd_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def gd_sname(s: str) -> str:
    return "&" + gd_str(s)


def gd_dict(d: dict, value_fmt=lambda v: repr(v)) -> str:
    if not d:
        return "{}"
    parts = [f"{gd_sname(k)}: {value_fmt(v)}" for k, v in d.items()]
    return "{\n" + ",\n".join(parts) + "\n}"


def gd_num(v) -> str:
    if isinstance(v, float):
        return repr(v)
    return str(v)


def gd_colour(hex_str: str) -> str:
    h = hex_str.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    return f"Color({r:.4f}, {g:.4f}, {b:.4f}, 1)"


def header(script_class: str, script_path: str) -> str:
    return (f'[gd_resource type="Resource" script_class="{script_class}" load_steps=2 format=3]\n\n'
            f'[ext_resource type="Script" path="{script_path}" id="1_script"]\n\n'
            f'[resource]\nscript = ExtResource("1_script")\n')


def write(path: str, text: str) -> None:
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def write_items(out: str) -> None:
    for i, (iid, name, tier, cat, tithe, col, desc) in enumerate(ITEMS):
        text = header("ItemDef", "res://scripts/data/item_def.gd")
        text += f"id = {gd_sname(iid)}\n"
        text += f"display_name = {gd_str(name)}\n"
        text += f"tier = {tier}\n"
        text += f"category = {gd_sname(cat)}\n"
        text += f"tithe_base = {tithe}\n"
        text += f"sort_order = {i}\n"
        text += f"colour = {gd_colour(col)}\n"
        text += f"description = {gd_str(desc)}\n"
        write(os.path.join(out, f"{iid}.tres"), text)


def write_recipes(out: str) -> None:
    for rid, name, inputs, outputs, duration, deposit in RECIPES:
        text = header("RecipeDef", "res://scripts/data/recipe_def.gd")
        text += f"id = {gd_sname(rid)}\n"
        text += f"display_name = {gd_str(name)}\n"
        text += f"inputs = {gd_dict(inputs)}\n"
        text += f"outputs = {gd_dict(outputs)}\n"
        text += f"duration = {float(duration)!r}\n"
        text += f"deposit = {gd_sname(deposit)}\n"
        write(os.path.join(out, f"{rid}.tres"), text)


def write_castes(out: str) -> None:
    for i, (cid, name, col, basic, comfort) in enumerate(CASTES):
        text = header("CasteDef", "res://scripts/data/caste_def.gd")
        text += f"id = {gd_sname(cid)}\n"
        text += f"display_name = {gd_str(name)}\n"
        text += f"sort_order = {i}\n"
        text += f"colour = {gd_colour(col)}\n"
        text += f"basic_needs = {gd_dict(basic, gd_num)}\n"
        text += f"comfort_needs = {gd_dict(comfort, gd_num)}\n"
        write(os.path.join(out, f"{cid}.tres"), text)


def write_buildings(out: str) -> None:
    for i, b in enumerate(B):
        cells = ", ".join(f"Vector2i({x}, {y})" for x, y in b["cells"])
        ports = ",\n".join(
            "{" + f'"cell": Vector2i({x}, {y}), "dir": Vector2i({SIDE[s][0]}, {SIDE[s][1]}), '
            f'"kind": {0 if k == "in" else 1}' + "}"
            for x, y, s, k in b["ports"])
        recipes = ", ".join(gd_sname(r) for r in b["recipes"])
        text = header("BuildingDef", "res://scripts/data/building_def.gd")
        text += f"id = {gd_sname(b['id'])}\n"
        text += f"display_name = {gd_str(b['name'])}\n"
        text += f"category = {gd_sname(b['category'])}\n"
        text += f"sort_order = {i}\n"
        text += f"description = {gd_str(b['description'])}\n"
        text += f"cells = Array[Vector2i]([{cells}])\n"
        text += f"ports = [{ports}]\n" if ports else "ports = []\n"
        text += f"recipes = Array[StringName]([{recipes}])\n"
        text += f"build_cost = {gd_dict(b['cost'])}\n"
        text += f"workers = {gd_dict(b['workers'])}\n"
        text += f"buffer_capacity = {b['buffer']}\n"
        text += f"colour = {gd_colour(b['colour'])}\n"
        text += f"height = {float(b['height'])!r}\n"
        text += f"housing_caste = {gd_sname(b['housing_caste'])}\n"
        text += f"housing_capacity = {b['housing_capacity']}\n"
        text += f"upgrade_to = {gd_sname(b['upgrade_to'])}\n"
        text += f"upgrade_cost = {gd_dict(b['upgrade_cost'])}\n"
        text += f"logistics_capacity = {float(b['logistics'])!r}\n"
        text += f"decay_per_minute = {float(b['decay'])!r}\n"
        text += f"service_kind = {gd_sname(b['service_kind'])}\n"
        text += f"service_capacity = {b['service_capacity']}\n"
        text += f"needs_deposit = {'true' if b['needs_deposit'] else 'false'}\n"
        text += f"module_slots = {b['module_slots']}\n"
        hosts = ", ".join(gd_sname(h) for h in b["module_hosts"])
        text += f"module_hosts = Array[StringName]([{hosts}])\n"
        text += f"module_effects = {gd_dict(b['module_effects'], gd_num)}\n"
        text += f"module_upkeep = {gd_dict(b['module_upkeep'], gd_num)}\n"
        mrec = ", ".join(gd_sname(r) for r in b["module_recipes"])
        text += f"module_recipes = Array[StringName]([{mrec}])\n"
        text += f"is_depot = {'true' if b['is_depot'] else 'false'}\n"
        text += f"station_capacity = {float(b['station_capacity'])!r}\n"
        text += f"drive_module = {gd_sname(b['drive_module'])}\n"
        write(os.path.join(out, f"{b['id']}.tres"), text)


def check() -> None:
    item_ids = {i[0] for i in ITEMS}
    assert len(item_ids) == len(ITEMS), "duplicate item id"
    for r in RECIPES:
        for k in list(r[2]) + list(r[3]):
            assert k in item_ids, f"recipe {r[0]} uses unknown item {k}"
        if r[5]:
            assert r[5] in item_ids, f"recipe {r[0]} unknown deposit {r[5]}"
    for c in CASTES:
        for k in list(c[3]) + list(c[4]):
            assert k in item_ids, f"caste {c[0]} needs unknown item {k}"
    building_ids = {b["id"] for b in B}
    assert len(building_ids) == len(B), "duplicate building id"
    caste_ids = {c[0] for c in CASTES}
    for b in B:
        for r in b["recipes"]:
            assert r in RECIPE_BY_ID, f"building {b['id']} unknown recipe {r}"
        for k in list(b["cost"]) + list(b["upgrade_cost"]):
            assert k in item_ids, f"building {b['id']} unknown cost item {k}"
        for k in b["workers"]:
            assert k in caste_ids, f"building {b['id']} unknown caste {k}"
        if b["upgrade_to"]:
            target = next((t for t in B if t["id"] == b["upgrade_to"]), None)
            assert target, f"{b['id']} upgrades to unknown {b['upgrade_to']}"
            assert sorted(target["cells"]) == sorted(b["cells"]), f"{b['id']} upgrade changes footprint"
        cellset = set(b["cells"])
        for x, y, s, k in b["ports"]:
            assert (x, y) in cellset, f"{b['id']} port off footprint at {(x, y)}"
            dx, dy = SIDE[s]
            assert (x + dx, y + dy) not in cellset, f"{b['id']} port at {(x, y)} faces inward"
    categories = {b["category"] for b in B}
    for b in B:
        for h in b["module_hosts"]:
            assert h in building_ids or h in categories, f"module {b['id']} unknown host {h}"
        for r in b["module_recipes"]:
            assert r in RECIPE_BY_ID, f"module {b['id']} unknown recipe {r}"
        for k in b["module_upkeep"]:
            assert k in item_ids, f"module {b['id']} unknown upkeep item {k}"
        for k in b["module_effects"]:
            assert k in ("speed", "output", "decay", "workers", "buffer", "drive"), f"module {b['id']} bad effect {k}"
        if b["category"] == "module":
            assert b["module_hosts"], f"module {b['id']} has no hosts"
    for b in B:
        if b["category"] in PRODUCTION:
            assert b["drive_module"], f"production building {b['id']} has no drive module"
    # every item is produced somewhere (raws by extraction)
    produced = {k for r in RECIPES for k in r[3]}
    missing = item_ids - produced
    assert not missing, f"items with no recipe producing them: {missing}"


def main() -> None:
    check()
    check_charters()
    for sub, fn in (("items", write_items), ("recipes", write_recipes),
                    ("castes", write_castes), ("buildings", write_buildings),
                    ("charters", write_charters)):
        out = os.path.join(DATA, sub)
        if os.path.isdir(out):
            shutil.rmtree(out)
        os.makedirs(out)
        fn(out)
    raws = sum(1 for i in ITEMS if i[2] == 0)
    print(f"Wrote {len(ITEMS)} items ({raws} raw), {len(RECIPES)} recipes, "
          f"{len(B)} buildings, {len(CASTES)} castes, {len(CHARTERS)} charters to {DATA}")


if __name__ == "__main__":
    main()
