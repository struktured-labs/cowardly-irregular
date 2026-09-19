extends GutTest

## Pressing "Aggressive" or "Defensive" in the autobattle menu applied a script whose EVERY
## condition evaluated false, and on the next boot the migration silently replaced it with the
## character's job default — discarding the choice.
##
##   MenuScene:1227  presets = ["Aggressive", "Defensive"]     two buttons
##   :1274           AutobattleSystem.load_script(name)         -> saved_scripts[name]
##   :1277           set_character_script(char_id, script)      APPLIED to the character
##   _create_default_scripts built them through create_condition/create_rule, which emit
##     {"type": <ConditionType int>, "compare_op": <CompareOp int>, "action_type": <int>}
##   _evaluate_grid_condition:263 reads condition.get("type") as a STRING against 24 string ids
##                           :264 reads condition.get("op")   — a DIFFERENT KEY
##   -> no arm matches an int -> push_warning + return false, for every rule in both presets
##
## ⚠️ TWO AXES, AND FIXING ONLY THE TYPE IS WORSE THAN THE BUG (cowir-main): `op` is absent, so
## `get("op", "==")` substitutes a LEGAL default before _compare_str can warn. `mp_percent >= 30`
## would silently become `mp_percent == 30` — a rule that fires on one integer and looks correct.
##
## Rebuilt as literals in the shape the catalog authors and the per-job builders already emit.
## `BattleScene:477` reaches the same data via set_autobattle_script("Aggressive").

const AutobattleScript = preload("res://src/autobattle/AutobattleSystem.gd")

var _ab


func before_each() -> void:
	_ab = AutobattleScript.new()
	if "_test_disable_persistence" in _ab:
		_ab._test_disable_persistence = true
	add_child_autofree(_ab)
	_ab._create_default_scripts()


func _preset_conditions() -> Array:
	var out: Array = []
	for name in ["Aggressive", "Defensive"]:
		for rule in _ab.saved_scripts[name]["rules"]:
			for c in rule["conditions"]:
				out.append(c)
	return out


func test_both_presets_exist_with_rules() -> void:
	## CONTROL: everything below is vacuous if the builder produced nothing.
	for name in ["Aggressive", "Defensive"]:
		assert_true(_ab.saved_scripts.has(name), "the menu offers '%s' and it must exist" % name)
		assert_gt(_ab.saved_scripts[name]["rules"].size(), 1, "'%s' must carry rules" % name)
	assert_gt(_preset_conditions().size(), 4, "CONTROL: conditions must be findable")


func test_no_preset_condition_carries_a_numeric_type() -> void:
	## AXIS 1. An int reaches no string arm, so the condition is permanently false.
	var numeric: Array[String] = []
	for c in _preset_conditions():
		var t = c.get("type")
		if typeof(t) == TYPE_INT or typeof(t) == TYPE_FLOAT:
			numeric.append(str(t))
	assert_eq(numeric.size(), 0,
		"a preset condition carries an ENUM type the live evaluator cannot match: " + str(numeric))


func test_every_preset_condition_uses_the_op_key() -> void:
	## AXIS 2, and the one that cannot warn: get("op", "==") substitutes a legal default, so a
	## condition keyed `compare_op` evaluates as `==` in silence.
	var wrong: Array[String] = []
	for c in _preset_conditions():
		if c.has("compare_op"):
			wrong.append(str(c.get("type", "?")))
		if c.has("value") and not c.has("op"):
			wrong.append("%s has a value and no op" % str(c.get("type", "?")))
	assert_eq(wrong.size(), 0, "a preset condition uses the key the evaluator does not read: " + str(wrong))


func test_every_preset_condition_is_a_type_the_evaluator_knows() -> void:
	## Derived from the evaluator's own arms rather than a hand list, so a renamed id reds here.
	var src: String = FileAccess.get_file_as_string("res://src/autobattle/AutobattleSystem.gd")
	var i: int = src.find("func _evaluate_grid_condition")
	var j: int = src.find("\nfunc ", i + 10)
	var known: Dictionary = {}
	for m in RegEx.create_from_string("(?m)^\\t\\t\"([a-z_]+)\"").search_all(src.substr(i, j - i)):
		known[m.get_string(1)] = true
	assert_gt(known.size(), 15, "CONTROL: the evaluator's arms must be findable")
	var unknown: Array[String] = []
	for c in _preset_conditions():
		var t: String = str(c.get("type", ""))
		if not known.has(t):
			unknown.append(t)
	assert_eq(unknown.size(), 0, "a preset names a condition type the evaluator has no arm for: " + str(unknown))


func test_a_preset_condition_actually_evaluates_true() -> void:
	## The consequence. The shape being right is the mechanism; this is the property.
	var c := Combatant.new()
	c.initialize({"name": "Hero", "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	c.current_mp = c.max_mp
	var fired: int = 0
	for cond in _preset_conditions():
		if str(cond.get("type", "")) == "always":
			if _ab._evaluate_grid_condition(c, cond):
				fired += 1
	assert_gt(fired, 0, "an `always` condition in a shipped preset must evaluate TRUE")


func test_every_preset_action_is_one_the_executor_runs() -> void:
	## The third axis: create_rule wrote `action_type` as an int, and _action_type_to_string maps
	## DEFAULT to "defend" — a spelling the executor has no arm for and the catalog never uses.
	var allowed := ["attack", "ability", "item", "defer"]
	var bad: Array[String] = []
	for name in ["Aggressive", "Defensive"]:
		for rule in _ab.saved_scripts[name]["rules"]:
			assert_true(rule.has("actions"), "a preset rule must carry an `actions` array, not action_type")
			for a in rule.get("actions", []):
				if not allowed.has(str(a.get("type", ""))):
					bad.append(str(a.get("type", "")))
	assert_eq(bad.size(), 0, "a preset action names a type the executor cannot run: " + str(bad))


func test_the_migration_no_longer_calls_these_old_format() -> void:
	## _migrate_old_format_scripts resets any character script whose condition type is numeric. If a
	## preset still tripped it, applying one would survive the session and vanish on the next boot.
	for c in _preset_conditions():
		var t = c.get("type")
		assert_false(typeof(t) == TYPE_INT or typeof(t) == TYPE_FLOAT,
			"the boot migration would flag this preset as old-format and discard the player's choice")
