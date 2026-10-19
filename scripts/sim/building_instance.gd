class_name BuildingInstance
extends RefCounted
## Runtime state of one placed building.

enum Status { IDLE, WORKING, NO_RECIPE, MISSING_INPUTS, OUTPUT_BLOCKED, NO_WORKERS,
	DEPOSIT_EXHAUSTED, HOUSING, PASSIVE, NO_ROAD, NO_MARKET, MODULE_ACTIVE, NO_HOST,
	UPKEEP_UNPAID }

const STATUS_TEXT := {
	Status.IDLE: "Idle",
	Status.WORKING: "Working",
	Status.NO_RECIPE: "No recipe selected",
	Status.MISSING_INPUTS: "Waiting for inputs",
	Status.OUTPUT_BLOCKED: "Output blocked",
	Status.NO_WORKERS: "No workers",
	Status.DEPOSIT_EXHAUSTED: "Deposit exhausted",
	Status.HOUSING: "Housing",
	Status.PASSIVE: "Operating",
	Status.NO_ROAD: "No road to the district depot",
	Status.NO_MARKET: "No walkway or road to the depot: needs unmet",
	Status.MODULE_ACTIVE: "Module active",
	Status.NO_HOST: "Not attached: place touching a valid host with a free slot",
	Status.UPKEEP_UNPAID: "Module off: upkeep not met",
}

var uid: int
var def: BuildingDef
var origin: Vector2i
var rotation: int
## World-space cells this building occupies.
var cells: Array[Vector2i] = []
## World-space ports: { "cell": Vector2i, "dir": Vector2i, "kind": int }
var ports: Array = []

var recipe: RecipeDef
var input_buffer: Dictionary = {}    # item -> int
var output_buffer: Dictionary = {}   # item -> int
var progress: float = 0.0            # 0..1 through the current cycle
var running: bool = false
## 0..100. Decays over time; low condition slows the building.
var condition: float = 100.0
var status: int = Status.IDLE
## Cluster id this extractor draws from, and how much of the footprint covers it.
var deposit_cluster: int = -1
var deposit_coverage: float = 0.0
## Buildings that receive goods directly from this one's output ports.
var links_out: Array[BuildingInstance] = []
## Game time the last service cycle finished (shrines, precincts).
var last_service_time: float = -1.0e9
## Last computed speed multiplier, for the inspection panel.
var last_speed: float = 0.0
var missing_input: StringName = &""

## District this building belongs to.
var district_id: int = -1
## Can trade with its district depot over roads (production buildings).
var road_access: bool = false
## Can reach its district depot on foot or by road (housing).
var market_access: bool = false
## 0..1 share of its workforce filled by commuters (set by Labour).
var staffing: float = 1.0
## caste -> workers assigned here (jobs) or residents employed (housing).
var workers_assigned: Dictionary = {}
## Modules: the host this module is attached to. Hosts: attached modules.
var host: BuildingInstance
var modules: Array[BuildingInstance] = []
var module_active: bool = true
var upkeep_owed: Dictionary = {}
## Fractional output from multipliers, carried between cycles.
var output_carry: Dictionary = {}
## Units moved to or from the depot recently (drives hauler visuals).
var hauled_recent: float = 0.0


func setup(p_uid: int, p_def: BuildingDef, p_origin: Vector2i, p_rotation: int) -> void:
	uid = p_uid
	def = p_def
	origin = p_origin
	rotation = posmod(p_rotation, 4)
	cells.clear()
	for c in Footprint.rotated_cells(def.cells, rotation):
		cells.append(origin + c)
	ports.clear()
	for p in Footprint.rotated_ports(def.cells, def.ports, rotation):
		ports.append({"cell": origin + p["cell"], "dir": p["dir"], "kind": p["kind"]})
	if def.is_housing():
		status = Status.HOUSING
	elif def.is_module():
		status = Status.NO_HOST
	elif def.recipes.is_empty():
		status = Status.PASSIVE


## Recipes this building can run now: its own plus any from attached modules.
func available_recipes() -> Array[StringName]:
	var out: Array[StringName] = def.recipes.duplicate()
	for m in modules:
		if m.module_active:
			for r in m.def.module_recipes:
				if not out.has(r):
					out.append(r)
	return out


## Product of an effect over active modules (1.0 when none apply).
func effect(key: String) -> float:
	var v := 1.0
	for m in modules:
		if m.module_active and m.def.module_effects.has(key):
			v *= float(m.def.module_effects[key])
	return v


func free_module_slots() -> int:
	return def.module_slots - modules.size()


func set_recipe(r: RecipeDef) -> void:
	if r == recipe:
		return
	recipe = r
	running = false
	progress = 0.0
	# Goods for the old recipe are kept; the economy returns them to the stockpile.


func capacity_for(item: StringName, amount_per_cycle: int) -> int:
	return int(maxi(def.buffer_capacity, amount_per_cycle * 2) * effect("buffer"))


func input_space(item: StringName) -> int:
	if recipe == null or not recipe.inputs.has(item):
		return 0
	var cap := capacity_for(item, int(recipe.inputs[item]))
	return maxi(0, cap - int(input_buffer.get(item, 0)))


func has_inputs_for_cycle() -> bool:
	if recipe == null:
		return false
	for item in recipe.inputs:
		if int(input_buffer.get(item, 0)) < int(recipe.inputs[item]):
			missing_input = item
			return false
	missing_input = &""
	return true


func consume_inputs() -> void:
	for item in recipe.inputs:
		input_buffer[item] = int(input_buffer.get(item, 0)) - int(recipe.inputs[item])


func output_has_room() -> bool:
	if recipe == null:
		return false
	for item in recipe.outputs:
		var cap := capacity_for(item, int(recipe.outputs[item]))
		if int(output_buffer.get(item, 0)) + int(recipe.outputs[item]) > cap:
			return false
	return true


func status_text() -> String:
	var text: String = STATUS_TEXT.get(status, "?")
	if status == Status.MISSING_INPUTS and missing_input != &"":
		text += ": " + Database.item_name(missing_input)
	return text


func has_input_port_at(cell: Vector2i, facing: Vector2i) -> bool:
	for p in ports:
		if p["kind"] == BuildingDef.PortKind.INPUT and p["cell"] == cell and p["dir"] == facing:
			return true
	return false
