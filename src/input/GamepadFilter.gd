extends Node

## GamepadFilter - Locks joypad input to a preferred controller by name.
## Also captures right stick input for Mode 7 camera rotation.

const IGNORED_NAME: String = "SNES30"

## Right stick X drives Mode 7 camera rotation. Named rather than a bare 2: an axis number only means
## something once SDL normalizes the pad, and this line previously accepted "2-5", which swept in the
## right stick Y and BOTH triggers. See ControllerMappings for why raw indices cannot be trusted.
const RIGHT_STICK_X_AXIS: JoyAxis = JOY_AXIS_RIGHT_X
const STICK_DEADZONE: float = 0.2

## Device-name substrings ranked best-first. struktured 2026-07-25: the 8BitDo Ultimate 2 is his
## PRIMARY pad and the Hyperkin Cadet is a backup, so USB enumeration order must not decide which one
## steers the camera when both are attached. Unlisted pads still work; they just rank last.
##
## ⚠️ SCOPE, measured 2026-07-29 — this ranking currently steers NOTHING LIVE. `preferred_device`'s
## only consumers are `right_stick_x` and `shoulder_rotate` below, and both are the input half of
## Mode 7 camera rotation, which `Mode7Overlay.gd:334` deliberately disables ("deferred to future
## release"). Verified against the strong dead-code rule: zero readers in src/ outside this file,
## zero in test/, zero string dispatch, zero scene/data refs — the ONLY mention of GamepadFilter
## anywhere else is a comment in InputProfileManager.
##
## KEEP IT. This is a ready seam, not rot — the same shape as autogrind's `manual_only`: correct,
## cheap, and one line from load-bearing the day rotation ships. But do not repeat the claim I made
## when I added it, that a second pad could "take the camera away" — it cannot, because there is no
## camera rotation to take. The ranking is preparation, and the honest justification is that it will
## be right on the day the feature turns on, not that it fixes something today.
const PREFERRED_NAMES: Array[String] = ["8bitdo", "ultimate"]

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
		if e.axis == RIGHT_STICK_X_AXIS:
			right_stick_x = e.axis_value if absf(e.axis_value) > STICK_DEADZONE else 0.0


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


## Lower is better. Unlisted pads rank last but remain fully usable — this ranks preference, it never
## excludes (that is IGNORED_NAME's job).
func preference_rank(device_name: String) -> int:
	var lowered := device_name.to_lower()
	for i in PREFERRED_NAMES.size():
		if lowered.contains(PREFERRED_NAMES[i]):
			return i
	return PREFERRED_NAMES.size()


func _scan_controllers() -> void:
	var connected = Input.get_connected_joypads()
	preferred_device = -1
	var best_rank := PREFERRED_NAMES.size() + 1

	for device_id in connected:
		var name = Input.get_joy_name(device_id)
		print("[GamepadFilter] Found controller %d: '%s'" % [device_id, name])

		if IGNORED_NAME != "" and name.to_upper().contains(IGNORED_NAME.to_upper()):
			print("[GamepadFilter] Ignoring device %d (%s)" % [device_id, name])
			continue

		# Rank rather than first-wins: with two pads attached, enumeration order used to decide, so
		# plugging in a backup pad silently took the camera away from struktured's primary.
		var rank := preference_rank(name)
		if rank < best_rank:
			best_rank = rank
			preferred_device = device_id
			print("[GamepadFilter] Selected device %d (%s) as preferred controller [rank %d]" % [device_id, name, rank])

	if preferred_device == -1 and connected.size() > 0:
		preferred_device = connected[0]
		print("[GamepadFilter] Fallback: using device %d" % preferred_device)

	_update_input_map()


## ALL joypad bindings stay device-agnostic (device = -1). struktured 2026-07-25: a
## second pad ('NEXT SNES Controller') enumerated first, won preferred_device, and this
## function locked EVERY action to it — his 8BitDo went totally dead (dpad, A, B, sticks).
## A spurious second controller is a far smaller harm than the player's own pad being
## ignored, so nothing is locked. preferred_device still steers Mode 7 camera polling.
func _update_input_map() -> void:
	for action in InputMap.get_actions():
		for event in InputMap.action_get_events(action):
			if (event is InputEventJoypadButton or event is InputEventJoypadMotion) and event.device != -1:
				InputMap.action_erase_event(action, event)
				event.device = -1
				InputMap.action_add_event(action, event)
