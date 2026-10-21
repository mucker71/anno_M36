class_name PlacementController
extends Node3D
## Mouse and keyboard handling for every placement tool.
##
##  SELECT    click a building or an empty tile (shows its district).
##  BUILD     a ghost follows the cursor, R rotates, click places (repeatedly).
##  NETWORK   click-drag an L-shaped line of walkway, road or rail.
##  BULLDOZE  click-drag a rectangle to clear transport tiles.
##  DISTRICT  click-drag a rectangle to paint (or erase) a district.
## Right click or Esc returns to SELECT.

signal selection_changed(inst: BuildingInstance)
signal district_selected(id: int)
signal deposit_selected(cluster_id: int)
signal build_mode_changed(def: BuildingDef)
signal mode_changed(mode: int)

enum Mode { SELECT, BUILD, NETWORK, BULLDOZE, DISTRICT }

var world: World
var camera: RtsCamera
var mode: int = Mode.SELECT
var build_def: BuildingDef
var build_rotation: int = 0
var network: int = TransportGrid.Net.ROAD
var paint_district: int = 0
var selected: BuildingInstance
var selected_district: int = -1
var selected_deposit: int = -1
var hover_check: Dictionary = {}
## For line and rectangle tools: what the drag would do. { tiles, ok_count, cost, reason }
var drag_preview: Dictionary = {}

var _ghost: Node3D
var _highlight: Node3D
var _ghost_key: String = ""
var _last_origin := Vector2i(-9999, -9999)
var _drag_start := Vector2i(-1, -1)
var _dragging := false


func _ready() -> void:
	_ghost = Node3D.new()
	_ghost.name = "Ghost"
	add_child(_ghost)
	_highlight = Node3D.new()
	_highlight.name = "Highlight"
	add_child(_highlight)


# --- Mode switching -------------------------------------------------------------

func begin_build(def: BuildingDef) -> void:
	# Set the building before switching mode: _set_mode emits mode_changed and
	# listeners (the HUD) read build_def straight away.
	build_def = def
	build_rotation = 0
	_set_mode(Mode.BUILD)
	build_mode_changed.emit(def)


func begin_network(net: int) -> void:
	_set_mode(Mode.NETWORK)
	network = net


func begin_bulldoze() -> void:
	_set_mode(Mode.BULLDOZE)


func begin_district_paint(id: int) -> void:
	_set_mode(Mode.DISTRICT)
	paint_district = id


func cancel_build() -> void:
	_set_mode(Mode.SELECT)
	build_mode_changed.emit(null)


func _set_mode(m: int) -> void:
	mode = m
	build_def = null if m != Mode.BUILD else build_def
	hover_check = {}
	drag_preview = {}
	_dragging = false
	_ghost_key = ""
	_last_origin = Vector2i(-9999, -9999)
	_clear_ghost()
	if m != Mode.SELECT:
		select(null)
		selected_district = -1
		_set_deposit(-1)
	mode_changed.emit(m)


func select(inst: BuildingInstance) -> void:
	if selected and world.views.has(selected.uid):
		world.views[selected.uid].set_selected(false)
	selected = inst
	if selected and world.views.has(selected.uid):
		world.views[selected.uid].set_selected(true)
	if inst:
		selected_district = -1
		_set_deposit(-1)
	selection_changed.emit(selected)


func select_district(id: int) -> void:
	select(null)
	_set_deposit(-1)
	selected_district = id
	district_selected.emit(id)


## Selects a deposit cluster for the inspector and outlines its tiles.
func select_deposit(cluster_id: int) -> void:
	select(null)
	selected_district = -1
	_set_deposit(cluster_id)
	deposit_selected.emit(cluster_id)


