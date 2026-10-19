extends Node
## Dev helper: builds a small sample hive and saves a screenshot.
## xvfb-run godot --rendering-driver opengl3 --path . res://tests/screenshot.tscn -- out.png

func _ready() -> void:
	var out := "user://screenshot.png"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var world: World = load("res://scenes/main.tscn").instantiate()
	world.world_seed = 42
	add_child(world)
	await get_tree().process_frame
	var c := world.map_size / 2
	# Find deposits near the centre and put mines on them.
	var placed := 0
	for cl in world.deposits.clusters:
		if Vector2(cl.cells[0]).distance_to(Vector2(c)) > 30:
			continue
		var def := Database.building(&"open_quarry") if cl.item in [&"limestone", &"silica_sand"] else (
			Database.building(&"scavenger_post") if cl.item == &"salvage_scrap" else Database.building(&"deep_ore_mine"))
		for cell in cl.cells:
			if world.try_build(def, cell, 0):
				placed += 1
				break
	world.economy.add(&"steel", 500)
	world.economy.add(&"ferrocrete", 500)
	world.try_build(Database.building(&"slum_stack"), c + Vector2i(-6, 3), 0)
	world.try_build(Database.building(&"slum_stack"), c + Vector2i(-6, 6), 0)
	world.try_build(Database.building(&"blast_furnace"), c + Vector2i(3, 3), 0)
	world.try_build(Database.building(&"plasteel_foundry"), c + Vector2i(5, 3), 0)
	world.try_build(Database.building(&"alloy_forge"), c + Vector2i(3, -4), 1)
	world.try_build(Database.building(&"shrine"), c + Vector2i(-3, 4), 0)
	world.economy.advance(0.0)
	for i in 240:
		world.economy.step(Economy.STEP)
	world.placement.begin_build(Database.building(&"cracking_tower"))
	world.placement.select(world.grid.building_at(c + Vector2i(3, 3)))
	if args.size() > 1:
		world.placement.cancel_build()
		world.camera._zoom = float(args[1])
		world.camera.camera.size = float(args[1])
	for i in 30:
		await get_tree().process_frame
	print("placed mines: ", placed)
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", ProjectSettings.globalize_path(out))
	get_tree().quit()
