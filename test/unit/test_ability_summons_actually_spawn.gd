extends GutTest

## The Cave Rat King's Royal Summon never summoned anything.
##
## `_execute_ability`'s "summon" arm routed EVERY summon-typed ability to _execute_magic_ability.
## That was written for the Summoner job's four eidolons, which are magic-shaped (damage_multiplier
## + element + all_enemies) and were fizzling to the unknown-type default. The comment justifying it
## said the ally-spawning summons were fine because "only enemy AI uses them via _execute_summon" —
## and that is the half that was false. _execute_summon has exactly one production caller, gated on
## _can_monster_summon, whose roster is the hardcoded list ["goblin","imp","skeleton","wolf","bat"]
## and which never consults a monster's abilities at all. Neither owner of a summon_id ability
## (cave_rat_king, blood_wolf_alpha) is on it, so the spawn path was unreachable for exactly the
## three abilities authored to use it: summon_id, summon_count and summon_message had ZERO readers
## in src/. Royal Summon burned 20 MP casting a 1.0x magic hit, and its bespoke flavour line —
## "The Rat King SQUEAKS imperiously!" — had never once printed.
##
## The trap is the one the fleet keeps naming: the case that worked (eidolons) certified the ones
## that did not. So these drive the REAL entry point and watch the monster_summoned signal, rather
## than asserting that a branch exists.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")
const SpawnerScript = preload("res://src/battle/BattleEnemySpawner.gd")

var _bm = null
var _spawned: Array = []
var _log: Array = []

func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)
	_spawned = []
	_log = []
	_bm.monster_summoned.connect(func(mtype, _summoner): _spawned.append(str(mtype)))
	_bm.battle_log_message.connect(func(msg): _log.append(str(msg)))

## A monster caster shaped the way BattleEnemySpawner leaves one: a job dict carrying its kit.
func _monster(display_name: String, monster_id: String) -> Combatant:
	var data: Dictionary = _monsters().get(monster_id, {})
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = display_name
	c.max_mp = 999
	c.current_mp = 999
	c.max_hp = 500
	c.current_hp = 500
	c.job = {"id": monster_id, "abilities": (data.get("abilities", []) as Array).duplicate()}
	c.set_meta("monster_type", monster_id)
	return c

func _monsters() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	assert_not_null(parsed, "CONTROL: monsters.json parses")
	return (parsed as Dictionary).get("monsters", parsed)

func _abilities() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	assert_not_null(parsed, "CONTROL: abilities.json parses")
	return (parsed as Dictionary).get("abilities", parsed)

func test_royal_summon_spawns_a_rat_guard() -> void:
	var king := _monster("Cave Rat King", "cave_rat_king")
	_bm._execute_ability(king, "royal_summon", [king])
	assert_eq(_spawned, ["rat_guard"],
		"the W1 tutorial boss's signature move must put a rat guard on the field, not cast magic at itself")

func test_rat_swarm_honours_summon_count() -> void:
	var king := _monster("Cave Rat King", "cave_rat_king")
	_bm._execute_ability(king, "rat_swarm", [king])
	assert_eq(_spawned, ["cave_rat", "cave_rat"],
		"summon_count is 2 — one spawn would read as working while halving the ability")

func test_pack_call_works_for_the_other_owner() -> void:
	## blood_wolf_alpha, not "wolf" — precisely the monster_type _can_monster_summon's roster misses.
	var alpha := _monster("Blood Wolf Alpha", "blood_wolf_alpha")
	_bm._execute_ability(alpha, "pack_call", [alpha])
	assert_eq(_spawned, ["wolf"], "pack_call must call the pack")

func test_the_authored_flavour_line_reaches_the_player() -> void:
	var king := _monster("Cave Rat King", "cave_rat_king")
	_bm._execute_ability(king, "royal_summon", [king])
	assert_string_contains("".join(_log), "SQUEAKS imperiously",
		"summon_message was authored for this one ability and had no reader at all")

func test_a_full_field_refuses_rather_than_floods() -> void:
	var king := _monster("Cave Rat King", "cave_rat_king")
	for i in _bm.MAX_FIELD_ENEMIES:
		var mook := Combatant.new()
		autofree(mook)
		mook.combatant_name = "Mook%d" % i
		mook.max_hp = 10
		mook.current_hp = 10
		_bm.enemy_party.append(mook)
	_bm._execute_ability(king, "rat_swarm", [king])
	assert_eq(_spawned.size(), 0, "the field ceiling must hold — a summoning boss can otherwise flood it")
	assert_string_contains("".join(_log), "no room on the field",
		"and say why, rather than consuming the turn in silence")

func test_the_eidolons_still_take_the_magic_path() -> void:
	## The regression this fix could cause. Ifrit authors no summon_id, so it must keep dealing
	## damage — routing it to the spawner would fizzle the Summoner job's whole kit.
	var ab := _abilities()
	assert_false(ab["summon_ifrit"].has("summon_id"), "CONTROL: the discriminator is absent on eidolons")
	var summoner := Combatant.new()
	autofree(summoner)
	summoner.combatant_name = "Eidolon Caller"
	summoner.max_mp = 999
	summoner.current_mp = 999
	summoner.job = {"id": "summoner", "abilities": ["summon_ifrit"]}
	var victim := Combatant.new()
	autofree(victim)
	victim.combatant_name = "Target"
	victim.max_hp = 4000
	victim.current_hp = 4000
	_bm.enemy_party.append(victim)
	_bm._execute_ability(summoner, "summon_ifrit", [victim])
	assert_eq(_spawned.size(), 0, "an eidolon must not spawn an ally")
	assert_lt(victim.current_hp, 4000, "it must still deal its damage — the magic path has to survive the branch")

func test_every_summon_id_names_a_monster_the_spawner_can_build() -> void:
	## _on_monster_summoned looks up BattleEnemySpawner.MONSTER_TYPES, a HARDCODED array — not
	## monsters.json. A summon_id present in the json but missing there push_warnings and spawns
	## nothing, which from the battle log is indistinguishable from a working summon.
	var buildable: Dictionary = {}
	for mt in SpawnerScript.MONSTER_TYPES:
		buildable[str(mt["id"])] = true
	assert_gt(buildable.size(), 5, "CONTROL: the spawner's hardcoded roster read non-empty")
	var all_abilities: Dictionary = _abilities()
	var checked: int = 0
	for aid in all_abilities:
		var sid: String = str((all_abilities[aid] as Dictionary).get("summon_id", ""))
		if sid == "":
			continue
		checked += 1
		assert_true(buildable.has(sid),
			"%s summons '%s', which BattleEnemySpawner.MONSTER_TYPES cannot build" % [aid, sid])
	assert_eq(checked, 3, "CONTROL: three abilities author a summon_id — if this moves, revisit the list")
