extends GutTest

## Repeat answered only in the battle log; a press is now heard: repeat_turn when it queues, menu_error when it declines.
## The REAL BattleScene._repeat_previous_actions runs; the probe replaces only the log and the menu close, which need a built scene.

const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const SfxState := preload("res://test/unit/helpers/sfx_state.gd")
const KEY := "repeat_turn"
const REFUSAL := "menu_error"


class ProbeScene extends "res://src/battle/BattleScene.gd":
	var logged: Array = []
	func log_message(message: String) -> void:
		logged.append(message)
	func _close_win98_menu() -> void:
		pass


var _bm_guard = null
var _saved_reason: String = ""


func before_each() -> void:
	_bm_guard = BattleStateGuard.new()
	_bm_guard.snapshot()
	_saved_reason = str(BattleManager.last_repeat_refusal)
	BattleManager.turbo_mode = true
	BattleManager.is_autobattle_enabled = false
	_clear()


func after_each() -> void:
	BattleManager.last_repeat_refusal = _saved_reason
	if _bm_guard != null:
		_bm_guard.restore()
	_clear()
	SoundManager._sfx_suppressed_by_cooldown = false
	SfxState.release_streams()


func _clear() -> void:
	SoundManager._ui_player.stream = null
	SoundManager._sfx_cooldowns.erase(KEY)
	SoundManager._sfx_cooldowns.erase(REFUSAL)


func _file(key: String) -> String:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sfx_manifest.json"))
	var sfx: Dictionary = (parsed as Dictionary).get("sfx", {}) if parsed is Dictionary else {}
	return str((sfx.get(key, {}) as Dictionary).get("file", ""))


## The file the UI voice holds now, or "" if it is silent.
func _heard() -> String:
	var s: AudioStream = SoundManager._ui_player.stream
	return s.resource_path.trim_prefix("res://") if s != null else ""


func _make(cname: String) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = cname
	c.max_hp = 500
	c.current_hp = 500
	c.max_mp = 30
	c.current_mp = 30
	c.attack = 10
	c.defense = 80
	c.magic = 10
	c.speed = 10
	c.current_ap = 1
	c.is_alive = true
	add_child_autofree(c)
	return c


## Ada's menu is open in a selection phase and last round remembered an attack for her: Repeat has something to queue.
func _stage_a_round_to_repeat() -> void:
	var ada := _make("Ada")
	var slime := _make("Slime")
	var bm := BattleManager
	for arr in [bm.player_party, bm.enemy_party, bm.all_combatants, bm.selection_order, bm.pending_actions, bm.execution_order]:
		arr.clear()
	bm.previous_round_actions.clear()
	bm.player_party.append(ada)
	bm.all_combatants.append(ada)
	bm.selection_order.append(ada)
	bm.previous_round_actions["ada"] = [{"type": "attack", "target": slime, "speed": 1.0}]
	if AutobattleSystem:
		AutobattleSystem.set_autobattle_enabled(bm._get_character_id(ada), false)
	bm.enemy_party.append(slime)
	bm.all_combatants.append(slime)
	bm.selection_order.append(slime)
	bm.selection_index = 0
	bm.current_combatant = ada
	bm.current_state = bm.BattleState.PLAYER_SELECTING
	bm.volatility = VolatilitySystem.new()
	bm.volatility.reset_battle()


## Kept OUT of the tree: BattleScene._ready builds its whole UI and wires the live battle, and the handler under test needs neither.
func _press() -> ProbeScene:
	var scene: ProbeScene = autofree(ProbeScene.new())
	_clear()
	scene._repeat_previous_actions()
	return scene


func test_the_cue_is_authored_and_loads_as_its_own_file() -> void:
	var f := _file(KEY)
	assert_ne(f, "", "repeat_turn is not registered in sfx_manifest.json")
	assert_true(FileAccess.file_exists("res://" + f), "repeat_turn names %s, which is not on disk" % f)
	var stream = load("res://" + f)
	assert_true(stream is AudioStream and (stream as AudioStream).get_length() > 0.2,
		"repeat_turn does not load as a real stream (length %s)" % [
			(stream as AudioStream).get_length() if stream is AudioStream else -1.0])
	assert_ne(f, _file(REFUSAL), "CONTROL: the success cue must not be the refusal's file, or the two arms below cannot tell them apart")


func test_a_repeat_that_queues_is_heard() -> void:
	_stage_a_round_to_repeat()
	var scene := _press()
	assert_true(BattleManager.pending_actions.size() >= 1, "CONTROL: Repeat queued nothing, so this is not the success path")
	assert_true(scene.logged.any(func(m): return "Repeating previous actions" in str(m)), "CONTROL: the scene did not log the success line")
	assert_eq(_heard(), _file(KEY), "a Repeat that queued last round's actions was not heard as repeat_turn")


func test_a_repeat_with_nothing_to_repeat_says_no() -> void:
	_stage_a_round_to_repeat()
	BattleManager.previous_round_actions.clear()
	var scene := _press()
	assert_eq(BattleManager.pending_actions.size(), 0, "CONTROL: Repeat queued something with no remembered round")
	assert_true(scene.logged.any(func(m): return "first round" in str(m)), "CONTROL: the refusal named was not round one's: %s" % [scene.logged])
	assert_eq(_heard(), _file(REFUSAL), "a Repeat declined on round one was silent, or played the success figure")


func test_a_repeat_outside_selection_says_no() -> void:
	_stage_a_round_to_repeat()
	BattleManager.current_state = BattleManager.BattleState.EXECUTION_PHASE
	var scene := _press()
	assert_eq(BattleManager.pending_actions.size(), 0, "CONTROL: Repeat queued something outside selection")
	assert_true(scene.logged.any(func(m): return "while you are choosing" in str(m)), "CONTROL: the scene's own gate did not speak: %s" % [scene.logged])
	assert_eq(_heard(), _file(REFUSAL), "a Repeat pressed outside selection was silent")
