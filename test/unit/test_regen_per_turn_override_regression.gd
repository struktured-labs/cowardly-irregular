extends GutTest

## tick 436: regenerate ability's authored regen_per_turn=40 now
## overrides the hardcoded 5%-max-hp regen tick.
##
## Pre-fix the regen-status tick in Combatant.update_buff_durations
## was hardcoded to max(1, int(max_hp * 0.05)) — 5 HP for a 100-max
## combatant. regenerate authored regen_per_turn=40 (8x higher)
## advertising "restoring HP each turn", but the field was never
## read.
##
## Implementation: BattleManager's "regen" support arm stores the
## authored regen_per_turn on target meta. Combatant's tick reads
## the meta (>0 → flat override, 0 → 5% fallback).

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _make(name_str: String, max_hp: int = 100) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({"name": name_str, "max_hp": max_hp, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


func test_battle_manager_arm_stores_override() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	# Find the "regen" arm specifically.
	var arm_idx: int = src.find("\"regen\":\n")
	if arm_idx < 0:
		arm_idx = src.find("\t\t\"regen\":")
	assert_gt(arm_idx, -1, "BattleManager must have a 'regen' arm")
	# Window around the arm.
	var window: String = src.substr(arm_idx, 1500)
	assert_true(window.contains("ability.get(\"regen_per_turn\", 0)"),
		"regen arm must read regen_per_turn from ability data")
	assert_true(window.contains("set_meta(\"_regen_per_turn\""),
		"regen arm must store the override on target meta")


func test_combatant_tick_reads_meta() -> void:
	var src := _read(COMBATANT_PATH)
	# Find the regen block in update_buff_durations.
	var idx: int = src.find("\"regen\" in status_effects and is_alive")
	assert_gt(idx, -1)
	var window: String = src.substr(idx, 800)
	assert_true(window.contains("get_meta(\"_regen_per_turn\""),
		"Combatant regen tick must read the override meta")
	# Fallback to 5% default when no override.
	assert_true(window.contains("max_hp * 0.05"),
		"5% max_hp default must remain as the fallback for non-override regens")


func test_runtime_override_used_when_set() -> void:
	var c: Combatant = _make("Hero", 100)
	c.current_hp = 10  # so the heal lands
	c.add_status("regen", 3)
	c.set_meta("_regen_per_turn", 40)
	c.update_buff_durations()
	# Expected: heal 40 → current_hp = 50.
	assert_eq(c.current_hp, 50,
		"regen with override=40 must heal exactly 40 — pre-fix was 5%% max_hp = 5")


func test_runtime_default_used_when_meta_absent() -> void:
	# Regression guard: regen without authored override still uses
	# the 5% default.
	var c: Combatant = _make("Hero", 100)
	c.current_hp = 10
	c.add_status("regen", 3)
	# Don't set _regen_per_turn meta.
	c.update_buff_durations()
	# Expected: 5% * 100 = 5 HP heal → current_hp = 15.
	assert_eq(c.current_hp, 15,
		"regen without override must heal 5%% max_hp (5 HP for 100-max combatant)")


func test_data_still_authors_regenerate_amount() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("regenerate"))
	assert_gt(int(data["regenerate"].get("regen_per_turn", 0)), 0,
		"regenerate must still author regen_per_turn > 0 (fix relies on this)")


func test_override_zero_falls_back_to_default() -> void:
	# A subsequent regen with no override resets the meta to 0; the
	# next tick reads 0 and uses the 5% default — no leak from a
	# previous override.
	var c: Combatant = _make("Hero", 100)
	c.current_hp = 10
	c.add_status("regen", 3)
	c.set_meta("_regen_per_turn", 0)  # explicit clear
	c.update_buff_durations()
	# Same as default: 5 HP → 15.
	assert_eq(c.current_hp, 15,
		"_regen_per_turn=0 must fall back to the 5% default (no override leak)")
