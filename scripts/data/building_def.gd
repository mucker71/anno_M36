class_name BuildingDef
extends Resource
## Static description of a building type.
## Generated from tools/gen_data.py; edit there, not in the .tres files.

enum PortKind { INPUT, OUTPUT }

@export var id: StringName
@export var display_name: String
## core, logistics, housing, extraction, industry, civic, service
@export var category: StringName
@export var sort_order: int = 0
@export_multiline var description: String

@export_group("Footprint")
## Occupied cells relative to the origin, at rotation 0. No holes allowed.
@export var cells: Array[Vector2i] = []
## Each port: { "cell": Vector2i, "dir": Vector2i, "kind": PortKind }
## dir is the side of the cell the port faces (N = (0,-1), E = (1,0)...).
@export var ports: Array = []

@export_group("Production")
@export var recipes: Array[StringName] = []
## Units each input and output buffer can hold, as a multiple of one cycle.
@export var buffer_capacity: int = 8
## caste id -> workers needed for full speed
@export var workers: Dictionary = {}
## Condition lost per minute (0..100 scale). Repaired with machine parts.
@export var decay_per_minute: float = 1.0
@export var needs_deposit: bool = false

@export_group("Cost")
@export var build_cost: Dictionary = {}

@export_group("Housing")
@export var housing_caste: StringName = &""
@export var housing_capacity: int = 0
## Next housing tier. Must share this footprint.
@export var upgrade_to: StringName = &""
@export var upgrade_cost: Dictionary = {}

@export_group("Logistics and services")
## Units per second this building adds to the logistics network.
@export var logistics_capacity: float = 0.0
## fervour or order
@export var service_kind: StringName = &""
## Citizens covered while the service is supplied.
@export var service_capacity: int = 0

@export_group("Visual")
@export var colour: Color = Color.GRAY
@export var height: float = 1.0


func size() -> Vector2i:
	var max_cell := Vector2i.ZERO
	for c in cells:
		max_cell.x = maxi(max_cell.x, c.x)
		max_cell.y = maxi(max_cell.y, c.y)
	return max_cell + Vector2i.ONE


func is_housing() -> bool:
	return housing_caste != &""


func total_workers() -> int:
	var total := 0
	for v in workers.values():
		total += int(v)
	return total
