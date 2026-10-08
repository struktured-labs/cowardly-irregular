extends GutTest

## Arriving in a new world fires three things into one top band at once: the zone banner, the quest tracker and the
## "New World" tutorial hint. The hint (fixed at y 8) covered the banner and cut the tracker off mid-word ("Explore
## the Clockwork Domini"). The tracker and banner now report the blocks they draw in, and the hint starts below them.

const PANEL_SIZE := Vector2(880, 100)


func test_the_hint_steps_below_a_reserved_block_in_its_columns() -> void:
	var banner := Rect2(0, 20, 1280, 48)
	var y := TutorialHint.top_clear_of(200.0, PANEL_SIZE, [banner])
	assert_gt(y, banner.end.y, "the hint starts below the arrival banner (y %.0f)" % y)


func test_a_block_beside_the_panel_does_not_move_it() -> void:
	var minimap := Rect2(1136, 16, 128, 214)
	assert_eq(TutorialHint.top_clear_of(200.0, PANEL_SIZE, [minimap]), TutorialHint.PANEL_TOP,
		"the minimap is outside the panel's columns, so the hint keeps its top")


func test_nothing_reserved_keeps_the_battle_position() -> void:
	assert_eq(TutorialHint.top_clear_of(200.0, PANEL_SIZE, []), TutorialHint.PANEL_TOP, "battle has no reserved HUD; the hint stays at the top")


func test_the_banner_reserves_its_band_only_while_it_shows() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var zp := ZoneNamePopup.new()
	host.add_child(zp)
	zp.setup(host)
	assert_false(zp.reserved_rect().has_area(), "CONTROL: a faded-out banner reserves nothing")
	zp._bg.modulate.a = 1.0
	assert_true(zp.reserved_rect().has_area(), "a showing banner reserves its band")
	assert_true(zp.is_in_group(OverworldMinimap.HUD_GROUP), "the banner joins the reserved-HUD group")


func test_a_shown_hint_keeps_its_own_height() -> void:
	var saved = GameState.game_constants.get("tutorial_hint_height_probe", null)
	var hint := TutorialHint.new()
	add_child_autofree(hint)
	hint.show_hint("hint_height_probe", "New World", "Each world transforms your party — new costumes, new abilities, same skills underneath.")
	for i in 4:
		await get_tree().process_frame
	assert_lt(hint._panel.size.y, 200.0, "a three-line hint stays compact (%.0f px); a PanelContainer that only grows covered the player" % hint._panel.size.y)
	if saved == null:
		GameState.game_constants.erase("tutorial_hint_height_probe")
	else:
		GameState.game_constants["tutorial_hint_height_probe"] = saved
