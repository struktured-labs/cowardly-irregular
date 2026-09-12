extends GutTest

## The third catalog unblocked by this session's grammar work, and the one that needed it most
## bluntly: Ifrit, Shiva and Ramuh cost 30 MP each, deal 3.0x to all enemies, and differ in NOTHING
## but element. To a script without `enemy_weak_to` they were the same ability three times over, so
## a preset had to pick one and hope. Now each answers the weakness that is actually on the field.
##
## ⚠️ recursive_summon gets its own arm because the SHARED anti-pin check cannot see it — see below.

const TEMPLATES := "res://data/autobattle_rule_templates.json"
const JOB := "summoner"

var _abs: Node = null
var _bm: Node = null
var _p_backup: Array = []
var _e_backup: Array = []
var _fixture_ids: Array[String] = []


func before_each() -> void:
	_abs = get_node_or_null("/root/AutobattleSystem")
	if _abs:
		_abs._test_disable_persistence = true
	_bm = get_node_or_null("/root/BattleManager")
	if _bm:
		_p_backup = _bm.player_party.duplicate()
		_e_backup = _bm.enemy_party.duplicate()
	_fixture_ids.clear()


func after_each() -> void:
	if _bm:
		_bm.player_party.clear()
		_bm.enemy_party.clear()
		for c in _p_backup:
			_bm.player_party.append(c)
		for c in _e_backup:
			_bm.enemy_party.append(c)
	if _abs:
		for cid in _fixture_ids:
			_abs.character_profiles.erase(cid)


func _json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_not_null(parsed, "CONTROL: %s parses" % path)
	return parsed


func _mine() -> Array:
	var all: Array = (_json(TEMPLATES).get("templates", []) as Array)
	assert_gt(all.size(), 20, "CONTROL: the catalog is populated (%d)" % all.size())
	return all.filter(func(t): return str((t as Dictionary).get("job_id", "")) == JOB)


func test_the_summoner_has_one_preset_per_stance() -> void:
	var names: Array = []
	for t in _mine():
		names.append(str((t as Dictionary).get("name", "")))
	names.sort()
	assert_eq(names, ["Aggressive", "Balanced", "Defensive"], "three stances: %s" % str(names))


func test_the_live_deep_check_accepts_every_rule() -> void:
	if _abs == null or not _abs.has_method("validate_rule"):
		pending("AutobattleSystem.validate_rule required")
		return
	var refused: Array = []
	var checked: int = 0
	for t in _mine():
		for r in ((t as Dictionary).get("rules", []) as Array):
			checked += 1
			var errors: Array = _abs.validate_rule(r, JOB)
			if errors.size() > 0:
				refused.append("%s rule %d: %s" % [str((t as Dictionary).get("id", "")), checked, str(errors)])
	assert_gt(checked, 14, "CONTROL: rules were submitted (%d)" % checked)
	assert_eq(refused.size(), 0, "the deep check refuses an authored rule: " + str(refused))


func test_the_catalog_offers_them_to_a_summoner() -> void:
	var cat = load("res://src/autobattle/AutobattleRuleTemplates.gd")
	assert_gt((cat.find_for_job("fighter") as Array).size(), 0, "CONTROL: find_for_job works at all")
	assert_eq((cat.find_for_job(JOB) as Array).size(), 3, "a Summoner must be offered three presets")


func test_the_eidolon_follows_the_weakness() -> void:
	## The artifact, and the whole reason this catalog waited. One combatant, one preset, and only
	## the ENEMY's weakness changing between turns — so the rules are shown choosing on the field
	## rather than on their order in the list.
	if _bm == null or _abs == null:
		pass_test("no battle autoloads in this harness")
		return
	var preset: Dictionary = {}
	for t in _mine():
		if str((t as Dictionary).get("id", "")) == "summoner_balanced":
			preset = t
	assert_false(preset.is_empty(), "CONTROL: the balanced preset was found to install")

	var c := Combatant.new()
	c.initialize({"name": "Pact Summoner", "max_hp": 620, "max_mp": 100,
		"attack": 70, "defense": 60, "magic": 130, "speed": 11})
	c.job = JobSystem.get_job(JOB)
	c.job_level = 10
	add_child_autofree(c)
	var foe := Combatant.new()
	foe.initialize({"name": "Shifting Foe", "max_hp": 99999, "max_mp": 0,
		"attack": 1, "defense": 999, "magic": 1, "speed": 1})
	add_child_autofree(foe)
	_bm.player_party.clear()
	_bm.enemy_party.clear()
	_bm.player_party.append(c)
	_bm.enemy_party.append(foe)
	var cid: String = _abs._get_character_id(c)
	_fixture_ids.append(cid)
	_abs.set_character_script(cid, {"character_id": cid, "name": "Balanced",
		"rules": (preset.get("rules", []) as Array)})
	var pick := func() -> String:
		var a: Dictionary = _abs.execute_grid_autobattle(c)[0]
		return str(a.get("ability_id", "")) if str(a.get("type", "")) == "ability" else str(a.get("type", ""))

	for pair in [["fire", "summon_ifrit"], ["ice", "summon_shiva"], ["lightning", "summon_ramuh"]]:
		foe.elemental_weaknesses.clear()
		foe.elemental_weaknesses.append(str(pair[0]))
		assert_eq(pick.call(), str(pair[1]), "weak to %s must summon %s" % [str(pair[0]), str(pair[1])])
	foe.elemental_weaknesses.clear()
	assert_ne(pick.call(), "summon_ifrit",
		"and weak to NOTHING must not fall back to the first eidolon in the list — that would mean "
		+ "the rules are ordered by luck rather than choosing")


func test_recursive_summon_cannot_be_cast_into_a_collapsed_spiral() -> void:
	## ⚠️ THE SHARED ANTI-PIN ARM IS BLIND TO THIS ONE, and the reason is worth keeping. That arm
	## skips any ability declaring a damage term, because a repeat still deals its damage.
	## recursive_summon declares `damage_multiplier: 2.0` and deals NO damage — the field is the
	## BUFF strength, applied as add_buff(..., "magic", 2.0, ...). So the shared predicate skips it
	## while it behaves exactly like a pure self-buff, and at max_depth the handler logs "the spiral
	## collapses on itself" and spends the turn on nothing. Third failure of that proxy, and the
	## first in the under-including direction.
	var abilities: Dictionary = _json("res://data/abilities.json")
	abilities = abilities.get("abilities", abilities)
	assert_true((abilities.get("recursive_summon", {}) as Dictionary).has("damage_multiplier"),
		"CONTROL: it really does declare a damage term, which is why the shared arm skips it")

	var unguarded: Array = []
	var seen: int = 0
	for t in (_json(TEMPLATES).get("templates", []) as Array):
		for r in ((t as Dictionary).get("rules", []) as Array):
			for a in ((r as Dictionary).get("actions", []) as Array):
				if str((a as Dictionary).get("id", "")) != "recursive_summon":
					continue
				seen += 1
				var bounded: bool = false
				for c in ((r as Dictionary).get("conditions", []) as Array):
					var ctype: String = str((c as Dictionary).get("type", ""))
					if ctype == "not_has_buff" or ctype == "turn":
						bounded = true
				if not bounded:
					unguarded.append(str((t as Dictionary).get("id", "")))
	assert_gt(seen, 1, "CONTROL: rules casting it were found to examine (%d)" % seen)
	assert_eq(unguarded.size(), 0,
		"a preset deepens the pact with nothing to stop it re-casting; past max_depth every one of "
		+ "those turns is spent on a log line: " + str(unguarded))
