extends GutTest

## The Summary's "Meta-Bosses: N beaten / M met" read 15 / 13 after a 100-battle grind with two collapses. A collapse boss
## is built as a meta-boss and its win goes through on_meta_boss_victory (beaten +1), but it was launched without
## touching meta_bosses_spawned. Every collapse you beat put "beaten" further past "met".

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

var _ag: Dictionary
var _ctrl


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	if AutogrindSystem.is_grinding:
		AutogrindSystem.stop_autogrind("test reset")
	var party: Array = []
	for n in ["Fighter", "Cleric"]:
		var c := Combatant.new()
		c.initialize({"name": n, "max_hp": 500, "max_mp": 50, "attack": 20, "defense": 10, "magic": 10, "speed": 10})
		add_child_autofree(c)
		party.append(c)
	_ctrl = preload("res://src/autogrind/AutogrindController.gd").new()
	add_child_autofree(_ctrl)
	assert_true(_ctrl.start_grind(party, {"ludicrous_speed": true, "auto_advance": false}, "plains"), "CONTROL: the grind must start")


func after_each() -> void:
	if _ctrl._state != _ctrl.State.IDLE:
		_ctrl.stop_grind("test cleanup")
	Engine.time_scale = 1.0
	AutogrindState.restore(_ag)


func test_a_beaten_collapse_boss_was_also_met() -> void:
	var met_before: int = AutogrindSystem.meta_bosses_spawned
	var beaten_before: int = AutogrindSystem.meta_bosses_defeated
	_ctrl._launch_collapse_boss_battle()
	_ctrl.on_battle_ended(true, 0, {})
	assert_eq(AutogrindSystem.meta_bosses_defeated - beaten_before, 1, "CONTROL: beating a collapse boss counts as a meta-boss beaten")
	assert_eq(AutogrindSystem.meta_bosses_spawned - met_before, 1, "and it must count as met, or the Summary reads more beaten than met")


func test_a_regular_meta_boss_still_counts_once_each() -> void:
	_ctrl._launch_meta_boss_battle()
	_ctrl.on_battle_ended(true, 0, {})
	assert_eq(AutogrindSystem.meta_bosses_spawned, 1, "CONTROL: a meta-boss is met once")
	assert_eq(AutogrindSystem.meta_bosses_defeated, 1, "and beaten once")


func test_beaten_never_exceeds_met() -> void:
	for i in 3:
		if i % 2 == 0:
			_ctrl._launch_collapse_boss_battle()
		else:
			_ctrl._launch_meta_boss_battle()
		_ctrl.on_battle_ended(true, 0, {})
	assert_lte(AutogrindSystem.meta_bosses_defeated, AutogrindSystem.meta_bosses_spawned,
		"the Summary showed %d beaten / %d met" % [AutogrindSystem.meta_bosses_defeated, AutogrindSystem.meta_bosses_spawned])
