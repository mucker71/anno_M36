extends Node
## Autoload "InputSetup": registers default key bindings at startup.
## Any action already defined in Project Settings > Input Map wins, so
## bindings can be remapped in the editor without touching this file.

const DEFAULTS := {
	&"cam_forward": [KEY_W, KEY_UP],
	&"cam_back": [KEY_S, KEY_DOWN],
	&"cam_left": [KEY_A, KEY_LEFT],
	&"cam_right": [KEY_D, KEY_RIGHT],
	&"cam_rotate_left": [KEY_Q],
	&"cam_rotate_right": [KEY_E],
	&"rotate_building": [KEY_R],
	&"demolish": [KEY_DELETE, KEY_X],
	&"upgrade": [KEY_U],
	&"pause": [KEY_SPACE],
	&"speed_1": [KEY_1],
	&"speed_2": [KEY_2],
	&"speed_3": [KEY_3],
}


func _enter_tree() -> void:
	for action in DEFAULTS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in DEFAULTS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
