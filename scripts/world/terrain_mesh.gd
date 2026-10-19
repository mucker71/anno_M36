class_name TerrainMesh
extends RefCounted
## Builds the stepped, blocky terrain mesh with SurfaceTool (ArrayMesh).
## One unit per tile. Deposits are tinted into the ground colour.

const LEVEL_HEIGHT := 0.6
const WATER_FLOOR := -0.5
const WATER_SURFACE := -0.18

const GROUND_A := Color(0.150, 0.138, 0.128)
const GROUND_B := Color(0.128, 0.118, 0.110)
const ROCK := Color(0.22, 0.21, 0.22)
const ROCK_TOP := Color(0.34, 0.32, 0.32)
const LAKE_BED := Color(0.10, 0.13, 0.12)


static func top_height(terrain: TerrainData, c: Vector2i) -> float:
	match terrain.tile(c):
		TerrainData.Tile.WATER:
			return WATER_FLOOR
		TerrainData.Tile.MOUNTAIN:
			return terrain.level(c) * LEVEL_HEIGHT
	return 0.0


static func build(terrain: TerrainData, deposits: DepositMap) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in terrain.size.y:
		for x in terrain.size.x:
			var c := Vector2i(x, y)
			var h := top_height(terrain, c)
			var col := _tile_colour(terrain, deposits, c)
			_quad(st, Vector3(x, h, y), Vector3(x + 1, h, y), Vector3(x + 1, h, y + 1), Vector3(x, h, y + 1),
				Vector3.UP, col)
			# Side walls where the neighbour is lower.
			for d in Footprint.DIRS:
				var n := c + d
				var nh := top_height(terrain, n) if terrain.in_bounds(n) else WATER_FLOOR
				if nh >= h:
					continue
				var wall := col.darkened(0.35)
				var normal := Vector3(d.x, 0, d.y)
				var a: Vector3
				var b: Vector3
				if d == Vector2i(0, -1):
					a = Vector3(x + 1, 0, y)
					b = Vector3(x, 0, y)
				elif d == Vector2i(1, 0):
					a = Vector3(x + 1, 0, y + 1)
					b = Vector3(x + 1, 0, y)
				elif d == Vector2i(0, 1):
					a = Vector3(x, 0, y + 1)
					b = Vector3(x + 1, 0, y + 1)
				else:
					a = Vector3(x, 0, y)
					b = Vector3(x, 0, y + 1)
				_quad(st, Vector3(a.x, h, a.z), Vector3(b.x, h, b.z), Vector3(b.x, nh, b.z),
					Vector3(a.x, nh, a.z), normal, wall)
	return st.commit()


static func make_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


static func make_water(terrain: TerrainData) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(terrain.size)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.24, 0.20, 0.82)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.2
	mat.metallic = 0.3
	plane.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "Sump"
	mi.mesh = plane
	mi.position = Vector3(terrain.size.x / 2.0, WATER_SURFACE, terrain.size.y / 2.0)
	return mi


static func _tile_colour(terrain: TerrainData, deposits: DepositMap, c: Vector2i) -> Color:
	match terrain.tile(c):
		TerrainData.Tile.WATER:
			return LAKE_BED
		TerrainData.Tile.MOUNTAIN:
			return ROCK.lerp(ROCK_TOP, float(terrain.level(c)) / TerrainGenerator.MAX_LEVEL)
	var base := GROUND_A if (c.x + c.y) % 2 == 0 else GROUND_B
	var cl: DepositMap.Cluster = deposits.cluster_at(c) if deposits else null
	if cl != null:
		var item := Database.item(cl.item)
		if item:
			return base.lerp(item.colour, 0.5)
	return base


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		normal: Vector3, col: Color) -> void:
	st.set_normal(normal)
	st.set_color(col)
	for v in [a, b, c, a, c, d]:
		st.add_vertex(v)
