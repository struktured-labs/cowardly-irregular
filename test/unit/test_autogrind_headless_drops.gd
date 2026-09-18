extends GutTest

## Regression coverage for ludicrous-mode drop parity.
## Pre-fix the headless path gave EXP + gold but ZERO item drops: rare_item_found
## never fired, Gold Farm's inventory_items interrupt was dead, and bestiary
## defeat-credit silently no-opped because _resolve_headless_battle never set the
## monster_type meta the resolver reads. These tests pin the pure roll math
## (injectable RNG), the seam methods, and the GameLoop wiring (source-inspection,
## same technique as test_autogrind_stop_notifications).

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")
const GdSource = preload("res://test/unit/helpers/gd_source.gd")

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


## ⛔ `result["enemy_party"]` HANDS OUT FREED OBJECTS, and is safe only because nothing reads it.
## GameLoop._resolve_headless_battle does `for e in enemies: e.free()` three lines after
## resolve_battle returns, so the Combatants in that key are invalid by the time any consumer could
## reach them. Measured 2026-09-17: zero readers in src/ and test/ — it is the one result key of
## twelve with no consumer at all, and the others average four.
##
## ⚠️ NOT A BUG TODAY, WHICH IS WHY IT IS A TRIGGER RATHER THAN A FIX. @cowir-music's distinction:
## a hazard is a defect only if nothing downstream compensates, and here nothing downstream EXISTS.
## The first lane to read this key gets freed instances, so the arm fires the moment one appears —
## which is the moment the reason needs saying, not now.
func test_nothing_reads_the_result_key_that_holds_freed_enemies() -> void:
	var readers: Array = []
	var stack: Array = ["res://src", "res://test/unit"]
	var scanned: int = 0
	while not stack.is_empty():
		var d: String = str(stack.pop_back())
		for sub in DirAccess.get_directories_at(d):
			stack.append("%s/%s" % [d, sub])
		for f in DirAccess.get_files_at(d):
			if not str(f).ends_with(".gd"):
				continue
			var path: String = "%s/%s" % [d, f]
			if path.ends_with("HeadlessBattleResolver.gd") or path.ends_with(get_script().resource_path.get_file()):
				continue   ## the producer, and this file's own prose about the key
			scanned += 1
			var code: String = GdSource.code_of(path)
			## The RESULT key, not BattleManager.enemy_party — that is a member var on the live
			## engine and appears ~12 times in BattleScene alone. Only a dict read counts.
			if code.contains('get("enemy_party"') or code.contains('["enemy_party"]'):
				readers.append(path.get_file())
	assert_gt(scanned, 100,
		"CONTROL: only %d files scanned — a walk that finds nothing reports 'no readers' for free" % scanned)
	assert_eq(readers, [],
		("something now reads result[\"enemy_party\"], whose Combatants GameLoop frees three lines " +
		"after resolve_battle returns — it will get freed instances: %s") % str(readers))


## ⛔ THE GRIND SILENTLY DISCARDED DUPLICATE EQUIPMENT DROPS (@cowir-adhoc, 2026-09-17).
## Live calls _deliver_item ONCE PER SUCCESSFUL ROLL, so three rolls put three pieces in the pool.
## The grind AGGREGATES to {item_id: qty} first — which is exactly what makes CONSUMABLES correct,
## because add_item(id, qty) honours the count — and then called the equipment router ONCE:
##
##     if not BattleManager.route_drop_to_equipment_pool(item_id):   # qty never read
##         party[0].add_item(item_id, qty)
##
## `_route_drop_to_equipment_pool` appends exactly ONE id per call, so qty-1 pieces vanished.
## ⚠️ NOT EXOTIC: `_generate_scaled_enemies` draws WITH REPLACEMENT and `_roll_drop_tables` rolls
## once per enemy, so the same monster appearing twice is the normal case.
##
## 📌 COMMENTS STRIPPED. The fix's own comment names this defect, and a sibling arm in this lane
## scored green on prose satisfying a source-presence assert. The claim is the CODE.
func test_every_copy_of_an_equipment_drop_reaches_the_pool() -> void:
	var code: String = GdSource.code_of("res://src/GameLoop.gd")
	assert_ne(code, "", "CONTROL: GameLoop source must survive the comment strip")
	var at := code.find("func _resolve_headless_battle")
	assert_gt(at, -1, "_resolve_headless_battle must exist")
	var end := code.find("\nfunc ", at + 20)
	var body := code.substr(at, (end - at) if end > 0 else -1)

	## CONTROL: we found the delivery block, not merely the function. Without this the arms below
	## are about whatever text happened to be in range.
	assert_true(body.contains("add_item(item_id, qty)"),
		"CONTROL: the consumable fallback must be in the extracted body, or this arm read the wrong range")

	## ⛔ THIS PAIR COUNTED SITES AND PINNED MY ARITHMETIC, AND WAS WRONG IN BOTH DIRECTIONS.
	## It was `count("route_drop_to_equipment_pool") > 1` plus `contains("qty - 1")`. A correct
	## refactor to `for _i in range(qty): route(item_id)` is ONE site with no "qty - 1" and would
	## have RED both arms; a duplicated call with qty ignored is two sites and would have PASSED.
	## @cowir-controller's shape from the nav-sound ratchet: the comment enumerated PATHS and the
	## assert counted SITES, and they agreed only because each path carried its own copy.
	##
	## The CLAIM is that the equipment branch iterates the rolled quantity. Assert that relationship.
	## ⛔ ANCHOR ON THE DELIVERY BLOCK, NOT ON THE ROUTER CALL. Anchoring at the router excludes any
	## loop that PRECEDES it — which is the shape a correct refactor takes — so the arm red on the
	## very refactor it exists to permit. Caught by the must-stay-green mutation, not by reading.
	var eq_at: int = body.find("var qty")
	assert_gt(eq_at, -1, "the delivery block must still derive a per-id quantity")
	var stop_at: int = body.find("add_item(item_id, qty)", eq_at)
	assert_gt(stop_at, eq_at, "CONTROL: the consumable fallback must follow the equipment branch, or the slice is inverted")
	var eq_branch: String = body.substr(eq_at, stop_at - eq_at)
	assert_gt(eq_branch.length(), 20,
		"CONTROL: the equipment branch must be locatable between the quantity and the consumable fallback")

	var loops := RegEx.create_from_string("for\\s+\\w+\\s+in\\s+[^\\n]*qty").search(eq_branch) != null
	assert_true(loops,
		("the equipment branch does not iterate the rolled quantity. The router appends ONE id per " +
		"call, so a stack of qty leaves qty-1 pieces of gear on the floor — live delivers one call " +
		"per successful roll and the grind's aggregation has to be undone for equipment."))
	assert_true(eq_branch.count("route_drop_to_equipment_pool") >= 1,
		"CONTROL: a loop bounded by qty means nothing if the router is not inside the branch it bounds")


func test_gameloop_merges_drops_into_items_gained() -> void:
	var src: String = load("res://src/GameLoop.gd").source_code
	var fn_start := src.find("func _resolve_headless_battle")
	var fn_end := src.find("\nfunc ", fn_start + 20)
	if fn_end < 0:
		fn_end = src.length()
	var body := src.substr(fn_start, fn_end - fn_start)
	assert_true(body.contains("headless_item_drops"),
		"headless path must merge rolled drops into items_gained so total_items_gained tracks them")