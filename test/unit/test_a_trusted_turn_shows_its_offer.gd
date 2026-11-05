extends GutTest

## cowir-main 2026-11-05 (21910): the trusted-turn window's offer is on SCREEN, not only in the battle log. Since .770
## the window is 1.0 WALL second, and its one announcement was a cyan line in a scrolling log, easy to miss from a
## couch. TrustTurnPill shows "<cancel> Take this turn" over the trusted member with a bar draining for the window;
## the opened handler also sounds cowir-sfx's `trust_window_open` cue (21913).
##
## ⛔ The bar drains in WALL time. A battle-time bar would still read "time left" at engine 0.25 after the window
## (which is wall-timed) had already closed. Arm 4 judges it against a wall reference at 0.25 AND 1.0.

const BattleStateHelper := preload("res://test/unit/helpers/battle_state.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const HEAD := Vector2(400, 420)

var _bm: RefCounted = null
var _scene: Node = null
var _saved_scale := 1.0
var _saved_text = null
var _saved_speed = null


func before_each() -> void:
	_bm = BattleStateHelper.new()
	_bm.snapshot()
	_saved_scale = Engine.time_scale
	_saved_text = GameState.text_size_scale if "text_size_scale" in GameState else null
	_saved_speed = GameState.default_battle_speed if "default_battle_speed" in GameState else null


func after_each() -> void:
	if _scene and is_instance_valid(_scene):
		_scene.queue_free()
	_scene = null
	Engine.time_scale = _saved_scale
	if _saved_text != null:
		GameState.text_size_scale = _saved_text
	if _saved_speed != null:
		GameState.default_battle_speed = _saved_speed
	if _bm != null:
		_bm.restore()


func after_all() -> void:
	SoundState.restore()


## A real BattleScene with ONE party member whose sprite stands at a known head point (no frames, so no head lift).
func _battle_with_member() -> Array:
	_scene = load("res://src/battle/BattleScene.tscn").instantiate()
	add_child(_scene)
	await get_tree().process_frame
	var pc := Combatant.new()
	autofree(pc)
	pc.combatant_name = "Trusty"
	BattleManager.player_party.assign([pc])
	var sprite := AnimatedSprite2D.new()
	_scene.add_child(sprite)
	sprite.global_position = HEAD
	_scene.party_sprite_nodes.assign([sprite])
	_scene._party_base_positions.assign([HEAD])
	return [_scene, pc]


func _presets() -> Array:
	var p: Array = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must hold more than one step, or the preset loop proves nothing")
	return p


func test_the_floor_names_every_member_this_file_drives() -> void:
	var r: Array = await _battle_with_member()
	var s: Node = r[0]
	for m in ["_on_trust_interrupt_window_opened", "_on_trust_interrupt_window_closed", "_trust_pill_keep_out", "_clear_trust_pill", "_get_combatant_sprite"]:
		assert_true(s.has_method(m), "BattleScene.%s must exist" % m)
	assert_true("_trust_pill" in s, "BattleScene._trust_pill must exist")
	var pill := TrustTurnPill.new()
	add_child_autofree(pill)
	for m in ["placed_rect", "show_over", "remaining_fraction", "setup"]:
		assert_true(pill.has_method(m), "TrustTurnPill.%s must exist" % m)
	assert_true(BattleManager.has_method("_trust_interrupt_token") and BattleManager.has_method("trust_window_offered"), "BattleManager's token and gate must exist")


func test_an_opened_window_shows_the_offer_over_the_member_and_sounds_its_cue() -> void:
	var r: Array = await _battle_with_member()
	var s: Node = r[0]
	s._on_trust_interrupt_window_opened(r[1], 1.0)
	var pill: Control = s._trust_pill
	assert_true(pill != null and is_instance_valid(pill) and pill.is_visible_in_tree(), "an opened window must put the offer on screen")
	assert_string_contains(pill.label.text, BattleManager._trust_interrupt_token(), "it names the SAME button the log line does")
	assert_string_contains(pill.label.text, "Take this turn", "and says what that button does")
	assert_lte(pill.get_global_rect().end.y, HEAD.y, "it stands ABOVE the member, not on them")
	var played = SoundManager._ui_player.stream
	assert_true(played != null and str(played.resource_path).contains("trust_window_open"), "the opened handler sounds the trusted-turn cue")


func test_a_closed_window_takes_the_offer_away_either_way() -> void:
	var r: Array = await _battle_with_member()
	var s: Node = r[0]
	for interrupted in [false, true]:
		s._on_trust_interrupt_window_opened(r[1], 1.0)
		var pill: Control = s._trust_pill
		s._on_trust_interrupt_window_closed(r[1], interrupted)
		assert_null(s._trust_pill, "closing (interrupted=%s) must drop the offer" % interrupted)
		assert_true(not is_instance_valid(pill) or pill.is_queued_for_deletion(), "and free the pill (interrupted=%s)" % interrupted)


func test_the_bar_drains_on_the_wall_clock_at_every_speed() -> void:
	var r: Array = await _battle_with_member()
	var s: Node = r[0]
	for scale in [0.25, 1.0]:
		Engine.time_scale = scale
		s._on_trust_interrupt_window_opened(r[1], 1.0)
		var pill = s._trust_pill
		await get_tree().create_timer(0.3, true, false, true).timeout   # a WALL reference
		assert_almost_eq(pill.remaining_fraction(), 0.7, 0.15, "at engine %s the bar must have lost the WALL 0.3 s, not %s battle-s" % [scale, 0.3 * scale])
		s._on_trust_interrupt_window_closed(r[1], false)


func test_the_offer_steps_clear_of_what_it_would_cover() -> void:
	var size := Vector2(120, 30)
	var vp := Vector2(1280, 720)
	var natural := TrustTurnPill.placed_rect(HEAD, size, [], vp)
	assert_lte(natural.end.y, HEAD.y, "CONTROL: with nothing in the way it sits just above the head")
	var menu := Rect2(natural.position.x - 10, natural.position.y - 5, size.x + 20, size.y + 10)
	var placed := TrustTurnPill.placed_rect(HEAD, size, [menu], vp)
	assert_false(placed.intersects(menu), "it must not cover the command menu / a bubble standing where it would go")
	var tall := Rect2(natural.position.x - 10, 0, size.x + 20, HEAD.y - 2)   # a menu from the top edge down to the head
	var under := TrustTurnPill.placed_rect(HEAD, size, [tall], vp)
	assert_false(under.intersects(tall), "with no room above a tall menu it goes below it, not back onto it after the clamp")
	var edge := TrustTurnPill.placed_rect(Vector2(5, 10), size, [], vp)
	assert_true(Rect2(Vector2.ZERO, vp).encloses(edge), "and it stays on screen near an edge")


## Rides the window's own gate: above 4x and in turbo trust_window_offered() is false, so nothing opens a pill.
func test_no_window_means_no_offer_above_four_x() -> void:
	GameState.default_battle_speed = 16.0
	assert_false(BattleManager.trust_window_offered(), "a 16x player is offered no window, so no pill is ever opened")
	GameState.default_battle_speed = 0.375
	assert_true(BattleManager.trust_window_offered(), "CONTROL: the default speed is offered one")


func test_the_offer_grows_with_the_text_and_still_fits() -> void:
	var widths: Array = []
	for scale in _presets():
		GameState.text_size_scale = scale
		var p := TrustTurnPill.new()
		p.setup("[Z]", 1.0)
		add_child_autofree(p)
		await get_tree().process_frame
		var font_px: int = p.label.get_theme_font_size("font_size")
		widths.append(font_px)
		assert_lte(p.label.get_combined_minimum_size().x, p.get_combined_minimum_size().x + 0.5,
			"at Text Size %s the label must fit inside its pill" % scale)
	for i in range(1, widths.size()):
		assert_gt(widths[i], widths[i - 1], "the offer's font must grow at every Text Size step: %s" % [widths])
