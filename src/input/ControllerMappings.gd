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

	# SAME PHYSICAL PAD, D-input mode (2dc8:6012). A mode switch changes the product id, so it is a
	# DIFFERENT GUID with a DIFFERENT layout - mapping one mode does nothing for the other.
	# This mode reports 24 buttons and inserts BTN_C (0x132) and BTN_Z (0x135) among the faces, which
	# shifts everything after them by two: unmapped, Godot walks the list ordinally and battle_toggle_auto
	# (button 4) lands under a face button, while L1/R1 land on START/L3. That is the "a face button
	# toggles autobattle" report, and it is a consequence of the extras, not of any binding.
	# Every entry below was measured from /dev/input/event14, struktured pressing each control:
	#   L1 0x136 raw b6 · R1 0x137 raw b7 · L2 0x138 raw b8 · R2 0x139 raw b9
	#   faces: SOUTH b0, EAST b1, NORTH b3, WEST b4   (BTN_C b2 / BTN_Z b5 are unused extras)
	#   Select b10 · Start b11 · Home b12 · L3 b13 · R3 b14
	# Triggers are analog on ABS_BRAKE (a5, L2) and ABS_GAS (a4, R2) - NOT ABS_Z/ABS_RZ, which are the
	# RIGHT STICK here (ABS_Z measured 85..255 on a rightward push). Assuming the usual Z/RZ trigger
	# convention would have bound the right stick to Defer/Advance.
	"03000000c82d00001260000011010000,8BitDo Ultimate 2 Wireless Controller for PC,a:b0,b:b1,x:b4,y:b3,leftshoulder:b6,rightshoulder:b7,lefttrigger:a5,righttrigger:a4,back:b10,start:b11,guide:b12,leftstick:b13,rightstick:b14,leftx:a0,lefty:a1,rightx:a2,righty:a3,dpup:h0.1,dpright:h0.2,dpdown:h0.4,dpleft:h0.8,platform:Linux",
]

## Modes of a known pad that produce NO gamepad at all, so "my controller is dead" is diagnosable
## instead of mysterious. 2dc8:6013 is the Ultimate 2 asleep in its dock: it enumerates over USB and
## binds usbhid, but its HID report descriptor is pure vendor-defined (06 a0 ff, two 63-byte raw
## reports, zero Generic Desktop usages) so the kernel builds no input device. Power the pad on.
const KNOWN_SILENT_MODES := {
	"2dc8:6013": "8BitDo Ultimate 2 asleep in its dock - exposes only the firmware/config interface. Press Home to power it on.",
}


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
