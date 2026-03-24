extends Node

## GamepadFilter - Locks joypad input to a preferred controller by name.
## Also captures right stick input for Mode 7 camera rotation.

const IGNORED_NAME: String = "SNES30"

var preferred_device: int = -1
var right_stick_x: float = 0.0

## Shoulder buttons as alternative rotation input (L1=left, R1=right)
var shoulder_rotate: float = 0.0


func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_scan_controllers()


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		var e = event as InputEventJoypadMotion
		# Only axis 2 = Right Stick X (was 2-5 which included Y, triggers)
		if e.axis == 2:
			if abs(e.axis_value) > 0.2:
				right_stick_x = e.axis_value
			else:
				right_stick_x = 0.0


func _process(_delta: float) -> void:
	# Shoulder buttons as alternative rotation (L1=4, R1=5)
	var l1 = Input.is_joy_button_pressed(preferred_device, JOY_BUTTON_LEFT_SHOULDER) if preferred_device >= 0 else false
	var r1 = Input.is_joy_button_pressed(preferred_device, JOY_BUTTON_RIGHT_SHOULDER) if preferred_device >= 0 else false
	if r1 and not l1:
		shoulder_rotate = 1.0
	elif l1 and not r1:
		shoulder_rotate = -1.0
	else:
		shoulder_rotate = 0.0


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_scan_controllers()


func _scan_controllers() -> void:
	var connected = Input.get_connected_joypads()
	preferred_device = -1

	for device_id in connected:
		var name = Input.get_joy_name(device_id)
		print("[GamepadFilter] Found controller %d: '%s'" % [device_id, name])

		if IGNORED_NAME != "" and name.to_upper().contains(IGNORED_NAME.to_upper()):
			print("[GamepadFilter] Ignoring device %d (%s)" % [device_id, name])
			continue

		if preferred_device == -1:
			preferred_device = device_id
			print("[GamepadFilter] Selected device %d (%s) as preferred controller" % [device_id, name])

	if preferred_device == -1 and connected.size() > 0:
		preferred_device = connected[0]
		print("[GamepadFilter] Fallback: using device %d" % preferred_device)

	_update_input_map()


func _update_input_map() -> void:
	if preferred_device == -1:
		return

	for action in InputMap.get_actions():
		var events = InputMap.action_get_events(action)
		for event in events:
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				if event.device != preferred_device:
					InputMap.action_erase_event(action, event)
					event.device = preferred_device
					InputMap.action_add_event(action, event)
