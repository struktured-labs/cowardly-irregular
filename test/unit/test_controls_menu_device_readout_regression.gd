extends GutTest

## Regression test for the diagnostic gap behind the 2026-07-25 controller hunt.
##
## Nothing in the game ever said whether SDL had a mapping for the attached pad. Unmapped, Godot
## reports RAW device indices, so every binding shown in Controls is wrong — and the screen said
## "Gamepad button remapping" either way. Eight lanes analysed source for hours because the one
## decisive fact had no representation on screen or in any log.
##
## describe_pad_status is deliberately a pure function so this is testable with no pad attached.

var _menu


func before_each() -> void:
	_menu = load("res://src/ui/ControlsMenu.gd").new()


func after_each() -> void:
	if is_instance_valid(_menu):
		_menu.free()


func test_no_pad_reads_as_no_pad_and_is_not_alarming() -> void:
	var status: Dictionary = _menu.describe_pad_status(false, "", false, "")
	assert_false(status["warn"], "absent pad is a normal state, not a warning")
	assert_true(status["text"].to_lower().contains("no gamepad"),
		"must say plainly that no pad is attached: %s" % status["text"])


func test_mapped_pad_reports_ok_with_its_name() -> void:
	var status: Dictionary = _menu.describe_pad_status(
		true, "8BitDo Ultimate 2 Wireless Controller", true, "03000000c82d00000b31000014010000")
	assert_false(status["warn"], "a mapped pad is healthy")
	assert_true(status["text"].contains("8BitDo Ultimate 2 Wireless Controller"),
		"must name the pad so mode changes are visible: %s" % status["text"])


## THE POINT OF THE WHOLE FILE: an unmapped pad must say so loudly, and must surface the GUID,
## because the GUID is the only thing needed to author a mapping for it.
func test_unmapped_pad_warns_and_surfaces_the_guid() -> void:
	var guid := "03000000c82d00001260000011010000"
	var status: Dictionary = _menu.describe_pad_status(
		true, "8BitDo Ultimate 2 Wireless Controller for PC", false, guid)
	assert_true(status["warn"], "an unmapped pad MUST warn — silent raw indices is the whole bug")
	assert_true(status["text"].contains(guid),
		"the GUID is what a mapping is keyed to; without it on screen the user cannot report it: %s" % status["text"])
	assert_true(status["text"].to_upper().contains("WRONG"),
		"must state that the displayed bindings are wrong, not merely that something is unmapped: %s" % status["text"])
	# GamepadDiagnostic (F11) has shown name/GUID/is_joy_known plus LIVE button and axis reads since
	# long before this readout existed — the 2026-07-28 hunt was a discoverability failure as much as
	# a diagnostic one. The warning must name it rather than leave a second tool undiscovered.
	assert_true(status["text"].contains("F11"),
		"the unmapped warning must point at the existing live-readout overlay, not silently duplicate half of it: %s" % status["text"])


func test_mapped_and_unmapped_are_visually_distinguishable() -> void:
	var ok: Dictionary = _menu.describe_pad_status(true, "Pad", true, "guid")
	var bad: Dictionary = _menu.describe_pad_status(true, "Pad", false, "guid")
	assert_ne(ok["warn"], bad["warn"], "severity must differ, not just wording")
	assert_ne(ok["text"], bad["text"], "text must differ too")


## A mode switch re-enumerates the pad under a different product id, so the readout must not be
## frozen at open-time or it will confidently show a stale identity.
func test_menu_listens_for_device_changes() -> void:
	assert_true(_menu.has_method("refresh_device_label"),
		"readout must be refreshable")
	assert_true(_menu.has_method("_on_joy_connection_changed"),
		"must react to joy_connection_changed — pads sleep, wake and change mode while settings are open")
	# Safe to call with no label built and no pad present.
	_menu.refresh_device_label()
	assert_true(true, "refresh tolerates being called before the UI is built")
