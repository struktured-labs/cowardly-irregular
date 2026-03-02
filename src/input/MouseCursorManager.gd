extends Node

## MouseCursorManager - Auto-show/hide mouse cursor based on input device
## Shows hardware cursor when mouse moves, hides when gamepad/keyboard input detected


func _ready() -> void:
	# Start with cursor hidden (gamepad-first design)
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion or event is InputEventKey:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_HIDDEN:
			Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
