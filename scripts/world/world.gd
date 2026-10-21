class_name World
extends Node3D
## Main scene: generates the map, owns the simulation, and wires up the views.

signal message_posted(text: String)

@export var map_size := Vector2i(160, 160)
## 0 picks a random seed each run.
@export var world_seed: int = 0

const STARTING_STOCK := {
	&"steel": 320, &"ferrocrete": 480, &"glass": 30, &"machine_parts": 40,
	&"ration_bricks": 500, &"purified_water": 500,
}
const DEMOLISH_REFUND := 0.5
const START_DISTRICT_SIZE := 40

var seed_used: int
var terrain: TerrainData
var deposits: DepositMap
var transport: TransportGrid
var districts: DistrictMap
var grid: BuildGrid
var economy: Economy
var tithe: TitheManager
var unlocks: Unlocks
var views: Dictionary = {}     # uid -> BuildingView
## 0 = paused, otherwise a multiplier on game time.
var speed: float = 1.0

var camera: RtsCamera
var placement: PlacementController
var hud: Hud
var crowds: CrowdSystem
var network_view: NetworkView
var district_overlay: DistrictOverlay
var _buildings_root: Node3D
var _view_timer := 0.0
var _overlay_forced := false


func _ready() -> void:
	seed_used = world_seed if world_seed != 0 else int(Time.get_unix_time_from_system()) % 1000000
	_generate()
	_setup_environment()
	_setup_views()
	_place_start()
	post("Seed %d. Found Hive Secundus: house %s citizens and the Administratum will recognise it." % [
		seed_used, _thousands(TitheManager.FOUNDING_POPULATION)])


func _process(delta: float) -> void:
	var sim_delta := delta * speed
	economy.advance(sim_delta)
	tithe.advance(sim_delta)
	district_overlay.visible = _overlay_forced or placement.mode == PlacementController.Mode.DISTRICT \
		or placement.selected_district >= 0
	_view_timer -= delta
	if _view_timer <= 0.0:
		_view_timer = 0.25
		for v in views.values():
			v.update_status()
		hud.refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		speed = 1.0 if speed == 0.0 else 0.0
	elif event.is_action_pressed(&"speed_1"):
		speed = 1.0
	elif event.is_action_pressed(&"speed_2"):
		speed = 2.0
	elif event.is_action_pressed(&"speed_3"):
		speed = 4.0
	elif event.is_action_pressed(&"toggle_districts"):
		_overlay_forced = not _overlay_forced


func post(text: String) -> void:
	message_posted.emit(text)


# --- Player actions -------------------------------------------------------------

func try_build(def: BuildingDef, origin: Vector2i, rot: int) -> BuildingInstance:
	if not unlocks.is_building_unlocked(def.id):
		var c := unlocks.charter_for(def.id)
		post("%s needs the %s charter." % [def.display_name, c.display_name if c else "right"])
		return null
	var check := grid.check_placement(def, origin, rot)
	if not check["ok"]:
		return null
	if not economy.pay(def.build_cost, check["district"]):
		post("Not enough materials for %s." % def.display_name)
		return null
	return grid.place(def, origin, rot)


func demolish(inst: BuildingInstance) -> void:
	if inst.def.category == &"core":
		post("The Administratum Bastion cannot be demolished.")
		return
	economy.return_buffers(inst)
	economy.refund(inst.def.build_cost, DEMOLISH_REFUND, inst.district_id)
	if placement.selected == inst:
		placement.select(null)
	grid.remove(inst)


func upgrade(inst: BuildingInstance) -> void:
	var next := Database.building(inst.def.upgrade_to)
	if next == null:
		return
	if not unlocks.is_building_unlocked(next.id):
		var c := unlocks.charter_for(next.id)
		post("Upgrading to %s needs the %s charter." % [next.display_name, c.display_name if c else "right"])
		return
	if not economy.pay(inst.def.upgrade_cost, inst.district_id):
		post("Upgrading to %s needs %s." % [next.display_name, cost_text(inst.def.upgrade_cost)])
		return
	var old_name := inst.def.display_name
	grid.replace_def(inst, next)
	if views.has(inst.uid):
		views[inst.uid].rebuild()
		views[inst.uid].set_selected(true)
	post("%s upgraded to %s." % [old_name, next.display_name])
	placement.select(inst)


