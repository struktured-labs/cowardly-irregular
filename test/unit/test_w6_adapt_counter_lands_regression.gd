extends GutTest

## Optimization Itself (W6 overworld and the abstract field elite) lists Adapt in
## counter_abilities. The counter log names that ability, then the hook used to
## send every non-magic type through _execute_physical_ability. Adapt is support
## (effect adapt_resistance, target self): the player saw "counters with Adapt!"
## and took a hit, and the monster never gained the resistance the ability applies
## when it is cast on its own turn.

const MONSTERS := "res://data/monsters.json"
const ABILITIES := "res://data/abilities.json"


var _monster: Combatant = null
var _saved_entry: Variant = null


func after_each() -> void:
	if _monster != null and is_instance_valid(_monster) and BattleManager.enemy_party.has(_monster):
		BattleManager.enemy_party.erase(_monster)
	_monster = null
	if _saved_entry != null and EncounterSystem != null:
		EncounterSystem.monster_database["optimization_itself"] = _saved_entry
	_saved_entry = null


func _make(name_str: String, hp: int, atk: int) -> Combatant:
	var c := Combatant.new()
	c.initialize({
		"name": name_str, "max_hp": hp, "max_mp": 50,
		"attack": atk, "defense": 40, "magic": 10, "magic_defense": 20, "speed": 10,
	})
	add_child_autofree(c)
	return c


func _has_adapted(monster: Combatant) -> bool:
	for b in monster.active_buffs:
		if str(b.get("effect", "")) == "Adapted" and str(b.get("stat", "")) == "defense":
			return true
	return false


func test_optimization_itself_authors_adapt_as_a_support_counter() -> void:
	var monsters: Variant = JSON.parse_string(FileAccess.get_file_as_string(MONSTERS))
	var abilities: Variant = JSON.parse_string(FileAccess.get_file_as_string(ABILITIES))
	assert_true(monsters is Dictionary and abilities is Dictionary, "monster and ability catalogs must parse")
	if not (monsters is Dictionary and abilities is Dictionary):
		return
	var row: Dictionary = (monsters as Dictionary).get("optimization_itself", {})
	var counters: Variant = row.get("counter_abilities", [])
	assert_true(counters is Array and (counters as Array).has("adapt"),
		"Optimization Itself must still counter with Adapt — that is the move this fight promises")
	var adapt: Dictionary = (abilities as Dictionary).get("adapt", {})
	assert_eq(str(adapt.get("type", "")), "support",
		"Adapt is a support ability; a counter that only strikes cannot perform it")
	assert_eq(str(adapt.get("effect", "")), "adapt_resistance")
	assert_eq(str(adapt.get("target_type", "")), "self")


func test_an_adapt_counter_raises_defense_and_does_not_strike() -> void:
	if EncounterSystem == null or not EncounterSystem.monster_database.has("optimization_itself"):
		pending("optimization_itself must be in EncounterSystem.monster_database")
		return
	if JobSystem == null or JobSystem.get_ability("adapt").is_empty():
		pending("JobSystem must resolve adapt")
		return
	var original: Variant = EncounterSystem.monster_database["optimization_itself"]
	assert_true(original is Dictionary, "optimization_itself row must be a dictionary")
	if not (original is Dictionary):
		return
	_saved_entry = original
	var narrowed: Dictionary = (original as Dictionary).duplicate(true)
	narrowed["counter_abilities"] = ["adapt"]
	EncounterSystem.monster_database["optimization_itself"] = narrowed

	_monster = _make("Optimization Itself", 400, 80)
	_monster.set_meta("monster_type", "optimization_itself")
	BattleManager.enemy_party.append(_monster)
	var hero := _make("Hero", 5000, 10)
	var hp_before := hero.current_hp

	for _i in range(40):
		BattleManager._trigger_monster_counter(_monster, hero)
		if _has_adapted(_monster):
			break

	var adapted := _has_adapted(_monster)
	var hp_after := hero.current_hp
	var defense_after := _monster.get_buffed_stat("defense", _monster.defense)
	BattleManager.enemy_party.erase(_monster)
	EncounterSystem.monster_database["optimization_itself"] = _saved_entry
	_saved_entry = null
	_monster = null

	assert_true(adapted,
		"Adapt as a counter must apply the Adapted defense buff — the log line is not the resistance")
	assert_gt(defense_after, 40,
		"the buff must raise defense, not sit in the list unused")
	assert_eq(hp_after, hp_before,
		"Adapt must not strike the attacker; the old path dealt a physical hit under the Adapt name")
