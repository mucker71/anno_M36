extends Node
## Headless test suite. Run from the project folder with:
##   godot --headless res://tests/test_runner.tscn
## Exits with code 0 on success, 1 on any failure.

var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	var tests := [
		test_data_counts,
		test_data_references,
		test_footprints_valid,
		test_rotation_round_trip,
		test_rotated_ports_face_out,
		test_grid_placement,
		test_port_linking,
		test_direct_link_transfer,
		test_extraction_chain_runs,
		test_deposit_depletes,
		test_maintenance_uses_parts,
		test_tithe_first_cycle,
		test_terrain_generation,
	]
	for t in tests:
		var before := _failures.size()
		t.call()
		var tname: String = t.get_method()
		print(("  ok   " if _failures.size() == before else "  FAIL ") + tname)
	print("%d checks, %d failures" % [_checks, _failures.size()])
	for f in _failures:
		printerr("    " + f)
	get_tree().quit(0 if _failures.is_empty() else 1)


func check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failures.append(msg)


# --- Helpers ------------------------------------------------------------------

func flat_world(size := Vector2i(24, 24)) -> Dictionary:
	var terrain := TerrainData.new(size)
	for y in size.y:
		for x in size.x:
			terrain.set_tile(Vector2i(x, y), TerrainData.Tile.GROUND, 0)
	var deposits := DepositMap.new()
	var grid := BuildGrid.new(terrain, deposits)
	var economy := Economy.new(grid, deposits)
	return {"terrain": terrain, "deposits": deposits, "grid": grid, "economy": economy}


func rect_cells(origin: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			out.append(origin + Vector2i(x, y))
	return out


func run(economy: Economy, seconds: float) -> void:
	var steps := int(seconds / Economy.STEP)
	for i in steps:
		economy.step(Economy.STEP)


# --- Data ---------------------------------------------------------------------

func test_data_counts() -> void:
	var raws := 0
	for def in Database.items.values():
		if def.tier == ItemDef.Tier.RAW:
			raws += 1
	check(raws == 12, "expected 12 raw items, got %d" % raws)
	check(Database.items.size() >= 38 and Database.items.size() <= 44,
		"expected about 40 items, got %d" % Database.items.size())
	check(Database.castes.size() == 4, "expected 4 castes")
	check(Database.building(&"administratum_bastion") != null, "missing bastion")


func test_data_references() -> void:
	for r in Database.recipes.values():
		for item in r.inputs.keys() + r.outputs.keys():
			check(Database.item(item) != null, "recipe %s uses unknown item %s" % [r.id, item])
	for b in Database.buildings.values():
		for rid in b.recipes:
			check(Database.recipe(rid) != null, "building %s has unknown recipe %s" % [b.id, rid])
		for item in b.build_cost:
			check(Database.item(item) != null, "building %s costs unknown item %s" % [b.id, item])
		for c in b.workers:
			check(Database.caste(c) != null, "building %s needs unknown caste %s" % [b.id, c])
		if b.upgrade_to != &"":
			var up := Database.building(b.upgrade_to)
			check(up != null, "%s upgrades to unknown %s" % [b.id, b.upgrade_to])
			if up:
				check(up.housing_caste == b.housing_caste, "%s upgrade changes caste" % b.id)
				check(up.housing_capacity > b.housing_capacity, "%s upgrade does not add capacity" % b.id)


func test_footprints_valid() -> void:
	for b in Database.buildings.values():
		check(Footprint.is_single_piece(b.cells), "%s footprint is not one piece" % b.id)
		check(Footprint.has_no_holes(b.cells), "%s footprint has a hole" % b.id)
	# The hole check itself: a ring must fail.
	var ring: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1),
		Vector2i(2, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)]
	check(not Footprint.has_no_holes(ring), "hole check missed a ring")


func test_rotation_round_trip() -> void:
	for b in Database.buildings.values():
		var cells := Footprint.rotated_cells(b.cells, 4)
		var a: Array[Vector2i] = b.cells.duplicate()
		a.sort()
		cells.sort()
		check(a == cells, "%s does not survive four rotations" % b.id)


