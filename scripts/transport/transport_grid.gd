class_name TransportGrid
extends RefCounted
## The three transport networks, stored as a bitmask per tile.
##
##  WALK  walkways: cheap, people only.
##  ROAD  civilian traffic: haulers move goods between buildings and their
##        district depot. Roads also carry pedestrians (pavements).
##  RAIL  cargo rail: freight trains between cargo stations, across districts.
##
## Crossings are allowed: rail over a road (level crossing) or over a walkway
## (footbridge). A walkway placed on a road does nothing; a road placed on a
## walkway upgrades it.
##
## Each network has its own graph. Connectivity (components) is cached and
## rebuilt lazily after any change. Paths use breadth-first search, which is
## exact on a uniform grid and cheap at these sizes.

signal changed

enum Net { WALK = 1, ROAD = 2, RAIL = 4 }
## Graphs: which tiles each kind of traffic can use.
enum Graph { PEOPLE, ROAD, RAIL }

const GRAPH_MASK := {
	Graph.PEOPLE: Net.WALK | Net.ROAD,
	Graph.ROAD: Net.ROAD,
	Graph.RAIL: Net.RAIL,
}
const NET_NAMES := {Net.WALK: "Walkway", Net.ROAD: "Road", Net.RAIL: "Cargo Rail"}
## TUNE: build cost per tile
const COSTS := {
	Net.WALK: {&"ferrocrete": 1},
	Net.ROAD: {&"ferrocrete": 2},
	Net.RAIL: {&"steel": 1, &"ferrocrete": 1},
}
const ALLOWED_MASKS := [Net.WALK, Net.ROAD, Net.RAIL, Net.ROAD | Net.RAIL, Net.WALK | Net.RAIL]
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

var terrain: TerrainData
var tiles: Dictionary = {}          # Vector2i -> int mask
var _components: Dictionary = {}    # Graph -> { Vector2i: int }
var _dirty := true


func _init(p_terrain: TerrainData) -> void:
	terrain = p_terrain


func mask_at(c: Vector2i) -> int:
	return int(tiles.get(c, 0))


func has(c: Vector2i, net: int) -> bool:
	return (mask_at(c) & net) != 0


func in_graph(c: Vector2i, graph: int) -> bool:
	return (mask_at(c) & int(GRAPH_MASK[graph])) != 0


## What adding this network to a tile would produce: { ok, reason, mask }.
## blocked_by_building is checked by the caller (BuildGrid owns occupancy).
func check_add(c: Vector2i, net: int) -> Dictionary:
	if not terrain.is_buildable(c):
		return {"ok": false, "reason": "Needs flat ground", "mask": 0}
	var old := mask_at(c)
	var new_mask := old | net
	if net == Net.ROAD and (old & Net.WALK) != 0:
		new_mask = (old & ~Net.WALK) | Net.ROAD   # road replaces walkway
	if net == Net.WALK and (old & Net.ROAD) != 0:
		return {"ok": false, "reason": "Roads already carry pedestrians", "mask": old}
	if new_mask == old:
		return {"ok": false, "reason": "Already built", "mask": old}
	if not ALLOWED_MASKS.has(new_mask):
		return {"ok": false, "reason": "Can't combine those networks", "mask": old}
	return {"ok": true, "reason": "", "mask": new_mask}


func set_mask(c: Vector2i, mask: int) -> void:
	if mask == 0:
		tiles.erase(c)
	else:
		tiles[c] = mask
	_dirty = true
	changed.emit()


## Sets many tiles and emits one change.
func set_masks(masks: Dictionary) -> void:
	for c in masks:
		if int(masks[c]) == 0:
			tiles.erase(c)
		else:
			tiles[c] = int(masks[c])
	_dirty = true
	changed.emit()


## Component id of a tile in a graph, or -1 if the tile is not on it.
func component(graph: int, c: Vector2i) -> int:
	_ensure_components()
	return int(_components[graph].get(c, -1))


## Network tiles of a graph orthogonally touching a footprint.
func touching(cells: Array, graph: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var own := {}
	for c in cells:
		own[c] = true
	for c: Vector2i in cells:
		for d in DIRS:
			var n := c + d
			if not own.has(n) and in_graph(n, graph) and not out.has(n):
				out.append(n)
	return out


## Components of a graph that a footprint touches.
func components_touching(cells: Array, graph: int) -> Dictionary:
	var out := {}
	for t in touching(cells, graph):
		out[component(graph, t)] = true
	return out


## Breadth-first distances from sources over a graph, up to max_dist steps.
func distances(graph: int, sources: Array, max_dist: int) -> Dictionary:
	var dist := {}
	var queue: Array[Vector2i] = []
	for s: Vector2i in sources:
		if in_graph(s, graph) and not dist.has(s):
			dist[s] = 0
			queue.append(s)
	var head := 0
	var mask := int(GRAPH_MASK[graph])
	while head < queue.size():
		var c := queue[head]
		head += 1
		var d: int = dist[c]
		if d >= max_dist:
			continue
		for dir in DIRS:
			var n := c + dir
			if dist.has(n) or (int(tiles.get(n, 0)) & mask) == 0:
				continue
			dist[n] = d + 1
			queue.append(n)
	return dist


## Shortest path over a graph from any source tile to any goal tile.
## Returns the tiles in order, or an empty array if unreachable.
func find_path(graph: int, sources: Array, goals: Array, max_dist: int = 400) -> Array[Vector2i]:
	var goal_set := {}
	for g in goals:
		goal_set[g] = true
	var came := {}
	var queue: Array[Vector2i] = []
	for s: Vector2i in sources:
		if in_graph(s, graph) and not came.has(s):
			came[s] = s
			queue.append(s)
	var head := 0
	var mask := int(GRAPH_MASK[graph])
	var found := Vector2i(-1, -1)
	var steps := {}
	for s in queue:
		steps[s] = 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		if goal_set.has(c):
			found = c
			break
		if int(steps[c]) >= max_dist:
			continue
		for dir in DIRS:
			var n := c + dir
			if came.has(n) or (int(tiles.get(n, 0)) & mask) == 0:
				continue
			came[n] = c
			steps[n] = int(steps[c]) + 1
			queue.append(n)
	var path: Array[Vector2i] = []
	if found.x < 0:
		return path
	var cur := found
	while true:
		path.append(cur)
		var prev: Vector2i = came[cur]
		if prev == cur:
			break
		cur = prev
	path.reverse()
	return path


func tile_count(net: int) -> int:
	var n := 0
	for c in tiles:
		if (int(tiles[c]) & net) != 0:
			n += 1
	return n


func _ensure_components() -> void:
	if not _dirty:
		return
	_dirty = false
	for graph in GRAPH_MASK:
		var comp := {}
		var mask := int(GRAPH_MASK[graph])
		var next_id := 0
		for start in tiles:
			if comp.has(start) or (int(tiles[start]) & mask) == 0:
				continue
			comp[start] = next_id
			var stack: Array[Vector2i] = [start]
			while not stack.is_empty():
				var c: Vector2i = stack.pop_back()
				for dir in DIRS:
					var n := c + dir
					if not comp.has(n) and (int(tiles.get(n, 0)) & mask) != 0:
						comp[n] = next_id
						stack.append(n)
			next_id += 1
		_components[graph] = comp
