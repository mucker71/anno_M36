class_name BuildGrid
extends RefCounted
## Dictionary-based placement grid: Vector2i cell -> BuildingInstance.
## Owns placement rules and the port-link graph between buildings.

signal building_placed(inst: BuildingInstance)
signal building_removed(inst: BuildingInstance)
signal links_changed

var terrain: TerrainData
var deposits: DepositMap
var occupancy: Dictionary = {}           # Vector2i -> BuildingInstance
var buildings: Array[BuildingInstance] = []
var _next_uid: int = 1


func _init(p_terrain: TerrainData, p_deposits: DepositMap) -> void:
	terrain = p_terrain
	deposits = p_deposits


func building_at(c: Vector2i) -> BuildingInstance:
	return occupancy.get(c)


## Checks placement without changing anything.
## Returns { ok, reason, cells, ports, recipe, cluster, coverage }.
func check_placement(def: BuildingDef, origin: Vector2i, rotation: int) -> Dictionary:
	var result := {
		"ok": false, "reason": "", "cells": [], "ports": [],
		"recipe": null, "cluster": -1, "coverage": 0.0,
	}
	var cells: Array[Vector2i] = []
	for c in Footprint.rotated_cells(def.cells, rotation):
		cells.append(origin + c)
	result["cells"] = cells
	var ports := []
	for p in Footprint.rotated_ports(def.cells, def.ports, rotation):
		ports.append({"cell": origin + p["cell"], "dir": p["dir"], "kind": p["kind"]})
	result["ports"] = ports

	for c in cells:
		if not terrain.in_bounds(c):
			result["reason"] = "Out of bounds"
			return result
		if not terrain.is_buildable(c):
			result["reason"] = "Needs flat ground"
			return result
		if occupancy.has(c):
			result["reason"] = "Space occupied"
			return result

	if def.needs_deposit:
		var best := _best_deposit(def, cells)
		if best.is_empty():
			result["reason"] = "Must cover a matching deposit"
			return result
		result["recipe"] = best["recipe"]
		result["cluster"] = best["cluster"]
		result["coverage"] = best["coverage"]
	elif def.recipes.size() > 0:
		result["recipe"] = Database.recipe(def.recipes[0])

	result["ok"] = true
	return result


func place(def: BuildingDef, origin: Vector2i, rotation: int) -> BuildingInstance:
	var check := check_placement(def, origin, rotation)
	if not check["ok"]:
		return null
	var inst := BuildingInstance.new()
	inst.setup(_next_uid, def, origin, rotation)
	_next_uid += 1
	inst.recipe = check["recipe"]
	inst.deposit_cluster = check["cluster"]
	inst.deposit_coverage = check["coverage"]
	for c in inst.cells:
		occupancy[c] = inst
	buildings.append(inst)
	relink()
	building_placed.emit(inst)
	return inst


func remove(inst: BuildingInstance) -> void:
	if not buildings.has(inst):
		return
	for c in inst.cells:
		if occupancy.get(c) == inst:
			occupancy.erase(c)
	buildings.erase(inst)
	relink()
	building_removed.emit(inst)


## Swaps a housing building for its upgrade in place. Same footprint by design.
func replace_def(inst: BuildingInstance, new_def: BuildingDef) -> void:
	inst.def = new_def
	links_changed.emit()


## Rebuilds every output-port -> input-port link. Cheap at the building counts
## a hive map reaches; revisit if it shows up in a profile.
func relink() -> void:
	for b in buildings:
		b.links_out.clear()
	for b in buildings:
		for p in b.ports:
			if p["kind"] != BuildingDef.PortKind.OUTPUT:
				continue
			var target_cell: Vector2i = p["cell"] + p["dir"]
			var other: BuildingInstance = occupancy.get(target_cell)
			if other == null or other == b:
				continue
			if other.has_input_port_at(target_cell, -p["dir"]) and not b.links_out.has(other):
				b.links_out.append(other)
	links_changed.emit()


## Finds the deposit under the footprint that one of the building's
## extraction recipes can work, preferring the best-covered cluster.
func _best_deposit(def: BuildingDef, cells: Array[Vector2i]) -> Dictionary:
	var counts := {}   # cluster id -> covered cells
	for c in cells:
		var cl := deposits.cluster_at(c)
		if cl != null and cl.remaining > 0:
			counts[cl.id] = int(counts.get(cl.id, 0)) + 1
	var best := {}
	var best_count := 0
	for cid in counts:
		var cl := deposits.get_cluster(cid)
		for rid in def.recipes:
			var r := Database.recipe(rid)
			if r != null and r.deposit == cl.item and counts[cid] > best_count:
				best_count = counts[cid]
				best = {"recipe": r, "cluster": cid,
					"coverage": float(counts[cid]) / float(cells.size())}
	return best
