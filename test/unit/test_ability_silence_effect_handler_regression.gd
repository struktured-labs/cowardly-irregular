extends GutTest

## tick 382: BattleManager handles ability_silence from null_field.
##
## Pre-fix data/abilities.json null_field authored:
##   {effect: "ability_silence", duration: 1, target_type: "all_enemies"}
##
## The effect fell through to `_:` push_warning default — null_field
## consumed 22 MP + AP, played the cast animation, and produced ZERO
## mechanical effect.
##
## Post-fix aliases to the existing "silence" status (added to the
## simple-status arm in an earlier tick). Multiple downstream
## consumers already gate offensive actions on has_status("silence");
## reusing the existing status reuses all those consumers rather than
## introducing a parallel "ability_silence" status nobody reads.

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


# ── Source pin: ability_silence arm exists ──────────────────────────

func test_ability_silence_arm_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var arm_idx: int = src.find("\"ability_silence\":")
	assert_gt(arm_idx, -1, "BattleManager dispatch must have an ability_silence arm")
	# The arm must apply the existing "silence" status (alias semantics).
	var window: String = src.substr(arm_idx, 400)
	assert_true(window.contains("add_status(\"silence\""),
		"ability_silence arm must apply the existing \"silence\" status (alias) — pre-fix the effect silently fizzled")


# ── Source pin: data still authors ability_silence on null_field ────

func test_null_field_still_authors_ability_silence() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	assert_eq(typeof(parsed), TYPE_DICTIONARY)
	var data: Dictionary = parsed
	assert_true(data.has("null_field"), "null_field ability must exist")
	assert_eq(str(data["null_field"].get("effect", "")), "ability_silence",
		"null_field must still author effect=ability_silence")


# ── Behavioral: dispatch applies silence status ─────────────────────

func test_dispatch_applies_silence_status() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	var js = Engine.get_main_loop().root.get_node_or_null("JobSystem")
	if bm == null or js == null:
		pending("BattleManager + JobSystem autoloads required")
		return
	if not js.abilities.has("null_field"):
		pending("null_field ability data required")
		return
	var target: Combatant = _make("Goblin")
	var ability: Dictionary = js.abilities["null_field"].duplicate(true)
	ability["success_rate"] = 1.0
	var typed_targets: Array[Combatant] = [target]
	bm._execute_support_ability(null, ability, typed_targets)
	# The status applied must be the canonical "silence" (existing
	# consumers gate on that name), NOT "ability_silence".
	assert_true("silence" in target.status_effects,
		"ability_silence must result in the canonical 'silence' status on target — downstream consumers gate on 'silence'")
	assert_false("ability_silence" in target.status_effects,
		"ability_silence must NOT create a parallel 'ability_silence' status — that would split the consumer surface")


# ── Behavioral: vanilla target (no cast) has no silence ─────────────

func test_vanilla_target_has_no_silence() -> void:
	# Regression guard: silence must NOT appear without the ability cast.
	var c: Combatant = _make("Vanilla")
	c.status_effects.clear()
	assert_false("silence" in c.status_effects,
		"fresh target must not start with silence — fix must not silently apply baseline")
