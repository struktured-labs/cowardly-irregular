extends GutTest

## The grid editor could WRITE "Enemy weak to Fire" and nothing else. `_apply_condition_type` seeds a named payload
## (element fire, status poison, stat defense) and that was the only writer; the value dial rightly refused to invent
## a number for such a condition and offered nothing instead. So eight conditions were stuck on their seed for a
## hand-written rule: the Mage's "weak to ice -> Blizzara" could be pasted or composed by the LLM, never authored
## (cowir-main 24531 / 24540). The dial that cycles weather now walks every named payload through a vocabulary derived
## from the game's own data. Driven against the real editor, by keyboard and by pad.

const EDITOR := "res://src/ui/autobattle/AutobattleGridEditor.gd"

var _abs


var _persist_before = false


## Persistence OFF for the whole file: an editor that saves on change must never write a fixture over a player's script.
func before_each() -> void:
	_abs = get_tree().root.get_node_or_null("AutobattleSystem")
	assert_not_null(_abs, "CONTROL: AutobattleSystem autoload must exist")
	_persist_before = _abs._test_disable_persistence
	_abs._test_disable_persistence = true


func after_each() -> void:
	_abs._test_disable_persistence = _persist_before


func _editor(type: String = "hp_percent") -> Node:
	var e: Node = load(EDITOR).new()
	add_child_autofree(e)
	await get_tree().process_frame
	var rules: Array = e.get("rules") as Array
	rules.clear()
	rules.append({"conditions": [{"type": "hp_percent", "op": "<", "value": 50}], "actions": [{"type": "attack"}], "enabled": true})
	e.set("cursor_row", 0)
	e.set("cursor_col", 0)
	if type != "hp_percent":
		e.call("_apply_condition_type", type)
	return e


func _cond(e: Node) -> Dictionary:
	return ((e.get("rules") as Array)[0] as Dictionary)["conditions"][0] as Dictionary


## The types whose payload is a NAME and nothing else, derived: a required field, and no number after seeding.
func _named_types() -> Array:
	var out: Array = []
	for t in _abs.CONDITION_REQUIRED_FIELD.keys():
		var e: Node = await _editor(str(t))
		if not _cond(e).has("value") and str(t) != "weather":
			out.append(str(t))
	return out


