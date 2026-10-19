class_name DepositScatter
extends RefCounted
## Seeded scatter of finite resource deposits over buildable ground.
## A few starter deposits are placed near the centre so the early game works.

## item, clusters, min cells, max cells, yield per cell, how many near the start
const SPECS := [
	[&"iron_ore", 7, 6, 14, 400, 1],
	[&"coal", 7, 6, 14, 400, 1],
	[&"copper_ore", 4, 5, 12, 350, 1],
	[&"silica_sand", 5, 8, 16, 350, 1],
	[&"limestone", 5, 8, 16, 350, 1],
	[&"salvage_scrap", 8, 3, 7, 120, 3],
	[&"nickel_ore", 3, 5, 10, 300, 0],
	[&"sulphur", 3, 5, 10, 300, 0],
	[&"crude_promethium", 4, 3, 6, 600, 0],
	[&"rare_earths", 3, 4, 8, 250, 0],
]

const HQ_KEEP_CLEAR := 7.0
const NEAR_MIN := 9.0
const NEAR_MAX := 15.0
const FAR_MIN := 22.0


static func scatter(terrain: TerrainData, seed_value: int) -> DepositMap:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 104729
	var map := DepositMap.new()
	var centre := Vector2(terrain.size) / 2.0
	for spec in SPECS:
		var item: StringName = spec[0]
		for i in int(spec[1]):
			var near := i < int(spec[5])
			var start := _pick_start(terrain, map, rng, centre, near)
			if start.x < 0:
				continue
			var target := rng.randi_range(int(spec[2]), int(spec[3]))
			var cells := _grow_blob(terrain, map, rng, start, target, centre)
			if cells.size() >= 2:
				map.add_cluster(item, cells, cells.size() * int(spec[4]))
	return map


static func _pick_start(terrain: TerrainData, map: DepositMap, rng: RandomNumberGenerator,
		centre: Vector2, near: bool) -> Vector2i:
	for attempt in 400:
		var c: Vector2i
		if near:
			var angle := rng.randf() * TAU
			var r := rng.randf_range(NEAR_MIN, NEAR_MAX)
			c = Vector2i(centre + Vector2(cos(angle), sin(angle)) * r)
		else:
			c = Vector2i(rng.randi_range(3, terrain.size.x - 4), rng.randi_range(3, terrain.size.y - 4))
			if Vector2(c).distance_to(centre) < FAR_MIN:
				continue
		if terrain.is_buildable(c) and not map.has_deposit(c):
			return c
	return Vector2i(-1, -1)


static func _grow_blob(terrain: TerrainData, map: DepositMap, rng: RandomNumberGenerator,
		start: Vector2i, target: int, centre: Vector2) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [start]
	var taken := {start: true}
	var frontier: Array[Vector2i] = [start]
	var guard := 0
	while cells.size() < target and not frontier.is_empty() and guard < target * 60:
		guard += 1
		var from: Vector2i = frontier[rng.randi() % frontier.size()]
		var d: Vector2i = Footprint.DIRS[rng.randi() % 4]
		var n := from + d
		if taken.has(n) or not terrain.is_buildable(n) or map.has_deposit(n):
			# Drop exhausted frontier cells now and then so blobs stay compact.
			if rng.randf() < 0.15:
				frontier.erase(from)
			continue
		if Vector2(n).distance_to(centre) < HQ_KEEP_CLEAR:
			continue
		taken[n] = true
		cells.append(n)
		frontier.append(n)
	return cells
