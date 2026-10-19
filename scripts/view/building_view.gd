class_name BuildingView
extends Node3D
## Placeholder visuals for a building: one block per cell, port markers and a
## status lamp. Swap for real models later; nothing in the sim depends on this.

const CELL_INSET := 0.92
const INPUT_COLOUR := Color(0.23, 0.54, 0.85)
const OUTPUT_COLOUR := Color(0.88, 0.54, 0.16)
const LAMP_COLOURS := {
	BuildingInstance.Status.WORKING: Color(0.3, 0.85, 0.3),
	BuildingInstance.Status.PASSIVE: Color(0.3, 0.85, 0.3),
	BuildingInstance.Status.HOUSING: Color(0.85, 0.75, 0.45),
	BuildingInstance.Status.MISSING_INPUTS: Color(0.95, 0.7, 0.15),
	BuildingInstance.Status.OUTPUT_BLOCKED: Color(0.95, 0.4, 0.1),
	BuildingInstance.Status.NO_WORKERS: Color(0.9, 0.15, 0.15),
	BuildingInstance.Status.DEPOSIT_EXHAUSTED: Color(0.5, 0.5, 0.5),
}

static var _materials: Dictionary = {}

var inst: BuildingInstance
var _lamp: MeshInstance3D
var _selection: MeshInstance3D


static func material(colour: Color, alpha: float = 1.0, unshaded: bool = false) -> StandardMaterial3D:
	var key := "%s|%.2f|%s" % [colour.to_html(), alpha, unshaded]
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(colour, alpha)
	mat.roughness = 0.85
	if alpha < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[key] = mat
	return mat


static func cell_centre(c: Vector2i, y: float = 0.0) -> Vector3:
	return Vector3(c.x + 0.5, y, c.y + 0.5)


## Builds one merged block for the footprint, plus port markers, into parent.
## Body materials that use vertex colours get a lit top and darker walls.
static func add_shape(parent: Node3D, cells: Array, ports: Array, height: float,
		body: Material, in_mat: Material, out_mat: Material, colour: Color = Color.WHITE) -> void:
	var body_mesh := MeshInstance3D.new()
	body_mesh.mesh = footprint_mesh(cells, height, colour)
	body_mesh.material_override = body
	parent.add_child(body_mesh)
	for p in ports:
		var dir: Vector2i = p["dir"]
		var marker := BoxMesh.new()
		var along := 0.22
		var across := 0.4
		marker.size = Vector3(along if dir.x != 0 else across, 0.18, along if dir.y != 0 else across)
		var mi := MeshInstance3D.new()
		mi.mesh = marker
		mi.material_override = in_mat if p["kind"] == BuildingDef.PortKind.INPUT else out_mat
		mi.position = cell_centre(p["cell"], 0.2) + Vector3(dir.x, 0, dir.y) * (CELL_INSET / 2.0)
		parent.add_child(mi)


## A single extruded mesh for a set of cells: no seams between cells of the
## same building, a small inset on the outside so neighbours stay readable.
static func footprint_mesh(cells: Array, height: float, colour: Color) -> ArrayMesh:
	var inset := (1.0 - CELL_INSET) / 2.0
	var lookup := {}
	for c in cells:
		lookup[c] = true
	var top_col := colour.lightened(0.12)
	var wall_col := colour.darkened(0.12)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c: Vector2i in cells:
		var x0 := c.x + (inset if not lookup.has(c + Vector2i(-1, 0)) else 0.0)
		var x1 := c.x + 1.0 - (inset if not lookup.has(c + Vector2i(1, 0)) else 0.0)
		var z0 := c.y + (inset if not lookup.has(c + Vector2i(0, -1)) else 0.0)
		var z1 := c.y + 1.0 - (inset if not lookup.has(c + Vector2i(0, 1)) else 0.0)
		_face(st, Vector3(x0, height, z0), Vector3(x1, height, z0), Vector3(x1, height, z1),
			Vector3(x0, height, z1), Vector3.UP, top_col)
		if not lookup.has(c + Vector2i(0, -1)):
			_face(st, Vector3(x1, height, z0), Vector3(x0, height, z0), Vector3(x0, 0, z0),
				Vector3(x1, 0, z0), Vector3.FORWARD, wall_col)
		if not lookup.has(c + Vector2i(0, 1)):
			_face(st, Vector3(x0, height, z1), Vector3(x1, height, z1), Vector3(x1, 0, z1),
				Vector3(x0, 0, z1), Vector3.BACK, wall_col)
		if not lookup.has(c + Vector2i(-1, 0)):
			_face(st, Vector3(x0, height, z0), Vector3(x0, height, z1), Vector3(x0, 0, z1),
				Vector3(x0, 0, z0), Vector3.LEFT, wall_col)
		if not lookup.has(c + Vector2i(1, 0)):
			_face(st, Vector3(x1, height, z1), Vector3(x1, height, z0), Vector3(x1, 0, z0),
				Vector3(x1, 0, z1), Vector3.RIGHT, wall_col)
	return st.commit()


static func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		normal: Vector3, col: Color) -> void:
	st.set_normal(normal)
	st.set_color(col)
	for v in [a, b, c, a, c, d]:
		st.add_vertex(v)


static func vertex_colour_material() -> StandardMaterial3D:
	if _materials.has("vertex"):
		return _materials["vertex"]
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials["vertex"] = mat
	return mat


func setup(p_inst: BuildingInstance) -> void:
	inst = p_inst
	rebuild()


func rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_lamp = null
	_selection = null
	add_shape(self, inst.cells, inst.ports, inst.def.height, vertex_colour_material(),
		material(INPUT_COLOUR), material(OUTPUT_COLOUR), inst.def.colour)

	var lamp_mesh := SphereMesh.new()
	lamp_mesh.radius = 0.16
	lamp_mesh.height = 0.32
	_lamp = MeshInstance3D.new()
	_lamp.mesh = lamp_mesh
	_lamp.position = cell_centre(inst.cells[0], inst.def.height + 0.25)
	add_child(_lamp)

	var ring := BoxMesh.new()
	ring.size = Vector3(1.0, 0.05, 1.0)
	_selection = MeshInstance3D.new()
	_selection.visible = false
	add_child(_selection)
	for c in inst.cells:
		var mi := MeshInstance3D.new()
		mi.mesh = ring
		mi.material_override = material(Color(1, 0.85, 0.3), 0.6, true)
		mi.position = cell_centre(c, 0.03)
		_selection.add_child(mi)
	update_status()


func update_status() -> void:
	if _lamp:
		var col: Color = LAMP_COLOURS.get(inst.status, Color(0.6, 0.6, 0.6))
		_lamp.material_override = material(col, 1.0, true)


func set_selected(on: bool) -> void:
	if _selection:
		_selection.visible = on
