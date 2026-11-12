extends GutTest

## .791 gate, 2026-11-11: a L1 party's grind at the first village drew a Viper (L6) and a Rat Guard (L7). The grind unioned every
## zone pool under the region's name (W1 overworld: 18 species, L1-9); it now draws the zone the party stands in, as live play does.

const ControllerScript := preload("res://src/autogrind/AutogrindController.gd")

var _es: Node
var _pool_was: Array[String] = []
var _region_was: String = ""
var _c


func before_each() -> void:
	_es = get_tree().root.get_node_or_null("EncounterSystem")
	_pool_was = _es.current_enemy_pool.duplicate()
	_region_was = str(AutogrindSystem.current_region_id)
	_c = ControllerScript.new()
	add_child_autofree(_c)
	AutogrindSystem.current_region_id = "Overworld"


func after_each() -> void:
	_es.current_enemy_pool = _pool_was
	AutogrindSystem.current_region_id = _region_was


func _stand_in(zone: String) -> void:
	var typed: Array[String] = []
	for id in _es.enemy_pools.get(zone, []):
		typed.append(str(id))
	_es.current_enemy_pool = typed


func _top_level(candidates: Array) -> int:
	var top := 0
	for c in candidates:
		top = maxi(top, int((_es.monster_database.get(str(c.get("id", "")), {}) as Dictionary).get("level", 0)))
	return top


func _zone_top(zone: String) -> int:
	var top := 0
	for id in _es.enemy_pools.get(zone, []):
		top = maxi(top, int((_es.monster_database.get(str(id), {}) as Dictionary).get("level", 0)))
	return top


func test_a_grind_in_the_starting_zone_draws_only_that_zone() -> void:
	_stand_in("overworld_central")
	var start_top := _zone_top("overworld_central")
	assert_gt(start_top, 0, "CONTROL: the starting zone has a pool with authored levels")
	var drawn: Array = _c._grind_draw_candidates()
	assert_gt(drawn.size(), 0, "CONTROL: the grind found something to fight")
	assert_lte(_top_level(drawn), start_top, "a grind where the game begins never draws above that zone's own strongest monster (L%d)" % start_top)


func test_a_grind_in_a_harder_zone_draws_that_zones_monsters() -> void:
	_stand_in("overworld_volcanic")
	assert_gt(_zone_top("overworld_volcanic"), _zone_top("overworld_central"), "CONTROL: the volcanic zone out-levels the starting one")
	assert_eq(_top_level(_c._grind_draw_candidates()), _zone_top("overworld_volcanic"), "standing in the volcanic zone, the grind draws its monsters")


func _party_at(level: int) -> void:
	var hero := Combatant.new()
	hero.initialize({"name": "Reach", "max_hp": 100, "max_mp": 10, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(hero)
	hero.job_level = level
	_c._party = [hero]


func test_no_live_pool_falls_back_to_the_regions_union() -> void:
	var none: Array[String] = []
	_es.current_enemy_pool = none
	_party_at(20)
	assert_gt(_top_level(_c._grind_draw_candidates()), _zone_top("overworld_central"),
		"with no live pool (a safe zone) the region's union still supplies a party that can face it")


## Villages and interiors push an EMPTY pool, so a grind started in the first village had no place to read and drew the fallbacks whole.
func test_a_village_grind_stays_within_a_fresh_partys_reach() -> void:
	var none: Array[String] = []
	_es.current_enemy_pool = none
	_party_at(1)
	var cap: int = 1 + _c.FALLBACK_LEVEL_REACH
	for region in ["Overworld", "Harmonia Village"]:
		AutogrindSystem.current_region_id = region
		var drawn: Array = _c._grind_draw_candidates()
		assert_gt(drawn.size(), 0, "CONTROL: a %s grind still finds something to fight" % region)
		assert_lte(_top_level(drawn), cap, "a L1 party grinding from %s never draws above L%d" % [region, cap])
	_party_at(12)
	AutogrindSystem.current_region_id = "Harmonia Village"
	assert_gt(_top_level(_c._grind_draw_candidates()), cap, "CONTROL: a L12 party in the same village reaches further")


func test_an_auto_advanced_grind_reads_its_new_region_not_where_it_started() -> void:
	_stand_in("overworld_central")
	_c._advanced_from_start = true
	_party_at(20)
	assert_gt(_top_level(_c._grind_draw_candidates()), _zone_top("overworld_central"),
		"after Auto-Advance the party no longer stands in the starting zone, so the region lookup answers")


func test_a_dungeon_floors_level_mark_reaches_the_grind() -> void:
	var marked: Array[String] = ["imp@L13"]
	_es.current_enemy_pool = marked
	var drawn: Array = _c._grind_draw_candidates()
	assert_eq(drawn.size(), 1, "CONTROL: the marked id resolved to its species")
	var imp: Dictionary = drawn[0]
	var catalog: Dictionary = _es.monster_database["imp"]
	assert_eq(str(imp.get("id", "")), "imp", "the grind's enemy is the species (bestiary, drops)")
	assert_eq(int(imp.get("spawn_level", 0)), 13, "fighting at the floor's level")
	assert_gt(int(imp["stats"]["max_hp"]), int(catalog["stats"]["max_hp"]) * 5, "with the re-levelled stats, not the catalog L4 row's")
	assert_gt(int(imp.get("exp_reward", 0)), int(catalog.get("exp_reward", 0)), "and the re-levelled reward")
	var gl: Node = load("res://src/GameLoop.gd").new()
	add_child_autofree(gl)
	var foe: Combatant = gl._combatant_for_headless(imp)
	add_child_autofree(foe)
	assert_eq(int(foe.get_meta("spawn_level", 0)), 13, "the headless combatant carries the level, so ExpRules and x10_ratio read it")
	assert_eq(int(foe.get_meta("exp_reward", 0)), int(imp["exp_reward"]), "and its own reward, which the resolver pays")


## The resolver pays a spawn's own reward over its species' catalog row (live's _authored_reward does the same).
func test_the_headless_battle_pays_a_relevelled_spawns_own_reward() -> void:
	var hero := Combatant.new()
	hero.initialize({"name": "Payee", "max_hp": 9999, "max_mp": 99, "attack": 9999, "defense": 999, "magic": 10, "speed": 50})
	add_child_autofree(hero)
	var paid: Array = []
	for own_reward in [0, 777]:
		var foe := Combatant.new()
		foe.initialize({"name": "Imp", "max_hp": 5, "max_mp": 0, "attack": 1, "defense": 0, "magic": 1, "speed": 1})
		add_child_autofree(foe)
		foe.set_meta("monster_type", "imp")
		if own_reward > 0:
			foe.set_meta("spawn_level", 13)
			foe.set_meta("exp_reward", own_reward)
		hero.current_hp = hero.max_hp
		var result: Dictionary = HeadlessBattleResolver.new().resolve_battle([hero], [foe])
		assert_true(bool(result.get("victory", false)), "CONTROL: the fight was won")
		paid.append(int(result.get("exp_gained", 0)))
	gut.p("    catalog imp paid %d, the re-levelled one %d" % [paid[0], paid[1]])
	assert_gt(paid[0], 0, "CONTROL: a catalog imp pays its row's EXP")
	assert_gt(paid[1], paid[0] * 5, "a spawn carrying its own EXP is paid that, not the catalog L4 row's")
