extends GutTest

## tick 388: ability_weaken (deprecate ability) applies a combined
## attack + magic debuff. Pre-fix the effect fell through to
## push_warning — 16 MP wasted.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _make(name_str: String) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({
		"name": name_str, "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10,
	})
	add_child_autofree(c)
	return c


func test_arm_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var arm_idx: int = src.find("\"ability_weaken\":")
	assert_gt(arm_idx, -1, "BattleManager dispatch must have an ability_weaken arm")
	var window: String = src.substr(arm_idx, 800)
	assert_true(window.contains("Deprecated (Atk)"),
		"ability_weaken must apply an attack debuff with the 'Deprecated (Atk)' label")
	assert_true(window.contains("Deprecated (Mag)"),
		"ability_weaken must apply a magic debuff with the 'Deprecated (Mag)' label")


func test_data_authors_ability_weaken() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	assert_eq(typeof(parsed), TYPE_DICTIONARY)
	var data: Dictionary = parsed
	assert_true(data.has("deprecate"))
	assert_eq(str(data["deprecate"].get("effect", "")), "ability_weaken")


func test_dispatch_applies_both_debuffs() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	var js = Engine.get_main_loop().root.get_node_or_null("JobSystem")
	if bm == null or js == null:
		pending("BattleManager + JobSystem autoloads required")
		return
	if not js.abilities.has("deprecate"):
		pending("deprecate ability required")
		return
	var target: Combatant = _make("Boss")
	var ability: Dictionary = js.abilities["deprecate"].duplicate(true)
	ability["success_rate"] = 1.0
	var typed_targets: Array[Combatant] = [target]
	bm._execute_support_ability(null, ability, typed_targets)
	# Both debuffs should be present.
	var atk_found: bool = false
	var mag_found: bool = false
	for d in target.active_debuffs:
		var e: String = str(d.get("effect", ""))
		if e == "Deprecated (Atk)":
			atk_found = true
		elif e == "Deprecated (Mag)":
			mag_found = true
	assert_true(atk_found,
		"Deprecated (Atk) debuff must be present after deprecate cast")
	assert_true(mag_found,
		"Deprecated (Mag) debuff must be present after deprecate cast")
