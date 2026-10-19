class_name RecipeDef
extends Resource
## One production cycle: consume inputs, wait duration, emit outputs.
## Generated from tools/gen_data.py; edit there, not in the .tres files.

@export var id: StringName
@export var display_name: String
## item id -> amount per cycle
@export var inputs: Dictionary = {}
## item id -> amount per cycle. Empty for service recipes (shrines, precincts).
@export var outputs: Dictionary = {}
## Seconds per cycle at full staffing, condition and morale.
@export var duration: float = 1.0
## Extraction only: the deposit item this recipe needs under the building.
@export var deposit: StringName = &""


func is_extraction() -> bool:
	return deposit != &""


func is_service() -> bool:
	return outputs.is_empty()
