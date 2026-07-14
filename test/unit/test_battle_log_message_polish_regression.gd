extends GutTest

## Smoke-log finds 2026-07-03, goblin battle leg:
## 1. "Goblin summons a Imp!" — article never adapted to vowels.
## 2. "Goblin has been defeated!" printed BEFORE "→ Goblin takes 109
##    lightning damage!" — died fires inside take_damage, so the kill
##    was announced before the blow that caused it. Both announcement
##    sites now defer one frame; the death LOGIC stays synchronous.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")


func _summon_message(monster_type: String) -> String:
	var bm = BattleManagerScript.new()
	add_child_autofree(bm)
	var caster = Combatant.new()
	caster.combatant_name = "Goblin"
	autofree(caster)
	var messages: Array = []
	bm.battle_log_message.connect(func(msg): messages.append(msg))
	bm._execute_summon(caster, monster_type)
	return "".join(messages)


func test_summon_article_an_before_vowel() -> void:
	assert_string_contains(_summon_message("imp"), "an Imp",
		"vowel-initial monsters must get 'an', not 'a Imp'")


func test_summon_article_a_before_consonant() -> void:
	assert_string_contains(_summon_message("goblin"), "a Goblin")


func test_defeat_announcements_are_deferred() -> void:
	var scene_src: String = FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_true(scene_src.contains("call_deferred(\"log_message\", \"[color=yellow]%s has been defeated!"),
		"BattleScene defeat line must defer or it precedes the killing blow's damage message")
	var mgr_src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_true(mgr_src.contains("call_deferred(\"_print_defeat_line\""),
		"BattleManager defeat print must defer for the same ordering reason")
