extends Node

## GamepadFilter - Locks joypad input to a preferred controller by name.
## Also captures right stick input for Mode 7 camera rotation.

const IGNORED_NAME: String = "SNES30"

var preferred_device: int = -1
var right_stick_x: float = 0.0


func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_scan_controllers()


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		var e = event as InputEventJoypadMotion
		if e.axis >= 2 and e.axis <= 5:
			if abs(e.axis_value) > 0.2:
				right_stick_x = e.axis_value
			else:
				right_stick_x = 0.0


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
