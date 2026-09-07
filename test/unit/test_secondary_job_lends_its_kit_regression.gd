extends GutTest

## struktured 2026-09-06: "job system needs to work: 2ndary job does nothing apparently?"
## It didn't — assign_secondary_job's own docstring said "visual accents + minor stat boost", no
## abilities. Now the secondary job LENDS ITS BASE KIT: knows_ability sees it, and the battle
## command menu + the autobattle editor enumerate from Combatant.get_known_abilities so the three
## surfaces can never disagree.


func _dual() -> Combatant:
	var c := Combatant.new()
	c.combatant_name = "Dual"
	c.job = {"id": "fighter_probe", "abilities": ["power_strike"], "abilities_at_level": {"3": ["guard_break"]}}
	c.secondary_job = {"id": "mage_probe", "abilities": ["fire", "blizzard"]}
	c.secondary_job_id = "mage_probe"
	c.job_level = 1
	c.current_mp = 100
	return c


func test_secondary_kit_is_known() -> void:
	var c := _dual()
	assert_true(c.knows_ability("fire"), "the secondary job's kit must count as known")
	assert_true(c.knows_ability("power_strike"), "CONTROL: primary kit still known")
	assert_false(c.knows_ability("cure"), "CONTROL: an ability in neither job stays unknown")
	c.free()


func test_known_list_orders_primary_then_secondary_and_dedupes() -> void:
	var c := _dual()
	c.learn_ability("fire")  # also learned — must appear ONCE
	var known: Array[String] = c.get_known_abilities()
	assert_eq(known, ["power_strike", "fire", "blizzard"] as Array[String],
		"primary kit first, then learned/secondary without duplicates; level-3 guard_break absent at level 1")
	c.job_level = 3
	assert_true(c.get_known_abilities().has("guard_break"), "level unlock joins the list once reached")
	c.free()


func test_no_secondary_job_changes_nothing() -> void:
	var c := _dual()
	c.secondary_job = null
	c.secondary_job_id = ""
	assert_false(c.knows_ability("fire"), "without a secondary job the mage kit is NOT lent")
	assert_eq(c.get_known_abilities(), ["power_strike"] as Array[String])
	c.free()


func test_battle_menu_and_editor_enumerate_from_the_one_list() -> void:
	var menu := FileAccess.get_file_as_string("res://src/battle/BattleCommandMenu.gd")
	assert_true(menu.contains("combatant.get_known_abilities()"), "the command menu must build Ability from get_known_abilities")
	assert_false(menu.contains('var job_abilities = combatant.job.get("abilities", [])'),
		"and must not re-derive the list from the primary kit alone (that was 'secondary does nothing')")
	var editor := FileAccess.get_file_as_string("res://src/ui/autobattle/AutobattleGridEditor.gd")
	var i: int = editor.find("func _get_character_abilities(")
	assert_true(editor.substr(i, 500).contains("get_known_abilities()"), "the autobattle ability picker must use the same list")
