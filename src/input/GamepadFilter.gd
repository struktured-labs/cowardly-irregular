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
	# Capture right stick from joypad events (any axis 2-5 that moves)
	if event is InputEventJoypadMotion:
		var e = event as InputEventJoypadMotion
		# Axes 0,1 = left stick. 2-5 could be right stick depending on driver.
		if e.axis >= 2 and e.axis <= 5:
			if abs(e.axis_value) > 0.2:
				right_stick_x = e.axis_value
			elif e.axis in [2, 3]:
				right_stick_x = 0.0
	# Steam may convert right stick to mouse motion
	elif event is InputEventMouseMotion:
		var mx = event.relative.x
		if abs(mx) > 3.0:
			right_stick_x = clampf(mx * 0.04, -1.0, 1.0)


func _process(_delta: float) -> void:
	# Also poll axes directly as a fallback (some drivers only support polling)
	if preferred_device >= 0 and abs(right_stick_x) < 0.1:
		for ax in [2, 3, 4, 5]:
			var val = Input.get_joy_axis(preferred_device, ax)
			if abs(val) > 0.2:
				right_stick_x = val
				break

	# Decay toward zero when no input (mouse events don't send "release")
	if abs(right_stick_x) > 0.01:
		right_stick_x *= 0.85


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
