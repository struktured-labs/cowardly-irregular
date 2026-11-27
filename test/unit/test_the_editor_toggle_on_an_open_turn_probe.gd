extends GutTest

## MEASUREMENT PROBE (main 28266), prints and asserts only its floors: in battle the grid editor opens on the current member's
## turn, Select turns that member's autobattle on, and on close GameLoop only shows the battle menu again (it runs nothing).
## Does that open turn run, wait on a visible manual menu, or wedge? CONTROL: the F6 shape (toggle, then run the open turn).

const SCENE := preload("res://src/battle/BattleScene.tscn")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const ABProfiles := preload("res://test/unit/helpers/autobattle_profiles.gd")
const CAP_MS := 10000

var _guard = null
var _saved_persist := false
var _profiles: Dictionary = {}


func before_each() -> void:
	_guard = BattleStateGuard.new()
	_guard.snapshot()
	_saved_persist = AutobattleSystem._test_disable_persistence
	AutobattleSystem._test_disable_persistence = true
	_profiles = ABProfiles.snapshot(AutobattleSystem)


func after_each() -> void:
	ABProfiles.restore(AutobattleSystem, _profiles)
	AutobattleSystem._test_disable_persistence = _saved_persist
	if _guard != null:
		_guard.restore()


func after_all() -> void:
	SoundState.restore()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## A slime fight, waited until a party member's own turn menu is up.
func _open_turn() -> Node:
	var scene = SCENE.instantiate()
	scene.encounter_enemies = ["slime"]
	add_child_autofree(scene)
	await _frames(3)
	if scene._waiting_for_dialogue:
		scene._battle_dialogue.dismiss()
		await _frames(3)
	for m in scene.party_members:
		AutobattleSystem.set_autobattle_enabled(m.combatant_name.to_lower().replace(" ", "_"), false)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 5000 and not (BattleManager.current_state == BattleManager.BattleState.PLAYER_SELECTING
			and BattleManager.current_combatant in BattleManager.player_party):
		await get_tree().process_frame
	return scene


func _toggle_event() -> InputEvent:
	for ev in InputMap.action_get_events("battle_toggle_auto"):
		if ev is InputEventJoypadButton:
			var e := ev.duplicate() as InputEventJoypadButton
			e.pressed = true
			return e
	return null


## Opens the editor on the open turn exactly as GameLoop does, presses Select in it, closes it as GameLoop does, then watches.
func _run(run_open_turn_on_close: bool) -> Dictionary:
	var scene: Node = await _open_turn()
	var who: Combatant = BattleManager.current_combatant
	assert_eq(BattleManager.current_state, BattleManager.BattleState.PLAYER_SELECTING, "PRECONDITION: a member's turn is open")
	var id := who.combatant_name.to_lower().replace(" ", "_")
	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	var ed: Control = load("res://src/ui/autobattle/AutobattleGridEditor.gd").new()
	ed.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(ed)
	ed.setup(id, who.combatant_name, who, BattleManager.player_party)
	scene.set_command_menu_visible(false)
	await _frames(2)
	var ev := _toggle_event()
	assert_not_null(ev, "FLOOR: battle_toggle_auto has a pad binding")
	ed._input(ev)
	assert_true(AutobattleSystem.is_autobattle_enabled(id), "FLOOR: Select in the editor turned %s's autobattle on" % id)
	ed.queue_free()
	scene.set_command_menu_visible(true)
	if run_open_turn_on_close and BattleManager.current_state == BattleManager.BattleState.PLAYER_SELECTING:
		BattleManager.execute_autobattle_for_current()
	var out := {"who": id, "turn_left": false, "ms": 0, "watchdog": 0, "menu_visible": false, "state": ""}
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < CAP_MS:
		out["watchdog"] = maxi(out["watchdog"], scene._menu_wd_retries)
		if BattleManager.current_combatant != who or BattleManager.current_state != BattleManager.BattleState.PLAYER_SELECTING:
			out["turn_left"] = true
			break
		await get_tree().process_frame
	out["ms"] = Time.get_ticks_msec() - t0
	out["menu_visible"] = is_instance_valid(scene.active_win98_menu) and scene.active_win98_menu.visible
	out["state"] = str(BattleManager.current_state)
	return out


func test_measure_the_editor_toggle_on_an_open_turn() -> void:
	var r := await _run(false)
	gut.p("EDTURN editor close (shipped): %s" % [r])
	assert_true(true, "probe printed")


func test_control_the_f6_shape_runs_the_open_turn() -> void:
	var r := await _run(true)
	gut.p("EDTURN CONTROL run-on-close: %s" % [r])
	assert_true(r["turn_left"], "CONTROL: toggling then running the open turn moves the battle on within %d ms" % CAP_MS)