func test_rotated_ports_face_out() -> void:
	for b in Database.buildings.values():
		for r in 4:
			var cells := Footprint.rotated_cells(b.cells, r)
			var lookup := {}
			for c in cells:
				lookup[c] = true
			for p in Footprint.rotated_ports(b.cells, b.ports, r):
				check(lookup.has(p["cell"]), "%s r%d port off footprint" % [b.id, r])
				check(not lookup.has(p["cell"] + p["dir"]), "%s r%d port faces inward" % [b.id, r])


# --- Grid ---------------------------------------------------------------------

func test_grid_placement() -> void:
	var w := flat_world()
	var grid: BuildGrid = w["grid"]
	var furnace := Database.building(&"blast_furnace")
	var a := grid.place(furnace, Vector2i(2, 2), 0)
	check(a != null, "furnace placement failed")
	check(grid.place(furnace, Vector2i(3, 3), 0) == null, "overlapping placement allowed")
	check(grid.place(furnace, Vector2i(23, 23), 0) == null, "out of bounds placement allowed")
	check(grid.building_at(Vector2i(3, 3)) == a, "occupancy lookup wrong")
	var mine := Database.building(&"deep_ore_mine")
	check(not grid.check_placement(mine, Vector2i(10, 10), 0)["ok"], "mine allowed off a deposit")
	grid.remove(a)
	check(grid.building_at(Vector2i(3, 3)) == null, "removal left cells occupied")
	var terrain: TerrainData = w["terrain"]
	terrain.set_tile(Vector2i(15, 15), TerrainData.Tile.MOUNTAIN, 2)
	check(grid.place(furnace, Vector2i(14, 14), 0) == null, "placement on a mountain allowed")


func test_port_linking() -> void:
	var w := flat_world()
	var grid: BuildGrid = w["grid"]
	# Furnace outputs face east from x=1; foundry inputs face west at x=2.
	var furnace := grid.place(Database.building(&"blast_furnace"), Vector2i(0, 0), 0)
	var foundry := grid.place(Database.building(&"plasteel_foundry"), Vector2i(2, 0), 0)
	check(furnace.links_out.has(foundry), "adjacent output/input ports did not link")
	check(not foundry.links_out.has(furnace), "link created in the wrong direction")
	# Turned around, the foundry's inputs face away: no link.
	grid.remove(foundry)
	var turned := grid.place(Database.building(&"plasteel_foundry"), Vector2i(2, 0), 2)
	check(turned != null and not furnace.links_out.has(turned), "back-to-front ports linked")


func test_direct_link_transfer() -> void:
	var w := flat_world()
	var grid: BuildGrid = w["grid"]
	var economy: Economy = w["economy"]
	var furnace := grid.place(Database.building(&"blast_furnace"), Vector2i(0, 0), 0)
	var foundry := grid.place(Database.building(&"plasteel_foundry"), Vector2i(2, 0), 0)
	furnace.output_buffer[&"steel"] = 4
	var left := economy._push_outputs(furnace, 0.0)   # no logistics budget at all
	check(int(foundry.input_buffer.get(&"steel", 0)) == 4, "linked steel did not reach the foundry")
	check(is_equal_approx(left, 0.0), "direct link spent logistics")
	check(economy.amount(&"steel") == 0, "linked steel went to the stockpile")


# --- Economy ------------------------------------------------------------------

func _chain_world() -> Dictionary:
	var w := flat_world(Vector2i(32, 32))
	var grid: BuildGrid = w["grid"]
	var deposits: DepositMap = w["deposits"]
	var economy: Economy = w["economy"]
	deposits.add_cluster(&"iron_ore", rect_cells(Vector2i(2, 2), Vector2i(2, 2)), 200)
	deposits.add_cluster(&"coal", rect_cells(Vector2i(6, 2), Vector2i(2, 2)), 200)
	grid.place(Database.building(&"administratum_bastion"), Vector2i(20, 20), 0)
	grid.place(Database.building(&"slum_stack"), Vector2i(10, 10), 0)
	grid.place(Database.building(&"slum_stack"), Vector2i(13, 10), 0)
	w["iron_mine"] = grid.place(Database.building(&"deep_ore_mine"), Vector2i(2, 2), 0)
	w["coal_mine"] = grid.place(Database.building(&"deep_ore_mine"), Vector2i(6, 2), 0)
	w["furnace"] = grid.place(Database.building(&"blast_furnace"), Vector2i(2, 8), 0)
	economy.add(&"ration_bricks", 500)
	economy.add(&"purified_water", 500)
	return w


