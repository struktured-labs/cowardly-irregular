extends GutTest

## The field menu said "Fighter / Fighter" in W1 (the party is called by class title); it says the job once, by battle's BattleUIManager.job_is_name.

var _saved_world = null


func before_each() -> void:
	_saved_world = GameState.current_world
	GameState.current_world = 1


func after_each() -> void:
	GameState.current_world = _saved_world


func _member(member_name: String, job_id: String) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = member_name
	c.job = JobSystem.get_job(job_id)
	c.job_level = 14
	autofree(c)
	return c


func _abilities_job_line(m: Combatant) -> String:
	var menu = load("res://src/ui/AbilitiesMenu.gd").new()
	menu.setup(m)
	add_child_autofree(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	for l in menu.find_children("*", "Label", true, false):
		if (l as Label).text.begins_with("Lv "):
			return (l as Label).text
	return "<no job line>"


func test_a_member_named_for_their_job_gets_a_blank_card_job_line() -> void:
	var m := _member(JobSystem.get_job_display_name("fighter"), "fighter")
	assert_true(BattleUIManager.job_is_name(m.combatant_name, m.job_display_name()), "CONTROL: in W1 the default name IS the job")
	assert_eq(OverworldMenu.card_job_text(m), "", "the card's name line already says it")


func test_a_renamed_member_still_shows_their_job() -> void:
	var m := _member("Mira", "fighter")
	assert_eq(OverworldMenu.card_job_text(m), m.job_display_name(), "a name that is not the job keeps the job line")
	assert_ne(OverworldMenu.card_job_text(m), "", "and it is not blank")


func test_the_abilities_panel_says_the_job_once() -> void:
	var same: String = await _abilities_job_line(_member(JobSystem.get_job_display_name("fighter"), "fighter"))
	assert_eq(same, "Lv 14", "a member named for their job reads the level alone")
	var renamed: String = await _abilities_job_line(_member("Mira", "fighter"))
	assert_eq(renamed, "Lv 14 %s" % JobSystem.get_job_display_name("fighter"), "CONTROL: a renamed member keeps the job")
