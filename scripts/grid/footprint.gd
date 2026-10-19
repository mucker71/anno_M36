class_name Footprint
extends RefCounted
## Rotation and shape helpers for building footprints and ports.
## Rotation r is in quarter turns clockwise seen from above (x east, y south).

const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


static func rotate_vec(v: Vector2i, r: int) -> Vector2i:
	var out := v
	for i in posmod(r, 4):
		out = Vector2i(-out.y, out.x)
	return out


## Cells after rotation, shifted so the minimum corner is (0, 0).
static func rotated_cells(cells: Array[Vector2i], r: int) -> Array[Vector2i]:
	var rotated: Array[Vector2i] = []
	for c in cells:
		rotated.append(rotate_vec(c, r))
	var offset := _min_corner(rotated)
	for i in rotated.size():
		rotated[i] -= offset
	return rotated


## Ports after rotation, using the same shift as rotated_cells.
static func rotated_ports(cells: Array[Vector2i], ports: Array, r: int) -> Array:
	var raw: Array[Vector2i] = []
	for c in cells:
		raw.append(rotate_vec(c, r))
	var offset := _min_corner(raw)
	var out := []
	for p in ports:
		out.append({
			"cell": rotate_vec(p["cell"], r) - offset,
			"dir": rotate_vec(p["dir"], r),
			"kind": p["kind"],
		})
	return out


static func is_single_piece(cells: Array[Vector2i]) -> bool:
	if cells.is_empty():
		return false
	var occupied := {}
	for c in cells:
		occupied[c] = true
	var seen := {cells[0]: true}
	var stack: Array[Vector2i] = [cells[0]]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for d in DIRS:
			var n := c + d
			if occupied.has(n) and not seen.has(n):
				seen[n] = true
				stack.append(n)
	return seen.size() == occupied.size()


## True if no empty cell is fully enclosed by the shape (the "no dead space" rule).
static func has_no_holes(cells: Array[Vector2i]) -> bool:
	var occupied := {}
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for c in cells:
		occupied[c] = true
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	lo -= Vector2i.ONE
	hi += Vector2i.ONE
	# Flood the empty space from outside the bounding box.
	var seen := {lo: true}
	var stack: Array[Vector2i] = [lo]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for d in DIRS:
			var n := c + d
			if n.x < lo.x or n.y < lo.y or n.x > hi.x or n.y > hi.y:
				continue
			if occupied.has(n) or seen.has(n):
				continue
			seen[n] = true
			stack.append(n)
	var empty_total := (hi.x - lo.x + 1) * (hi.y - lo.y + 1) - occupied.size()
	return seen.size() == empty_total


static func _min_corner(cells: Array[Vector2i]) -> Vector2i:
	var lo := Vector2i(1 << 20, 1 << 20)
	for c in cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
	return lo
