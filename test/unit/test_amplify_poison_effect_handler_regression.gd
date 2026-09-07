extends GutTest

## tick 380: BattleManager dispatch + Combatant poison-tick now
## handle amplify_poison from the fester ability.
##
## Pre-fix data/abilities.json fester authored:
##   {effect: "amplify_poison", multiplier: 2.0}
##
## Effect fell through to `_:` push_warning default in
## _execute_support_ability — the cast consumed MP+AP, played the
## animation, and produced ZERO mechanical effect. Player got nothing
## for the "Worsen existing poison effects" line in the description.
##
## Post-fix:
##   1. BattleManager applies "festered" status to targets.
##   2. Combatant.update_buff_durations poison block reads
##      has_status("festered") and doubles poison tick damage.
##
## Festered alone does nothing — it amplifies poison ticks only when
## both are active. A fester-then-poison combo also amplifies (the
## status stays in status_effects independently), rewarding strategic
## ordering.
##
## Closes the third and last of the authored-but-unhandled effect
## trilogy (tick 378 magic_defense_down, tick 379 static).

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


# ── Source pin: amplify_poison arm exists ───────────────────────────

func test_amplify_poison_arm_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("\"amplify_poison\":"),
		"BattleManager support-effect dispatch must have an amplify_poison arm")
	assert_true(src.contains("add_status(\"festered\""),
		"amplify_poison arm must apply the 'festered' status")


# ── Source pin: Combatant poison block reads festered ───────────────

func test_combatant_poison_block_reads_festered() -> void:
	var src := _read(COMBATANT_PATH)
	# The poison block must check has_status("festered") (or in form).
	assert_true(src.contains("\"festered\" in status_effects"),
		"Combatant.update_buff_durations poison block must check for festered")
	# Doubling must be visible.
	assert_true(src.contains("poison_damage *= 2"),
		"poison block must double damage when festered is present")


# ── Source pin: data/abilities.json still authors amplify_poison ────

func test_fester_still_authors_amplify_poison() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	assert_eq(typeof(parsed), TYPE_DICTIONARY)
	var data: Dictionary = parsed
	assert_true(data.has("fester"), "fester ability must exist in abilities.json")
	assert_eq(str(data["fester"].get("effect", "")), "amplify_poison",
		"fester must still author effect=amplify_poison")


# ── Behavioral: dispatch applies festered status ────────────────────

func test_dispatch_applies_festered_status() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	var js = Engine.get_main_loop().root.get_node_or_null("JobSystem")
	if bm == null or js == null:
		pending("BattleManager + JobSystem autoloads required")
		return
	if not js.abilities.has("fester"):
		pending("fester ability data required")
		return

	var target: Combatant = _make("Goblin")
	var ability: Dictionary = js.abilities["fester"].duplicate(true)
	ability["success_rate"] = 1.0
	var typed_targets: Array[Combatant] = [target]
	bm._execute_support_ability(null, ability, typed_targets)

	assert_true("festered" in target.status_effects,
		"festered status must be present on target after fester — pre-fix the effect silently fizzled")


# ── Behavioral: festered + poison doubles tick damage ───────────────

func test_festered_doubles_poison_damage() -> void:
	var c: Combatant = _make("Hero")
	c.current_hp = 100
	# Baseline: poison alone deals 5% max_hp = 5 damage.
	c.add_status("poison", 5)
	c.update_buff_durations()
	var poison_only_damage: int = 100 - c.current_hp

	# Reset HP, add festered.
	c.current_hp = 100
	c.add_status("festered", 3)
	c.update_buff_durations()
	var festered_damage: int = 100 - c.current_hp

	assert_gt(festered_damage, poison_only_damage,
		"festered must INCREASE poison damage on each tick")
	# Expected 2x: poison_only_damage * 2 = festered_damage (within rounding).
	# poison alone was 5, festered 10.
	assert_almost_eq(float(festered_damage), float(poison_only_damage) * 2.0, 1.0,
		"festered must DOUBLE poison damage (~%dx, got %d vs %d)" % [2, festered_damage, poison_only_damage])


# ── Behavioral: festered alone does nothing ─────────────────────────

func test_festered_alone_no_damage() -> void:
	# Festered without poison must be inert — it amplifies, doesn't deal.
	var c: Combatant = _make("Hero")
	c.current_hp = 100
	c.status_effects.clear()
	c.add_status("festered", 3)
	c.update_buff_durations()
	assert_eq(c.current_hp, 100,
		"festered alone (no poison) must NOT deal damage — it only amplifies")


# ── Behavioral: pre-poisoned target + fester combo works ────────────

func test_fester_then_no_op_when_no_poison_but_amplifies_later() -> void:
	# The dispatch applies festered to ALL targets (including
	# non-poisoned ones). If poison is applied afterward, the festered
	# status persists and amplifies — rewarding strategic ordering.
	var c: Combatant = _make("Hero")
	c.current_hp = 100
	c.status_effects.clear()
	c.add_status("festered", 5)
	# Now apply poison.
	c.add_status("poison", 3)
	# A single tick should deal doubled damage.
	c.update_buff_durations()
	var damage: int = 100 - c.current_hp
	# Expected ~10 (poison 5 doubled).
	assert_true(damage >= 9 and damage <= 11,
		"fester-then-poison combo must deal ~10 doubled poison damage (got %d)" % damage)
