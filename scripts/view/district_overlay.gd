class_name DistrictOverlay
extends MeshInstance3D
## Translucent tint over painted district cells, with darker edges at borders.

var districts: DistrictMap
var _queued := false


func setup(p_districts: DistrictMap) -> void:
	districts = p_districts
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	districts.changed.connect(_queue)
	rebuild()


func _queue() -> void:
	if not _queued:
		_queued = true
		rebuild.call_deferred()


func rebuild() -> void:
	_queued = false
	var cells := districts.painted_cells()
	if cells.is_empty():
		mesh = null
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for c: Vector2i in cells:
		var id := int(cells[c])
		var d := districts.get_district(id)
		if d == null:
			continue
		var fill := Color(d.colour, 0.16)
		_rect(st, c.x, c.y, c.x + 1.0, c.y + 1.0, 0.07, fill)
		var edge := Color(d.colour, 0.75)
		var w := 0.08
		if districts.id_at(c + Vector2i(0, -1)) != id:
			_rect(st, c.x, c.y, c.x + 1.0, c.y + w, 0.075, edge)
		if districts.id_at(c + Vector2i(0, 1)) != id:
			_rect(st, c.x, c.y + 1.0 - w, c.x + 1.0, c.y + 1.0, 0.075, edge)
		if districts.id_at(c + Vector2i(-1, 0)) != id:
			_rect(st, c.x, c.y, c.x + w, c.y + 1.0, 0.075, edge)
		if districts.id_at(c + Vector2i(1, 0)) != id:
			_rect(st, c.x + 1.0 - w, c.y, c.x + 1.0, c.y + 1.0, 0.075, edge)
	mesh = st.commit()


func _rect(st: SurfaceTool, x0: float, z0: float, x1: float, z1: float, y: float, col: Color) -> void:
	st.set_color(col)
	for v in [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1),
			Vector3(x0, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)]:
		st.add_vertex(v)
