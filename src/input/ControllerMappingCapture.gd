extends RefCounted
class_name ControllerMappingCapture

## Builds a verified SDL mapping string by walking a pad control-by-control.
##
## Why this exists: a pad SDL does not know reports RAW indices, so shoulder/trigger/stick
## bindings point at the wrong physical controls with nothing in the log. Hand-writing the
## mapping is not viable — one controller yields several GUIDs (wired / BT / 2.4GHz / mode
## toggles) and the GUIDs differ again per platform. The owner pressing buttons IS the
## measurement; this turns that into a string.
##
## Deliberately free of UI and of Input polling so the string generation — the part where a
## mistake is silent — is testable without hardware attached.

## SDL's canonical control order. Walked in this sequence so the prompt matches the physical
## layout a player scans: faces, shoulders, centre, sticks, then the d-pad.
const CONTROLS: Array = [
	["a", "the SOUTH face button (bottom)"],
	["b", "the EAST face button (right)"],
	["x", "the WEST face button (left)"],
	["y", "the NORTH face button (top)"],
	["leftshoulder", "the LEFT shoulder (L / LB / L1)"],
	["rightshoulder", "the RIGHT shoulder (R / RB / R1)"],
	["lefttrigger", "the LEFT trigger (ZL / LT / L2)"],
	["righttrigger", "the RIGHT trigger (ZR / RT / R2)"],
	["back", "BACK (Select / Minus / Share)"],
	["start", "START (Plus / Options)"],
	["guide", "the HOME / GUIDE button — skip if it has none"],
	["leftstick", "pressing the LEFT stick in (L3)"],
	["rightstick", "pressing the RIGHT stick in (R3)"],
	["leftx", "the LEFT stick, pushed RIGHT"],
	["lefty", "the LEFT stick, pushed DOWN"],
	["rightx", "the RIGHT stick, pushed RIGHT"],
	["righty", "the RIGHT stick, pushed DOWN"],
	["dpup", "D-pad UP"],
	["dpdown", "D-pad DOWN"],
	["dpleft", "D-pad LEFT"],
	["dpright", "D-pad RIGHT"],
]

## Controls a pad may legitimately lack. Anything else missing makes the mapping incomplete.
const OPTIONAL := ["guide", "leftstick", "rightstick", "rightx", "righty", "lefttrigger", "righttrigger"]

var guid: String = ""
var pad_name: String = ""
var platform: String = ""
var bindings: Dictionary = {}   # sdl control name -> binding token ("b0", "a1", "h0.1")
var index: int = 0


func _init(p_guid: String = "", p_name: String = "", p_platform: String = "") -> void:
	guid = p_guid
	pad_name = p_name
	platform = p_platform if p_platform != "" else default_platform()


## SDL mappings are platform-tagged and a Linux-tagged entry does NOT apply on Windows —
## capturing on one OS and shipping to another silently registers nothing.
static func default_platform() -> String:
	match OS.get_name():
		"Windows": return "Windows"
		"macOS": return "Mac OS X"
		_: return "Linux"


func current_control() -> String:
	return CONTROLS[index][0] if index < CONTROLS.size() else ""


func current_prompt() -> String:
	if index >= CONTROLS.size():
		return "Done — every control captured."
	return "Press %s   (%d of %d)" % [CONTROLS[index][1], index + 1, CONTROLS.size()]


func is_complete() -> bool:
	return index >= CONTROLS.size()


## Records a raw event against the control currently being asked for, then advances.
## Returns false when the event carries nothing bindable, so the caller can keep waiting
## rather than silently burning a step.
func record(event: InputEvent) -> bool:
	var token := binding_token(event)
	if token == "":
		return false
	bindings[current_control()] = token
	index += 1
	return true


## Skips the current control — legitimate for a pad with no Guide button or no right stick.
func skip() -> void:
	index += 1


## The SDL token for a raw event. Buttons are bN, axes aN, hats hN.mask.
static func binding_token(event: InputEvent) -> String:
	if event is InputEventJoypadButton:
		return "b%d" % (event as InputEventJoypadButton).button_index
	if event is InputEventJoypadMotion:
		var m := event as InputEventJoypadMotion
		# A resting stick jitters; require a decisive push so noise cannot claim a control.
		if absf(m.axis_value) < 0.5:
			return ""
		return "a%d" % m.axis
	return ""


## Controls with no binding that are not optional. A mapping missing a d-pad direction
## registers fine and then steers wrong — SDL does not complain.
func missing_required() -> Array[String]:
	var missing: Array[String] = []
	for entry in CONTROLS:
		var name: String = entry[0]
		if bindings.has(name):
			continue
		if name in OPTIONAL:
			continue
		missing.append(name)
	return missing


## The finished SDL mapping string, or "" when required controls are outstanding — refusing
## to emit an incomplete mapping is the point, since SDL would accept it silently.
func build() -> String:
	if guid.strip_edges().length() != 32 or pad_name.strip_edges() == "":
		return ""
	if not missing_required().is_empty():
		return ""
	var parts: Array[String] = [guid, pad_name.replace(",", " ")]
	for entry in CONTROLS:
		var name: String = entry[0]
		if bindings.has(name):
			parts.append("%s:%s" % [name, bindings[name]])
	parts.append("platform:%s" % platform)
	return ",".join(parts)
