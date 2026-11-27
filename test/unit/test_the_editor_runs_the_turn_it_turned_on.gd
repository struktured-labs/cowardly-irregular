extends GutTest

## In battle the grid editor opens on the member whose turn is open, and its Select turns that member's autobattle on.
## Closing only showed the menu again, so the member read as on and still waited on a manual menu: measured (ff671f391) on
## Hero's turn, 10 005 ms without the turn moving, watchdog 0. F6 runs such a turn at once; closing the editor now does too.
## Open and close are DRIVEN through GameLoop._toggle_autobattle_editor (the Start/F5 path) on a GameLoop that is not booted.

const SCENE := preload("res://src/battle/BattleScene.tscn")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const ABProfiles := preload("res://test/unit/helpers/autobattle_profiles.gd")
const WAIT_MS := 5000

var _guard = null
var _saved_persist := false
var _profiles: Dictionary = {}
var _saved_enabled: Dictionary = {}
var _saved_unlock := false


func before_each() -> void:
	_guard = BattleStateGuard.new()
	_guard.snapshot()
	_saved_persist = AutobattleSystem._test_disable_persistence
	AutobattleSystem._test_disable_persistence = true
	_profiles = ABProfiles.snapshot(AutobattleSystem)
	## Established, not just snapshotted: an earlier arm's member left on would act at its first turn and skip the open one.
	_saved_enabled = AutobattleSystem.autobattle_enabled.duplicate(true)
	AutobattleSystem.autobattle_enabled = {}
	## Every member editable, so the editor's own member switch can reach one whose turn is not open.
	_saved_unlock = GameState.debug_all_pcs_unlocked
	GameState.debug_all_pcs_unlocked = true


func after_each() -> void:
	AutobattleSystem.autobattle_enabled = _saved_enabled
	GameState.debug_all_pcs_unlocked = _saved_unlock
	ABProfiles.restore(AutobattleSystem, _profiles)
	AutobattleSystem._test_disable_persistence = _saved_persist
	if _guard != null:
		_guard.restore()


func after_all() -> void:
	SoundState.restore()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _id(c: Combatant) -> String:
	return c.combatant_name.to_lower().replace(" ", "_")


## A slime fight with nobody on autobattle, waited until a party member's own turn is open.
func _open_turn() -> Node:
	var scene = SCENE.instantiate()
	scene.encounter_enemies = ["slime"]
	add_child_autofree(scene)
	await _frames(3)
	if scene._waiting_for_dialogue:
		scene._battle_dialogue.dismiss()
		await _frames(3)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 15000 and not (BattleManager.current_state == BattleManager.BattleState.PLAYER_SELECTING
			and BattleManager.current_combatant in BattleManager.player_party):
		await get_tree().process_frame
	assert_eq(BattleManager.current_state, BattleManager.BattleState.PLAYER_SELECTING, "PRECONDITION: a member's turn is open")
	return scene


func _toggle_event() -> InputEvent:
	for ev in InputMap.action_get_events("battle_toggle_auto"):
		if ev is InputEventJoypadButton:
			var e := ev.duplicate() as InputEventJoypadButton
			e.pressed = true
			return e
	return null


