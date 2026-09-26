extends GutTest

## Rogue Process (W5 overworld and Root Process) casts Clone Self. BattleManager
## logs the fork and emits monster_summoned("rogue_process"). BattleScene only
## looked that id up in BattleEnemySpawner.MONSTER_TYPES, which stops at the
## early-game roster, so the handler warned and returned. The player saw
## "forks a copy of itself" and no second enemy.

const BS := preload("res://src/battle/BattleScene.gd")

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
