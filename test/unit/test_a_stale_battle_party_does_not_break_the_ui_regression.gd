extends GutTest

## Regression: a BattleScene freed before end_battle left BattleManager.player_party holding freed Combatants (load a save and GameLoop frees the old party too).
## The next battle's UI picked that list because size() > 0 and aborted in BattleUIManager (_ensure_party_status_boxes:218, _update_auto_toggle_button:130).

var _saved_party: Array = []


func before_each() -> void:
	_saved_party = BattleManager.player_party.duplicate()


func after_each() -> void:
	BattleManager.player_party.assign(_saved_party)


## Stale the way the game does it: stored while live, freed afterwards (a typed array refuses an already-freed object).
func _stale_party() -> void:
	var c := Combatant.new()
	c.combatant_name = "Ghost"
	var mine: Array[Combatant] = [c]
	BattleManager.player_party = mine
	c.free()


func _live_combatant(n: String) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = n
	autofree(c)
	return c


func test_control_a_live_battle_party_is_preferred_over_the_scene() -> void:
	var a := _live_combatant("Ari")
	var b := _live_combatant("Bo")
	var mine: Array[Combatant] = [a]
	BattleManager.player_party = mine
	assert_eq(BattleManager.live_party_or([b]), [a], "CONTROL: while a battle owns a live party, the UI draws that party")


func test_a_stale_freed_party_falls_back_to_the_scene() -> void:
	_stale_party()
	var b := _live_combatant("Bo")
	var drawn: Array = BattleManager.live_party_or([b])
	assert_eq(drawn, [b], "a party of freed Combatants must not be drawn; the scene's own party is")
	assert_eq(BattleManager.player_party.size(), 1, "SCOPE: the stale list is non-empty, which is what the old size() > 0 test trusted")


func test_a_freed_scene_member_is_skipped_too() -> void:
	BattleManager.player_party.clear()
	var ghost := Combatant.new()
	var b := _live_combatant("Bo")
	var fallback: Array = [ghost, b]
	ghost.free()
	assert_eq(BattleManager.live_party_or(fallback), [b], "the fallback is filtered the same way")


func test_no_battle_ui_site_still_trusts_a_bare_size_check() -> void:
	var offenders: Array[String] = []
	for f in ["res://src/battle/BattleUIManager.gd", "res://src/battle/BattleScene.gd"]:
		var src := FileAccess.get_file_as_string(f)
		assert_gt(src.length(), 1000, "SCOPE: %s read back empty" % f)
		if src.contains("BattleManager.player_party if BattleManager.player_party.size() > 0"):
			offenders.append(f)
	assert_eq(offenders, [] as Array[String], "these still pick player_party by size alone, so a stale freed list wins: %s" % [offenders])


func test_a_battle_ui_redrawn_on_a_stale_party_draws_its_status_boxes() -> void:
	var scene = load("res://src/battle/BattleScene.tscn").instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	## Stale it AFTER the scene's own battle started, or start_battle overwrites the list and the UI self-heals.
	_stale_party()
	var ui = scene._ui_manager
	assert_not_null(ui, "SCOPE: the scene built its UI manager")
	ui.update_character_status()
	assert_gt(scene.party_members.size(), 0, "SCOPE: the scene has a party to draw")
	var live: int = 0
	for box in ui._party_status_boxes:
		if is_instance_valid(box):
			live += 1
	assert_eq(live, scene.party_members.size(), "the status panel must draw one box per live party member, not abort on a freed one")
