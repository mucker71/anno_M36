class_name NetworkView
extends Node3D
## Draws walkways, roads and cargo rail as low slabs that join up with their
## neighbours, rebuilt whenever the transport grid changes.

const WALK_COLOUR := Color(0.42, 0.40, 0.36)
const ROAD_COLOUR := Color(0.17, 0.16, 0.16)
const ROAD_LINE := Color(0.55, 0.45, 0.20)
const BALLAST := Color(0.26, 0.22, 0.20)
const SLEEPER := Color(0.30, 0.22, 0.15)
const RAIL := Color(0.62, 0.62, 0.66)

var transport: TransportGrid
var _mesh := MeshInstance3D.new()
var _queued := false


func setup(p_transport: TransportGrid) -> void:
	transport = p_transport
	_mesh.material_override = BuildingView.vertex_colour_material()
	add_child(_mesh)
	transport.changed.connect(_queue)
	rebuild()


func _queue() -> void:
	if not _queued:
		_queued = true
		rebuild.call_deferred()


func rebuild() -> void:
	_queued = false
	if transport.tiles.is_empty():
		_mesh.mesh = null
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c: Vector2i in transport.tiles:
		var m := transport.mask_at(c)
		var cx := c.x + 0.5
		var cz := c.y + 0.5
		if m & TransportGrid.Net.ROAD:
			add_box(st, Vector3(c.x + 0.02, 0.0, c.y + 0.02), Vector3(c.x + 0.98, 0.05, c.y + 0.98), ROAD_COLOUR)
			for d in TransportGrid.DIRS:
				if transport.has(c + d, TransportGrid.Net.ROAD):
					_arm(st, cx, cz, d, 0.06, 0.05, 0.065, ROAD_LINE)
		elif m & TransportGrid.Net.WALK:
			add_box(st, Vector3(cx - 0.25, 0.0, cz - 0.25), Vector3(cx + 0.25, 0.04, cz + 0.25), WALK_COLOUR)
			for d in TransportGrid.DIRS:
				if transport.in_graph(c + d, TransportGrid.Graph.PEOPLE):
					_arm(st, cx, cz, d, 0.5, 0.0, 0.04, WALK_COLOUR)
		if m & TransportGrid.Net.RAIL:
			var base := 0.06 if m & TransportGrid.Net.ROAD else 0.0
			var any := false
			for d in TransportGrid.DIRS:
				if transport.has(c + d, TransportGrid.Net.RAIL):
					any = true
					_rail_arm(st, cx, cz, d, base)
			if not any:
				_rail_arm(st, cx, cz, Vector2i(1, 0), base)
				_rail_arm(st, cx, cz, Vector2i(-1, 0), base)
	_mesh.mesh = st.commit()


func _arm(st: SurfaceTool, cx: float, cz: float, d: Vector2i, width: float, y0: float, y1: float, col: Color) -> void:
	var h := width / 2.0
	var ex := cx + d.x * 0.5
	var ez := cz + d.y * 0.5
	add_box(st, Vector3(minf(cx, ex) - (h if d.x == 0 else 0.0), y0, minf(cz, ez) - (h if d.y == 0 else 0.0)),
		Vector3(maxf(cx, ex) + (h if d.x == 0 else 0.0), y1, maxf(cz, ez) + (h if d.y == 0 else 0.0)), col)


func _rail_arm(st: SurfaceTool, cx: float, cz: float, d: Vector2i, base: float) -> void:
	_arm(st, cx, cz, d, 0.62, base, base + 0.04, BALLAST)
	# Sleepers across the arm.
	for i in 2:
		var t := 0.12 + i * 0.25
		var sx := cx + d.x * t
		var sz := cz + d.y * t
		var across := Vector2(absf(d.y), absf(d.x)) * 0.28
		var along := Vector2(absf(d.x), absf(d.y)) * 0.05
		add_box(st, Vector3(sx - across.x - along.x, base + 0.04, sz - across.y - along.y),
			Vector3(sx + across.x + along.x, base + 0.07, sz + across.y + along.y), SLEEPER)
	# Two rails.
	for side: float in [-0.15, 0.15]:
		var ox := cx + absf(d.y) * side
		var oz := cz + absf(d.x) * side
		_arm(st, ox, oz, d, 0.05, base + 0.07, base + 0.11, RAIL)


## Axis-aligned box: top and four sides (no bottom).
static func add_box(st: SurfaceTool, lo: Vector3, hi: Vector3, col: Color) -> void:
	var top := col.lightened(0.06)
	var side := col.darkened(0.2)
	_quad(st, Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3.UP, top)
	_quad(st, Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3.FORWARD, side)
	_quad(st, Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3.BACK, side)
	_quad(st, Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3.LEFT, side)
	_quad(st, Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3.RIGHT, side)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	st.set_normal(n)
	st.set_color(col)
	for v in [a, b, c, a, c, d]:
		st.add_vertex(v)
