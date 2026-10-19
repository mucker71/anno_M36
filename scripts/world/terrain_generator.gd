class_name TerrainGenerator
extends RefCounted
## Procedural hive floor: large flat expanses for building, broken up by
## mountain "islands" (collapsed spire stumps) and sunken sump-lakes.

const CLEAR_RADIUS := 16.0        ## flat ground kept around the map centre
const MOUNTAIN_THRESHOLD := 0.42  ## TUNE: higher = fewer mountains
const LAKE_THRESHOLD := -0.52     ## TUNE: lower = fewer lakes
const MAX_LEVEL := 5


static func generate(map_size: Vector2i, seed_value: int) -> TerrainData:
	var data := TerrainData.new(map_size)

	var mountains := FastNoiseLite.new()
	mountains.seed = seed_value
	mountains.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	mountains.frequency = 0.025
	mountains.fractal_octaves = 3

	var lakes := FastNoiseLite.new()
	lakes.seed = seed_value + 7919
	lakes.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	lakes.frequency = 0.035
	lakes.fractal_octaves = 2

	var centre := Vector2(map_size) / 2.0
	for y in map_size.y:
		for x in map_size.x:
			var c := Vector2i(x, y)
			var dist := Vector2(x, y).distance_to(centre)
			# Fade features out near the centre so the start area is open.
			var fade := clampf((dist - CLEAR_RADIUS) / 12.0, 0.0, 1.0)
			var m := mountains.get_noise_2d(x, y) * fade
			var w := lakes.get_noise_2d(x, y) * fade
			# A ragged wall of rock at the map edge.
			var edge := mini(mini(x, y), mini(map_size.x - 1 - x, map_size.y - 1 - y))
			if edge < 2:
				m = maxf(m, MOUNTAIN_THRESHOLD + 0.1 + 0.05 * (2 - edge))
			if m > MOUNTAIN_THRESHOLD:
				var lvl := clampi(1 + int((m - MOUNTAIN_THRESHOLD) * 14.0), 1, MAX_LEVEL)
				data.set_tile(c, TerrainData.Tile.MOUNTAIN, lvl)
			elif w < LAKE_THRESHOLD:
				data.set_tile(c, TerrainData.Tile.WATER, -1)
			else:
				data.set_tile(c, TerrainData.Tile.GROUND, 0)
	return data
