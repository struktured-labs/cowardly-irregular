extends GutTest

## Rogue Process (W5 overworld and Root Process) casts Clone Self. BattleManager
## logs the fork and emits monster_summoned("rogue_process"). BattleScene only
## looked that id up in BattleEnemySpawner.MONSTER_TYPES, which stops at the
## early-game roster, so the handler warned and returned. The player saw
## "forks a copy of itself" and no second enemy.

const BS := preload("res://src/battle/BattleScene.gd")
const BM := preload("res://src/battle/BattleManager.gd")

## _ready boots a battle off scene nodes this probe does not have. Presentation
## is skipped so the assertion is the party membership, not the sprite tween.
class QuietSummon extends BS:
	func _ready() -> void:
		pass

	func _present_summoned_enemy(_enemy: Combatant, _monster_type: String, _new_idx: int, _display_name: String) -> void:
		pass

	func log_message(_message: String) -> void:
		pass

	func _update_ui() -> void:
		pass


var _party_size: int = 0
var _all_size: int = 0


func before_each() -> void:
	_party_size = BattleManager.enemy_party.size()
	_all_size = BattleManager.all_combatants.size()


func after_each() -> void:
	while BattleManager.enemy_party.size() > _party_size:
		BattleManager.enemy_party.pop_back()
	while BattleManager.all_combatants.size() > _all_size:
		BattleManager.all_combatants.pop_back()


func test_a_rogue_process_clone_joins_the_fight_with_its_own_kit() -> void:
	var scene := QuietSummon.new()
	var caster := Combatant.new()
	caster.combatant_name = "Rogue Process"
	caster.set_meta("monster_type", "rogue_process")
	scene._on_monster_summoned("rogue_process", caster)
	assert_gt(BattleManager.enemy_party.size(), _party_size,
		"Clone Self must put a Rogue Process on the field — the log line alone is not a summon")
	if BattleManager.enemy_party.size() <= _party_size:
		scene.free()
		caster.free()
		return
	var clone: Combatant = BattleManager.enemy_party[BattleManager.enemy_party.size() - 1]
	assert_eq(clone.get_meta("monster_type", ""), "rogue_process",
		"the summon must be the caster's species, not a fallback mook")
	assert_eq(clone.max_hp, 2800, "the copy must use the catalog HP, not a hardcoded early-game block")
	assert_eq(clone.attack, 480, "the copy must use the catalog attack")
	assert_eq(clone.combatant_name, "Rogue Process", "a lone clone keeps the species name")
	assert_true("ice" in clone.elemental_weaknesses, "the copy keeps the species weakness")
	assert_true("physical" in clone.elemental_resistances, "the copy keeps the species resistance")
	assert_false(clone.has_meta("_utility_spent"),
		"a fork starts with its own once-per-battle budget — the parent's spent flag does not copy")
	assert_not_null(clone.job, "an identical enemy carries the species kit")
	if clone.job is Dictionary:
		assert_true("clone_self" in clone.job.get("abilities", []),
			"the fork must be able to fork — Clone Self is on the species kit")
	scene.free()
	caster.free()


func test_a_hardcoded_summon_does_not_gain_the_catalog_kit() -> void:
	## Royal Summon's rat guard is built from MONSTER_TYPES and fights with a basic attack.
	## Falling through to monsters.json would hand it shield_bash and change that fight.
	var scene := QuietSummon.new()
	var caster := Combatant.new()
	caster.combatant_name = "Cave Rat King"
	scene._on_monster_summoned("rat_guard", caster)
	assert_gt(BattleManager.enemy_party.size(), _party_size, "rat_guard is on the hardcoded roster and must still appear")
	if BattleManager.enemy_party.size() <= _party_size:
		scene.free()
		caster.free()
		return
	var guard: Combatant = BattleManager.enemy_party[BattleManager.enemy_party.size() - 1]
	assert_eq(guard.max_hp, 1600, "rat_guard keeps the MONSTER_TYPES stat block")
	assert_null(guard.job, "the hardcoded summon path does not import the json kit")
	scene.free()
	caster.free()


