extends GutTest

## The capture flow builds an SDL mapping from a pad the owner walks control-by-control.
##
## The string generation is the dangerous half: SDL ACCEPTS a malformed or incomplete mapping
## silently and then reports wrong physical controls. So every guard here is about refusing to
## emit rather than about emitting.

const Capture = preload("res://src/input/ControllerMappingCapture.gd")
const GUID := "03000000c82d00000b31000014010000"


func _btn(idx: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = idx
	e.pressed = true
	return e


func _axis(axis: int, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e


func _walk_all(cap) -> void:
	# Drive every control with a distinct button so the ordering is checkable.
	var i := 0
	while not cap.is_complete():
		cap.record(_btn(i))
		i += 1


func test_button_and_axis_tokens() -> void:
	assert_eq(Capture.binding_token(_btn(0)), "b0")
	assert_eq(Capture.binding_token(_btn(11)), "b11")
	assert_eq(Capture.binding_token(_axis(3, 0.9)), "a3")


func test_a_resting_stick_cannot_claim_a_control() -> void:
	# Sticks jitter at rest. Without a threshold the walk would auto-advance through every
	# remaining control on noise, producing a complete-looking and totally wrong mapping.
	assert_eq(Capture.binding_token(_axis(1, 0.05)), "", "idle jitter is not a binding")
	assert_eq(Capture.binding_token(_axis(1, -0.9)), "a1", "a decisive push is")


func test_record_refuses_unbindable_events_without_advancing() -> void:
	var cap = Capture.new(GUID, "Test Pad", "Linux")
	var before: int = cap.index
	assert_false(cap.record(InputEventKey.new()), "a keypress is not a pad binding")
	assert_eq(cap.index, before, "a rejected event must not burn a step")


func test_incomplete_mapping_refuses_to_build() -> void:
	var cap = Capture.new(GUID, "Test Pad", "Linux")
	cap.record(_btn(0))  # only 'a'
	assert_eq(cap.build(), "", "an incomplete mapping must NOT be emitted — SDL accepts it silently")
	assert_true(cap.missing_required().size() > 0, "and it must be able to say what is missing")


func test_dpad_directions_are_required_not_optional() -> void:
	# A mapping missing dpleft registers fine and then steers wrong.
	var cap = Capture.new(GUID, "Test Pad", "Linux")
	_walk_all(cap)
	cap.bindings.erase("dpleft")
	assert_true("dpleft" in cap.missing_required(), "d-pad directions must be required")
	assert_eq(cap.build(), "", "and their absence must block the build")


func test_optional_controls_do_not_block() -> void:
	# A pad with no Guide button or no right stick is legitimate.
	var cap = Capture.new(GUID, "Test Pad", "Linux")
	_walk_all(cap)
	for opt in ["guide", "rightstick", "righty"]:
		cap.bindings.erase(opt)
	assert_eq(cap.missing_required(), [] as Array[String], "optional controls may be absent")
	assert_ne(cap.build(), "", "and the mapping still builds")


func test_built_mapping_is_wellformed_by_the_loader_that_will_read_it() -> void:
	# The consumer's own validator is the honest judge — not a second opinion written here.
	var cm = load("res://src/input/ControllerMappings.gd").new()
	add_child_autofree(cm)
	var cap = Capture.new(GUID, "Test Pad", "Linux")
	_walk_all(cap)
	var mapping: String = cap.build()
	assert_ne(mapping, "", "walk produced a mapping")
	assert_true(cm.is_wellformed(mapping), "the loader must accept what the capture emits")
	assert_eq(cm.guid_of(mapping), GUID, "GUID survives round-trip to the loader")
	assert_string_contains(mapping, "platform:Linux")


func test_a_comma_in_the_pad_name_cannot_corrupt_the_format() -> void:
	# SDL is comma-delimited; a pad whose name contains one would shift every field.
	var cap = Capture.new(GUID, "Evil, Pad", "Linux")
	_walk_all(cap)
	var mapping: String = cap.build()
	assert_false(mapping.split(",")[1].contains(","), "name is sanitised")
	assert_eq(mapping.split(",")[0], GUID, "GUID stays field 0")


func test_refuses_a_bad_guid() -> void:
	var cap = Capture.new("tooshort", "Test Pad", "Linux")
	_walk_all(cap)
	assert_eq(cap.build(), "", "a 32-hex GUID is mandatory; SDL ignores anything else silently")


func test_platform_defaults_to_the_host_not_a_hardcoded_linux() -> void:
	# A Linux-tagged mapping does NOT apply on Windows. Capturing on the demo machine must
	# produce a Windows-tagged entry or it silently registers nothing there.
	var p: String = Capture.default_platform()
	assert_true(p in ["Windows", "Mac OS X", "Linux"], "platform is one SDL recognises, got '%s'" % p)


func test_prompts_cover_every_control_and_are_distinct() -> void:
	var cap = Capture.new(GUID, "Test Pad", "Linux")
	var seen := {}
	while not cap.is_complete():
		var p: String = cap.current_prompt()
		assert_false(seen.has(p), "duplicate prompt would leave the player unsure what to press: %s" % p)
		seen[p] = true
		cap.skip()
	assert_eq(seen.size(), Capture.CONTROLS.size(), "every control prompts exactly once")
