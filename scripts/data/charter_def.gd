class_name CharterDef
extends Resource
## A group of buildings (and transport networks) the Administratum permits the
## hive to build. Bought with charters earned from tithes.
## Generated from tools/gen_data.py; edit there, not in the .tres files.

@export var id: StringName
@export var display_name: String
## 0 = founding (owned from the start), then 1..3.
@export var tier: int = 1
## Charters spent to unlock it.
@export var cost: int = 1
@export var sort_order: int = 0
## Charter ids that must be owned first.
@export var prerequisites: Array[StringName] = []
## Building ids unlocked, including drive modules of production buildings.
@export var buildings: Array[StringName] = []
## walk, road, rail
@export var networks: Array[StringName] = []
@export_multiline var description: String
