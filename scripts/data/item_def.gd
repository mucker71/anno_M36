class_name ItemDef
extends Resource
## A good that can sit in a stockpile or a building buffer.
## Generated from tools/gen_data.py; edit there, not in the .tres files.

enum Tier { RAW, REFINED, COMPONENT, FINISHED }

@export var id: StringName
@export var display_name: String
@export var tier: int = Tier.RAW
## raw, industrial, construction, civic, tithe
@export var category: StringName
## Base quota per tithe cycle. 0 = never demanded by the Imperium.
@export var tithe_base: int = 0
@export var sort_order: int = 0
@export var colour: Color = Color.GRAY
@export_multiline var description: String


func is_tithe_eligible() -> bool:
	return tithe_base > 0
