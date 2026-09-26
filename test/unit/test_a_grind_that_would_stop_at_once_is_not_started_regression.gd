extends GutTest

## struktured 2026-09-25 on .502: "got stuck in the autogrind menu again", "i cant escape the menu", "the music also stopped".
## A grind stopped on low HP; he pressed Start again without healing. The pre-battle HP check stopped the new session
## inside its own start call, and every console, lock and music restore then ran on the abort branch.
## The console now asks the same check BEFORE starting and refuses with the reason, touching nothing.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")

var _ag_state: Dictionary
var _bm_guard = BattleStateGuard.new()
var _saved_rules: Dictionary
var _gl: Node
var _ui: Control
var _requested := 0
var _closed := 0


func before_each() -> void:
	_ag_state = AutogrindState.snapshot()
	_bm_guard.snapshot()
	AutogrindSystem._test_disable_persistence = true
	if AutogrindSystem.is_grinding:
		AutogrindSystem.stop_autogrind("test reset")
	_saved_rules = AutogrindSystem.interrupt_rules.duplicate(true)
	AutogrindSystem.interrupt_rules["hp_threshold"] = 20.0
	AutogrindSystem.interrupt_rules["item_depleted"] = false
	_requested = 0
	_closed = 0
	_gl = load("res://src/GameLoop.gd").new()
	add_child_autofree(_gl)
	var explore := Node.new()
	add_child_autofree(explore)
	_gl._exploration_scene = explore
	_gl._current_map_id = "overworld"
	_gl.current_state = _gl.LoopState.EXPLORATION
	var layer := CanvasLayer.new()
	_ui = load("res://src/ui/autogrind/AutogrindUI.gd").new()
	layer.add_child(_ui)
	_gl.add_child(layer)
	_gl._autogrind_ui_layer = layer
	_gl._autogrind_ui = _ui


func after_each() -> void:
	InputLockManager.pop_all()
	if AutogrindSystem.is_grinding:
		AutogrindSystem.stop_autogrind("test teardown")
	AutogrindSystem.interrupt_rules = _saved_rules
	Engine.time_scale = 1.0
	AutogrindState.restore(_ag_state)
	_bm_guard.restore()
	SoundManager.stop_music()


func _member(name: String, hp: int) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": 100, "max_mp": 10, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	c.current_hp = hp
	return c


## wire=false stops at the emit: a healthy start would otherwise launch a real battle on the BattleManager autoload.
func _open_console(party: Array, wire: bool = true) -> void:
	var typed: Array[Combatant] = []
	for m in party:
		typed.append(m)
	_gl.party = typed
	_ui.setup(typed, "Test Plains")
	_ui.grind_requested.connect(func(_c): _requested += 1)
	if wire:
		_ui.grind_requested.connect(_gl._start_autogrind)
	_ui.closed.connect(func(): _closed += 1)
	await wait_frames(2)


func _log_text() -> String:
	return _ui._battle_log.get_parsed_text() if _ui._battle_log else ""


func test_the_precheck_names_the_hp_stop_and_passes_a_healthy_party() -> void:
	var hurt: Dictionary = AutogrindSystem.stop_before_first_battle([_member("Hurt", 5), _member("Fine", 100)])
	assert_eq(str(hurt.get("rule", "")), "hp_threshold", "a 5%% member under a 20%% stop must be named as the HP rule")
	assert_eq(str(hurt.get("member", "")), "Hurt", "and the refusal must say WHO is low")
	assert_true(AutogrindSystem.stop_before_first_battle([_member("A", 100), _member("B", 90)]).is_empty(),
		"CONTROL: a healthy party must pass, or every arm below is a refusal for the wrong reason")


## The pre-check is only honest if it is the controller's own opinion: same rules, same filtering, same answer.
func test_the_precheck_agrees_with_what_a_real_start_does() -> void:
	var party: Array = [_member("Hurt", 5), _member("Fine", 100)]
	var predicted: String = str(AutogrindSystem.stop_before_first_battle(party).get("reason", ""))
	var stopped_with: Array = [""]
	var ctrl = preload("res://src/autogrind/AutogrindController.gd").new()
	add_child_autofree(ctrl)
	ctrl.grind_complete.connect(func(r): stopped_with[0] = r)
	ctrl.start_grind(party, {"ludicrous_speed": true, "auto_advance": false}, "plains")
	assert_ne(predicted, "", "CONTROL: the fixture must be one the pre-check refuses")
	assert_eq(stopped_with[0], predicted, "the console's pre-check and the controller's first pre-battle check disagree")


func test_start_with_a_wounded_party_is_refused_and_changes_nothing() -> void:
	SoundManager.play_area_music("overworld")
	await wait_frames(2)
	var music_before: String = SoundManager._current_music
	var area_before: String = SoundManager._current_area
	await _open_console([_member("Hurt", 5), _member("Fine", 100)])
	var state_before = _gl.current_state
	_ui._toggle_grinding()
	await wait_frames(3)
	assert_eq(_requested, 0, "a start that would stop before its first battle must never reach GameLoop")
	assert_true(_ui.visible, "the console must stay on screen")
	assert_false(_ui._is_grinding, "and must not think it is grinding")
	assert_eq(_gl.current_state, state_before, "GameLoop's state must be untouched")
	assert_false(_gl._autogrind_summary != null and is_instance_valid(_gl._autogrind_summary),
		"no stop summary for a session that never began")
	assert_false(InputLockManager.has_lock("autogrind_summary"), "and no lock left behind")
	assert_eq(SoundManager._current_music, music_before, "the field bed must be exactly what was playing before the press")
	assert_eq(SoundManager._current_area, area_before, "and its area unchanged")
	assert_string_contains(_log_text(), "Heal first", "the player must be told why, and what to do")
	assert_string_contains(_log_text(), "Hurt", "naming the member who is low")


func test_the_console_still_closes_after_a_refusal() -> void:
	await _open_console([_member("Hurt", 5)])
	_ui._toggle_grinding()
	await wait_frames(2)
	_ui.cursor_row = _ui.rules.size()
	_ui.cursor_col = 0
	var ev := InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	get_viewport().push_input(ev)
	await wait_frames(2)
	assert_eq(_closed, 1, "Cancel on the start row must close the console after a refused start")


func test_a_healthy_party_still_starts() -> void:
	await _open_console([_member("A", 100), _member("B", 100)], false)
	_ui._toggle_grinding()
	await wait_frames(3)
	assert_eq(_requested, 1, "CONTROL: a healthy party must still reach GameLoop, or the refusal arms prove nothing")
