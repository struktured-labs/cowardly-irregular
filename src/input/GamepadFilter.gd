extends Node

## GamepadFilter - Locks joypad input to a preferred controller by name.
## Ignores input from other connected controllers so they don't interfere.
## Configure PREFERRED_NAME / IGNORED_NAME below.

## Substring to match for the IGNORED controller (case-insensitive).
## The SNES30 is the Megaman controller — ignore it for this game.
const IGNORED_NAME: String = "SNES30"

var preferred_device: int = -1


func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_scan_controllers()


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_scan_controllers()


func _scan_controllers() -> void:
	var connected = Input.get_connected_joypads()
	preferred_device = -1

	for device_id in connected:
		var name = Input.get_joy_name(device_id)
		print("[GamepadFilter] Found controller %d: '%s'" % [device_id, name])

		# Skip the ignored controller
		if IGNORED_NAME != "" and name.to_upper().contains(IGNORED_NAME.to_upper()):
			print("[GamepadFilter] Ignoring device %d (%s)" % [device_id, name])
			continue

		# Use the first non-ignored controller
		if preferred_device == -1:
			preferred_device = device_id
			print("[GamepadFilter] Selected device %d (%s) as preferred controller" % [device_id, name])

	if preferred_device == -1 and connected.size() > 0:
		# Fallback: use first available if all are "ignored"
		preferred_device = connected[0]
		print("[GamepadFilter] Fallback: using device %d" % preferred_device)

	_update_input_map()


func _update_input_map() -> void:
	if preferred_device == -1:
		return

	# Update all InputMap actions: set joypad events to preferred device
	for action in InputMap.get_actions():
		var events = InputMap.action_get_events(action)
		for event in events:
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				if event.device != preferred_device:
					event.device = preferred_device
