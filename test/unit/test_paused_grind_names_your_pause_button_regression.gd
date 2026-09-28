extends GutTest

## Pausing a grind showed "Autogrind paused. Press P to resume." and "|| PAUSED — Press P to Resume" to everyone. P is the
## keyboard pause; a pad pauses and resumes on the battle_toggle_auto action and has no P. The HUD strip beside it already
## derived the pad's button, so the two now share AutogrindInputHelper.pause_hint.

const PADS := {
	"nintendo": "Nintendo Switch Pro Controller",
	"xbox": "Xbox Series Controller",
	"playstation": "Sony DualSense Wireless Controller",
}


func test_a_pad_is_told_its_own_button_not_p() -> void:
	for family in PADS:
		var hint: String = AutogrindInputHelper.pause_hint(PADS[family])
		assert_ne(hint, "", "%s: the pause hint must name something" % family)
		assert_ne(hint, "P", "%s: a pad player was told to press P, a key they do not have" % family)


func test_the_hint_agrees_with_the_hud_strip() -> void:
	for family in PADS:
		var strip: String = AutogrindInputHelper.grind_hud_strip(PADS[family])
		assert_string_contains(strip, "%s: Pause" % AutogrindInputHelper.pause_hint(PADS[family]),
			"%s: the paused message and the HUD strip must name the same button" % family)


func test_the_keyboard_still_reads_p() -> void:
	if not Input.get_connected_joypads().is_empty():
		pending("a pad is attached to this machine; the keyboard arm needs none")
		return
	assert_eq(AutogrindInputHelper.pause_hint(), "P", "CONTROL: with no pad the keyboard pause key is P")


func test_the_paused_captions_are_derived_not_written() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_gt(src.length(), 1000, "CONTROL: GameLoop must actually be read")
	assert_false(src.contains("Press P to"), "a paused caption still hardcodes P")
	assert_eq(src.count("AutogrindInputHelper.pause_hint()"), 2, "both paused captions must name the derived button")