func _set_deposit(cluster_id: int) -> void:
	selected_deposit = cluster_id
	for child in _highlight.get_children():
		child.queue_free()
	var cl := world.deposits.get_cluster(cluster_id) if world else null
	if cl == null:
		return
	var item := Database.item(cl.item)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lookup := {}
	for c in cl.cells:
		lookup[c] = true
	# Mostly white so dark deposits (coal) still show, tinted toward the resource.
	var col := Color((item.colour if item else Color.WHITE).lerp(Color(1, 0.95, 0.8), 0.7), 0.95)
	for c: Vector2i in cl.cells:
		# Bright edge wherever the cluster ends, so its outline reads at any zoom.
		var w := 0.16
		if not lookup.has(c + Vector2i(0, -1)):
			NetworkView.add_box(st, Vector3(c.x, 0.0, c.y), Vector3(c.x + 1, 0.16, c.y + w), col)
		if not lookup.has(c + Vector2i(0, 1)):
			NetworkView.add_box(st, Vector3(c.x, 0.0, c.y + 1 - w), Vector3(c.x + 1, 0.16, c.y + 1), col)
		if not lookup.has(c + Vector2i(-1, 0)):
			NetworkView.add_box(st, Vector3(c.x, 0.0, c.y), Vector3(c.x + w, 0.16, c.y + 1), col)
		if not lookup.has(c + Vector2i(1, 0)):
			NetworkView.add_box(st, Vector3(c.x + 1 - w, 0.0, c.y), Vector3(c.x + 1, 0.16, c.y + 1), col)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _ghost_material()
	_highlight.add_child(mi)


# --- Per frame ------------------------------------------------------------------

func _process(_delta: float) -> void:
	match mode:
		Mode.BUILD:
			var origin := _origin_under_mouse()
			if origin == _last_origin and _ghost_key != "":
				return
			_last_origin = origin
			hover_check = world.grid.check_placement(build_def, origin, build_rotation)
			var affordable := world.economy.can_afford(build_def.build_cost)
			_draw_building_ghost(hover_check, hover_check["ok"] and affordable)
		Mode.NETWORK, Mode.BULLDOZE, Mode.DISTRICT:
			var cell := camera.cell_under_mouse()
			var start := _drag_start if _dragging else cell
			var key := "%s|%s|%s|%s|%s" % [mode, start, cell, network, paint_district]
			if key == _ghost_key:
				return
			_ghost_key = key
			var tiles: Array[Vector2i] = line_cells(start, cell) if mode == Mode.NETWORK else rect_cells(start, cell)
			drag_preview = _preview(tiles)
			_draw_tile_ghost(drag_preview)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_left_button(mb.pressed)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if mode != Mode.SELECT:
				cancel_build()
			else:
				select(null)
				selected_district = -1
				_set_deposit(-1)
				district_selected.emit(-1)
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"rotate_building") and mode == Mode.BUILD:
		build_rotation = (build_rotation + 1) % 4
		_ghost_key = ""
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_cancel"):
		if mode != Mode.SELECT:
			cancel_build()
		else:
			select(null)
	elif event.is_action_pressed(&"demolish") and selected:
		world.demolish(selected)
	elif event.is_action_pressed(&"upgrade") and selected:
		world.upgrade(selected)


func _left_button(pressed: bool) -> void:
	var cell := camera.cell_under_mouse()
	match mode:
		Mode.SELECT:
			if pressed:
				var b := world.grid.building_at(cell)
				var cl := world.deposits.cluster_at(cell)
				if b:
					select(b)
				elif cl:
					select_deposit(cl.id)
				else:
					select_district(world.grid.districts.id_at(cell))
		Mode.BUILD:
			if pressed and world.try_build(build_def, _origin_under_mouse(), build_rotation):
				_ghost_key = ""
		_:
			if pressed:
				_drag_start = cell
				_dragging = true
				_ghost_key = ""
			elif _dragging:
				_dragging = false
				var tiles: Array[Vector2i] = line_cells(_drag_start, cell) if mode == Mode.NETWORK else rect_cells(_drag_start, cell)
				match mode:
					Mode.NETWORK:
						world.build_network(tiles, network)
					Mode.BULLDOZE:
						world.bulldoze(tiles)
					Mode.DISTRICT:
						world.paint_district(tiles, paint_district)
				_ghost_key = ""


# --- Shapes ---------------------------------------------------------------------

