extends GutTest

## struktured 2026-09-02, two playtest reports in one message:
##  (1) "F1 is unreadable menu most of the time when in battles" — the overlay Control
##      measured (0,0) under its CanvasLayer parent, so the 0.96-alpha backdrop collapsed
##      and the help text drew naked over the live battle. set_anchors_preset sets ANCHORS
##      ONLY; the port out of TitleScreen changed the parent type and the offsets never
##      resolved. Reproduced and fix-verified by pixel via the render smoke's f1_in_battle shot.
##  (2) "speech bubbles overlap the battle menu ... cant see ur selection until it fades" —
##      bubbles spawned at z 120 over a menu at z 100. Flavor above interactive UI.


func test_help_overlay_fills_the_viewport_under_a_canvas_layer() -> void:
	# Behavioral, in the exact parent shape GameLoop uses — the title-screen parent shape is
	# the one that masked this for weeks.
	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	var overlay = load("res://src/ui/HowToPlayOverlay.gd").new()
	layer.add_child(overlay)
	await get_tree().process_frame
	var vp: Vector2 = get_viewport().get_visible_rect().size
	assert_gt(overlay.size.x, vp.x - 2.0, "overlay must span the viewport width, measured %s" % str(overlay.size))
	assert_gt(overlay.size.y, vp.y - 2.0, "overlay must span the viewport height")
	var bg: ColorRect = null
	for c in overlay.get_children():
		if c is ColorRect:
			bg = c
			break
	assert_not_null(bg, "the dark backdrop must exist")
	assert_gt(bg.get_global_rect().size.x, vp.x - 2.0,
		"the backdrop must cover the screen — a (0,0) backdrop is exactly the unreadable-in-battle bug")
	assert_gt(bg.color.a, 0.9, "and it must be near-opaque, or battle chrome bleeds through")
	overlay.queue_free()


func test_speech_bubbles_render_below_the_command_menu() -> void:
	# The RELATIONSHIP, not the coordinates: whatever the numbers become, flavor must not
	# out-draw the menu the player is choosing from.
	var bubble_src := FileAccess.get_file_as_string("res://src/battle/BattleSpeechBubble.gd")
	var menu_src := FileAccess.get_file_as_string("res://src/battle/BattleCommandMenu.gd")
	var re := RegEx.create_from_string("z_index = (\\d+)")
	var bm := re.search(bubble_src)
	assert_not_null(bm, "bubble z_index assignment must exist")
	var bubble_z := int(bm.get_string(1))
	var mm := re.search(menu_src)
	assert_not_null(mm, "menu z_index assignment must exist")
	var menu_z := int(mm.get_string(1))
	assert_lt(bubble_z, menu_z,
		"bubbles (z %d) must draw BELOW the command menu (z %d) — the player's selection outranks flavor" % [bubble_z, menu_z])


func test_the_reference_documents_the_battle_speed_key() -> void:
	# His question 3: "is there a keyboard button to change battle speed?" — there was
	# (backtick), and the one screen that lists controls didn't list it.
	var txt: String = HowToPlayOverlay.build_text()
	assert_true(txt.contains("backtick"), "the reference must name the battle-speed key")
	assert_true(txt.contains("Battle speed"), "with a label a player can scan for")
