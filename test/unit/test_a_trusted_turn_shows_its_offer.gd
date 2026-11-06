extends GutTest

## cowir-main 2026-11-05 (21910): the trusted-turn window's offer is on SCREEN, not only in the battle log. Since .770
## the window is 1.0 WALL second, and its one announcement was a cyan line in a scrolling log, easy to miss from a
## couch. TrustTurnPill shows "<cancel> Take this turn" over the trusted member with a bar draining for the window;
## the opened handler also sounds cowir-sfx's `trust_window_open` cue (21913).
##
## ⛔ The bar drains on the WINDOW'S OWN timer (BattleManager.trust_window_time_left), which ignores battle speed. Arm 4
## judges it against that timer and against battle time at 0.25 AND 1.0; the clock arms below pin which timer it reads.

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
	BattleManager._trust_window_timer = null
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
	assert_true(BattleManager.has_method("trust_window_time_left") and BattleManager.has_method("_run_trust_interrupt_window"), "BattleManager's window clock must exist")
	assert_true("_trust_window_timer" in BattleManager, "BattleManager._trust_window_timer must exist")


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
		BattleManager._trust_window_timer = get_tree().create_timer(1.0, true, false, true)
		s._on_trust_interrupt_window_opened(r[1], 1.0)
		var pill = s._trust_pill
		## Measured on the wall clock ITSELF. A SceneTreeTimer reference fired early late in a long GUT sweep (the runner's
		## timer skew, sprites 21800), reading 0.86 for a correct bar; frames are awaited until real time has passed.
		var start := Time.get_ticks_msec()
		var frames := 0
		while Time.get_ticks_msec() - start < 300 and frames < 2000:
			await get_tree().process_frame
			frames += 1
		var waited := float(Time.get_ticks_msec() - start) / 1000.0
		assert_gt(waited, 0.29, "CONTROL: real time must actually have passed (frames %d)" % frames)
		## Against the WINDOW, not the wall: headless GUT runs an unscaled timer fast at engine < 1 (0.45 s lost in 0.30).
		assert_almost_eq(pill.remaining_fraction(), BattleManager.trust_window_time_left(), 0.02,
			"at engine %s the bar must show exactly the time its window has left" % scale)
		if scale < 1.0:  # at 1.0 battle time IS unscaled time, so there is nothing to tell apart
			assert_gt(1.0 - pill.remaining_fraction(), waited * scale * 2.0,
				"and it is not battle time: at engine %s it lost more than the %.3f battle-s that passed" % [scale, waited * scale])
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


## The bar reads the timer that CLOSES the window, not a deadline of its own. A 0.6 s timer under a 1.0 s offer must
## read ~0.6: a private clock reads ~1.0 there, so this is the arm that tells the two apart.
func test_the_bar_reads_the_windows_own_timer() -> void:
	var r: Array = await _battle_with_member()
	var s: Node = r[0]
	BattleManager._trust_window_timer = get_tree().create_timer(0.6, true, false, true)
	s._on_trust_interrupt_window_opened(r[1], 1.0)
	assert_almost_eq(BattleManager.trust_window_time_left(), 0.6, 0.05, "CONTROL: the window's timer reads its own 0.6 s")
	assert_almost_eq(s._trust_pill.remaining_fraction(), 0.6, 0.05, "the offer must show the WINDOW's time left, not a 1.0 s clock of its own")
	BattleManager._trust_window_timer = null
	assert_eq(s._trust_pill.remaining_fraction(), 0.0, "and with no window open it reads empty, never full")


## Through the real window: the offer is full the moment it opens (the timer exists BEFORE the opened signal), and the
## window takes the offer away when its own timer runs out.
func test_a_real_window_opens_full_and_closes_on_its_timer() -> void:
	var r: Array = await _battle_with_member()
	var s: Node = r[0]
	var pc: Combatant = r[1]
	BattleManager.current_combatant = null
	BattleManager._run_trust_interrupt_window(pc)
	var pill = s._trust_pill
	assert_true(pill != null and is_instance_valid(pill), "CONTROL: the real window opened an offer")
	assert_gt(pill.remaining_fraction(), 0.9, "the offer is FULL as it opens, read off a timer that already exists")
	var start := Time.get_ticks_msec()
	while s._trust_pill != null and Time.get_ticks_msec() - start < 3000:
		await get_tree().process_frame
	assert_null(s._trust_pill, "the window's own timer closes it and takes the offer away")
	assert_eq(BattleManager.trust_window_time_left(), -1.0, "and BattleManager forgets the finished timer")


## A window the player claims early is over at once: its clock must not keep reporting time until the timer runs out.
func test_a_claimed_window_reports_no_time_left() -> void:
	var r: Array = await _battle_with_member()
	var pc: Combatant = r[1]
	pc.player_trust = true
	BattleManager.current_combatant = null
	BattleManager._run_trust_interrupt_window(pc)
	assert_gt(BattleManager.trust_window_time_left(), 0.5, "CONTROL: the window is open with time left")
	assert_true(BattleManager.request_trust_interrupt(), "CONTROL: the player claims the turn")
	assert_eq(BattleManager.trust_window_time_left(), -1.0, "a claimed window reports no time left, not the rest of its timer")
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 1500:
		await get_tree().process_frame
