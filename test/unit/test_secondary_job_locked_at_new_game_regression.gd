extends GutTest

## #763 (struktured: "2ndary jobs should not be set at beginning of game. just none (and locked
## eventually until you get a bit further)"). New-game parties start with no secondary; the slot is
## locked until the Cave Rat King (W1's first boss) is defeated. Saves that already carry a
## secondary keep it.

var _saved_flags: Dictionary = {}
var _saved_consts: Dictionary = {}
var _saved_debug: bool = false


func before_each() -> void:
	_saved_flags = GameState.story_flags.duplicate()
	_saved_consts = GameState.game_constants.duplicate()
	_saved_debug = GameState.debug_log_enabled
	GameState.story_flags.erase("rat_king_defeated")
	GameState.game_constants.erase("cutscene_flag_rat_king_defeated")
	GameState.debug_log_enabled = false


func after_each() -> void:
	GameState.story_flags = _saved_flags
	GameState.game_constants = _saved_consts
	GameState.debug_log_enabled = _saved_debug


func test_locked_on_a_fresh_game() -> void:
	assert_false(JobSystem.is_secondary_job_unlocked())


func test_unlocks_on_the_story_flag() -> void:
	GameState.set_story_flag("rat_king_defeated")
	assert_true(JobSystem.is_secondary_job_unlocked())


func test_unlocks_on_the_cutscene_constant_alone() -> void:
	GameState.game_constants["cutscene_flag_rat_king_defeated"] = true
	assert_true(JobSystem.is_secondary_job_unlocked(), "older saves may carry only the constant")


func test_game_loop_assigns_no_starting_secondary() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	for fn in ["_create_party_from_customizations", "_create_party"]:
		var start := src.find("func %s(" % fn)
		assert_gt(start, -1, fn)
		var end := src.find("\nfunc ", start + 6)
		var body := src.substr(start, end - start)
		assert_false(body.contains("assign_secondary_job("), "%s must not assign a starting secondary" % fn)


func test_job_menu_shows_locked_and_refuses_the_slot() -> void:
	var c := Combatant.new()
	c.initialize({"name": "Hero", "max_hp": 100})
	add_child_autofree(c)
	JobSystem.assign_job(c, "fighter")
	var menu = load("res://src/ui/JobMenu.gd").new()
	menu.character = c
	autofree(menu)
	assert_true(menu.is_slot_locked(1))
	assert_false(menu.is_slot_locked(0))
	assert_eq(menu._get_current_job_name(1), "(locked)")
	GameState.set_story_flag("rat_king_defeated")
	assert_false(menu.is_slot_locked(1))
	assert_eq(menu._get_current_job_name(1), "(none)")


func test_an_existing_secondary_is_kept_and_editable_while_locked() -> void:
	var c := Combatant.new()
	c.initialize({"name": "Vex", "max_hp": 100})
	add_child_autofree(c)
	JobSystem.assign_job(c, "mage")
	assert_true(JobSystem.assign_secondary_job(c, "cleric"), "legacy saves restore through this call")
	var menu = load("res://src/ui/JobMenu.gd").new()
	menu.character = c
	autofree(menu)
	assert_eq(c.secondary_job_id, "cleric")
	assert_false(menu.is_slot_locked(1), "never strip or freeze a secondary a save already has")


func test_combatant_with_null_secondary_is_battle_safe() -> void:
	var c := Combatant.new()
	c.initialize({"name": "Solo", "max_hp": 100})
	add_child_autofree(c)
	JobSystem.assign_job(c, "fighter")
	assert_null(c.secondary_job)
	c.recalculate_stats()
	assert_eq(c.get_profile_key().ends_with(":"), true)
	var d: Dictionary = c.to_dict() if c.has_method("to_dict") else {}
	assert_true(d.is_empty() or str(d.get("secondary_job_id", "")) == "")