func test_extraction_chain_runs() -> void:
	var w := _chain_world()
	var economy: Economy = w["economy"]
	var iron: BuildingInstance = w["iron_mine"]
	check(iron != null and iron.recipe != null and iron.recipe.id == &"extract_iron_ore",
		"mine did not pick the iron recipe from its deposit")
	run(economy, 120.0)
	check(int(economy.produced_total.get(&"steel", 0)) > 0, "no steel produced in 120s")
	check(economy.amount(&"steel") > 0, "steel never reached the stockpile")
	check(float(economy.staffing.get(&"menial", 0.0)) > 0.9, "menials not staffing the chain")


func test_deposit_depletes() -> void:
	var w := _chain_world()
	var economy: Economy = w["economy"]
	var deposits: DepositMap = w["deposits"]
	var iron: BuildingInstance = w["iron_mine"]
	run(economy, 600.0)
	var cl := deposits.get_cluster(iron.deposit_cluster)
	check(cl.remaining == 0, "iron deposit not exhausted after 600s (left %d)" % cl.remaining)
	economy.step(Economy.STEP)
	check(iron.status == BuildingInstance.Status.DEPOSIT_EXHAUSTED, "mine did not report exhaustion")


func test_maintenance_uses_parts() -> void:
	var w := _chain_world()
	var economy: Economy = w["economy"]
	var furnace: BuildingInstance = w["furnace"]
	furnace.condition = 50.0
	economy.add(&"machine_parts", 3)
	economy.step(Economy.STEP)
	check(furnace.condition > 70.0, "low condition was not repaired")
	check(economy.amount(&"machine_parts") < 3, "repair did not use a machine part")


func test_tithe_first_cycle() -> void:
	var w := flat_world()
	var economy: Economy = w["economy"]
	var tithe := TitheManager.new(economy, 1234)
	check(tithe.cycle == 1, "tithe did not start at cycle 1")
	check(tithe.quota.keys() == [&"steel"], "first tithe should be steel only, got %s" % [tithe.quota])
	economy.add(&"steel", 10000)
	var favour := tithe.favour
	tithe.resolve()
	check(tithe.favour > favour, "full delivery did not raise favour")
	tithe.advance(TitheManager.CYCLE_LENGTH + 1.0)
	check(tithe.cycle >= 2, "tithe did not roll over")


# --- World generation ---------------------------------------------------------

func test_terrain_generation() -> void:
	var size := Vector2i(160, 160)
	var a := TerrainGenerator.generate(size, 42)
	var b := TerrainGenerator.generate(size, 42)
	check(a.tiles == b.tiles, "terrain is not deterministic for a seed")
	var centre := size / 2
	for y in range(-5, 6):
		for x in range(-5, 6):
			check(a.is_buildable(centre + Vector2i(x, y)), "start area not clear at %s" % [centre + Vector2i(x, y)])
	var ground := 0
	for t in a.tiles:
		if t == TerrainData.Tile.GROUND:
			ground += 1
	var share := float(ground) / a.tiles.size()
	check(share > 0.6, "too little buildable ground (%d%%)" % int(share * 100))
	var deposits := DepositScatter.scatter(a, 42)
	var kinds := {}
	for cl in deposits.clusters:
		kinds[cl.item] = true
		for c in cl.cells:
			check(a.is_buildable(c), "deposit on unbuildable tile")
	check(kinds.size() == DepositScatter.SPECS.size(), "some deposit types missing: %s" % [kinds.keys()])
	var mesh := TerrainMesh.build(a, deposits)
	check(mesh != null and mesh.get_surface_count() == 1, "terrain mesh not built")
