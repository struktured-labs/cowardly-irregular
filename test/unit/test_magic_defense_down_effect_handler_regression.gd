extends GutTest

## tick 378: BattleManager._apply_support_effect handles the
## magic_defense_down effect from soul_wail.
##
## Pre-fix data/abilities.json soul_wail authored:
##   {effect: "magic_defense_down", stat_modifier: 0.7, duration: 2}
##
## The support-effect dispatch in BattleManager had arms for many
## status names but NOT magic_defense_down. The ability fell through
## to the `_:` push_warning default — the cast consumed MP and AP,
## ran the cast animation, and produced ZERO mechanical effect.
## Silent design failure of the same class as ticks 350-356.
##
## Post-fix routes magic_defense_down through the existing defense
## debuff arm with a distinct "Soul Sap" effect label (so the UI
## source-of-debuff stays legible — coexists cleanly with the regular
## "Armor Break" from defense_down). Both reduce get_buffed_stat's
## defense stat the same way; take_damage uses defense for both
## physical and magical attacks (magic halves it).

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: magic_defense_down arm exists ───────────────────────

func test_magic_defense_down_arm_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("\"magic_defense_down\":"),
		"BattleManager support-effect dispatch must have a magic_defense_down arm")
	# Pin the distinct label so UI legibility is preserved.
	assert_true(src.contains("\"Soul Sap\""),
		"magic_defense_down arm must apply the distinct 'Soul Sap' debuff label (not collide with Armor Break)")


# ── Source pin: arm uses defense stat (the right mechanical fit) ────

func test_magic_defense_down_uses_defense_stat() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	# Slice from the magic_defense_down arm to the next case label.
	var arm_idx: int = src.find("\"magic_defense_down\":")
	assert_gt(arm_idx, -1)
	var window: String = src.substr(arm_idx, 400)
	assert_true(window.contains("add_debuff(\"Soul Sap\", \"defense\""),
		"magic_defense_down must add_debuff on the 'defense' stat (take_damage uses defense for both physical + magical, halved in the magical case)")


# ── Source pin: data/abilities.json still authors soul_wail with this effect

func test_soul_wail_still_authors_magic_defense_down() -> void:
	# Sanity: a future rebalance that drops the effect from soul_wail
	# should also drop the handler arm. Pin both ways.
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	assert_false(raw.is_empty(), "abilities.json must be readable")
	var parsed: Variant = JSON.parse_string(raw)
	assert_eq(typeof(parsed), TYPE_DICTIONARY, "abilities.json root must be a Dictionary")
	var data: Dictionary = parsed
	assert_true(data.has("soul_wail"), "soul_wail must still exist in abilities.json")
	assert_eq(str(data["soul_wail"].get("effect", "")), "magic_defense_down",
		"soul_wail must still author effect=magic_defense_down — drop this test if intentionally rebalanced")


# ── Behavioral: applying soul_wail to a target produces the debuff ──

func test_magic_defense_down_applies_debuff() -> void:
	# Exercise the BattleManager autoload directly.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var js = Engine.get_main_loop().root.get_node_or_null("JobSystem")
	if js == null or not js.abilities.has("soul_wail"):
		pending("JobSystem autoload + soul_wail ability required")
		return

	var c_script: GDScript = load(COMBATANT_PATH)
	var target: Combatant = c_script.new()
	target.initialize({
		"name": "Goblin", "max_hp": 100, "max_mp": 0,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10,
	})
	add_child_autofree(target)

	# Apply the support effect directly (skip MP/AP cost path).
	# Force success_rate to 1.0 for determinism (soul_wail defaults to
	# 1.0 but pin explicitly).
	var ability: Dictionary = js.abilities["soul_wail"].duplicate(true)
	ability["success_rate"] = 1.0
	var typed_targets: Array[Combatant] = [target]
	if bm.has_method("_execute_support_ability"):
		bm._execute_support_ability(null, ability, typed_targets)
	else:
		pending("_execute_support_ability helper missing — dispatch path moved?")
		return

	# Pre-fix this would have fallen through to push_warning with no
	# debuff applied. Post-fix the Soul Sap debuff should be present.
	var has_debuff: bool = false
	if "active_debuffs" in target:
		for d in target.active_debuffs:
			if d.get("effect", "") == "Soul Sap":
				has_debuff = true
				break
	assert_true(has_debuff,
		"Soul Sap debuff must be present on the target after soul_wail with success_rate=1.0 — pre-fix the magic_defense_down effect silently fizzled")
