class_name World
extends Node3D
## Main scene: generates the map, owns the simulation, and wires up the views.

signal message_posted(text: String)

@export var map_size := Vector2i(160, 160)
## 0 picks a random seed each run.
@export var world_seed: int = 0

const STARTING_STOCK := {
	&"steel": 150, &"ferrocrete": 120, &"glass": 30, &"machine_parts": 25,
	&"ration_bricks": 120, &"purified_water": 120, &"recaf": 20,
}
const DEMOLISH_REFUND := 0.5

var seed_used: int
var terrain: TerrainData
var deposits: DepositMap
var grid: BuildGrid
var economy: Economy
var tithe: TitheManager
var views: Dictionary = {}     # uid -> BuildingView
## 0 = paused, otherwise a multiplier on game time.
var speed: float = 1.0

var camera: RtsCamera
var placement: PlacementController
var hud: Hud
var _buildings_root: Node3D
var _view_timer := 0.0


func _ready() -> void:
	seed_used = world_seed if world_seed != 0 else int(Time.get_unix_time_from_system()) % 1000000
	_generate()
	_setup_environment()
	_setup_views()
	_place_starting_buildings()
	post("Seed %d. Hive Secundus awaits the Administratum's demands." % seed_used)
	_on_tithe_started(tithe.cycle, tithe.quota)


func _process(delta: float) -> void:
	var sim_delta := delta * speed
	economy.advance(sim_delta)
	tithe.advance(sim_delta)
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


func post(text: String) -> void:
	message_posted.emit(text)


# --- Player actions -------------------------------------------------------------

func try_build(def: BuildingDef, origin: Vector2i, rot: int) -> BuildingInstance:
	var check := grid.check_placement(def, origin, rot)
	if not check["ok"]:
		return null
	if not economy.pay(def.build_cost):
		post("Not enough materials for %s." % def.display_name)
		return null
	return grid.place(def, origin, rot)


func demolish(inst: BuildingInstance) -> void:
	if inst.def.category == &"core":
		post("The Administratum Bastion cannot be demolished.")
		return
	economy.return_buffers(inst)
	economy.refund(inst.def.build_cost, DEMOLISH_REFUND)
	if placement.selected == inst:
		placement.select(null)
	grid.remove(inst)


func upgrade(inst: BuildingInstance) -> void:
	var next := Database.building(inst.def.upgrade_to)
	if next == null:
		return
	if not economy.pay(inst.def.upgrade_cost):
		post("Upgrading to %s needs %s." % [next.display_name, _cost_text(inst.def.upgrade_cost)])
		return
	grid.replace_def(inst, next)
	if views.has(inst.uid):
		views[inst.uid].rebuild()
		views[inst.uid].set_selected(true)
	post("%s upgraded to %s." % [inst.def.display_name, next.display_name])
	placement.select(inst)


func set_recipe(inst: BuildingInstance, recipe_id: StringName) -> void:
	inst.set_recipe(Database.recipe(recipe_id))


# --- Setup ----------------------------------------------------------------------

func _generate() -> void:
	terrain = TerrainGenerator.generate(map_size, seed_used)
	deposits = DepositScatter.scatter(terrain, seed_used)
	grid = BuildGrid.new(terrain, deposits)
	economy = Economy.new(grid, deposits)
	for item in STARTING_STOCK:
		economy.add(item, STARTING_STOCK[item])
	tithe = TitheManager.new(economy, seed_used)
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
	_buildings_root = Node3D.new()
	_buildings_root.name = "Buildings"
	add_child(_buildings_root)
	grid.building_placed.connect(_on_building_placed)
	grid.building_removed.connect(_on_building_removed)

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


func _place_starting_buildings() -> void:
	var def := Database.building(&"administratum_bastion")
	var centre := map_size / 2 - Vector2i(1, 1)
	if grid.place(def, centre, 0) == null:
		push_error("World: could not place the starting bastion at %s" % centre)


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
	post("Tithe %d demanded: %s." % [cycle, _cost_text(quota)])


func _on_tithe_resolved(cycle: int, _delivered: Dictionary, _quota: Dictionary, ratio: float) -> void:
	if ratio >= 1.0:
		post("Tithe %d delivered in full. The Imperium is pleased." % cycle)
	elif ratio >= 0.75:
		post("Tithe %d delivered at %d%%. Noted." % [cycle, int(ratio * 100.0)])
	else:
		post("Tithe %d short at %d%%. Imperial favour falls." % [cycle, int(ratio * 100.0)])


func _cost_text(d: Dictionary) -> String:
	var parts := []
	for item in d:
		parts.append("%d %s" % [int(d[item]), Database.item_name(item)])
	return ", ".join(parts) if not parts.is_empty() else "nothing"
