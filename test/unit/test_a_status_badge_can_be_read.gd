extends GutTest

## cowir-sprites' status render (2026-11-12): the BLIND badge was dark grey text on the dark pill, unreadable in every
## tile. Three more were as dark (curse, silence, permakilled). A badge colour keeps one channel bright.

const BS := preload("res://src/battle/BattleScene.gd")


func test_every_badge_colour_is_bright_enough_to_read_on_its_pill() -> void:
	var dark: Array = []
	for status in BS.STATUS_ICON_CONFIG:
		var c: Color = BS.STATUS_ICON_CONFIG[status]["color"]
		if maxf(c.r, maxf(c.g, c.b)) < BS.STATUS_BADGE_MIN_BRIGHT:
			dark.append("%s (%.2f, %.2f, %.2f)" % [status, c.r, c.g, c.b])
	assert_gt(BS.STATUS_ICON_CONFIG.size(), 30, "FLOOR: the badge table was read")
	assert_eq(dark, [], "every badge colour has a channel at or above %.2f" % BS.STATUS_BADGE_MIN_BRIGHT)


func test_the_four_that_were_dark_keep_their_own_hue() -> void:
	var blind: Color = BS.STATUS_ICON_CONFIG["blind"]["color"]
	var silence: Color = BS.STATUS_ICON_CONFIG["silence"]["color"]
	var curse: Color = BS.STATUS_ICON_CONFIG["curse"]["color"]
	var dead: Color = BS.STATUS_ICON_CONFIG["permakilled"]["color"]
	assert_lt(blind.s, 0.2, "blind stays a grey, now a pale one")
	assert_lt(silence.s, 0.2, "silence stays a grey")
	assert_true(curse.b > curse.g and curse.r > curse.g, "curse stays purple")
	assert_true(dead.r > dead.g * 2.0 and dead.r > dead.b * 2.0, "permakilled stays red")
	assert_ne(blind, silence, "CONTROL: the two greys are not the same colour")