func _key(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	return ev


func _stick(v: float) -> InputEventJoypadMotion:
	var ev := InputEventJoypadMotion.new()
	ev.axis = JOY_AXIS_RIGHT_Y
	ev.axis_value = v
	return ev


func test_the_floor_names_every_member_this_file_drives() -> void:
	var e: Node = await _editor()
	for f in ["_apply_condition_type", "_adjust_condition_value", "_handle_value_stick", "_format_condition", "_input", "_is_on_condition_cell"]:
		assert_true(e.has_method(f), "AutobattleGridEditor.%s must exist" % f)
	assert_true(e.has_method("payload_vocabulary"), "AutobattleGridEditor.payload_vocabulary must exist")
	assert_true(_abs.has_method("set_character_script") and "character_profiles" in _abs, "AutobattleSystem can hold a script to share")
	assert_true("CONDITION_REQUIRED_FIELD" in _abs and "CONDITION_TYPES" in _abs and _abs.has_method("validate_rule"), "AutobattleSystem's grammar maps and validator must exist")
	assert_true(e._is_on_condition_cell(), "PRECONDITION: the fixture's cursor is on a condition cell")


## THE ARM, with no list: every named-payload type reaches more than one value, comes back round, never gains a number,
## and the cell's text names what was chosen.
func test_the_dial_walks_every_named_payload() -> void:
	var types: Array = await _named_types()
	assert_gt(types.size(), 5, "CONTROL: the grammar has named-payload conditions (%s)" % [types])
	assert_true("enemy_weak_to" in types and "has_status" in types and "has_buff" in types, "CONTROL: the three families are in the walk: %s" % [types])
	for t in types:
		var e: Node = await _editor(t)
		var field: String = str(_abs.CONDITION_REQUIRED_FIELD[t])
		var seed: String = str(_cond(e).get(field, ""))
		var names: Array = load(EDITOR).payload_vocabulary(field)
		assert_gt(names.size(), 1, "%s: its %s has more than one value to choose" % [t, field])
		assert_eq(names[0], seed, "%s: the vocabulary starts at the seed '%s'" % [t, seed])
		var seen: Array = [seed]
		var texts: Array = [e._format_condition(_cond(e))]
		for i in names.size() - 1:
			e.call("_adjust_condition_value", 1)
			seen.append(str(_cond(e).get(field, "")))
			texts.append(e._format_condition(_cond(e)))
		assert_eq(seen, names.map(func(n): return str(n)), "%s: Up walks the whole vocabulary in order" % t)
		var distinct: Dictionary = {}
		for x in texts:
			distinct[x] = true
		assert_eq(distinct.size(), names.size(), "%s: the cell reads differently for every choice" % t)
		e.call("_adjust_condition_value", 1)
		assert_eq(str(_cond(e).get(field, "")), seed, "%s: one more step comes back to the seed" % t)
		e.call("_adjust_condition_value", -1)
		assert_eq(str(_cond(e).get(field, "")), str(names[names.size() - 1]), "%s: and Down goes the other way" % t)
		assert_false(_cond(e).has("value"), "%s: the dial still invents no number" % t)
		assert_false(_cond(e).has("op"), "%s: nor an operator" % t)


## By KEYBOARD (- / =) and by PAD (the right stick), through the editor's own input handlers, for EVERY named type.
func test_keyboard_and_pad_both_reach_the_second_value() -> void:
	var types: Array = await _named_types()
	assert_gt(types.size(), 5, "CONTROL: the walk has types (%s)" % [types])
	for t in types:
		var field: String = str(_abs.CONDITION_REQUIRED_FIELD[t])
		var names: Array = load(EDITOR).payload_vocabulary(field)
		var by_key: Node = await _editor(t)
		by_key._input(_key(KEY_EQUAL))
		assert_eq(str(_cond(by_key)[field]), str(names[1]), "%s: = steps its %s forward" % [t, field])
		by_key._input(_key(KEY_MINUS))
		assert_eq(str(_cond(by_key)[field]), str(names[0]), "%s: - steps it back" % t)
		var by_pad: Node = await _editor(t)
		assert_true(by_pad._handle_value_stick(_stick(1.0)), "CONTROL %s: the stick push is taken" % t)
		assert_eq(str(_cond(by_pad)[field]), str(names[1]), "%s: the right stick steps its %s" % [t, field])
		by_pad._handle_value_stick(_stick(1.0))
		assert_eq(str(_cond(by_pad)[field]), str(names[1]), "CONTROL %s: a held stick steps once, not every frame" % t)


## A script holding a payload the dial chose survives the share code: what a player writes, a friend can paste.
func test_a_chosen_payload_survives_the_share_code() -> void:
	var cid := "payload_probe_hero"
	var rules: Array = []
	for t in await _named_types():
		var field: String = str(_abs.CONDITION_REQUIRED_FIELD[t])
		var names: Array = load(EDITOR).payload_vocabulary(field)
		rules.append({"conditions": [{"type": t, field: names[names.size() - 1]}], "actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true})
	_abs.set_character_script(cid, {"character_id": cid, "name": "Named", "rules": rules.duplicate(true)})
	var decoded: Dictionary = ScriptShareManager.decode_share_code(ScriptShareManager.encode_share_code(cid))
	_abs.character_profiles.erase(cid)
	assert_false(decoded.is_empty(), "CONTROL: the code decodes")
	var back: Array = decoded.get("script", decoded).get("rules", [])
	assert_eq(back.size(), rules.size(), "every rule came back")
	for i in mini(back.size(), rules.size()):
		assert_eq(back[i]["conditions"][0], rules[i]["conditions"][0], "rule %d keeps its payload, the LAST of its vocabulary" % i)


## The element list is the game's own: every weakness a monster carries and every element an ability has can be chosen.
func test_every_element_the_game_has_can_be_chosen() -> void:
	var names: Array = load(EDITOR).payload_vocabulary("element")
	var monsters = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var weak: Dictionary = {}
	for m in (monsters.get("monsters", monsters) as Dictionary).values():
		if m is Dictionary:
			for w in m.get("weaknesses", []):
				weak[str(w)] = true
	assert_gt(weak.size(), 3, "CONTROL: monsters carry weaknesses (%s)" % [weak.keys()])
	for w in weak:
		assert_true(names.has(w), "'%s' is a weakness some monster has, so a rule can name it" % w)
	assert_true(names.has("ice") and names.has("lightning"), "the two the Mage's second and third spells answer")
	assert_false(names.has(""), "and no blank")


## A rule holding any reachable payload is one the validator accepts: what the dial writes, the game can run.
func test_every_reachable_payload_validates() -> void:
	var types: Array = await _named_types()
	var bad: Array = []
	var seen := 0
	for t in types:
		var field: String = str(_abs.CONDITION_REQUIRED_FIELD[t])
		for n in load(EDITOR).payload_vocabulary(field):
			seen += 1
			var errs: Array = _abs.validate_rule({"conditions": [{"type": t, field: n}], "actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true})
			if errs.size() > 0:
				bad.append("%s %s=%s: %s" % [t, field, n, errs])
	assert_gt(seen, 50, "CONTROL: the sweep judged real rules (%d)" % seen)
	assert_eq(bad, [], "every payload the dial can write validates: %s" % [bad])


## CONTROLS: a numbered condition still dials its number, a nullary one still does nothing, weather still cycles.
func test_the_other_conditions_dial_as_before() -> void:
	var num: Node = await _editor("hp_percent")
	num.call("_adjust_condition_value", 1)
	assert_eq(int(_cond(num)["value"]), 55, "hp_percent steps its number by 5")
	var none: Node = await _editor("always")
	var before: Dictionary = _cond(none).duplicate(true)
	none.call("_adjust_condition_value", 1)
	assert_eq(_cond(none), before, "a nullary condition has nothing to dial")
	var items: Node = await _editor("item_count")
	var item_before: String = str(_cond(items).get("item_id", ""))
	items.call("_adjust_condition_value", 1)
	assert_eq(str(_cond(items).get("item_id", "")), item_before, "item_count keeps its item and dials its NUMBER")
	assert_true(_cond(items).has("value"), "which it still has")
