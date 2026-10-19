extends Node
## Dev helper: builds a small sample hive and saves a screenshot.
##   xvfb-run godot --rendering-driver opengl3 --path . res://tests/screenshot.tscn -- out.png [zoom]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://screenshot.png"
	var world: World = load("res://scenes/main.tscn").instantiate()
	world.world_seed = 42
	add_child(world)
	await get_tree().process_frame
	var c := world.map_size / 2
	var e := world.economy
	for item in [&"steel", &"ferrocrete", &"glass", &"machine_parts", &"iron_ore", &"coal", &"polymer"]:
		e.add(item, 2000)
	var R := TransportGrid.Net.ROAD
	var W := TransportGrid.Net.WALK
	# Road spine east-west below the Bastion, and a cross street.
	world.build_network(PlacementController.line_cells(c + Vector2i(-14, 6), c + Vector2i(14, 6)), R)
	world.build_network(PlacementController.line_cells(c + Vector2i(0, 3), c + Vector2i(0, 6)), R)
	# Housing on a walkway north-west.
	world.build_network(PlacementController.line_cells(c + Vector2i(-12, -6), c + Vector2i(-12, 5)), W)
	for i in 4:
		_build(world, &"slum_stack", c + Vector2i(-11, -6 + i * 3), 0)
	_build(world, &"slum_stack", c + Vector2i(-6, 7), 0)
	_build(world, &"slum_stack", c + Vector2i(-9, 7), 0)
	# Industry along the spine: furnace feeding a foundry by direct link, with modules.
	_build(world, &"blast_furnace", c + Vector2i(3, 7), 0)
	_build(world, &"plasteel_foundry", c + Vector2i(5, 7), 0)
	_build(world, &"storage_annex", c + Vector2i(3, 9), 1)
	_build(world, &"machine_spirit_shrine", c + Vector2i(8, 7), 0)
	_build(world, &"water_filter", c + Vector2i(10, 7), 0)
	_build(world, &"sump_pump", c + Vector2i(11, 7), 0)
	_build(world, &"shrine", c + Vector2i(-3, 7), 0)
	# A second district to the east, joined by cargo rail.
	var east := world.new_district()
	world.paint_district(PlacementController.rect_cells(c + Vector2i(15, -12), c + Vector2i(36, 12)), east)
	world.build_network(PlacementController.line_cells(c + Vector2i(14, 6), c + Vector2i(30, 6)), R)
	_build(world, &"district_depot", c + Vector2i(20, 7), 0)
	world.build_network(PlacementController.line_cells(c + Vector2i(-6, -4), c + Vector2i(30, -4)), TransportGrid.Net.RAIL)
	_build(world, &"cargo_station", c + Vector2i(4, -3), 0)
	world.build_network(PlacementController.line_cells(c + Vector2i(7, -3), c + Vector2i(7, 5)), R)
	_build(world, &"cargo_station", c + Vector2i(24, -3), 0)
	world.build_network(PlacementController.line_cells(c + Vector2i(27, -3), c + Vector2i(27, 5)), R)
	_build(world, &"slum_stack", c + Vector2i(22, 7), 0)
	_build(world, &"casing_press", c + Vector2i(25, 7), 0)
	_build(world, &"servitor_bay", c + Vector2i(25, 8), 1)
	world.districts.get_district(east).add(&"steel", 300)
	# Mines on nearby deposits, with a road back to the spine.
	for cl in world.deposits.clusters:
		if Vector2(cl.cells[0]).distance_to(Vector2(c)) > 24:
			continue
		var def := &"open_quarry" if cl.item in [&"limestone", &"silica_sand"] else (
			&"scavenger_post" if cl.item == &"salvage_scrap" else &"deep_ore_mine")
		for cell in cl.cells:
			var m := _build(world, def, cell, 0)
			if m:
				var below := m.cells[-1] + Vector2i(0, 1)
				world.build_network(PlacementController.line_cells(below, Vector2i(below.x, c.y + 6)), R)
				break
	for i in 480:
		e.step(Economy.STEP)
	world.placement.select_district(-1)
	world.placement.select(world.grid.building_at(c + Vector2i(3, 7)))
	if args.size() > 1:
		world.camera._zoom = float(args[1])
		world.camera.camera.size = float(args[1])
	world.camera.focus(Vector3(c.x + 6, 0, c.y + 2))
	if args.size() > 2:
		world._overlay_forced = true
		world.camera.focus(Vector3(c.x + 10, 0, c.y + 1))
	for i in 40:
		await get_tree().process_frame
	var wm: MultiMesh = world.crowds._walkers.multimesh
	print("walkers drawn: ", wm.visible_instance_count, " trucks: ", world.crowds._trucks.multimesh.visible_instance_count,
		" cars: ", world.crowds._trains.multimesh.visible_instance_count)
	print("gangs: ", world.crowds.active_gangs(), "  links: ", e.freight.links.size(),
		"  assignments: ", e.labour.assignments.size())
	for l in e.freight.links:
		print("  link ", l.a, "-", l.b, " rail=", l.rail, " cap=", l.capacity, " flow=", l.flow_recent)
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", ProjectSettings.globalize_path(out))
	get_tree().quit()


func _build(world: World, id: StringName, origin: Vector2i, rot: int) -> BuildingInstance:
	var b := world.try_build(Database.building(id), origin, rot)
	if b == null:
		var check := world.grid.check_placement(Database.building(id), origin, rot)
		if not String(id).contains("mine") and not String(id).contains("quarry") and not String(id).contains("scavenger"):
			print("could not place %s at %s: %s" % [id, origin, check["reason"]])
	return b
