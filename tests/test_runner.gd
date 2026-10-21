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
		test_district_rules,
		test_port_linking,
		test_direct_link_transfer,
		test_transport_rules,
		test_transport_paths,
		test_extraction_chain_runs,
		test_road_access_required,
		test_housing_needs_market,
		test_commute_range,
		test_deposit_depletes,
		test_maintenance_uses_parts,
		test_freight_road_and_rail,
		test_modules_attach_and_slots,
		test_module_effects,
		test_module_recipe_and_upkeep,
		test_tithe_first_cycle,
		test_worker_scale,
		test_drive_required,
		test_unlocks,
		test_founding_threshold,
		test_quota_only_producible,
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

## A flat map with one district covering everything.
func flat_world(size := Vector2i(24, 24)) -> Dictionary:
	var terrain := TerrainData.new(size)
	for y in size.y:
		for x in size.x:
			terrain.set_tile(Vector2i(x, y), TerrainData.Tile.GROUND, 0)
	var deposits := DepositMap.new()
	var transport := TransportGrid.new(terrain)
	var districts := DistrictMap.new(size)
	var home := districts.create()
	districts.paint(rect_cells(Vector2i.ZERO, size), home.id)
	var grid := BuildGrid.new(terrain, deposits, transport, districts)
	var economy := Economy.new(grid, deposits)
	return {"terrain": terrain, "deposits": deposits, "grid": grid, "economy": economy,
		"transport": transport, "districts": districts, "home": home}


