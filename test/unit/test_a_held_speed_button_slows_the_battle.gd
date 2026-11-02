extends GutTest

## struktured (2026-11-01, via cowir-main): the battle speed button TAPS one rung UP the ladder as it
## always has, and a LONG PRESS steps one rung DOWN ("long press … should go from 2x to 1.5x, and
## again would 1.5x to 1x"), clamped at the slowest, no wrap.
##
## 🔑 ONE PRESS IS ONE STEP: a tap steps up on RELEASE; a hold steps down ONCE when it reaches
## SPEED_HOLD_MS, and that release then does nothing. The clock is Time.get_ticks_msec (battle time
## is scaled by the very speed being changed), so these arms move the hold's START back rather
## than waiting.

const BattleStateHelper := preload("res://test/unit/helpers/battle_state.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const BS := preload("res://src/battle/BattleScene.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")

var _bm: RefCounted = null
var _scene: Node = null
var _saved_index := 0
var _saved_scale := 1.0
var _saved_default = null
var _had_speed_hint := false


func before_each() -> void:
	_bm = BattleStateHelper.new()
	_bm.snapshot()
	_saved_index = BS._battle_speed_index   # static: persists across battles, so it must be restored
	_saved_scale = Engine.time_scale
	_saved_default = GameState.default_battle_speed if "default_battle_speed" in GameState else null
	_had_speed_hint = BS._hints_shown.has("speed_toggle")


func after_each() -> void:
	if _scene and is_instance_valid(_scene):
		_scene.queue_free()
	_scene = null
	BS._battle_speed_index = _saved_index
	Engine.time_scale = _saved_scale
	if _saved_default != null:
		GameState.default_battle_speed = _saved_default
	if not _had_speed_hint:
		BS._hints_shown.erase("speed_toggle")
	if _bm != null:
		_bm.restore()


func after_all() -> void:
	SoundState.restore()


func _battle() -> Node:
	_scene = load("res://src/battle/BattleScene.tscn").instantiate()
	add_child(_scene)
	await get_tree().process_frame
	return _scene


## The hold has lasted `ms` already: the start is moved back, so no wall-clock wait.
func _held_for(s: Node, ms: int) -> void:
	s._speed_hold_start_ms = Time.get_ticks_msec() - ms


func test_the_floor_names_every_member_this_file_drives() -> void:
	var s: Node = await _battle()
	var src: String = GdSource.code_of("res://test/unit/test_a_held_speed_button_slows_the_battle.gd")
	var names: Dictionary = {}
	for hit in RegEx.create_from_string("\\bs\\.([A-Za-z_][A-Za-z0-9_]*)").search_all(src):
		names[hit.get_string(1)] = true
	assert_gt(names.size(), 3, "CONTROL: the derivation must find the members this file drives")
	var missing: Array = []
	for n in names:
		if not (s.has_method(str(n)) or str(n) in s):
			missing.append(str(n))
	assert_eq(missing, [], "every member this file reaches must exist on BattleScene: %s" % [names.keys()])
	assert_between(BS.SPEED_HOLD_MS, 200, 1000, "a hold must be longer than a tap and short enough to feel like one")


func test_a_tap_steps_up() -> void:
	var s: Node = await _battle()
	BS._battle_speed_index = 2
	s._speed_button(true)
	s._speed_button(false)
	assert_eq(BS._battle_speed_index, 3, "a quick press and release must step ONE rung up, as the button always has")


func test_a_hold_steps_down_once_and_its_release_does_nothing() -> void:
	var s: Node = await _battle()
	BS._battle_speed_index = 3
	s._speed_button(true)
	_held_for(s, BS.SPEED_HOLD_MS + 50)
	s._tick_speed_hold()
	assert_eq(BS._battle_speed_index, 2, "reaching the hold threshold must step ONE rung down")
	s._tick_speed_hold()
	assert_eq(BS._battle_speed_index, 2, "and only once per hold, however long it lasts")
	s._speed_button(false)
	assert_eq(BS._battle_speed_index, 2, "the hold's release must NOT also step up: one press is one step")


## The tick may not have run before the release (a fast frame boundary): a late release still slows.
func test_a_hold_released_before_the_tick_still_steps_down() -> void:
	var s: Node = await _battle()
	BS._battle_speed_index = 4
	s._speed_button(true)
	_held_for(s, BS.SPEED_HOLD_MS + 50)
	s._speed_button(false)
	assert_eq(BS._battle_speed_index, 3, "a held press released before the tick must still be a hold, not a tap")


func test_a_hold_at_the_slowest_stays_there() -> void:
	var s: Node = await _battle()
	BS._battle_speed_index = 0
	s._speed_button(true)
	_held_for(s, BS.SPEED_HOLD_MS + 50)
	s._tick_speed_hold()
	s._speed_button(false)
	assert_eq(BS._battle_speed_index, 0, "a hold at the slowest must clamp, not wrap to the fastest")


## Alt-tab mid-press: the release never arrives. Without the drop, the hold slows the battle and eats the next tap.
func test_a_hold_whose_release_is_lost_to_a_focus_change_is_dropped() -> void:
	var s: Node = await _battle()
	BS._battle_speed_index = 3
	s._speed_button(true)
	s._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_lt(s._speed_hold_start_ms, 0, "losing focus must drop the armed hold")
	if s._speed_hold_start_ms >= 0:
		_held_for(s, BS.SPEED_HOLD_MS + 50)   # the time that passes while the player is away
	s._tick_speed_hold()
	assert_eq(BS._battle_speed_index, 3, "a hold whose release was lost must not slow the battle")
	s._speed_button(true)
	s._speed_button(false)
	assert_eq(BS._battle_speed_index, 4, "and the next tap must step up, not be eaten by the stale hold")


## The persisted choice and the live scale follow the one writer, both ways.
func test_both_directions_persist_through_the_one_writer() -> void:
	var s: Node = await _battle()
	BS._battle_speed_index = 3
	s._speed_button(true)
	_held_for(s, BS.SPEED_HOLD_MS + 50)
	s._tick_speed_hold()
	assert_almost_eq(float(GameState.default_battle_speed), BS.BATTLE_SPEEDS[2], 0.0001,
		"a step DOWN must persist like a step up, so the next battle starts at the slower speed")
	s._speed_button(false)
	s._speed_button(true)
	s._speed_button(false)
	assert_almost_eq(float(GameState.default_battle_speed), BS.BATTLE_SPEEDS[3], 0.0001, "and a tap back up persists too")
	var src: String = GdSource.code_of("res://src/battle/BattleScene.gd")
	assert_eq(src.count("_battle_speed_index = "), 1,
		"inside BattleScene, _apply_battle_speed_index must stay the ONE writer of the persisted index " +
		"(New Game, save load and Settings set it from outside, by design)")


## REAL ROUTING, not a direct call: the command menu is a CHILD of BattleScene, so it sees the speed
## button first. If it ever ate the RELEASE, a tap would never step up, and after SPEED_HOLD_MS it
## would step DOWN instead. A live battle-mode menu, a pad press and release pushed through the viewport.
func test_a_tap_through_a_live_command_menu_steps_up_once() -> void:
	var s: Node = await _battle()
	BS._battle_speed_index = 2
	var menu := Win98Menu.new()
	menu.battle_mode = true
	s.add_child(menu)
	menu.setup("Fighter", [{"id": "attack", "label": "Attack"}], Vector2(400, 300), "fighter")
	menu._can_accept_input = true
	assert_false(menu._nav_is_blocked(), "CONTROL: the menu must be LIVE, or the release never meets it")
	for pressed in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.button_index = JOY_BUTTON_Y
		ev.pressed = pressed
		get_tree().root.push_input(ev)
	assert_eq(BS._battle_speed_index, 3, "a tap with the command menu up must reach BattleScene and step ONE rung up")
	assert_lt(s._speed_hold_start_ms, 0, "and its release must have arrived, or the next tick turns the tap into a slow-down")
	menu.queue_free()
