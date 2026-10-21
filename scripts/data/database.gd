extends Node
## Autoload "Database": loads every definition under res://data/ once at startup
## and serves them by id.

const ITEMS_DIR := "res://data/items"
const RECIPES_DIR := "res://data/recipes"
const BUILDINGS_DIR := "res://data/buildings"
const CASTES_DIR := "res://data/castes"
const CHARTERS_DIR := "res://data/charters"

var items: Dictionary = {}       # StringName -> ItemDef
var recipes: Dictionary = {}     # StringName -> RecipeDef
var buildings: Dictionary = {}   # StringName -> BuildingDef
var castes: Dictionary = {}      # StringName -> CasteDef
var charters: Dictionary = {}    # StringName -> CharterDef


func _ready() -> void:
	reload()


func reload() -> void:
	items = _load_dir(ITEMS_DIR)
	recipes = _load_dir(RECIPES_DIR)
	buildings = _load_dir(BUILDINGS_DIR)
	castes = _load_dir(CASTES_DIR)
	charters = _load_dir(CHARTERS_DIR)


func item(id: StringName) -> ItemDef:
	return items.get(id)


func recipe(id: StringName) -> RecipeDef:
	return recipes.get(id)


func building(id: StringName) -> BuildingDef:
	return buildings.get(id)


func caste(id: StringName) -> CasteDef:
	return castes.get(id)


func charter(id: StringName) -> CharterDef:
	return charters.get(id)


func sorted_charters() -> Array:
	var list := charters.values()
	list.sort_custom(func(a, b): return a.sort_order < b.sort_order)
	return list


func sorted_items() -> Array:
	var list := items.values()
	list.sort_custom(func(a, b): return a.sort_order < b.sort_order)
	return list


func sorted_buildings() -> Array:
	var list := buildings.values()
	list.sort_custom(func(a, b): return a.sort_order < b.sort_order)
	return list


func sorted_castes() -> Array:
	var list := castes.values()
	list.sort_custom(func(a, b): return a.sort_order < b.sort_order)
	return list


func item_name(id: StringName) -> String:
	var def: ItemDef = items.get(id)
	return def.display_name if def else String(id)


## Lists .tres files, coping with the .remap names Godot uses in exported builds.
func _load_dir(path: String) -> Dictionary:
	var out := {}
	var dir := DirAccess.open(path)
	if dir == null:
		push_error("Database: cannot open %s" % path)
		return out
	for file in dir.get_files():
		var name := file.trim_suffix(".remap")
		if not name.ends_with(".tres"):
			continue
		var res := load(path.path_join(name))
		if res == null or not ("id" in res):
			push_error("Database: bad resource %s" % name)
			continue
		out[res.id] = res
	return out
