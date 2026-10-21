extends Node
## Dev helper: builds a small early hive from the founding charter and saves
## a screenshot. Usage:
##   xvfb-run godot --rendering-driver opengl3 --path . res://tests/screenshot.tscn -- out.png [zoom] [tab]
## tab is a build menu category such as extraction or charters.

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://screenshot.png"
	var world: World = load("res://scenes/main.tscn").instantiate()
	world.world_seed = 42
	add_child(world)
	await get_tree().process_frame
	var c := world.map_size / 2
	var e := world.economy
	for item in [&"steel", &"ferrocrete"]:
		e.add(item, 1500)
	var R := TransportGrid.Net.ROAD
	var W := TransportGrid.Net.WALK
	world.build_network(PlacementController.line_cells(c + Vector2i(-16, 6), c + Vector2i(16, 6)), R)
	world.build_network(PlacementController.line_cells(c + Vector2i(0, 3), c + Vector2i(0, 6)), R)
	# A walkway street of slum stacks to the north-west.
	world.build_network(PlacementController.line_cells(c + Vector2i(-12, -9), c + Vector2i(-12, 5)), W)
	for i in 5:
		_build(world, &"slum_stack", c + Vector2i(-11, -9 + i * 3), 0)
		_build(world, &"slum_stack", c + Vector2i(-14, -9 + i * 3), 0)
	# Food and water on the spine, each with its drive modules.
	var pump := _build(world, &"sump_pump", c + Vector2i(-6, 7), 0)
	_drive(world, pump, 2)
	var filter := _build(world, &"water_filter", c + Vector2i(-3, 7), 0)
	_drive(world, filter, 2)
	# Steel: a furnace with bellows and a warehouse.
	var furnace := _build(world, &"blast_furnace", c + Vector2i(4, 7), 0)
	_drive(world, furnace, 2)
	_attach(world, furnace, &"warehouse")
	# Mines on the nearest iron and coal, with grinder rigs, and a road back.
	var selected_deposit := -1
	for item in [&"iron_ore", &"coal"]:
		for cl in world.deposits.clusters:
			if cl.item != item or Vector2(cl.cells[0]).distance_to(Vector2(c)) > 20:
				continue
			for cell in cl.cells:
				var m := _build(world, &"deep_ore_mine", cell, 0)
				if m:
					_drive(world, m, 2)
					_attach(world, m, &"warehouse")
					var below := m.cells[-1] + Vector2i(0, 1)
					world.build_network(PlacementController.line_cells(below, Vector2i(below.x, c.y + 6)), R)
					break
			if selected_deposit < 0 and item == &"coal":
				pass
			break
	for cl in world.deposits.clusters:
		var taken := false
		for b in world.grid.buildings:
			if b.deposit_cluster == cl.id:
				taken = true
		if not taken and Vector2(cl.cells[0]).distance_to(Vector2(c)) < 16:
			selected_deposit = cl.id
			break
	for i in 480:
		e.step(Economy.STEP)
	world.tithe.advance(0.0)
	if selected_deposit >= 0:
		world.placement.select_deposit(selected_deposit)
	if args.size() > 1:
		world.camera._zoom = float(args[1])
		world.camera.camera.size = float(args[1])
	if args.size() > 3 and args[3] == "found":
		world.tithe.found()
		world.unlocks.award(2)
		world.buy_charter(&"hiver_quarters")
	if args.size() > 2:
		world.hud._show_category(StringName(args[2]))
	world.camera.focus(Vector3(c.x - 2, 0, c.y + 1))
	for i in 40:
		await get_tree().process_frame
	print("population ", e.total_population(), "  founded ", world.tithe.founded,
		"  gangs ", world.crowds.active_gangs(), "  deposit ", selected_deposit)
	for b in world.grid.buildings:
		if b.def.needs_drive():
			print("  %s: %s, drive %d%%, staff %d%%" % [b.def.display_name, b.status_text(),
				int(b.drive() * 100), int(b.staffing * 100)])
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", ProjectSettings.globalize_path(out))
	get_tree().quit()


func _build(world: World, id: StringName, origin: Vector2i, rot: int) -> BuildingInstance:
	var b := world.try_build(Database.building(id), origin, rot)
	if b == null and not String(id).contains("mine"):
		var check := world.grid.check_placement(Database.building(id), origin, rot)
		print("could not place %s at %s: %s" % [id, origin, check["reason"]])
	return b


func _drive(world: World, host: BuildingInstance, n: int) -> void:
	if host == null:
		return
	for i in n:
		_attach(world, host, host.def.drive_module)


## Places a module touching host without covering its ports, if there's room.
func _attach(world: World, host: BuildingInstance, id: StringName) -> BuildingInstance:
	if host == null:
		return null
	var def := Database.building(id)
	var ports := {}
	for p in host.ports:
		ports[p["cell"] + p["dir"]] = true
	for r in 4:
		for c in host.cells:
			for y in range(c.y - 2, c.y + 3):
				for x in range(c.x - 2, c.x + 3):
					var check := world.grid.check_placement(def, Vector2i(x, y), r)
					if not check["ok"] or check["host"] != host:
						continue
					var blocked := false
					for cell in check["cells"]:
						if ports.has(cell):
							blocked = true
					if not blocked:
						return world.try_build(def, Vector2i(x, y), r)
	print("no room for %s beside %s" % [id, host.def.id])
	return null
