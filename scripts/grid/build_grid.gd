class_name BuildGrid
extends RefCounted
## Dictionary-based placement grid: Vector2i cell -> BuildingInstance.
## Owns placement rules, the port-link graph between buildings and module
## attachment. Transport tiles and districts live alongside it and share the
## same cells, so all "can this go here" rules are answered in one place.

signal building_placed(inst: BuildingInstance)
signal building_removed(inst: BuildingInstance)
signal links_changed
## Anything that changes connectivity: buildings, transport or districts.
signal topology_changed

var terrain: TerrainData
var deposits: DepositMap
var transport: TransportGrid
var districts: DistrictMap
var occupancy: Dictionary = {}           # Vector2i -> BuildingInstance
var buildings: Array[BuildingInstance] = []
## Bumped on every topology change; the economy rebuilds caches when it moves.
var topology_version: int = 0
var _next_uid: int = 1


func _init(p_terrain: TerrainData, p_deposits: DepositMap,
		p_transport: TransportGrid = null, p_districts: DistrictMap = null) -> void:
	terrain = p_terrain
	deposits = p_deposits
	transport = p_transport if p_transport else TransportGrid.new(p_terrain)
	districts = p_districts if p_districts else DistrictMap.new(p_terrain.size)
	transport.changed.connect(_bump)
	districts.changed.connect(_bump)


func building_at(c: Vector2i) -> BuildingInstance:
	return occupancy.get(c)


## Checks placement without changing anything.
## Returns { ok, reason, cells, ports, recipe, cluster, coverage, district, host }.
func check_placement(def: BuildingDef, origin: Vector2i, rotation: int) -> Dictionary:
	var result := {
		"ok": false, "reason": "", "cells": [], "ports": [],
		"recipe": null, "cluster": -1, "coverage": 0.0, "district": -1, "host": null,
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
		if transport.mask_at(c) != 0:
			result["reason"] = "Transport in the way"
			return result

	var district := districts.district_of(cells)
	if district < 0:
		result["reason"] = "Must sit inside one district"
		return result
	result["district"] = district

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

	if def.is_module():
		# Placement is allowed without a host (it can wait for one), but say so.
		result["host"] = _find_host(def, cells, null)

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
	inst.district_id = check["district"]
	for c in inst.cells:
		occupancy[c] = inst
	buildings.append(inst)
	relink()
	reattach_modules()
	building_placed.emit(inst)
	_bump()
	return inst


func remove(inst: BuildingInstance) -> void:
	if not buildings.has(inst):
		return
	for c in inst.cells:
		if occupancy.get(c) == inst:
			occupancy.erase(c)
	buildings.erase(inst)
	relink()
	reattach_modules()
	inst.modules.clear()
	inst.host = null
	building_removed.emit(inst)
	_bump()


## Swaps a housing building for its upgrade in place. Same footprint by design.
func replace_def(inst: BuildingInstance, new_def: BuildingDef) -> void:
	inst.def = new_def
	links_changed.emit()
	_bump()


## Rebuilds every output-port -> input-port link.
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


## Attaches every module to a host it touches, oldest modules first.
## A host takes modules up to its slot count; extras wait unattached.
func reattach_modules() -> void:
	for b in buildings:
		b.modules.clear()
		b.host = null
	for b in buildings:
		if not b.def.is_module():
			continue
		var h := _find_host(b.def, b.cells, b)
		if h:
			b.host = h
			h.modules.append(b)
		b.status = BuildingInstance.Status.NO_HOST if h == null else BuildingInstance.Status.MODULE_ACTIVE
	# A host that lost a module recipe falls back to its own first recipe.
	for b in buildings:
		if b.recipe and not b.def.is_module() and not b.available_recipes().has(b.recipe.id):
			b.set_recipe(Database.recipe(b.def.recipes[0]) if not b.def.recipes.is_empty() else null)


## Cells touching a footprint from outside.
func neighbours_of(cells: Array) -> Array[BuildingInstance]:
	var own := {}
	for c in cells:
		own[c] = true
	var out: Array[BuildingInstance] = []
	for c: Vector2i in cells:
		for d in Footprint.DIRS:
			var n := c + d
			if own.has(n):
				continue
			var other: BuildingInstance = occupancy.get(n)
			if other and not out.has(other):
				out.append(other)
	return out


func _find_host(def: BuildingDef, cells: Array, self_inst: BuildingInstance) -> BuildingInstance:
	var best: BuildingInstance = null
	var best_edges := 0
	for other in neighbours_of(cells):
		if other == self_inst or other.def.is_module() or not def.accepts_host(other.def):
			continue
		if other.free_module_slots() <= 0:
			continue
		var edges := _shared_edges(cells, other)
		if edges > best_edges or (edges == best_edges and best and other.uid < best.uid):
			best = other
			best_edges = edges
	return best


func _shared_edges(cells: Array, other: BuildingInstance) -> int:
	var n := 0
	for c: Vector2i in cells:
		for d in Footprint.DIRS:
			if occupancy.get(c + d) == other:
				n += 1
	return n


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


func _bump() -> void:
	topology_version += 1
	topology_changed.emit()
