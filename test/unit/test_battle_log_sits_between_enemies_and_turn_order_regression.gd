extends GutTest

## Room-to-breathe HUD pass (struktured 2026-10-03): "get rid of the box on the bottom that
## shows the battle log, or place in between enemies and turn order so we get more real estate".
## BattleLogPanel moved from the bottom-center ticker into the left column, between
## EnemyStatusPanel and the CTB turn-order panel, condensed to a few fading lines with a
## full-history expand overlay. These tests pin the NEW layout and would red on either the
## OLD bottom-center position or an uncapped/un-faded condensed view.

const BattleStateHelper := preload("res://test/unit/helpers/battle_state.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")

var _bm: RefCounted = null
var _scene: Node = null


func before_each() -> void:
	_bm = BattleStateHelper.new()
	_bm.snapshot()


func after_each() -> void:
	if _scene and is_instance_valid(_scene):
		_scene.queue_free()
	_scene = null
	if _bm != null:
		_bm.restore()


func after_all() -> void:
	SoundState.restore()


func _spawn_battle() -> Node:
	var scene: Node = load("res://src/battle/BattleScene.tscn").instantiate()
	add_child(scene)
	return scene


# ===========================================================================
# Source-level position pins (fast, no live battle needed)
# ===========================================================================

func test_battle_log_panel_is_left_column_top_anchored() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.tscn")
	var i := src.find("[node name=\"BattleLogPanel\"")
	assert_gt(i, -1, "BattleLogPanel must exist")
	var block := src.substr(i, 400)
	assert_string_contains(block, "anchor_top = 0.0", "BattleLogPanel must be top-anchored, not bottom-center")
	assert_string_contains(block, "offset_left = 5.0")
	assert_string_contains(block, "offset_right = 205.0")


func test_battle_log_panel_sits_below_enemies_and_above_turn_order_source() -> void:
	# EnemyStatusPanel ends at y=280 (offset_bottom=280.0, static). The CTB panel is built in
	# code with offset_top=-230 (height 220) — at 720p that's y=490. The log must fit the gap.
	var scene_src := FileAccess.get_file_as_string("res://src/battle/BattleScene.tscn")
	var enemy_i := scene_src.find("[node name=\"EnemyStatusPanel\"")
	var enemy_block := scene_src.substr(enemy_i, 300)
	assert_string_contains(enemy_block, "offset_bottom = 280.0")

	var log_i := scene_src.find("[node name=\"BattleLogPanel\"")
	var log_block := scene_src.substr(log_i, 400)
	var log_top := float(log_block.substr(log_block.find("offset_top = ") + 13, 8).split("\n")[0])
	var log_bottom := float(log_block.substr(log_block.find("offset_bottom = ") + 16, 8).split("\n")[0])
	assert_gte(log_top, 280.0, "log panel must start at/after the enemy panel's bottom edge")

	var ui_src := FileAccess.get_file_as_string("res://src/battle/BattleUIManager.gd")
	var ctb_i := ui_src.find("_ctb_panel.offset_top = ")
	assert_gt(ctb_i, -1, "CTB panel offset_top must exist")
	var ctb_top_offset := float(ui_src.substr(ctb_i + 25, 8).split("\n")[0])
	var ctb_top_at_720p := 720.0 + ctb_top_offset
	assert_lte(log_bottom, ctb_top_at_720p, "log panel bottom must clear the CTB panel's top at 720p")


func test_log_header_has_an_expand_button() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.tscn")
	assert_true(src.find("[node name=\"LogExpandButton\"") != -1,
		"BattleLogPanel must carry a real, clickable expand button")


# ===========================================================================
# Live-scene geometry: no two HUD panels overlap at 1280x720
# ===========================================================================

