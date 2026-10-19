class_name TerrainData
extends RefCounted
## Per-tile terrain: mostly flat buildable ground, with mountain islands and
## sunken sump-lakes that break up the space.

enum Tile { GROUND, MOUNTAIN, WATER }

var size: Vector2i
var tiles: PackedByteArray
## Stepped height level per tile. Ground is 0, mountains 1+, water -1.
var levels: PackedInt32Array


func _init(map_size: Vector2i) -> void:
	size = map_size
	tiles.resize(size.x * size.y)
	levels.resize(size.x * size.y)


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y


func index(c: Vector2i) -> int:
	return c.y * size.x + c.x


func tile(c: Vector2i) -> int:
	return tiles[index(c)] if in_bounds(c) else Tile.MOUNTAIN


func level(c: Vector2i) -> int:
	return levels[index(c)] if in_bounds(c) else 0


func set_tile(c: Vector2i, t: int, lvl: int) -> void:
	var i := index(c)
	tiles[i] = t
	levels[i] = lvl


func is_buildable(c: Vector2i) -> bool:
	return in_bounds(c) and tiles[index(c)] == Tile.GROUND