func test_an_unlisted_summon_uses_catalog_magic_defense() -> void:
	## memory_leak is not on MONSTER_TYPES. defense 150 would fallback to magic_defense 75;
	## the catalog authors 70, so a passing 90 on rogue_process (exactly defense/2) would not catch a dropped key.
	var scene := QuietSummon.new()
	var caster := Combatant.new()
	caster.combatant_name = "Memory Leak"
	scene._on_monster_summoned("memory_leak", caster)
	assert_gt(BattleManager.enemy_party.size(), _party_size, "a catalog species outside the early roster must still join")
	if BattleManager.enemy_party.size() <= _party_size:
		scene.free()
		caster.free()
		return
	var leak: Combatant = BattleManager.enemy_party[BattleManager.enemy_party.size() - 1]
	assert_eq(leak.get_meta("monster_type", ""), "memory_leak")
	assert_eq(leak.magic_defense, 70, "catalog magic_defense must win over the defense/2 fallback")
	assert_eq(leak.max_hp, 3500)
	assert_not_null(leak.job, "an unlisted summon still brings its species kit")
	scene.free()
	caster.free()


func test_an_unknown_summon_id_adds_nobody() -> void:
	var scene := QuietSummon.new()
	var caster := Combatant.new()
	scene._on_monster_summoned("not_a_real_monster", caster)
	assert_eq(BattleManager.enemy_party.size(), _party_size, "an id in neither roster must warn and return, not crash or invent a body")
	scene.free()
	caster.free()


func test_clone_self_stops_at_the_field_ceiling() -> void:
	## Each body may fork once, and the child is a new combatant with a fresh budget, so the chain
	## is one new Rogue Process per successful cast until something refuses. MAX_FIELD_ENEMIES is that refusal.
	var bm = BM.new()
	add_child_autofree(bm)
	var spawned: Array = []
	var log: Array = []
	bm.monster_summoned.connect(func(mtype, _summoner):
		spawned.append(str(mtype))
		var body := Combatant.new()
		autofree(body)
		body.combatant_name = "Fork"
		body.max_hp = 10
		body.current_hp = 10
		body.set_meta("monster_type", str(mtype))
		bm.enemy_party.append(body)
	)
	bm.battle_log_message.connect(func(msg): log.append(str(msg)))
	var caster := Combatant.new()
	autofree(caster)
	caster.combatant_name = "Rogue Process"
	caster.max_hp = 100
	caster.current_hp = 100
	caster.max_mp = 999
	caster.current_mp = 999
	caster.current_ap = 4
	caster.job = {"abilities": ["clone_self"], "name": "Rogue Process"}
	caster.set_meta("monster_type", "rogue_process")
	bm.enemy_party.append(caster)
	var room: int = bm.MAX_FIELD_ENEMIES - 1
	for _i in room:
		bm._execute_ability(caster, "clone_self", [caster])
	assert_eq(spawned.size(), room, "each cast under the ceiling must put another Rogue Process on the field")
	assert_string_contains("".join(log), "forks a copy of itself", "a fork that joins must still say so")
	spawned.clear()
	log.clear()
	bm._execute_ability(caster, "clone_self", [caster])
	assert_eq(spawned.size(), 0, "a full field must not take another clone")
	assert_string_contains("".join(log), "no room on the field", "and say why, rather than logging a fork that never arrives")
	assert_false("".join(log).contains("forks a copy of itself"), "the success line is a lie when nothing joined")


func test_a_clone_can_pick_clone_self_once_and_its_parent_cannot_pick_it_again() -> void:
	## _utility_spent is per combatant. The scene builds a new Combatant, so the child does not inherit it.
	var bm = BM.new()
	add_child_autofree(bm)
	var ability: Dictionary = JobSystem.get_ability("clone_self")
	assert_false(ability.is_empty(), "CONTROL: clone_self resolves")
	var caster := Combatant.new()
	autofree(caster)
	caster.combatant_name = "Rogue Process"
	caster.max_hp = 100
	caster.current_hp = 100
	var foe := Combatant.new()
	autofree(foe)
	foe.combatant_name = "Hero"
	foe.max_hp = 100
	foe.current_hp = 100
	var first: Dictionary = bm._ai_utility_action(caster, [ability], [foe], 1.0)
	assert_eq(str(first.get("ability_id", "")), "clone_self", "the opener is allowed")
	var second: Dictionary = bm._ai_utility_action(caster, [ability], [foe], 1.0)
	assert_true(second.is_empty(), "the same body does not fork again — once per combatant, even at chance 1")
	var child := Combatant.new()
	autofree(child)
	child.combatant_name = "Rogue Process"
	child.max_hp = 100
	child.current_hp = 100
	var child_pick: Dictionary = bm._ai_utility_action(child, [ability], [foe], 1.0)
	assert_eq(str(child_pick.get("ability_id", "")), "clone_self",
		"the copy is a new combatant, so it may fork once too — the field ceiling is what bounds the chain")