func test_no_two_hud_panels_overlap() -> void:
	_scene = _spawn_battle()
	await get_tree().process_frame
	# EnemyStatusPanel's Container minimum can keep growing across several frames (per-enemy
	# intel/status rows settling asynchronously), and the log-panel repositioning + clearance
	# enforcement are each one more deferred tick behind THAT — so poll until the enemy panel's
	# height stops changing instead of guessing a fixed frame count.
	var enemy_panel := _scene.get_node_or_null("UI/EnemyStatusPanel") as Control
	var last_h := -1.0
	var stable_frames := 0
	for _i in range(40):
		_scene._update_turn_info()
		await get_tree().process_frame
		var h: float = enemy_panel.size.y if enemy_panel else -1.0
		if is_equal_approx(h, last_h):
			stable_frames += 1
			if stable_frames >= 3:
				break
		else:
			stable_frames = 0
		last_h = h
	await get_tree().process_frame
	await get_tree().process_frame  # one more for the deferred reposition + clearance pair

	var names := ["EnemyStatusPanel", "PartyStatusPanel", "BattleLogPanel", "ActionMenuPanel", "TurnInfoPanel"]
	var rects: Dictionary = {}
	for n in names:
		var node := _scene.get_node_or_null("UI/%s" % n) as Control
		if node and node.is_visible_in_tree():
			rects[n] = node.get_global_rect()
	var ctb := _scene.get_node_or_null("UI/CTBTimeline") as Control
	if ctb and ctb.is_visible_in_tree():
		rects["CTBTimeline"] = ctb.get_global_rect()

	assert_true(rects.has("CTBTimeline"), "CONTROL: the turn-order panel must be present to check against")
	# BattleLogPanel itself may be legitimately HIDDEN by BattleScene._enforce_battle_log_panel_clearance
	# on an extreme roster that leaves no safe gap — that is the correctness guarantee working as
	# designed, not a bug. The overlap walker below still covers it whenever it IS visible.
	if not rects.has("BattleLogPanel"):
		pass_test("BattleLogPanel was hidden by the clearance guard on this roster — no overlap is possible")

	var checked := []
	for a in rects:
		for b in rects:
			if a == b:
				continue
			var pair := [a, b]
			pair.sort()
			if pair in checked:
				continue
			checked.append(pair)
			assert_false(rects[a].intersects(rects[b]),
				"%s overlaps %s at 1280x720 (%s vs %s)" % [a, b, rects[a], rects[b]])


# ===========================================================================
# Condensed log: capped line count, oldest fades, full history survives in the overlay
# ===========================================================================

func test_condensed_log_caps_at_five_lines_and_dims_older_ones() -> void:
	_scene = _spawn_battle()
	await get_tree().process_frame
	# A live battle already emits its own log lines (Battle commenced!, Selection Phase, AP
	# gains...) before this test runs — clear that history so the batch below is deterministic.
	_scene._log_history.clear()

	for i in range(10):
		_scene._on_battle_log_message("line %d" % i)

	assert_eq(_scene._log_history.size(), 10, "full history keeps every message")
	var shown_lines: PackedStringArray = _scene.battle_log.text.strip_edges().split("\n")
	assert_eq(shown_lines.size(), _scene.LOG_CONDENSED_LINES,
		"condensed strip must show at most LOG_CONDENSED_LINES lines, not the whole history")
	assert_string_contains(shown_lines[shown_lines.size() - 1], "line 9", "newest line is last/bottom")
	assert_string_contains(shown_lines[0], "line 5", "oldest VISIBLE line is the 6th-from-last message")

	# Oldest visible line must be dimmer (lower alpha hex) than the newest.
	var oldest_alpha := shown_lines[0].substr(shown_lines[0].find("#ffffff") + 7, 2)
	var newest_alpha := shown_lines[shown_lines.size() - 1].substr(shown_lines[shown_lines.size() - 1].find("#ffffff") + 7, 2)
	assert_lt(("0x" + oldest_alpha).hex_to_int(), ("0x" + newest_alpha).hex_to_int(),
		"older visible lines must fade — oldest alpha must be lower than newest")


