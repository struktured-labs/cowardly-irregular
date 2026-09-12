extends GutTest

## The Speculator had no preset catalog, and like the Ninja it was blocked on grammar rather than on
## authoring. All six of its abilities are pure support — it owns no damage spell at all — and the
## two that matter, press_the_edge and circuit_breaker, SPEND a volatility band that no condition
## could read until .318. Authored before that, its stances would have pressed the edge at whatever
## band happened to be up, which is the job's entire decision made by coin flip.
##
## ⚠️ forecast is deliberately absent from all three, and the arm at the bottom pins that with its
## reason: its handler emits a battle-log line and changes NOTHING. It is a readout for a human, so
## in an autobattle script it is a turn spent on a message nobody is reading.

const TEMPLATES := "res://data/autobattle_rule_templates.json"
const JOB := "speculator"

var _abs: Node = null
var _bm: Node = null
var _p_backup: Array = []
var _e_backup: Array = []
var _vol_backup = null
var _fixture_ids: Array[String] = []


func before_each() -> void:
	_abs = get_node_or_null("/root/AutobattleSystem")
	if _abs:
		_abs._test_disable_persistence = true
	_bm = get_node_or_null("/root/BattleManager")
	if _bm:
		_p_backup = _bm.player_party.duplicate()
		_e_backup = _bm.enemy_party.duplicate()
		_vol_backup = _bm.volatility
		if _bm.volatility == null:
			_bm.volatility = VolatilitySystem.new()
	_fixture_ids.clear()


func after_each() -> void:
	if _bm:
		_bm.player_party.clear()
		_bm.enemy_party.clear()
		for c in _p_backup:
			_bm.player_party.append(c)
		for c in _e_backup:
			_bm.enemy_party.append(c)
		_bm.volatility = _vol_backup
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


func test_the_speculator_has_one_preset_per_stance() -> void:
	var mine := _mine()
	assert_eq(mine.size(), 3, "three stances, like every other covered job")
	var names: Array = []
	for t in mine:
		names.append(str((t as Dictionary).get("name", "")))
	names.sort()
	assert_eq(names, ["Aggressive", "Balanced", "Defensive"], "named for them: %s" % str(names))


func test_the_live_deep_check_accepts_every_rule() -> void:
	## Kit membership, unknown ids and the MP guard, computed by the engine rather than by a second
	## copy of ceil(cost / 65 * 100) in this file.
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
	assert_gt(checked, 10, "CONTROL: rules were submitted (%d)" % checked)
	assert_eq(refused.size(), 0, "the deep check refuses an authored rule: " + str(refused))


func test_the_catalog_offers_them_to_a_speculator() -> void:
	var cat = load("res://src/autobattle/AutobattleRuleTemplates.gd")
	assert_not_null(cat, "CONTROL: the catalog script loads")
	assert_gt((cat.find_for_job("fighter") as Array).size(), 0, "CONTROL: find_for_job works at all")
	assert_eq((cat.find_for_job(JOB) as Array).size(), 3,
		"a Speculator must be offered three presets")


func test_the_press_waits_for_the_band_and_then_stops() -> void:
	## The artifact, and the whole reason this catalog waited for .318. press_the_edge scales with
	## the band and CONSUMES a level, so the rule must fire when the band is worth it and yield once
	## it is spent — measured on one combatant with the band moved between turns.
	if _bm == null or _abs == null or _bm.volatility == null:
		pass_test("no battle autoloads in this harness")
		return
	var preset: Dictionary = {}
	for t in _mine():
		if str((t as Dictionary).get("id", "")) == "speculator_balanced":
			preset = t
	assert_false(preset.is_empty(), "CONTROL: the balanced preset was found to install")

	var c := Combatant.new()
	c.initialize({"name": "Pressing Spec", "max_hp": 700, "max_mp": 65,
		"attack": 90, "defense": 70, "magic": 110, "speed": 14})
	c.job = JobSystem.get_job(JOB)
	c.job_level = 10
	add_child_autofree(c)
	var foe := Combatant.new()
	foe.initialize({"name": "Edge Foe", "max_hp": 99999, "max_mp": 0,
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

	_bm.volatility.global_band = 3
	assert_eq(pick.call(), "press_the_edge", "band is worth it: cash out")
	_bm.volatility.global_band = 0
	assert_ne(pick.call(), "press_the_edge",
		"band spent: the press must yield to the rules below it rather than pressing an edge that "
		+ "is no longer there")


func test_forecast_is_left_out_and_still_deserves_to_be() -> void:
	## A scope note that cannot outlive its reason. forecast costs 5 MP and its handler emits a
	## battle-log line and nothing else — no damage, no buff, no band shift — so in a script it is a
	## turn spent on a message. If someone gives it a mechanical effect, this reds and the decision
	## to exclude it gets revisited instead of quietly standing.
	var blob: String = FileAccess.get_file_as_string(TEMPLATES)
	assert_false(blob.contains("\"id\": \"forecast\""),
		"forecast is excluded on purpose — if a preset now uses it, delete this arm and say why")

	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var idx: int = src.find("\t\t\"forecast\":")
	assert_gt(idx, -1, "CONTROL: the forecast handler arm was found to inspect")
	var arm: String = src.substr(idx, src.find("\n\t\t\"", idx + 5) - idx)
	var effects: Array = []
	for call in ["take_damage", "add_buff", "add_debuff", "add_status", "shift_band", "gain_ap"]:
		if arm.contains(call):
			effects.append(call)
	assert_eq(effects.size(), 0,
		"forecast now CHANGES something (%s) — it is no longer a readout, so a preset may want it: "
		% str(effects) + arm.strip_edges())
