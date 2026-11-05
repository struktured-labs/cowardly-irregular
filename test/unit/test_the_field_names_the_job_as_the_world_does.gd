extends GutTest

## (battle d4d226a85's Combatant.job_display_name.) The field menu and the Abilities panel showed a member's job by its BASE name ("Cleric") while every other screen
## asks JobSystem.get_job_display_name, so from World 2 on they disagreed with the rest of the game ("School Nurse").

var _saved_world = null


func before_each() -> void:
	_saved_world = GameState.current_world


func after_each() -> void:
	GameState.current_world = _saved_world


## A job whose world-2 name differs from its base name, derived rather than assumed.
func _renamed_job_in_world_2() -> String:
	GameState.current_world = 2
	for id in ["cleric", "fighter", "mage", "rogue", "bard"]:
		if JobSystem.get_job_display_name(id) != str(JobSystem.get_job(id).get("name", id)):
			return id
	return ""


func _member(job_id: String) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = "Mira"
	c.job = JobSystem.get_job(job_id)
	autofree(c)
	return c


func test_the_shared_helper_reads_this_worlds_name() -> void:
	var id := _renamed_job_in_world_2()
	assert_ne(id, "", "CONTROL: some starter job must be renamed in world 2, or this file proves nothing")
	if id == "":
		return
	var m := _member(id)
	assert_eq(m.job_display_name(), JobSystem.get_job_display_name(id), "the field reads the world's name")
	assert_ne(m.job_display_name(), str(m.job.get("name")), "and not the base job name")
	GameState.current_world = 1
	assert_eq(m.job_display_name(), JobSystem.get_job_display_name(id), "W1 reads the same helper (its base name)")


func test_the_abilities_panel_shows_this_worlds_name() -> void:
	var id := _renamed_job_in_world_2()
	if id == "":
		assert_ne(id, "", "CONTROL: a renamed job must exist")
		return
	var menu = load("res://src/ui/AbilitiesMenu.gd").new()
	menu.setup(_member(id))
	add_child_autofree(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	var want := JobSystem.get_job_display_name(id)
	var found := false
	for l in menu.find_children("*", "Label", true, false):
		if (l as Label).text.ends_with(want) and (l as Label).text.begins_with("Lv "):
			found = true
	assert_true(found, "the Abilities panel's job line must read '%s' in world 2" % want)


## Both field-menu job labels (the party row and its in-place refresh) go through the shared helper.
func test_both_field_menu_job_labels_use_the_helper() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/OverworldMenu.gd")
	assert_eq(src.count("text = member.job_display_name()"), 2, "the party row and its refresh must both ask Combatant.job_display_name")
	assert_eq(src.count('job.get("name", "Fighter") if member.job'), 0, "no field job label reads the base name directly")