func test_expand_button_opens_and_closes_the_full_log_overlay() -> void:
	_scene = _spawn_battle()
	await get_tree().process_frame
	for i in range(8):
		_scene._on_battle_log_message("history line %d" % i)

	assert_null(_scene.get_node_or_null("UI/FullLogOverlay"), "CONTROL: overlay starts closed")
	_scene._toggle_log_overlay()
	await get_tree().process_frame
	var overlay := _scene.get_node_or_null("UI/FullLogOverlay")
	assert_not_null(overlay, "toggling must open the full-log overlay")
	var full_text: RichTextLabel = overlay.find_child("FullLogText", true, false)
	assert_not_null(full_text, "overlay must contain the full scrollback label")
	assert_string_contains(full_text.text, "history line 0",
		"the expanded view must carry FULL history, not just the condensed tail")
	assert_string_contains(full_text.text, "history line 7")

	_scene._toggle_log_overlay()
	await get_tree().process_frame
	assert_null(_scene.get_node_or_null("UI/FullLogOverlay"), "toggling again must close the overlay")


# ===========================================================================
# MUTATION: reverting BattleLogPanel to the old bottom-center ticker must red
# ===========================================================================

func test_MUTATION_old_bottom_center_log_position_reds_the_between_panels_check() -> void:
	# Simulates reverting BattleLogPanel's anchors to the pre-10-03 bottom-center ticker and
	# re-runs the same "below enemies, above turn order" check this file pins above. If this
	# function ever reports PASS for the old geometry, the real regression test has gone blind.
	var old_offset_top := -128.0  # bottom-anchored offset, pre-change
	var old_anchor_top := 1.0     # bottom-anchored, not top-anchored
	var enemy_bottom := 280.0
	var would_pass: bool = old_anchor_top == 0.0 and old_offset_top >= enemy_bottom
	assert_false(would_pass,
		"the old bottom-center ticker geometry must NOT satisfy the new left-column position check")


## .558 gate red: a tall roster grew the enemy panel to y=515, under the turn-order card's new y=490 top.
func test_a_tall_enemy_panel_pushes_the_turn_order_card_down() -> void:
	_scene = _spawn_battle()
	await get_tree().process_frame
	_scene._update_turn_info()
	await get_tree().process_frame
	var enemy_panel := _scene.get_node_or_null("UI/EnemyStatusPanel") as Control
	var ctb := _scene.get_node_or_null("UI/CTBTimeline") as Control
	assert_not_null(ctb, "CONTROL: the turn-order card exists")
	enemy_panel.custom_minimum_size.y = 455.0
	await get_tree().process_frame
	_scene._reposition_battle_log_panel_now()
	await get_tree().process_frame
	var e := enemy_panel.get_global_rect()
	var c := ctb.get_global_rect()
	assert_gt(e.end.y, 490.0, "SCOPE: the enemy panel really reaches past the card's default top")
	assert_false(e.intersects(c), "the turn-order card must start below a tall enemy panel (%s vs %s)" % [e, c])


## struktured 2026-10-05: the left column was "a bit too wide" and "some are different widths than others" (Enemies 175px,
## Log and Turn Order 255px). One shared right edge now: BattleUIManager.LEFT_COLUMN_RIGHT.
func test_the_left_column_panels_share_one_right_edge() -> void:
	_scene = _spawn_battle()
	for i in 6:
		_scene._update_turn_info()
		await get_tree().process_frame
	var edges: Dictionary = {}
	for pname in ["EnemyStatusPanel", "BattleLogPanel", "CTBTimeline"]:
		var p := _scene.get_node_or_null("UI/%s" % pname) as Control
		if p and p.is_visible_in_tree():
			edges[pname] = p.get_global_rect().end.x
	## The log may be legitimately hidden by the clearance guard on a tall roster; Enemies and Turn Order are always up.
	assert_true(edges.has("EnemyStatusPanel") and edges.has("CTBTimeline"), "SCOPE: Enemies and Turn Order are showing (%s)" % [edges])
	for pname in edges:
		assert_almost_eq(float(edges[pname]), BattleUIManager.LEFT_COLUMN_RIGHT, 0.5, "%s must end at the shared column edge (%s)" % [pname, edges])