## Horizontal leg first, then vertical: the classic L-shaped road drag.
static func line_cells(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var step_x := 1 if b.x >= a.x else -1
	var step_y := 1 if b.y >= a.y else -1
	var x := a.x
	while true:
		out.append(Vector2i(x, a.y))
		if x == b.x:
			break
		x += step_x
	var y := a.y
	while y != b.y:
		y += step_y
		out.append(Vector2i(b.x, y))
	return out


static func rect_cells(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
		for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
			out.append(Vector2i(x, y))
	return out


func _preview(tiles: Array[Vector2i]) -> Dictionary:
	match mode:
		Mode.NETWORK:
			return world.plan_network(tiles, network)
		Mode.BULLDOZE:
			var hits: Array[Vector2i] = []
			for c in tiles:
				if world.grid.transport.mask_at(c) != 0:
					hits.append(c)
			return {"tiles": tiles, "ok_tiles": hits, "cost": {}, "reason": "" if not hits.is_empty() else "No transport here"}
		_:
			var ok: Array[Vector2i] = []
			for c in tiles:
				if world.terrain.in_bounds(c) and world.grid.building_at(c) == null:
					ok.append(c)
			return {"tiles": tiles, "ok_tiles": ok, "cost": {}, "reason": ""}


## Centres the footprint on the cursor.
func _origin_under_mouse() -> Vector2i:
	var cell := camera.cell_under_mouse()
	var rotated := Footprint.rotated_cells(build_def.cells, build_rotation)
	var size := Vector2i.ZERO
	for c in rotated:
		size = Vector2i(maxi(size.x, c.x + 1), maxi(size.y, c.y + 1))
	return cell - Vector2i(int((size.x - 1) / 2.0), int((size.y - 1) / 2.0))


# --- Ghosts ---------------------------------------------------------------------

func _draw_building_ghost(check: Dictionary, ok: bool) -> void:
	var key := "%s|%s|%s|%s" % [build_def.id, build_rotation, _last_origin, ok]
	if key == _ghost_key:
		return
	_ghost_key = key
	_clear_ghost()
	var colour := Color(0.3, 0.9, 0.4) if ok else Color(0.95, 0.25, 0.2)
	if build_def.is_module() and ok and check.get("host") == null:
		colour = Color(0.95, 0.75, 0.2)   # placeable, but nothing to attach to yet
	BuildingView.add_shape(_ghost, check["cells"], check["ports"], build_def.height,
		BuildingView.material(colour, 0.45, true),
		BuildingView.material(BuildingView.INPUT_COLOUR, 0.8, true),
		BuildingView.material(BuildingView.OUTPUT_COLOUR, 0.8, true))
	var host: BuildingInstance = check.get("host")
	if host:
		_outline(host.cells, Color(0.3, 0.9, 0.4))


func _draw_tile_ghost(preview: Dictionary) -> void:
	_clear_ghost()
	var ok := {}
	for c in preview.get("ok_tiles", []):
		ok[c] = true
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var good := Color(0.3, 0.9, 0.4, 0.5)
	if mode == Mode.BULLDOZE:
		good = Color(0.95, 0.4, 0.2, 0.55)
	elif mode == Mode.DISTRICT:
		var d := world.grid.districts.get_district(paint_district)
		good = Color(d.colour, 0.45) if d else Color(0.5, 0.5, 0.5, 0.45)
	var bad := Color(0.95, 0.25, 0.2, 0.35)
	for c: Vector2i in preview.get("tiles", []):
		var col := good if ok.has(c) else bad
		if mode == Mode.BULLDOZE and not ok.has(c):
			col = Color(0.5, 0.5, 0.5, 0.15)
		NetworkView.add_box(st, Vector3(c.x + 0.06, 0.0, c.y + 0.06), Vector3(c.x + 0.94, 0.12, c.y + 0.94), col)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _ghost_material()
	_ghost.add_child(mi)


func _outline(cells: Array, colour: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c: Vector2i in cells:
		NetworkView.add_box(st, Vector3(c.x - 0.04, 0.0, c.y - 0.04), Vector3(c.x + 1.04, 0.06, c.y + 1.04), Color(colour, 0.5))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _ghost_material()
	_ghost.add_child(mi)


static func _ghost_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _clear_ghost() -> void:
	if _ghost == null:
		return
	for child in _ghost.get_children():
		child.queue_free()
