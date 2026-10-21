class_name Unlocks
extends RefCounted
## Tracks which charters the hive owns, and so which buildings and transport
## networks the player may build. The founding charter (cost 0) is owned from
## the start; the rest are bought with charters earned from tithes.

signal changed

const NETWORK_IDS := {
	TransportGrid.Net.WALK: &"walk",
	TransportGrid.Net.ROAD: &"road",
	TransportGrid.Net.RAIL: &"rail",
}

var charters: int = 0            ## unspent charters
var owned: Dictionary = {}       ## charter id -> true
var _buildings: Dictionary = {}  ## building id -> true
var _networks: Dictionary = {}   ## network id -> true
var _producible: Dictionary = {} ## item id -> true, cached
var _all := false


func _init() -> void:
	for c in Database.sorted_charters():
		if c.cost == 0:
			_grant(c)
	_refresh()


func is_building_unlocked(id: StringName) -> bool:
	return _all or _buildings.has(id)


func is_network_unlocked(net: int) -> bool:
	return _all or _networks.has(NETWORK_IDS.get(net, &""))


func is_owned(id: StringName) -> bool:
	return owned.has(id)


## Why a charter can't be bought, or "" if it can.
func block_reason(c: CharterDef) -> String:
	if owned.has(c.id):
		return "Owned"
	var missing := []
	for p in c.prerequisites:
		if not owned.has(p):
			missing.append(Database.charter(p).display_name)
	if not missing.is_empty():
		return "Needs " + ", ".join(missing)
	if charters < c.cost:
		return "Needs %d charter%s" % [c.cost, "" if c.cost == 1 else "s"]
	return ""


func buy(id: StringName) -> bool:
	var c := Database.charter(id)
	if c == null or block_reason(c) != "":
		return false
	charters -= c.cost
	_grant(c)
	_refresh()
	return true


func award(n: int) -> void:
	if n > 0:
		charters += n
		changed.emit()


## The charter that unlocks a building, for "requires X" hints.
func charter_for(building_id: StringName) -> CharterDef:
	for c in Database.sorted_charters():
		if c.buildings.has(building_id):
			return c
	return null


## True if some unlocked building can make the item (including recipes that
## unlocked modules add). Used to keep tithe demands achievable.
func can_produce(item: StringName) -> bool:
	return _all or _producible.has(item)


## Developer and test helper: everything is buildable.
func unlock_all() -> void:
	_all = true
	_refresh()


func _grant(c: CharterDef) -> void:
	owned[c.id] = true
	for b in c.buildings:
		_buildings[b] = true
	for n in c.networks:
		_networks[n] = true


func _refresh() -> void:
	_producible.clear()
	for id in _buildings:
		var def := Database.building(id)
		if def == null:
			continue
		for rid in def.recipes + def.module_recipes:
			var r := Database.recipe(rid)
			if r:
				for item in r.outputs:
					_producible[item] = true
	changed.emit()
