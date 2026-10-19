class_name CasteDef
extends Resource
## A population caste. Castes never upgrade into each other: better housing
## holds more of the same caste.
## Generated from tools/gen_data.py; edit there, not in the .tres files.

@export var id: StringName
@export var display_name: String
@export var sort_order: int = 0
@export var colour: Color = Color.GRAY
## item id -> units per 100 citizens per minute. Shortfalls shrink the workforce.
@export var basic_needs: Dictionary = {}
## item id -> units per 100 citizens per minute. Feeds the Comfort lever of morale.
@export var comfort_needs: Dictionary = {}
