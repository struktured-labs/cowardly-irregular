extends GutTest

## tick 379: BattleManager dispatch + Combatant DOT tick now handle
## the `static` effect from static_field.
##
## Pre-fix data/abilities.json static_field authored:
##   {effect: "static", duration: 3, damage_multiplier: 1.0}
##
## Two gaps closed:
##
## 1) BattleManager._execute_support_ability simple-status arm did
##    NOT list "static" — fell through to the `_:` push_warning
##    default. Status never applied.
##
## 2) Combatant.update_buff_durations had no "static" block — even
##    if the status WAS applied (e.g. by hand-edited script), the DOT
##    tick would never fire because no consumer ticks "static" damage.
##
## Post-fix routes through the simple-status arm and adds a 4%
## max_hp-per-turn lightning DOT to update_buff_durations (lighter
## than burn's 8% and poison's 5% — static is persistent zaps, not
## a sear). Lethal-tick guard ordering mirrors poison/burn so a
## static-kill grays the sprite cleanly.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: BattleManager dispatch lists "static" ───────────────

func test_battle_manager_dispatch_lists_static() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	# The simple-status arm must include "static". Pin the literal
	# pattern that proves it's in the case list.
	assert_true(src.contains("\"burning\", \"static\", \"confuse\""),
		"BattleManager simple-status arm must list \"static\" — pre-fix it fell through to push_warning")


# ── Source pin: Combatant DOT tick has static block ─────────────────

func test_combatant_dot_tick_has_static_block() -> void:
	var src := _read(COMBATANT_PATH)
	# update_buff_durations must include a `"static" in status_effects` block.
	assert_true(src.contains("\"static\" in status_effects"),
		"Combatant.update_buff_durations must include a static-DOT block")
	# Lethal-tick guard parity with poison/burn.
	assert_true(src.contains("status_tick_damage.emit(static_damage, \"static\")"),
		"static DOT block must emit status_tick_damage so BattleScene spawns the popup")


# ── Source pin: data/abilities.json still authors static effect ─────

func test_static_field_still_authors_static_effect() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	assert_false(raw.is_empty(), "abilities.json must be readable")
	var parsed: Variant = JSON.parse_string(raw)
	assert_eq(typeof(parsed), TYPE_DICTIONARY, "abilities.json root must be Dictionary")
	var data: Dictionary = parsed
	assert_true(data.has("static_field"), "static_field must exist")
	assert_eq(str(data["static_field"].get("effect", "")), "static",
		"static_field must still author effect=static — drop this test if intentionally rebalanced")


# ── Behavioral: applying static_field via dispatch adds the status ──

func test_dispatch_applies_static_status() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	var js = Engine.get_main_loop().root.get_node_or_null("JobSystem")
	if bm == null or js == null:
		pending("BattleManager + JobSystem autoloads required")
		return
	if not js.abilities.has("static_field"):
		pending("static_field ability data required")
		return

	var c_script: GDScript = load(COMBATANT_PATH)
	var target: Combatant = c_script.new()
	target.initialize({
		"name": "Goblin", "max_hp": 100, "max_mp": 0,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10,
	})
	add_child_autofree(target)

	var ability: Dictionary = js.abilities["static_field"].duplicate(true)
	ability["success_rate"] = 1.0
	var typed_targets: Array[Combatant] = [target]
	bm._execute_support_ability(null, ability, typed_targets)

	assert_true("static" in target.status_effects,
		"static status must be present on the target after static_field — pre-fix the effect silently fizzled")


# ── Behavioral: DOT tick deals damage ───────────────────────────────

func test_static_dot_tick_deals_damage() -> void:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({
		"name": "Goblin", "max_hp": 100, "max_mp": 0,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10,
	})
	add_child_autofree(c)
	c.current_hp = 100
	c.add_status("static", 3)
	var hp_before: int = c.current_hp
	c.update_buff_durations()
	assert_lt(c.current_hp, hp_before,
		"static DOT must reduce current_hp on each update_buff_durations tick")
	# Expected: 4% of 100 = 4 HP. Allow ±1 for rounding.
	var damage: int = hp_before - c.current_hp
	assert_true(damage >= 3 and damage <= 5,
		"static DOT must deal ~4%% max_hp (3-5 HP on 100-max target) — got %d" % damage)


# ── Behavioral: no static = no DOT (regression guard) ───────────────

func test_no_static_no_dot_tick() -> void:
	# Regression guard: don't silently inflict DOT on combatants that
	# don't have the status.
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({
		"name": "Vanilla", "max_hp": 100, "max_mp": 0,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10,
	})
	add_child_autofree(c)
	c.current_hp = 100
	c.status_effects.clear()  # explicitly no statuses
	c.update_buff_durations()
	assert_eq(c.current_hp, 100,
		"target without static status must NOT take DOT damage on tick")
