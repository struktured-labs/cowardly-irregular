extends GutTest

## The Ninja Defensive preset said it would blind the room and keep fighting. Its first rule
## cast Smoke Bomb, and Smoke Bomb's guaranteed_escape ends every non-boss battle. The default
## Ninja script opened the same way. A player on autobattle saw "escaped successfully" and no
## rewards. Casting Smoke Bomb on purpose still leaves; these scripts must not choose it.


var _saved_state
var _saved_pp: Array = []
var _saved_ep: Array = []
var _saved_escape: bool = true
var _fixture_ids: Array[String] = []


func before_each() -> void:
	_saved_state = BattleManager.current_state
	_saved_pp = BattleManager.player_party.duplicate()
	_saved_ep = BattleManager.enemy_party.duplicate()
	_saved_escape = BattleManager.escape_allowed
	AutobattleSystem._test_disable_persistence = true
	_fixture_ids.clear()


func after_each() -> void:
	BattleManager.escape_allowed = _saved_escape
	BattleManager.current_state = _saved_state
	BattleManager.player_party.clear()
	for c in _saved_pp:
		BattleManager.player_party.append(c)
	BattleManager.enemy_party.clear()
	for c in _saved_ep:
		BattleManager.enemy_party.append(c)
	for cid in _fixture_ids:
		AutobattleSystem.character_profiles.erase(cid)


func _ninja(who: String) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.initialize({"name": who, "max_hp": 850, "max_mp": 45,
		"attack": 140, "defense": 80, "magic": 80, "speed": 18})
	c.job = JobSystem.get_job("ninja")
	c.job_level = 10
	c.is_alive = true
	return c


func _field(caster: Combatant) -> void:
	var foe := Combatant.new()
	autofree(foe)
	foe.initialize({"name": "Road Slime", "max_hp": 99999, "max_mp": 0,
		"attack": 1, "defense": 999, "magic": 1, "speed": 1})
	foe.is_alive = true
	var cid: String = AutobattleSystem._get_character_id(caster)
	_fixture_ids.append(cid)
	BattleManager.player_party.clear()
	BattleManager.enemy_party.clear()
	BattleManager.player_party.append(caster)
	BattleManager.enemy_party.append(foe)
	BattleManager.escape_allowed = true


func _play_opening(caster: Combatant) -> void:
	var actions: Array = AutobattleSystem.execute_grid_autobattle(caster)
	assert_gt(actions.size(), 0, "the script must choose an action")
	var action: Dictionary = actions[0]
	var ability_id: String = str(action.get("ability_id", ""))
	if ability_id != "":
		var ability: Dictionary = JobSystem.get_ability(ability_id)
		assert_false(bool(ability.get("guaranteed_escape", false)),
			"the opening action is %s, which ends a non-boss battle" % ability_id)
	var allies: Array = []
	for a in BattleManager.player_party:
		allies.append(a)
	var foes: Array = []
	for e in BattleManager.enemy_party:
		foes.append(e)
	var converted: Dictionary = BattleManager._convert_autobattle_action(caster, action, allies, foes)
	assert_false(converted.is_empty(), "the opening action must be playable, got %s" % str(action))
	watch_signals(BattleManager)
	match str(converted.get("type", "")):
		"attack":
			BattleManager._execute_attack(caster, converted.get("target"))
		"ability":
			BattleManager._execute_ability(caster, str(converted.get("ability_id", "")), converted.get("targets", []))
		"item":
			BattleManager._execute_item(caster, str(converted.get("item_id", "")), converted.get("targets", []))
		_:
			fail_test("opening action type %s is not a battle action" % str(converted.get("type", "")))
	assert_signal_not_emitted(BattleManager, "battle_ended",
		"the script's first action ended the fight — the player was trying to keep fighting")


func test_the_defensive_preset_does_not_open_by_escaping() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/autobattle_rule_templates.json"))
	assert_not_null(parsed, "CONTROL: the preset catalog parses")
	var preset: Dictionary = {}
	for t in (parsed.get("templates", []) as Array):
		if str((t as Dictionary).get("id", "")) == "ninja_defensive":
			preset = t
	assert_false(preset.is_empty(), "CONTROL: ninja_defensive is in the catalog")
	var desc: String = str(preset.get("description", "")).to_lower()
	assert_false(desc.contains("blind"),
		"the on-screen stance text still promises a blind the opener no longer performs: %s" % desc)
	var caster := _ninja("Defensive Ninja")
	_field(caster)
	AutobattleSystem.set_character_script(AutobattleSystem._get_character_id(caster), {
		"character_id": AutobattleSystem._get_character_id(caster),
		"name": "Defensive",
		"rules": (preset.get("rules", []) as Array),
	})
	_play_opening(caster)


func test_the_default_ninja_script_does_not_open_by_escaping() -> void:
	var caster := _ninja("Default Ninja")
	_field(caster)
	var script: Dictionary = AutobattleSystem.create_default_character_script("ninja")
	assert_eq(str(script.get("name", "")), "Ninja Default",
		"CONTROL: the ninja id must receive the ninja default, not the generic attack script")
	AutobattleSystem.set_character_script(AutobattleSystem._get_character_id(caster), script)
	_play_opening(caster)


func test_a_deliberate_smoke_bomb_still_escapes() -> void:
	## Control: the ability still leaves. This file must not go green by breaking escape itself.
	var caster := _ninja("Casting Ninja")
	_field(caster)
	assert_true(caster.knows_ability("smoke_bomb"), "CONTROL: the ninja kit includes smoke_bomb")
	assert_true(JobSystem.can_use_ability(caster, "smoke_bomb"), "CONTROL: the caster can pay for it")
	var foes: Array = []
	for e in BattleManager.enemy_party:
		foes.append(e)
	assert_gt(foes.size(), 0, "CONTROL: there is someone to throw it at")
	watch_signals(BattleManager)
	BattleManager._execute_ability(caster, "smoke_bomb", foes)
	assert_signal_emitted(BattleManager, "battle_ended",
		"Smoke Bomb itself must still end a non-boss battle when the player casts it")
