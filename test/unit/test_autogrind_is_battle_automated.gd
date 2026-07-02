extends GutTest

## Regression coverage for the quest-gate predicate AutogrindSystem.is_battle_automated().
## Contract (cowir-overworld msg 2113): the manual_only kill_n credit gate asks
## "was THIS battle automated" — a PAUSED grind is NOT automated, so manual
## encounters fought during pause must credit normally. Gating on raw is_grinding
## had exactly that false positive.

var _system: Node


func before_each() -> void:
	_system = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(_system)
	_system.is_grinding = false
	_system._automation_paused = false


func test_false_when_no_grind_session() -> void:
	assert_false(_system.is_battle_automated(),
		"No grind session → battles are manual")


func test_true_while_actively_chaining() -> void:
	_system.is_grinding = true
	assert_true(_system.is_battle_automated(),
		"Active unpaused grind → battles are automated")


func test_false_while_grind_paused() -> void:
	# THE false positive: session exists (is_grinding stays true through pause)
	# but the player is hand-fighting manual encounters.
	_system.is_grinding = true
	_system.set_automation_paused(true)
	assert_false(_system.is_battle_automated(),
		"Paused grind → manual encounters must NOT be classified as automated (manual_only quests would wrongly block credit)")


func test_resume_restores_automated() -> void:
	_system.is_grinding = true
	_system.set_automation_paused(true)
	_system.set_automation_paused(false)
	assert_true(_system.is_battle_automated(),
		"Resume → chaining battles are automated again")


func test_start_autogrind_resets_stale_pause() -> void:
	# A pause flag leaked from a prior session must not mark the fresh session's
	# battles as manual — that would let manual_only quests be autogrind-farmed.
	_system._automation_paused = true
	var member = Combatant.new()
	member.initialize({"name": "T", "max_hp": 100, "max_mp": 10, "attack": 10, "defense": 5, "magic": 5, "speed": 10})
	add_child_autofree(member)
	var party: Array[Combatant] = [member]
	_system.start_autogrind(party, {})
	assert_true(_system.is_battle_automated(),
		"start_autogrind must clear a stale pause flag — fresh session chains immediately")
	_system.stop_autogrind("test cleanup")


func test_stop_autogrind_clears_pause_flag() -> void:
	_system.is_grinding = true
	_system._automation_paused = true
	_system.is_grinding = true
	_system.stop_autogrind("test")
	assert_false(_system._automation_paused,
		"stop_autogrind must clear the pause flag — no leak into the next session")
	assert_false(_system.is_battle_automated(),
		"After stop, battles are manual")


func test_controller_bridges_all_three_transitions() -> void:
	# Source-inspection pin: the controller must call set_automation_paused(true)
	# at BOTH paused entries (immediate pause_grind + deferred post-battle) and
	# (false) in resume_grind. Missing the deferred site would mark manual battles
	# automated after a mid-battle pause request.
	var src: String = load("res://src/autogrind/AutogrindController.gd").source_code
	var true_calls := src.count("set_automation_paused(true)")
	var false_calls := src.count("set_automation_paused(false)")
	assert_eq(true_calls, 2,
		"Controller must bridge BOTH pause entries (immediate + deferred), found %d" % true_calls)
	assert_eq(false_calls, 1,
		"Controller must bridge resume_grind, found %d" % false_calls)