extends GutTest

## W1 balance audit 2026-11-11: the dragon caves spawned L2-9 trash in front of L17-22 bosses, and EXP halves per 3 levels
## over the fight, so L12 to L25 had no EXP. Each floor now re-levels the species it draws ("imp@L13") toward its boss.

const DUNGEONS := ["FireDragonCave", "IceDragonCave", "LightningDragonCave", "ShadowDragonCave", "CastleHarmonia"]
const MAX_GAP := 5
const MAX_OFFENSE_SHARE := 0.7

var _es: Node


func before_each() -> void:
	_es = get_tree().root.get_node_or_null("EncounterSystem")


## {floor: [ids]} and the boss id, read from the dungeon script's own source.
func _pools_of(dungeon: String) -> Dictionary:
	var src := FileAccess.get_file_as_string("res://src/maps/dungeons/%s.gd" % dungeon)
	var out := {"boss": "", "floors": {}}
	var boss := RegEx.create_from_string("boss_id = \"([a-z_]+)\"").search(src)
	if boss:
		out["boss"] = boss.get_string(1)
	var at := src.find("floor_encounter_pools = {")
	var block := src.substr(at, src.find("\n\t}", at) - at)
	for m in RegEx.create_from_string("(\\d+): \\[([^\\]]*)\\]").search_all(block):
		var ids: Array = []
		for q in RegEx.create_from_string("\"([^\"]+)\"").search_all(m.get_string(2)):
			ids.append(q.get_string(1))
		out["floors"][int(m.get_string(1))] = ids
	return out


func _level_of(spawn_id: String) -> int:
	return int(_es._create_enemy_data(spawn_id).get("level", 0))


func test_every_dungeon_floor_fights_near_its_boss() -> void:
	assert_not_null(_es, "CONTROL: EncounterSystem is reachable")
	var floors_seen := 0
	var far: Array = []
	for d in DUNGEONS:
		var p := _pools_of(d)
		var boss_level := int((_es.monster_database.get(p["boss"], {}) as Dictionary).get("level", 0))
		assert_gt(boss_level, 0, "CONTROL: %s names a catalog boss (%s)" % [d, p["boss"]])
		for f in p["floors"]:
			if (p["floors"][f] as Array).is_empty():
				continue
			floors_seen += 1
			var top := 0
			for id in p["floors"][f]:
				top = maxi(top, _level_of(id))
				if _level_of(id) > boss_level:
					far.append("%s F%d %s is above its boss (L%d)" % [d, f, id, boss_level])
			if top < boss_level - MAX_GAP:
				far.append("%s F%d tops out at L%d, boss L%d" % [d, f, top, boss_level])
	assert_gt(floors_seen, 15, "CONTROL: the floors were read (%d)" % floors_seen)
	assert_eq(far, [], "a dungeon floor's strongest spawn stays within %d levels below its boss, never above" % MAX_GAP)


func test_a_cave_never_gets_easier_as_it_descends() -> void:
	for d in DUNGEONS:
		var p := _pools_of(d)
		var last := 0
		var keys: Array = p["floors"].keys()
		keys.sort()
		for f in keys:
			for id in p["floors"][f]:
				assert_gte(_level_of(id), last, "%s F%d %s is below the floor above it" % [d, f, id])
			for id in p["floors"][f]:
				last = maxi(last, _level_of(id))