func set_recipe(inst: BuildingInstance, recipe_id: StringName) -> void:
	inst.set_recipe(Database.recipe(recipe_id))


## What building a line of network tiles would do, without doing it.
## Returns { tiles, ok_tiles, masks, cost, reason }.
func plan_network(tiles: Array[Vector2i], net: int) -> Dictionary:
	var ok_tiles: Array[Vector2i] = []
	var masks := {}
	var cost := {}
	var reason := ""
	for c in tiles:
		if grid.building_at(c):
			reason = "Buildings in the way"
			continue
		var check := transport.check_add(c, net)
		if not check["ok"]:
			if reason == "":
				reason = check["reason"]
			continue
		ok_tiles.append(c)
		masks[c] = check["mask"]
		for item in TransportGrid.COSTS[net]:
			cost[item] = int(cost.get(item, 0)) + int(TransportGrid.COSTS[net][item])
	if not ok_tiles.is_empty() and not economy.can_afford(cost):
		reason = "Cannot afford"
	return {"tiles": tiles, "ok_tiles": ok_tiles, "masks": masks, "cost": cost, "reason": reason}


func build_network(tiles: Array[Vector2i], net: int) -> int:
	if not unlocks.is_network_unlocked(net):
		post("%s needs the Cargo Rail charter." % TransportGrid.NET_NAMES[net])
		return 0
	var plan := plan_network(tiles, net)
	var ok: Array = plan["ok_tiles"]
	if ok.is_empty():
		if plan["reason"] != "":
			post("%s: %s." % [TransportGrid.NET_NAMES[net], plan["reason"]])
		return 0
	var district := districts.id_at(ok[0])
	if not economy.pay(plan["cost"], district):
		post("Not enough materials for %d tiles of %s (%s)." % [ok.size(), TransportGrid.NET_NAMES[net], cost_text(plan["cost"])])
		return 0
	transport.set_masks(plan["masks"])
	return ok.size()


## Clears transport tiles, refunding half their cost.
func bulldoze(tiles: Array[Vector2i]) -> int:
	var masks := {}
	for c in tiles:
		var m := transport.mask_at(c)
		if m == 0:
			continue
		masks[c] = 0
		for net in TransportGrid.COSTS:
			if (m & int(net)) != 0:
				economy.refund(TransportGrid.COSTS[net], DEMOLISH_REFUND, districts.id_at(c))
	if not masks.is_empty():
		transport.set_masks(masks)
	return masks.size()


## Paints cells into a district (id -1 erases). Cells under buildings keep
## their district so no building ends up split.
func paint_district(tiles: Array[Vector2i], id: int) -> void:
	var cells: Array[Vector2i] = []
	for c in tiles:
		if terrain.in_bounds(c) and grid.building_at(c) == null:
			cells.append(c)
	districts.paint(cells, id)


func new_district() -> int:
	var d := districts.create()
	if d == null:
		post("The Administratum permits no more than %d districts." % DistrictMap.MAX_DISTRICTS)
		return -1
	post("%s chartered. Paint its bounds, then build a District Depot inside." % d.name)
	return d.id


# --- Setup ----------------------------------------------------------------------

func _generate() -> void:
	terrain = TerrainGenerator.generate(map_size, seed_used)
	deposits = DepositScatter.scatter(terrain, seed_used)
	transport = TransportGrid.new(terrain)
	districts = DistrictMap.new(map_size)
	grid = BuildGrid.new(terrain, deposits, transport, districts)
	economy = Economy.new(grid, deposits)
	unlocks = Unlocks.new()
	tithe = TitheManager.new(economy, seed_used, unlocks)
	tithe.hive_founded.connect(_on_hive_founded)
	tithe.cycle_resolved.connect(_on_tithe_resolved)
	tithe.cycle_started.connect(_on_tithe_started)

	var mesh := MeshInstance3D.new()
	mesh.name = "Terrain"
	mesh.mesh = TerrainMesh.build(terrain, deposits)
	mesh.material_override = TerrainMesh.make_material()
	add_child(mesh)
	add_child(TerrainMesh.make_water(terrain))


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.05, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.48, 0.42)
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.22, 0.17, 0.13)
	env.fog_density = 0.004
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.85, 0.68)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-55, 35, 0)
	add_child(sun)