## Opens the editor through GameLoop, optionally switches it to the next member (its D-pad handler), presses Select `presses`
## times inside it, closes it through GameLoop, then watches.
func _run(presses: int, already_auto: bool, other_member: bool = false) -> Dictionary:
	var scene: Node = await _open_turn()
	var who: Combatant = BattleManager.current_combatant
	if already_auto:
		AutobattleSystem.set_autobattle_enabled(_id(who), true)
	var ended := [0]
	var on_end := func(c: Combatant) -> void:
		if c == who:
			ended[0] += 1
	BattleManager.selection_turn_ended.connect(on_end)
	var gl: Node = load("res://src/GameLoop.gd").new()
	autofree(gl)
	gl.current_scene = scene
	gl.current_state = gl.LoopState.BATTLE
	gl.party.assign(BattleManager.player_party)
	gl._toggle_autobattle_editor()
	var ed: Control = gl._autobattle_editor
	assert_not_null(ed, "FLOOR: GameLoop opened the editor")
	var layer: CanvasLayer = gl._autobattle_layer
	gl.remove_child(layer)
	add_child(layer)
	await _frames(2)
	assert_eq(str(ed.get("character_id")), _id(who), "PRECONDITION: the editor opened on the member whose turn is open")
	if other_member:
		ed._cycle_character(1)
		assert_ne(str(ed.get("character_id")), _id(who), "PRECONDITION: the editor switched to another member")
	var edited: String = str(ed.get("character_id"))
	var ev := _toggle_event()
	assert_not_null(ev, "FLOOR: battle_toggle_auto has a pad binding")
	for i in presses:
		ed._input(ev)
	var on_after: bool = AutobattleSystem.is_autobattle_enabled(_id(who))
	gl._toggle_autobattle_editor()
	var out := {"who": _id(who), "edited": edited, "edited_auto": AutobattleSystem.is_autobattle_enabled(edited), "auto": on_after, "editor_gone": gl._autobattle_editor == null, "turn_left": false, "ms": 0, "watchdog": 0}
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < WAIT_MS:
		out["watchdog"] = maxi(out["watchdog"], scene._menu_wd_retries)
		if BattleManager.current_combatant != who or BattleManager.current_state != BattleManager.BattleState.PLAYER_SELECTING:
			out["turn_left"] = true
			break
		await get_tree().process_frame
	out["ms"] = Time.get_ticks_msec() - t0
	await _frames(2)
	out["ended"] = ended[0]
	BattleManager.selection_turn_ended.disconnect(on_end)
	if is_instance_valid(layer):
		layer.queue_free()
	gut.p("EDTURN presses=%d already_auto=%s: %s" % [presses, str(already_auto), out])
	return out


func test_select_on_then_close_runs_that_turn() -> void:
	var r: Dictionary = await _run(1, false)
	assert_true(r["auto"], "PRECONDITION: Select in the editor turned %s's autobattle on" % r["who"])
	assert_true(r["editor_gone"], "PRECONDITION: GameLoop closed the editor")
	assert_true(r["turn_left"], "closing the editor runs the open turn it turned to autobattle (waited %d ms)" % r["ms"])
	assert_eq(r["ended"], 1, "and that turn is chosen once")
	assert_eq(r["watchdog"], 0, "without the menu watchdog")


## CONTROL: no Select, so the member stays manual and the editor does not take the turn from the player.
func test_control_closing_without_select_leaves_the_turn_manual() -> void:
	var r: Dictionary = await _run(0, false)
	assert_false(r["auto"], "PRECONDITION: nothing turned autobattle on")
	assert_false(r["turn_left"], "a manual turn stays the player's after the editor closes")


## CONTROL (main 28271): a member already on when the editor opened is not run again by the close.
func test_control_a_member_already_on_is_not_run_by_the_close() -> void:
	var r: Dictionary = await _run(0, true)
	assert_true(r["auto"], "PRECONDITION: the member was already on")
	assert_false(r["turn_left"], "the close does not run a turn whose autobattle it did not turn on")


## CONTROL (main 28307): Select turns ON a DIFFERENT member than the one whose turn is open, so the close leaves that turn alone.
func test_control_turning_on_another_member_leaves_the_open_turn_alone() -> void:
	var r: Dictionary = await _run(1, false, true)
	assert_true(r["edited_auto"], "PRECONDITION: Select turned the other member (%s) on" % r["edited"])
	assert_false(r["auto"], "PRECONDITION: the open turn's member (%s) is still manual" % r["who"])
	assert_false(r["turn_left"], "the close does not run a turn whose member it did not turn on")