func test_a_level_mark_scales_the_species_on_the_level_curve() -> void:
	var base: Dictionary = _es._create_enemy_data("goblin")
	var up: Dictionary = _es._create_enemy_data("goblin@L14")
	assert_eq(int(base.get("level", 0)), 4, "CONTROL: the catalog goblin is L4")
	assert_eq(str(up.get("id", "")), "goblin@L14", "the mark survives in the id, so the battle spawner re-levels it too")
	assert_eq(int(up.get("level", 0)), 14, "the spawn fights at the floor's level")
	var growth := Combatant.level_multiplier(14) / Combatant.level_multiplier(4)
	assert_eq(int(up["max_hp"]), int(round(float(base["max_hp"]) * growth)), "HP rides the level curve the party's does")
	assert_eq(int(up["attack"]), int(round(float(base["attack"]) * growth * _es.SPAWN_OFFENSE_DIAL)), "attack rides it too, under the offense dial")
	assert_eq(int(up["speed"]), int(base["speed"]), "speed is left alone")
	assert_eq(int(up["exp_reward"]), int(round(float(base["exp_reward"]) * 14.0 / 4.0)), "EXP scales with the level, as a level's cost does")
	assert_eq(_es.spawn_level_of("goblin"), 0, "CONTROL: an unmarked id carries no level")
	assert_eq(_es.spawn_base_id("goblin@L14"), "goblin", "and a marked one names its species")


func test_a_relevelled_spawn_pays_exp_at_its_own_level() -> void:
	var foe := Combatant.new()
	foe.initialize({"name": "Goblin", "max_hp": 10, "max_mp": 0, "attack": 1, "defense": 1, "magic": 1, "speed": 1})
	add_child_autofree(foe)
	foe.set_meta("monster_type", "goblin")
	assert_eq(ExpRules.area_level_of([foe]), 4, "CONTROL: an ordinary goblin is a L4 fight")
	foe.set_meta("spawn_level", 14)
	assert_eq(ExpRules.area_level_of([foe]), 14, "a re-levelled one is a fight at its floor's level, so a L14 party is not over-levelled for it")


func test_an_exterminated_species_stays_gone_from_a_marked_pool() -> void:
	var was: Array = GameState.permakilled_monster_types.duplicate()
	GameState.permakilled_monster_types.append("goblin")
	var kept: Array = _es._filter_permakilled(["goblin@L14", "imp@L14"])
	GameState.permakilled_monster_types.clear()
	for t in was:
		GameState.permakilled_monster_types.append(t)
	assert_eq(kept, ["imp@L14"], "permakill reads the species under the level mark")


## cowir-main 2026-11-11: "trash must not out-stat its own boss." A floor's hardest regular hits well under the boss it guards.
func test_floor_trash_hits_well_under_its_boss() -> void:
	var over: Array = []
	var checked := 0
	for d in DUNGEONS:
		var p := _pools_of(d)
		var boss: Dictionary = (_es.monster_database.get(p["boss"], {}) as Dictionary).get("stats", {})
		for f in p["floors"]:
			for id in p["floors"][f]:
				var foe: Dictionary = _es._create_enemy_data(id)
				checked += 1
				for stat in ["attack", "magic"]:
					if float(foe.get(stat, 0)) > MAX_OFFENSE_SHARE * float(boss.get(stat, 0)):
						over.append("%s F%d %s %s %d > %d%% of the boss's %d" % [d, f, id, stat, int(foe[stat]), int(MAX_OFFENSE_SHARE * 100), int(boss.get(stat, 0))])
				if int(foe.get("max_hp", 0)) >= int(boss.get("max_hp", 0)):
					over.append("%s F%d %s has its boss's HP or more" % [d, f, id])
	assert_gt(checked, 30, "CONTROL: the spawns were built (%d)" % checked)
	assert_eq(over, [], "no floor spawn out-stats the boss it guards")


func test_a_relevelled_spawn_converts_flat_values_at_its_own_level() -> void:
	var foe := Combatant.new()
	foe.initialize({"name": "Goblin", "max_hp": 10, "max_mp": 0, "attack": 1, "defense": 1, "magic": 1, "speed": 1})
	add_child_autofree(foe)
	foe.set_meta("monster_type", "goblin")
	var catalog: float = foe.x10_ratio()
	assert_gt(catalog, 0.0, "CONTROL: the catalog goblin has a ratio")
	foe.set_meta("spawn_level", 14)
	assert_almost_eq(foe.x10_ratio(), catalog * Combatant.level_multiplier(14) / Combatant.level_multiplier(4), 0.0001,
		"a L14 goblin's flat heals and items convert at L14, not at the catalog's L4")
