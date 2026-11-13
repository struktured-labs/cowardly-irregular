extends GutTest

## cowir-battle's `enemy_signature_in` (.795) counts boss turns to a signature's release, 1..every+charge_turns+1. The
## editor gave it the generic `< 50` seed, which is TRUE on every turn of every cadence fight, and autobattle is first
## match wins, so one such rule shadows every rule under it (the AP defect, test_an_ap_condition_is_not_born_always_true).
## Its seed is now `<= 1` (guard on the turn before it lands), its dial is bounded, and a bounded scale steps by 1:
## the same step-5 dial skipped volatility_band's middle (0..3), so Shifting and Unstable were unreachable.

const EDITOR := "res://src/ui/autobattle/AutobattleGridEditor.gd"

var _abs
var _profiles_backup: Dictionary = {}
var _persist_before := false


func before_each() -> void:
	_abs = get_tree().root.get_node_or_null("AutobattleSystem")
	assert_not_null(_abs, "CONTROL: AutobattleSystem autoload must exist")
	_profiles_backup = (_abs.character_profiles as Dictionary).duplicate(true)
	_persist_before = _abs._test_disable_persistence
	_abs._test_disable_persistence = true


func after_each() -> void:
	if _abs != null:
		_abs._test_disable_persistence = _persist_before
		var live: Dictionary = _abs.character_profiles
		live.clear()
		for k in _profiles_backup:
			live[k] = _profiles_backup[k]


## One rule, one condition, exactly as _add_and_condition leaves it: carrying hp_percent's `< 50`.
func _editor() -> Node:
	var ed: Node = load(EDITOR).new()
	add_child_autofree(ed)
	await get_tree().process_frame
	var rules: Array = ed.get("rules") as Array
	rules.clear()
	rules.append({"conditions": [{"type": "hp_percent", "op": "<", "value": 50}], "actions": [{"type": "attack"}], "enabled": true})
	ed.set("cursor_row", 0)
	ed.set("cursor_col", 0)
	return ed


func _cond(ed: Node) -> Dictionary:
	return ((ed.get("rules") as Array)[0] as Dictionary)["conditions"][0] as Dictionary


## The longest wait any authored cadence can show: every + charge_turns + 1 (BossCadence.turns_to_release on a fresh clock).
func _longest_authored_wait() -> int:
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var rows: Array = (raw as Dictionary).values()
	var longest := 0
	for m in rows:
		if m is Dictionary and (m as Dictionary).has("cadence"):
			var c: Dictionary = m["cadence"]
			longest = maxi(longest, int(c.get("every", 0)) + int(c.get("charge_turns", 0)) + 1)
	return longest


func test_the_floor_names_every_member_this_file_drives() -> void:
	var ed: Node = await _editor()
	for f in ["_apply_condition_type", "_adjust_condition_value"]:
		assert_true(ed.has_method(f), "AutobattleGridEditor.%s must exist" % f)
	assert_true("NUMERIC_BOUNDS" in ed and "rules" in ed and "cursor_row" in ed, "AutobattleGridEditor.NUMERIC_BOUNDS / rules / cursor_row must exist")
	assert_true(AutobattleSystem.CONDITION_TYPES.has("enemy_signature_in"), "the condition exists (cowir-battle's evaluator)")
	assert_has((load("res://src/battle/BossCadence.gd") as GDScript).get_script_method_list().map(func(m): return m["name"]), "turns_to_release", "BossCadence.turns_to_release must exist (the scale this dial follows)")


func test_the_seed_is_the_turn_before_the_release_not_always_true() -> void:
	var ed: Node = await _editor()
	ed.call("_apply_condition_type", "enemy_signature_in")
	var c := _cond(ed)
	assert_eq([str(c.get("op", "")), int(c.get("value", -1))], ["<=", 1], "a new signature rule fires on the boss's next turn")
	var longest := _longest_authored_wait()
	assert_gt(longest, 1, "CONTROL: monsters.json authors a cadence with a wait (%d)" % longest)
	## The defect: under the generic seed the rule held at EVERY wait a boss can show.
	assert_false(int(c["value"]) >= longest, "the seed is not true at the longest authored wait (%d)" % longest)


## The dial walks every value a boss can show, one at a time, and never past the authored range.
func test_the_dial_steps_one_turn_and_reaches_every_wait() -> void:
	var ed: Node = await _editor()
	ed.call("_apply_condition_type", "enemy_signature_in")
	var bounds: Array = ed.NUMERIC_BOUNDS["enemy_signature_in"]
	assert_gte(int(bounds[1]), _longest_authored_wait(), "the dial's top reaches the longest authored wait (%d)" % _longest_authored_wait())
	assert_eq(int(bounds[0]), 1, "and its floor is 1, the soonest a release can be")
	var seen: Array = [int(_cond(ed)["value"])]
	for i in 12:
		ed.call("_adjust_condition_value", 1)
		seen.append(int(_cond(ed)["value"]))
	for i in range(1, seen.size()):
		assert_lte(absi(seen[i] - seen[i - 1]), 1, "one press moves one turn (%s)" % [seen])
	assert_eq(seen.max(), int(bounds[1]), "and stops at the top")


## The same step rule reaches volatility_band's middle: 0..3 with a step of 5 only ever clamped between 0 and 3.
func test_a_bounded_band_dial_reaches_its_middle() -> void:
	var ed: Node = await _editor()
	ed.call("_apply_condition_type", "volatility_band")
	var seen := {}
	seen[int(_cond(ed)["value"])] = true
	for d in [-1, -1, -1, -1, 1, 1, 1, 1]:
		ed.call("_adjust_condition_value", d)
		seen[int(_cond(ed)["value"])] = true
	var got: Array = seen.keys()
	got.sort()
	assert_eq(got, [0, 1, 2, 3], "the band dial visits Stable, Shifting, Unstable and Fractured")


## CONTROL: a percentage still steps by 5, so the rule above did not flatten every dial.
func test_a_percentage_still_steps_by_five() -> void:
	var ed: Node = await _editor()
	var before := int(_cond(ed)["value"])
	ed.call("_adjust_condition_value", 1)
	assert_eq(int(_cond(ed)["value"]) - before, 5, "hp_percent moves 5 a press, as before")