func _setup_views() -> void:
	network_view = NetworkView.new()
	network_view.name = "Networks"
	add_child(network_view)
	network_view.setup(transport)

	district_overlay = DistrictOverlay.new()
	district_overlay.name = "DistrictOverlay"
	add_child(district_overlay)
	district_overlay.setup(districts)

	_buildings_root = Node3D.new()
	_buildings_root.name = "Buildings"
	add_child(_buildings_root)
	grid.building_placed.connect(_on_building_placed)
	grid.building_removed.connect(_on_building_removed)

	crowds = CrowdSystem.new()
	crowds.name = "Crowds"
	add_child(crowds)
	crowds.setup(self)

	camera = RtsCamera.new()
	camera.name = "CameraRig"
	camera.bounds = Rect2(Vector2.ZERO, Vector2(map_size))
	add_child(camera)
	camera.focus(Vector3(map_size.x / 2.0, 0, map_size.y / 2.0))

	placement = PlacementController.new()
	placement.name = "Placement"
	placement.world = self
	placement.camera = camera
	add_child(placement)

	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.setup(self)


## The Bastion district, the Bastion and a ring road around it.
func _place_start() -> void:
	var centre := map_size / 2
	var home := districts.create()
	economy.bastion_district = home.id
	var half := START_DISTRICT_SIZE / 2
	districts.paint(PlacementController.rect_cells(centre - Vector2i(half, half),
		centre + Vector2i(half - 1, half - 1)), home.id)
	for item in STARTING_STOCK:
		economy.add(item, STARTING_STOCK[item], home.id)
	var bastion := Database.building(&"administratum_bastion")
	if grid.place(bastion, centre - Vector2i(1, 1), 0) == null:
		push_error("World: could not place the starting bastion at %s" % centre)
	var ring := {}
	for c in PlacementController.rect_cells(centre - Vector2i(2, 2), centre + Vector2i(2, 2)):
		if grid.building_at(c) == null and terrain.is_buildable(c):
			ring[c] = TransportGrid.Net.ROAD
	transport.set_masks(ring)


func _on_building_placed(inst: BuildingInstance) -> void:
	var view := BuildingView.new()
	view.name = "B%d_%s" % [inst.uid, inst.def.id]
	_buildings_root.add_child(view)
	view.setup(inst)
	views[inst.uid] = view


func _on_building_removed(inst: BuildingInstance) -> void:
	if views.has(inst.uid):
		views[inst.uid].queue_free()
		views.erase(inst.uid)


func _on_tithe_started(cycle: int, quota: Dictionary) -> void:
	post("Tithe %d demanded: %s. Deliver it to the Bastion Ward." % [cycle, cost_text(quota)])


func _on_hive_founded() -> void:
	post("Hive Secundus is recognised by the Administratum. You are granted %d charter: spend it in the Charters tab." % TitheManager.FOUNDING_CHARTERS)


func buy_charter(id: StringName) -> bool:
	var c := Database.charter(id)
	if c == null or not unlocks.buy(id):
		return false
	post("Charter granted: %s." % c.display_name)
	return true


static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


func _on_tithe_resolved(cycle: int, _delivered: Dictionary, _quota: Dictionary, ratio: float, earned: int = 0) -> void:
	var reward := "" if earned <= 0 else " %d charter%s granted." % [earned, "" if earned == 1 else "s"]
	if ratio >= 1.0:
		post("Tithe %d delivered in full. The Imperium is pleased.%s" % [cycle, reward])
	elif ratio >= 0.75:
		post("Tithe %d delivered at %d%%. Noted.%s" % [cycle, int(ratio * 100.0), reward])
	else:
		post("Tithe %d short at %d%%. Imperial favour falls, and no charters are granted." % [cycle, int(ratio * 100.0)])


static func cost_text(d: Dictionary) -> String:
	var parts := []
	for item in d:
		parts.append("%d %s" % [int(d[item]), Database.item_name(item)])
	return ", ".join(parts) if not parts.is_empty() else "nothing"
