extends GutTest

## Regression coverage for ludicrous-mode drop parity.
## Pre-fix the headless path gave EXP + gold but ZERO item drops: rare_item_found
## never fired, Gold Farm's inventory_items interrupt was dead, and bestiary
## defeat-credit silently no-opped because _resolve_headless_battle never set the
## monster_type meta the resolver reads. These tests pin the pure roll math
## (injectable RNG), the seam methods, and the GameLoop wiring (source-inspection,
## same technique as test_autogrind_stop_notifications).

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")

var _fake_db := {
	"test_slime": {
		"reward_multiplier": 1.0,
		"drop_table": [
			{"item": "potion", "chance": 0.5},
			{"item": "rare_gem", "chance": 0.05},
		],
	},
	"test_boss": {
		"reward_multiplier": 2.0,
		"drop_table": [
			{"item": "boss_relic", "chance": 0.25},
		],
	},
	"test_empty": {},
}


func _always() -> float:
	return 0.0


func _never() -> float:
	return 0.999


func test_roll_all_drops_when_rng_low() -> void:
	var out: Dictionary = ResolverScript._roll_drop_tables(
		["test_slime"], _fake_db, 1.0, Callable(self, "_always"))
	assert_eq(int(out["item_drops"].get("potion", 0)), 1, "potion should drop on a 0.0 roll")
	assert_eq(int(out["item_drops"].get("rare_gem", 0)), 1, "rare_gem should drop on a 0.0 roll")


func test_roll_nothing_when_rng_high() -> void:
	var out: Dictionary = ResolverScript._roll_drop_tables(
		["test_slime"], _fake_db, 1.0, Callable(self, "_never"))
	assert_eq(out["item_drops"].size(), 0, "0.999 roll should beat every chance in the table")
	assert_eq(out["rare_drops"].size(), 0, "no drops → no rare drops")


func test_rare_classification_uses_base_chance() -> void:
	# rare_gem (0.05 < 0.10) is rare; potion (0.5) is not — even though both rolled.
	var out: Dictionary = ResolverScript._roll_drop_tables(
		["test_slime"], _fake_db, 1.0, Callable(self, "_always"))
	assert_eq(out["rare_drops"].size(), 1, "exactly one sub-10%-chance drop in the table")
	assert_eq(str(out["rare_drops"][0]["item"]), "rare_gem",
		"rare classification keys off BASE chance, not the multiplied roll target")


func test_duplicate_enemy_types_stack_quantities() -> void:
	var out: Dictionary = ResolverScript._roll_drop_tables(
		["test_slime", "test_slime", "test_slime"], _fake_db, 1.0, Callable(self, "_always"))
	assert_eq(int(out["item_drops"].get("potion", 0)), 3,
		"three slimes each dropping a potion must merge to qty 3, not overwrite")


func test_unknown_and_tableless_types_are_skipped() -> void:
	var out: Dictionary = ResolverScript._roll_drop_tables(
		["nonexistent", "test_empty"], _fake_db, 1.0, Callable(self, "_always"))
	assert_eq(out["item_drops"].size(), 0,
		"unknown monster ids and records without drop_table must not crash or drop")


func test_drop_rate_multiplier_widens_roll_window() -> void:
	# roll 0.4: base potion chance 0.5 → 0.4 < 0.5 passes at mult 1.0,
	# but boss_relic 0.25 fails until reward_multiplier (2.0) doubles it to 0.5... still
	# 0.4 < 0.5 passes. Use a 0.3 roll against boss_relic: 0.25*1.0=0.25 fails, with
	# monster's own reward_multiplier 2.0 → 0.5 passes.
	var out: Dictionary = ResolverScript._roll_drop_tables(
		["test_boss"], _fake_db, 1.0, func() -> float: return 0.3)
	assert_eq(int(out["item_drops"].get("boss_relic", 0)), 1,
		"reward_multiplier 2.0 must widen 0.25 → 0.5 so a 0.3 roll passes — same rare-reward parity BattleManager tick 339 fixed live")
	var out_flat: Dictionary = ResolverScript._roll_drop_tables(
		["test_slime"], _fake_db, 1.0, func() -> float: return 0.6)
	assert_eq(int(out_flat["item_drops"].get("potion", 0)), 0,
		"0.6 roll vs 0.5 chance at mult 1.0 must fail — multiplier math shouldn't inflate unmultiplied rolls")


func test_resolver_results_include_drop_keys() -> void:
	# _build_results must always carry the keys, even on defeat, so GameLoop's
	# .get() defaults never mask a schema drift.
	var resolver = ResolverScript.new()
	var winner = Combatant.new()
	winner.initialize({"name": "W", "max_hp": 9999, "max_mp": 10, "attack": 500, "defense": 200, "magic": 10, "speed": 20})
	add_child_autofree(winner)
	var loser = Combatant.new()
	loser.initialize({"name": "L", "max_hp": 1, "max_mp": 0, "attack": 1, "defense": 0, "magic": 0, "speed": 1})
	add_child_autofree(loser)
	var result: Dictionary = resolver.resolve_battle([winner], [loser])
	assert_true(result.has("item_drops"), "results must always include item_drops")
	assert_true(result.has("rare_drops"), "results must always include rare_drops")


func test_notify_rare_drop_flips_interrupt_flag() -> void:
	var system = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(system)
	system._test_disable_persistence = true
	system._rare_drop_this_session = false
	system.notify_rare_drop("rare_gem", 0.05)
	assert_true(system._rare_drop_this_session,
		"notify_rare_drop must flip the same flag the rare_item_found interrupt condition reads")


func test_battle_manager_public_routing_wrapper_exists() -> void:
	assert_true(BattleManager.has_method("route_drop_to_equipment_pool"),
		"BattleManager must expose the public routing seam the headless path uses")
	assert_false(BattleManager.route_drop_to_equipment_pool("definitely_not_an_item_xyz"),
		"garbage ids must return false (caller falls back to add_item)")


func test_gameloop_sets_monster_type_meta_in_headless_path() -> void:
	# THE bestiary regression: _resolve_headless_battle built bare Combatants with
	# no monster_type meta, so the resolver's mark_defeated call silently no-opped
	# for every ludicrous battle. Pin the set_meta line.
	var src: String = load("res://src/GameLoop.gd").source_code
	var fn_start := src.find("func _resolve_headless_battle")
	assert_true(fn_start >= 0, "_resolve_headless_battle must exist")
	var fn_end := src.find("\nfunc ", fn_start + 20)
	if fn_end < 0:
		fn_end = src.length()
	var body := src.substr(fn_start, fn_end - fn_start)
	assert_true(body.contains('set_meta("monster_type"'),
		"headless Combatant build must set monster_type meta — without it bestiary credit AND drop lookup silently no-op for the whole ludicrous path")
	assert_true(body.contains("notify_rare_drop"),
		"headless path must notify rare drops so rare_item_found interrupts work in ludicrous mode")
	assert_true(body.contains("route_drop_to_equipment_pool"),
		"headless drops must route through the same equipment-vs-consumable split as live battles")


func test_gameloop_merges_drops_into_items_gained() -> void:
	var src: String = load("res://src/GameLoop.gd").source_code
	var fn_start := src.find("func _resolve_headless_battle")
	var fn_end := src.find("\nfunc ", fn_start + 20)
	if fn_end < 0:
		fn_end = src.length()
	var body := src.substr(fn_start, fn_end - fn_start)
	assert_true(body.contains("headless_item_drops"),
		"headless path must merge rolled drops into items_gained so total_items_gained tracks them")