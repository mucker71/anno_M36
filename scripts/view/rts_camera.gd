class_name RtsCamera
extends Node3D
## Top-down orthographic camera on a pivot.
## WASD / arrows pan, middle-drag pans, wheel zooms, Q / E rotate in 90 degree steps.

@export var pan_speed := 30.0
@export var min_zoom := 8.0
@export var max_zoom := 90.0
@export var pitch_degrees := 55.0

var bounds := Rect2(0, 0, 160, 160)
var camera: Camera3D
var _zoom := 36.0
var _target_yaw := 45.0
var _dragging := false


func _ready() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = _zoom
	camera.near = 0.1
	camera.far = 500.0
	add_child(camera)
	rotation_degrees.y = _target_yaw
	_place_camera()


func _process(delta: float) -> void:
	var input := Vector2(
		Input.get_axis(&"cam_left", &"cam_right"),
		Input.get_axis(&"cam_forward", &"cam_back"))
	if input != Vector2.ZERO:
		var move := Vector3(input.x, 0, input.y).rotated(Vector3.UP, rotation.y)
		position += move * pan_speed * delta * (_zoom / 36.0)
	rotation_degrees.y = lerp_angle_degrees(rotation_degrees.y, _target_yaw, minf(1.0, delta * 10.0))
	camera.size = lerpf(camera.size, _zoom, minf(1.0, delta * 12.0))
	position.x = clampf(position.x, bounds.position.x, bounds.end.x)
	position.z = clampf(position.z, bounds.position.y, bounds.end.y)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom = maxf(min_zoom, _zoom * 0.88)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom = minf(max_zoom, _zoom / 0.88)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		var px_scale := camera.size / get_viewport().get_visible_rect().size.y
		var move := Vector3(-mm.relative.x, 0, -mm.relative.y / sin(deg_to_rad(pitch_degrees)))
		position += move.rotated(Vector3.UP, rotation.y) * px_scale
	elif event.is_action_pressed(&"cam_rotate_left"):
		_target_yaw += 90.0
	elif event.is_action_pressed(&"cam_rotate_right"):
		_target_yaw -= 90.0


func focus(world_pos: Vector3) -> void:
	position = Vector3(world_pos.x, 0, world_pos.z)


## Grid cell under the mouse, or (-1, -1) if the ray misses the ground plane.
func cell_under_mouse() -> Vector2i:
	var hit: Variant = ground_point_under_mouse()
	if hit == null:
		return Vector2i(-1, -1)
	return Vector2i(floori(hit.x), floori(hit.z))


func ground_point_under_mouse() -> Variant:
	var mouse := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	return Plane(Vector3.UP, 0.0).intersects_ray(from, dir)


func _place_camera() -> void:
	var pitch := deg_to_rad(pitch_degrees)
	camera.position = Vector3(0, sin(pitch), cos(pitch)) * 120.0
	camera.rotation = Vector3(-pitch, 0, 0)


static func lerp_angle_degrees(from: float, to: float, weight: float) -> float:
	return rad_to_deg(lerp_angle(deg_to_rad(from), deg_to_rad(to), weight))