func rect_cells(origin: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			out.append(origin + Vector2i(x, y))
	return out


func lay(transport: TransportGrid, cells: Array[Vector2i], net: int) -> void:
	var masks := {}
	for c in cells:
		var ch := transport.check_add(c, net)
		if ch["ok"]:
			masks[c] = ch["mask"]
	transport.set_masks(masks)


## Places a module touching host, at the first spot (scanning outward) where
## it attaches to that host without covering one of the host's ports.
func attach(grid: BuildGrid, host: BuildingInstance, module_id: StringName) -> BuildingInstance:
	var def := Database.building(module_id)
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for c in host.cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var port_cells := {}
	for p in host.ports:
		port_cells[p["cell"] + p["dir"]] = true
	# First pass keeps the host's ports clear; the second accepts covering one.
	for allow_blocking in [false, true]:
		for r in 4:
			for y in range(lo.y - 3, hi.y + 3):
				for x in range(lo.x - 3, hi.x + 3):
					var check := grid.check_placement(def, Vector2i(x, y), r)
					if not check["ok"] or check["host"] != host:
						continue
					var blocks := false
					for c in check["cells"]:
						if port_cells.has(c):
							blocks = true
					if allow_blocking or not blocks:
						return grid.place(def, Vector2i(x, y), r)
	return null


## Attaches n of the host's own drive module.
func drive(grid: BuildGrid, host: BuildingInstance, n: int = 2) -> void:
	for i in n:
		check(attach(grid, host, host.def.drive_module) != null,
			"could not attach drive module %d to %s" % [i + 1, host.def.id])


func run(economy: Economy, seconds: float) -> void:
	for i in int(seconds / Economy.STEP):
		economy.step(Economy.STEP)


## Bastion, five slums, two mines and a furnace (each with two drive modules),
## all on one road: along y = 10, and up x = 19 to the Bastion at (20, 20).
func chain_world() -> Dictionary:
	var w := flat_world(Vector2i(48, 48))
	var grid: BuildGrid = w["grid"]
	var deposits: DepositMap = w["deposits"]
	var economy: Economy = w["economy"]
	var transport: TransportGrid = w["transport"]
	deposits.add_cluster(&"iron_ore", rect_cells(Vector2i(2, 8), Vector2i(2, 2)), 200)
	deposits.add_cluster(&"coal", rect_cells(Vector2i(6, 8), Vector2i(2, 2)), 200)
	lay(transport, rect_cells(Vector2i(0, 10), Vector2i(32, 1)), TransportGrid.Net.ROAD)
	lay(transport, rect_cells(Vector2i(19, 11), Vector2i(1, 10)), TransportGrid.Net.ROAD)
	w["bastion"] = grid.place(Database.building(&"administratum_bastion"), Vector2i(20, 20), 0)
	w["slum_a"] = grid.place(Database.building(&"slum_stack"), Vector2i(12, 11), 0)
	w["slum_b"] = grid.place(Database.building(&"slum_stack"), Vector2i(15, 11), 0)
	for x in [26, 29, 32]:
		grid.place(Database.building(&"slum_stack"), Vector2i(x, 11), 0)
	w["iron_mine"] = grid.place(Database.building(&"deep_ore_mine"), Vector2i(2, 8), 0)
	w["coal_mine"] = grid.place(Database.building(&"deep_ore_mine"), Vector2i(6, 8), 0)
	w["furnace"] = grid.place(Database.building(&"blast_furnace"), Vector2i(10, 8), 0)
	for key in ["iron_mine", "coal_mine", "furnace"]:
		drive(grid, w[key], 2)
	var home: DistrictMap.District = w["home"]
	home.add(&"ration_bricks", 500)
	home.add(&"purified_water", 500)
	economy.step(Economy.STEP)
	return w


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
	check(Database.building(&"administratum_bastion").is_depot, "bastion is not a depot")
	var modules := 0
	for b in Database.buildings.values():
		if b.is_module():
			modules += 1
	check(modules >= 6, "expected at least 6 modules, got %d" % modules)


func test_data_references() -> void:
	for r in Database.recipes.values():
		for item in r.inputs.keys() + r.outputs.keys():
			check(Database.item(item) != null, "recipe %s uses unknown item %s" % [r.id, item])
	for b in Database.buildings.values():
		for rid in b.recipes + b.module_recipes:
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
		if b.is_module():
			var any_host := false
			for h in Database.buildings.values():
				if b.accepts_host(h):
					any_host = true
			check(any_host, "module %s has no possible host" % b.id)


func test_footprints_valid() -> void:
	for b in Database.buildings.values():
		check(Footprint.is_single_piece(b.cells), "%s footprint is not one piece" % b.id)
		check(Footprint.has_no_holes(b.cells), "%s footprint has a hole" % b.id)
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


# --- Grid and districts ---------------------------------------------------------

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


func test_district_rules() -> void:
	var w := flat_world()
	var grid: BuildGrid = w["grid"]
	var districts: DistrictMap = w["districts"]
	var furnace := Database.building(&"blast_furnace")
	districts.paint(rect_cells(Vector2i(10, 0), Vector2i(14, 24)), -1)   # unpaint the right side
	check(grid.check_placement(furnace, Vector2i(12, 2), 0)["reason"] == "Must sit inside one district",
		"placement allowed outside any district")
	var second := districts.create()
	districts.paint(rect_cells(Vector2i(10, 0), Vector2i(14, 24)), second.id)
	check(grid.check_placement(furnace, Vector2i(9, 2), 0)["reason"] == "Must sit inside one district",
		"placement allowed across two districts")
	var b := grid.place(furnace, Vector2i(12, 2), 0)
	check(b != null and b.district_id == second.id, "building not assigned to its district")


func test_port_linking() -> void:
	var w := flat_world()
	var grid: BuildGrid = w["grid"]
	var furnace := grid.place(Database.building(&"blast_furnace"), Vector2i(0, 0), 0)
	var foundry := grid.place(Database.building(&"plasteel_foundry"), Vector2i(2, 0), 0)
	check(furnace.links_out.has(foundry), "adjacent output/input ports did not link")
	check(not foundry.links_out.has(furnace), "link created in the wrong direction")
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
	economy._push_outputs(furnace, null, {})   # no depot access at all
	check(int(foundry.input_buffer.get(&"steel", 0)) == 4, "linked steel did not reach the foundry")
	check(economy.amount(&"steel") == 0, "linked steel went to the stockpile")


# --- Transport ------------------------------------------------------------------

func test_transport_rules() -> void:
	var w := flat_world()
	var t: TransportGrid = w["transport"]
	var grid: BuildGrid = w["grid"]
	var c := Vector2i(5, 5)
	var one: Array[Vector2i] = [c]
	lay(t, one, TransportGrid.Net.WALK)
	check(t.mask_at(c) == TransportGrid.Net.WALK, "walkway not laid")
	check(not t.check_add(c, TransportGrid.Net.WALK)["ok"], "double walkway allowed")
	lay(t, one, TransportGrid.Net.ROAD)
	check(t.mask_at(c) == TransportGrid.Net.ROAD, "road did not replace the walkway")
	check(not t.check_add(c, TransportGrid.Net.WALK)["ok"], "walkway allowed on a road")
	lay(t, one, TransportGrid.Net.RAIL)
	check(t.mask_at(c) == TransportGrid.Net.ROAD | TransportGrid.Net.RAIL, "level crossing not allowed")
	check(t.in_graph(c, TransportGrid.Graph.PEOPLE), "crossing not walkable")
	check(grid.check_placement(Database.building(&"shrine"), c, 0)["reason"] == "Transport in the way",
		"building allowed on a transport tile")


func test_transport_paths() -> void:
	var w := flat_world()
	var t: TransportGrid = w["transport"]
	lay(t, rect_cells(Vector2i(0, 5), Vector2i(10, 1)), TransportGrid.Net.WALK)
	lay(t, rect_cells(Vector2i(9, 5), Vector2i(1, 6)), TransportGrid.Net.ROAD)
	lay(t, rect_cells(Vector2i(15, 5), Vector2i(4, 1)), TransportGrid.Net.WALK)
	check(t.component(TransportGrid.Graph.PEOPLE, Vector2i(0, 5)) == t.component(TransportGrid.Graph.PEOPLE, Vector2i(9, 10)),
		"walkway and road not joined for people")
	check(t.component(TransportGrid.Graph.ROAD, Vector2i(0, 5)) == -1, "walkway counted as road")
	check(t.component(TransportGrid.Graph.PEOPLE, Vector2i(0, 5)) != t.component(TransportGrid.Graph.PEOPLE, Vector2i(15, 5)),
		"separate walkways share a component")
	var path := t.find_path(TransportGrid.Graph.PEOPLE, [Vector2i(0, 5)], [Vector2i(9, 10)])
	check(path.size() == 15, "shortest path wrong length (%d)" % path.size())
	check(t.find_path(TransportGrid.Graph.PEOPLE, [Vector2i(0, 5)], [Vector2i(15, 5)]).is_empty(),
		"path found between unconnected walkways")


# --- Economy ------------------------------------------------------------------

func test_extraction_chain_runs() -> void:
	var w := chain_world()
	var economy: Economy = w["economy"]
	var iron: BuildingInstance = w["iron_mine"]
	check(iron.recipe != null and iron.recipe.id == &"extract_iron_ore", "mine did not pick the iron recipe")
	check(iron.road_access, "mine has no road access")
	check(iron.staffing > 0.9, "mine not staffed by commuters (%.2f)" % iron.staffing)
	run(economy, 120.0)
	check(int(economy.produced_total.get(&"steel", 0)) > 0, "no steel produced in 120s")
	check(economy.amount(&"steel") > 0, "steel never reached the depot")
	check(not economy.labour.assignments.is_empty(), "no commute assignments")


func test_road_access_required() -> void:
	var w := chain_world()
	var grid: BuildGrid = w["grid"]
	var economy: Economy = w["economy"]
	var home: DistrictMap.District = w["home"]
	home.add(&"iron_ore", 50)
	home.add(&"coal", 50)
	var lonely := grid.place(Database.building(&"blast_furnace"), Vector2i(2, 25), 0)
	drive(grid, lonely, 2)
	run(economy, 10.0)
	check(not lonely.road_access, "isolated furnace claims road access")
	check(int(lonely.input_buffer.get(&"iron_ore", 0)) == 0, "isolated furnace pulled goods without a road")
	check(lonely.status == BuildingInstance.Status.NO_ROAD or lonely.status == BuildingInstance.Status.NO_WORKERS,
		"isolated furnace status is %s" % lonely.status_text())


func test_housing_needs_market() -> void:
	var w := chain_world()
	var grid: BuildGrid = w["grid"]
	var economy: Economy = w["economy"]
	var cut_off := grid.place(Database.building(&"slum_stack"), Vector2i(26, 2), 0)
	economy.step(Economy.STEP)
	check(not cut_off.market_access, "unconnected housing has market access")
	check(cut_off.status == BuildingInstance.Status.NO_MARKET, "unconnected housing status wrong")
	var slum: BuildingInstance = w["slum_a"]
	check(slum.market_access, "road-side housing has no market access")


func test_commute_range() -> void:
	var w := flat_world(Vector2i(120, 12))
	var grid: BuildGrid = w["grid"]
	var economy: Economy = w["economy"]
	var t: TransportGrid = w["transport"]
	lay(t, rect_cells(Vector2i(0, 5), Vector2i(120, 1)), TransportGrid.Net.ROAD)
	grid.place(Database.building(&"administratum_bastion"), Vector2i(0, 6), 0)
	grid.place(Database.building(&"slum_stack"), Vector2i(4, 6), 0)
	var near := grid.place(Database.building(&"casing_press"), Vector2i(10, 6), 0)
	var far := grid.place(Database.building(&"ration_press"), Vector2i(100, 6), 0)
	drive(grid, near, 2)
	drive(grid, far, 2)
	economy.step(Economy.STEP)
	check(near.staffing > 0.5, "nearby job not staffed (%.2f)" % near.staffing)
	check(far.staffing == 0.0, "job beyond walking range was staffed")
	check(near.staffing < 1.0, "a commute of several tiles cost nothing")


func test_deposit_depletes() -> void:
	var w := chain_world()
	var economy: Economy = w["economy"]
	var deposits: DepositMap = w["deposits"]
	var iron: BuildingInstance = w["iron_mine"]
	run(economy, 1000.0)
	var cl := deposits.get_cluster(iron.deposit_cluster)
	check(cl.remaining == 0, "iron deposit not exhausted after 1000s (left %d)" % cl.remaining)
	economy.step(Economy.STEP)
	check(iron.status == BuildingInstance.Status.DEPOSIT_EXHAUSTED, "mine did not report exhaustion")


func test_maintenance_uses_parts() -> void:
	var w := chain_world()
	var economy: Economy = w["economy"]
	var home: DistrictMap.District = w["home"]
	var furnace: BuildingInstance = w["furnace"]
	furnace.condition = 50.0
	home.add(&"machine_parts", 3)
	economy.step(Economy.STEP)
	check(furnace.condition > 70.0, "low condition was not repaired")
	check(home.amount(&"machine_parts") < 3, "repair did not use a machine part")


func test_freight_road_and_rail() -> void:
	var w := flat_world(Vector2i(60, 20))
	var grid: BuildGrid = w["grid"]
	var economy: Economy = w["economy"]
	var t: TransportGrid = w["transport"]
	var districts: DistrictMap = w["districts"]
	var home: DistrictMap.District = w["home"]
	var east := districts.create()
	districts.paint(rect_cells(Vector2i(30, 0), Vector2i(30, 20)), east.id)
	# One road along y = 5 joins both depots.
	lay(t, rect_cells(Vector2i(0, 5), Vector2i(60, 1)), TransportGrid.Net.ROAD)
	grid.place(Database.building(&"administratum_bastion"), Vector2i(2, 6), 0)
	grid.place(Database.building(&"district_depot"), Vector2i(40, 6), 0)
	grid.place(Database.building(&"slum_stack"), Vector2i(44, 6), 0)
	east.add(&"steel", 100)
	economy.step(Economy.STEP)
	var link := economy.freight.link_between(home.id, east.id)
	check(link != null and not link.rail, "depots on one road did not get a road link")
	run(economy, 20.0)
	var by_road := home.amount(&"steel")
	check(by_road > 0, "surplus did not flow to the Bastion district by road")
	check(by_road <= int(Freight.ROAD_CAPACITY * 20.0) + 1, "road freight beat its capacity (%d)" % by_road)

	# Rail along y = 2 with a station on each side; stations reach the road at y = 5.
	lay(t, rect_cells(Vector2i(0, 2), Vector2i(60, 1)), TransportGrid.Net.RAIL)
	lay(t, rect_cells(Vector2i(13, 3), Vector2i(1, 2)), TransportGrid.Net.ROAD)
	lay(t, rect_cells(Vector2i(53, 3), Vector2i(1, 2)), TransportGrid.Net.ROAD)
	grid.place(Database.building(&"cargo_station"), Vector2i(10, 3), 0)
	grid.place(Database.building(&"cargo_station"), Vector2i(50, 3), 0)
	grid.place(Database.building(&"slum_stack"), Vector2i(14, 6), 0)
	east.add(&"steel", 400)
	run(economy, 4.0)
	link = economy.freight.link_between(home.id, east.id)
	check(link != null and link.rail, "stations on one line did not get a rail link")
	check(link != null and not link.path.is_empty(), "rail link has no path for trains")
	var before := home.amount(&"steel")
	run(economy, 10.0)
	check(home.amount(&"steel") - before > int(Freight.ROAD_CAPACITY * 10.0), "rail freight no faster than road")


# --- Modules ------------------------------------------------------------------

func test_modules_attach_and_slots() -> void:
	var w := flat_world()
	var grid: BuildGrid = w["grid"]
	var press := grid.place(Database.building(&"casing_press"), Vector2i(5, 5), 0)   # 2x1
	check(press.def.module_slots == 3, "small production building should have 3 slots, has %d" % press.def.module_slots)
	var below := grid.place(Database.building(&"warehouse"), Vector2i(5, 6), 1)       # 2x1 under it
	check(below != null and below.host == press, "warehouse did not attach to the touching host")
	var above := grid.place(Database.building(&"warehouse"), Vector2i(5, 4), 1)
	var left := grid.place(Database.building(&"stamping_press"), Vector2i(4, 5), 0)
	check(above.host == press and left.host == press, "second and third modules did not attach")
	var extra := grid.place(Database.building(&"stamping_press"), Vector2i(7, 5), 0)
	check(extra != null and extra.host == null, "module attached beyond the slot count")
	grid.remove(below)
	check(extra.host == press, "waiting module did not take the freed slot")
	var housing := grid.place(Database.building(&"slum_stack"), Vector2i(12, 12), 0)
	check(grid.check_placement(Database.building(&"warehouse"), Vector2i(14, 12), 0)["host"] == null,
		"module would attach to housing")
	check(housing.modules.is_empty(), "housing took a module")
	check(grid.check_placement(Database.building(&"grinder_rig"), Vector2i(7, 5), 0)["host"] == null,
		"a mine's drive module would attach to a casing press")


func test_module_effects() -> void:
	var w := chain_world()
	var grid: BuildGrid = w["grid"]
	var economy: Economy = w["economy"]
	var furnace: BuildingInstance = w["furnace"]
	var cap_before := furnace.capacity_for(&"iron_ore", 2)
	var store := attach(grid, furnace, &"warehouse")
	check(store != null and store.host == furnace, "warehouse did not attach to the furnace")
	economy.step(Economy.STEP)
	check(furnace.capacity_for(&"iron_ore", 2) == cap_before * 2, "warehouse did not double buffers")
	var mine: BuildingInstance = w["iron_mine"]
	var req_before := int(Labour.job_requirements(mine)[&"menial"])
	var bay := attach(grid, mine, &"servitor_bay")
	check(bay != null and bay.host == mine, "servitor bay did not attach to the mine")
	var home: DistrictMap.District = w["home"]
	home.add(&"machine_parts", 20)
	economy.step(Economy.STEP)
	check(int(Labour.job_requirements(mine)[&"menial"]) < req_before, "servitor bay did not cut workers")


func test_module_recipe_and_upkeep() -> void:
	var w := chain_world()
	var grid: BuildGrid = w["grid"]
	var economy: Economy = w["economy"]
	var press := grid.place(Database.building(&"ration_press"), Vector2i(22, 11), 0)
	check(not press.available_recipes().has(&"press_rations_direct"), "recipe available without module")
	var mill := attach(grid, press, &"fungal_mill")
	check(mill != null and mill.host == press, "fungal mill did not attach")
	check(press.available_recipes().has(&"press_rations_direct"), "module recipe not unlocked")
	press.set_recipe(Database.recipe(&"press_rations_direct"))
	grid.remove(mill)
	check(press.recipe.id == &"press_rations", "host kept a recipe its module took away")
	# Upkeep: a machine-spirit shrine with no unguents switches off.
	var furnace: BuildingInstance = w["furnace"]
	var shrine := attach(grid, furnace, &"machine_spirit_shrine")
	check(shrine != null and shrine.host == furnace, "machine-spirit shrine did not attach")
	run(economy, 130.0)
	check(not shrine.module_active, "unpaid module stayed active")
	check(is_equal_approx(furnace.effect("decay"), 1.0), "inactive module still applied its effect")


func test_tithe_first_cycle() -> void:
	var w := flat_world()
	var economy: Economy = w["economy"]
	var home: DistrictMap.District = w["home"]
	var unlocks := Unlocks.new()
	var tithe := TitheManager.new(economy, 1234, unlocks)
	check(not tithe.founded and tithe.cycle == 0, "tithe started before the hive was founded")
	tithe.advance(TitheManager.CYCLE_LENGTH * 3.0)
	check(tithe.cycle == 0, "an unfounded hive was tithed")
	tithe.found()
	check(tithe.cycle == 1, "founding did not start cycle 1")
	check(unlocks.charters == TitheManager.FOUNDING_CHARTERS, "founding did not grant a charter")
	check(tithe.quota.keys() == [&"steel"], "first tithe should be steel only, got %s" % [tithe.quota])
	check(economy.tithe_quota == tithe.quota, "economy does not know the quota")
	home.add(&"steel", 10000)
	var favour := tithe.favour
	tithe.resolve()
	check(tithe.favour > favour, "full delivery did not raise favour")
	check(unlocks.charters == TitheManager.FOUNDING_CHARTERS + 2, "full delivery did not grant 2 charters")
	check(TitheManager.charters_for(0.8) == 1 and TitheManager.charters_for(0.5) == 0, "charter scale wrong")
	tithe.advance(TitheManager.CYCLE_LENGTH + 1.0)
	check(tithe.cycle >= 2, "tithe did not roll over")


func test_worker_scale() -> void:
	var mine := Database.building(&"deep_ore_mine")
	check(int(mine.workers[&"menial"]) == 150, "mine crew not scaled x5 (%s)" % [mine.workers])
	var slum := Database.building(&"slum_stack")
	check(slum.housing_capacity == 100, "housing capacity changed with the worker scale")
	for b in Database.buildings.values():
		if b.category in [&"extraction", &"industry", &"civic"]:
			check(b.module_slots >= 3, "%s has fewer than 3 module slots" % b.id)
			check(b.needs_drive(), "%s has no drive module" % b.id)
			var dm := Database.building(b.drive_module)
			check(dm != null and dm.accepts_host(b), "%s drive module does not fit it" % b.id)


func test_drive_required() -> void:
	var w := chain_world()
	var grid: BuildGrid = w["grid"]
	var economy: Economy = w["economy"]
	var home: DistrictMap.District = w["home"]
	home.add(&"iron_ore", 100)
	home.add(&"coal", 100)
	var bare := grid.place(Database.building(&"blast_furnace"), Vector2i(36, 8), 0)
	economy.refresh_topology()
	run(economy, 5.0)
	check(bare.status == BuildingInstance.Status.NEEDS_MODULE, "furnace ran without a drive module (%s)" % bare.status_text())
	check(Labour.job_requirements(bare).is_empty(), "idle furnace still hires workers")
	check(is_zero_approx(bare.drive()), "drive not zero without modules")
	var first := attach(grid, bare, &"bellows_house")
	check(first != null and is_equal_approx(bare.drive(), 0.5), "one drive module should give 50%")
	attach(grid, bare, &"bellows_house")
	check(is_equal_approx(bare.drive(), 1.0), "two drive modules should give 100%")
	check(not Labour.job_requirements(bare).is_empty(), "driven furnace hires nobody")


func test_unlocks() -> void:
	var u := Unlocks.new()
	check(u.is_building_unlocked(&"slum_stack") and u.is_building_unlocked(&"deep_ore_mine"),
		"founding buildings locked")
	check(u.is_building_unlocked(&"grinder_rig"), "a founding building's drive module is locked")
	check(not u.is_building_unlocked(&"plasteel_foundry"), "plasteel foundry unlocked at start")
	check(not u.is_building_unlocked(&"ferrocrete_block"), "housing upgrade unlocked at start")
	check(u.is_network_unlocked(TransportGrid.Net.ROAD) and not u.is_network_unlocked(TransportGrid.Net.RAIL),
		"wrong networks at start")
	var locked := 0
	for b in Database.buildings.values():
		if not u.is_building_unlocked(b.id):
			locked += 1
	check(locked > Database.buildings.size() / 2, "most buildings should start locked (%d locked)" % locked)
	check(not u.buy(&"cargo_rail"), "bought a charter with none to spend")
	u.award(1)
	check(not u.buy(&"workshops"), "bought a charter without its prerequisite")
	check(u.buy(&"cargo_rail") and u.charters == 0, "could not buy an affordable charter")
	check(u.is_network_unlocked(TransportGrid.Net.RAIL) and u.is_building_unlocked(&"cargo_station"),
		"cargo rail charter did not unlock rail")
	check(not u.buy(&"cargo_rail"), "bought the same charter twice")


func test_founding_threshold() -> void:
	var w := flat_world(Vector2i(60, 60))
	var grid: BuildGrid = w["grid"]
	var economy: Economy = w["economy"]
	var unlocks := Unlocks.new()
	var tithe := TitheManager.new(economy, 99, unlocks)
	var needed := ceili(TitheManager.FOUNDING_POPULATION / 100.0)
	for i in needed - 1:
		grid.place(Database.building(&"slum_stack"), Vector2i(2 + (i % 10) * 3, 2 + int(i / 10.0) * 3), 0)
	economy.step(Economy.STEP)
	tithe.advance(1.0)
	check(not tithe.founded, "hive founded below the population threshold (%d)" % economy.total_population())
	grid.place(Database.building(&"slum_stack"), Vector2i(2, 50), 0)
	economy.step(Economy.STEP)
	tithe.advance(1.0)
	check(tithe.founded and tithe.cycle == 1, "hive not founded at %d citizens" % economy.total_population())


func test_quota_only_producible() -> void:
	var w := flat_world()
	var unlocks := Unlocks.new()
	var tithe := TitheManager.new(w["economy"], 5, unlocks)
	for n in range(1, 9):
		for item in tithe._make_quota(n):
			check(unlocks.can_produce(item), "cycle %d asked for %s, which the hive cannot make" % [n, item])
	unlocks.award(10)
	unlocks.buy(&"hiver_quarters")
	unlocks.buy(&"promethium")
	check(unlocks.can_produce(&"promethium_fuel"), "promethium charter does not allow fuel")
	var seen := {}
	for n in range(2, 12):
		for item in tithe._make_quota(n):
			seen[item] = true
	check(seen.has(&"promethium_fuel"), "newly producible tithe good never demanded")


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
