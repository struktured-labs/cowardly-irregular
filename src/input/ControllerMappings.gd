extends Node

## ControllerMappings - registers SDL gamecontroller mappings for pads Godot's bundled DB lacks.
##
## Godot only normalizes a pad to the JoyButton/JoyAxis constants when SDL has a mapping for its
## GUID. With no mapping `Input.is_joy_known()` is false and Godot reports RAW evdev indices, so
## every constant in project.godot silently points at the wrong physical control. This is invisible
## from the game side: bindings look correct, the pad enumerates, and half the buttons do the wrong
## thing. Registering a mapping fixes every action at once instead of per-profile patching.

## GUID (Linux/SDL) -> full mapping string. Verified against real hardware, never guessed:
## an incorrect mapping is worse than none, because it looks authoritative.
const MAPPINGS: Array[String] = [
	# 8BitDo Ultimate 2 Wireless Controller, wired "for PC" mode (2dc8:310b) - struktured's primary pad.
	# Verified 2026-07-25 by decoding /proc/bus/input/devices: this pad reports BTN_TL/BTN_TR as raw
	# indices 4/5 (Godot's LEFT/RIGHT_SHOULDER constants are 9/10, which here are the STICK CLICKS),
	# and its left trigger is ABS_Z/axis 2 (Godot expects axis 4, which here is right-stick-Y).
	# Unmapped, that puts Defer on a stick click and lets a right-stick nudge fire a battle action.
	# Layout is identical to SDL's existing "8BitDo Adapter 2" entry (2dc8:3106) - same family, and
	# only the product id differs, which is why the bundled DB misses it.
	"03000000c82d00000b31000014010000,8BitDo Ultimate 2 Wireless Controller,a:b0,b:b1,x:b2,y:b3,leftshoulder:b4,rightshoulder:b5,back:b6,start:b7,guide:b8,leftstick:b9,rightstick:b10,lefttrigger:a2,righttrigger:a5,leftx:a0,lefty:a1,rightx:a3,righty:a4,dpup:h0.1,dpright:h0.2,dpdown:h0.4,dpleft:h0.8,platform:Linux",
]


func _ready() -> void:
	register_all()
	# Pads present at boot never emit joy_connection_changed, so audit them directly.
	for device in Input.get_connected_joypads():
		warn_if_unmapped(device)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


## Registers every known mapping. Idempotent - SDL replaces by GUID. Returns the count applied.
func register_all() -> int:
	for mapping in MAPPINGS:
		Input.add_joy_mapping(mapping, true)
	print("[ControllerMappings] Registered %d SDL mapping(s)" % MAPPINGS.size())
	return MAPPINGS.size()


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	match connected:
		true: warn_if_unmapped(device)
		false: pass


## Loud-fail on an unmapped pad. Silence here reads to the player as "half my buttons are wrong"
## with nothing in the log to explain it - the exact failure that cost a full session to diagnose.
func warn_if_unmapped(device: int) -> void:
	if Input.is_joy_known(device):
		return
	push_warning("[ControllerMappings] '%s' (guid %s) has NO SDL mapping - Godot is reporting RAW device indices, so shoulder, trigger and stick bindings will point at the wrong physical controls. Add a verified entry to ControllerMappings.MAPPINGS." % [Input.get_joy_name(device), Input.get_joy_guid(device)])


## The GUID field of a mapping string (everything before the first comma).
func guid_of(mapping: String) -> String:
	return mapping.split(",")[0]


## True when a mapping for this GUID is registered here.
func has_mapping_for_guid(guid: String) -> bool:
	for mapping in MAPPINGS:
		if guid_of(mapping) == guid:
			return true
	return false
