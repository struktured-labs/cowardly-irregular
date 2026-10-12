extends GutTest

## The autogrind controls legend anchors to the bottom-right corner, which is exactly where a battle's PARTY panel ends.
## Measured in a live watched grind at 720p: legend (950,520,320x190) against panel (1079,40,196x656) — 33,616 px of
## overlap, hiding the Bard's whole row and the Mage's stats for the entire grind. It is on by default
## (GameState.show_controller_overlay = true), so every player watching a grind lost the bottom of the party panel.

const OverlayScript = preload("res://src/ui/ControllerOverlay.gd")


func _overlay() -> Control:
	var o: Control = OverlayScript.new()
	add_child_autofree(o)
	await wait_frames(2)
	return o


## The panel's real shape: a tall column hugging the right edge, like BattleScene's UI/PartyStatusPanel.
func _panel_rect(o: Control) -> Rect2:
	var vp: Vector2 = o.get_viewport().get_visible_rect().size
	return Rect2(Vector2(vp.x - 201.0, 40.0), Vector2(196.0, vp.y - 64.0))


func test_with_no_rect_declared_it_still_sits_bottom_right() -> void:
	var o: Control = await _overlay()
	var vp: Vector2 = o.get_viewport().get_visible_rect().size
	assert_almost_eq(o.position.x, vp.x - o.OVERLAY_SIZE.x - o.SCREEN_MARGIN, 0.5,
		"CONTROL: a caller that declares nothing must get the unchanged bottom-right corner")
	assert_almost_eq(o.position.y, vp.y - o.OVERLAY_SIZE.y - o.SCREEN_MARGIN, 0.5, "and the unchanged bottom margin")


func test_it_moves_clear_of_a_declared_panel() -> void:
	var o: Control = await _overlay()
	var panel: Rect2 = _panel_rect(o)
	assert_true(o.get_global_rect().intersects(panel), "CONTROL: the default corner must collide, or this proves nothing")
	o.set_keep_clear_rect(panel)
	await wait_frames(1)
	assert_false(o.get_global_rect().intersects(panel), "the legend still covers the party panel")


func test_it_stays_on_screen_when_there_is_no_room() -> void:
	var o: Control = await _overlay()
	var vp: Vector2 = o.get_viewport().get_visible_rect().size
	## A panel claiming almost the whole width leaves nowhere to the left of it.
	o.set_keep_clear_rect(Rect2(Vector2(20.0, 0.0), Vector2(vp.x - 20.0, vp.y)))
	await wait_frames(1)
	assert_gte(o.position.x, 0.0, "a legend pushed off the left edge is as lost as one under the panel")
	assert_lte(o.position.x + o.OVERLAY_SIZE.x, vp.x + 0.5, "and it must not leave the right edge either")


func test_clearing_the_rect_restores_the_corner() -> void:
	var o: Control = await _overlay()
	var vp: Vector2 = o.get_viewport().get_visible_rect().size
	o.set_keep_clear_rect(_panel_rect(o))
	await wait_frames(1)
	o.set_keep_clear_rect(Rect2())
	await wait_frames(1)
	assert_almost_eq(o.position.x, vp.x - o.OVERLAY_SIZE.x - o.SCREEN_MARGIN, 0.5,
		"with nothing to avoid, the legend returns to the corner it belongs in")


## The half that fails if GameLoop stops telling the overlay about the panel.
func test_gameloop_declares_the_panel_and_drops_it_when_there_is_none() -> void:
	var gl: Node = load("res://src/GameLoop.gd").new()
	add_child_autofree(gl)
	var o: Control = await _overlay()
	gl._controller_overlay = o
	var holder := Control.new()
	holder.name = "UI"
	var panel := Control.new()
	panel.name = "PartyStatusPanel"
	panel.position = Vector2(400, 40)
	panel.size = Vector2(196, 300)
	holder.add_child(panel)
	var scene := Node.new()
	scene.add_child(holder)
	add_child_autofree(scene)
	await wait_frames(2)
	gl._keep_controller_overlay_off_the_party_panel(scene)
	assert_true(o.keep_clear_rect.get_area() > 0.0, "GameLoop must hand the panel's rect to the legend")
	assert_false(o.get_global_rect().intersects(panel.get_global_rect()), "and the legend must then clear it")
	var bare := Node.new()
	add_child_autofree(bare)
	gl._keep_controller_overlay_off_the_party_panel(bare)
	assert_eq(o.keep_clear_rect.get_area(), 0.0,
		"a scene with no party panel must DROP the rect, or the legend keeps dodging a panel that is gone")


## ⚠️ A SOURCE PIN, deliberately, and it is the weaker kind: it proves the call EXISTS, not that it RAN.
## Mutation-measured — deleting the call from _start_autogrind_battle left every behavioural arm above green,
## because they drive the helper directly. Driving the real path instead would mean standing up a live
## BattleScene inside a unit test, which is the fragile shape this lane has already measured twice.
func test_the_battle_path_still_declares_the_panel() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_gt(src.length(), 1000, "CONTROL: GameLoop must actually be read")
	var at: int = src.find("func _start_autogrind_battle")
	assert_gt(at, -1, "CONTROL: the autogrind battle path must exist to be pinned")
	var body: String = src.substr(at, src.find("\nfunc ", at + 10) - at)
	assert_string_contains(body, "_keep_controller_overlay_off_the_party_panel(",
		"the autogrind battle path no longer tells the legend where the party panel is, so it will cover it again")
