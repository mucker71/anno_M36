class_name PlacementController
extends Node3D
## Mouse and keyboard handling for building placement and selection.
## Build mode: a ghost follows the cursor, R rotates, left click places
## (and keeps placing), right click or Esc leaves build mode.
## Select mode: left click selects, Delete demolishes, U upgrades housing.

signal selection_changed(inst: BuildingInstance)
signal build_mode_changed(def: BuildingDef)

var world: World
var camera: RtsCamera
var build_def: BuildingDef
var build_rotation: int = 0
var selected: BuildingInstance
var hover_check: Dictionary = {}

var _ghost: Node3D
var _ghost_key: String = ""
var _last_origin := Vector2i(-9999, -9999)


func _ready() -> void:
	_ghost = Node3D.new()
	_ghost.name = "Ghost"
	add_child(_ghost)


func begin_build(def: BuildingDef) -> void:
	build_def = def
	build_rotation = 0
	_ghost_key = ""
	_last_origin = Vector2i(-9999, -9999)
	select(null)
	build_mode_changed.emit(def)


func cancel_build() -> void:
	build_def = null
	hover_check = {}
	_clear_ghost()
	build_mode_changed.emit(null)


func select(inst: BuildingInstance) -> void:
	if selected and world.views.has(selected.uid):
		world.views[selected.uid].set_selected(false)
	selected = inst
	if selected and world.views.has(selected.uid):
		world.views[selected.uid].set_selected(true)
	selection_changed.emit(selected)


func _process(_delta: float) -> void:
	if build_def == null:
		return
	var origin := _origin_under_mouse()
	if origin == _last_origin and _ghost_key != "":
		return
	_last_origin = origin
	hover_check = world.grid.check_placement(build_def, origin, build_rotation)
	var affordable := world.economy.can_afford(build_def.build_cost)
	_draw_ghost(hover_check, hover_check["ok"] and affordable)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if build_def:
				_try_place()
			else:
				select(world.grid.building_at(camera.cell_under_mouse()))
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if build_def:
				cancel_build()
			else:
				select(null)
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"rotate_building") and build_def:
		build_rotation = (build_rotation + 1) % 4
		_ghost_key = ""
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_cancel"):
		if build_def:
			cancel_build()
		else:
			select(null)
	elif event.is_action_pressed(&"demolish") and selected:
		world.demolish(selected)
	elif event.is_action_pressed(&"upgrade") and selected:
		world.upgrade(selected)


func _try_place() -> void:
	var origin := _origin_under_mouse()
	var inst := world.try_build(build_def, origin, build_rotation)
	if inst:
		_ghost_key = ""   # force a redraw: the space is now taken


## Centres the footprint on the cursor.
func _origin_under_mouse() -> Vector2i:
	var cell := camera.cell_under_mouse()
	var rotated := Footprint.rotated_cells(build_def.cells, build_rotation)
	var size := Vector2i.ZERO
	for c in rotated:
		size = Vector2i(maxi(size.x, c.x + 1), maxi(size.y, c.y + 1))
	return cell - Vector2i((size.x - 1) / 2, (size.y - 1) / 2)


func _draw_ghost(check: Dictionary, ok: bool) -> void:
	var key := "%s|%s|%s|%s" % [build_def.id, build_rotation, _last_origin, ok]
	if key == _ghost_key:
		return
	_ghost_key = key
	_clear_ghost()
	var colour := Color(0.3, 0.9, 0.4) if ok else Color(0.95, 0.25, 0.2)
	BuildingView.add_shape(_ghost, check["cells"], check["ports"], build_def.height,
		BuildingView.material(colour, 0.45, true),
		BuildingView.material(BuildingView.INPUT_COLOUR, 0.8, true),
		BuildingView.material(BuildingView.OUTPUT_COLOUR, 0.8, true))


func _clear_ghost() -> void:
	for child in _ghost.get_children():
		child.queue_free()
