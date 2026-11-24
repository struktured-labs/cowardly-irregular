extends GutTest

## Summon Boost said "+35% summon damage and duration" while its data gives +35% magic and ONE extra turn.
## A passive's, an item's or a piece of equipment's description is typed by hand beside values that balance moves.
## Every number such a description states must be a reading of some number in that entry's own data, or be
## declared with a reason. (Abilities have the stricter, field-by-field guard: test_a_description_states_the_datas_number.)

## file -> the keys of an entry that hold its numbers
const SOURCES := {
	"res://data/passives.json": ["stat_mods", "meta_effects", "conditional_mods", "restrictions"],
	"res://data/items.json": ["effects"],
	"res://data/equipment.json": ["stat_mods", "special_effects"],
}
## A number as written: not part of a word, a hex code or a longer number ("W4", "#4A7FD4").
const NUMBER := "(?<![#A-Za-z0-9.])\\d+(?:\\.\\d+)?"

## "<entry id>:<number as written>" -> why none of the entry's own data backs it
const DECLARED := {
	"devastating_criticals:1.5": "the base critical multiplier lives in BattleManager; the text shows it before the bonus",
	"devastating_criticals:2.0": "base 1.5 plus this passive's 0.5, shown as the result",
	"last_stand:25": "the threshold is the condition's own key, hp_below_25, not a value",
	"death_resistance:1": "surviving at 1 HP is the handler's constant",
}


func _leaves(v: Variant, out: Array) -> void:
	if v is Dictionary:
		for k in v:
			_leaves(v[k], out)
	elif v is Array:
		for item in v:
			_leaves(item, out)
	elif v is float or v is int:
		out.append(float(v))


## How a value may be written: itself (3 turns), unsigned (-100 defense), as a percentage (0.25 -> 25%),
## or as a multiplier's distance from one (1.35 -> +35%, 0.6 -> -40%).
func _states(stated: float, value: float) -> bool:
	for reading in [value, absf(value), value * 100.0, absf(value - 1.0) * 100.0]:
		if absf(stated - reading) < 0.001:
			return true
	return false


## {"loose": ["id:number …"], "judged": entries with numbers of their own, "numbers": stated numbers read,
##  "seen": {"id:number": true}} over every entry of every source.
func _census(sources: Dictionary) -> Dictionary:
	var out := {"loose": [], "judged": 0, "numbers": 0, "seen": {}}
	var number := RegEx.create_from_string(NUMBER)
	for path in sources:
		_walk(JSON.parse_string(FileAccess.get_file_as_string(path)), "", sources[path], number, out)
	return out


func _walk(node: Variant, id: String, keys: Array, number: RegEx, out: Dictionary) -> void:
	if node is Array:
		for item in node:
			_walk(item, id, keys, number, out)
		return
	if not node is Dictionary:
		return
	var values := []
	for k in keys:
		_leaves(node.get(k), values)
	if node.get("description") is String and not values.is_empty():
		out["judged"] += 1
		for m in number.search_all(node["description"]):
			out["numbers"] += 1
			var key := "%s:%s" % [id, m.get_string()]
			out["seen"][key] = true
			var backed := false
			for v in values:
				backed = backed or _states(float(m.get_string()), v)
			if not backed and not DECLARED.has(key):
				out["loose"].append("%s  (\"%s\"; its data holds %s)" % [key, node["description"], str(values)])
	for k in node:
		if not k in keys:
			_walk(node[k], str(k), keys, number, out)


func test_the_readings_are_the_four_a_description_uses() -> void:
	assert_true(_states(3.0, 3.0), "3 turns is 3")
	assert_true(_states(25.0, 0.25), "0.25 is 25%")
	assert_true(_states(35.0, 1.35) and _states(40.0, 0.6), "a multiplier is its distance from one")
	assert_true(_states(100.0, -100.0), "a penalty is written unsigned")
	assert_false(_states(35.0, 1.0), "CONTROL: one extra turn is not 35 of anything")
	var number := RegEx.create_from_string(NUMBER)
	assert_eq(number.search_all("W4 sky #4A7FD4, 3 turns").size(), 1, "a world tag and a hex code are not stated numbers")


func test_a_stated_number_is_in_the_entrys_own_data() -> void:
	var c := _census(SOURCES)
	assert_gt(c["judged"], 80, "CONTROL: passives, items and equipment with numbers of their own were read")
	assert_gt(c["numbers"], 40, "CONTROL: their descriptions state numbers")
	assert_eq(c["loose"], [], "a description states a number its entry's data does not hold")


func test_summon_boost_says_one_more_turn() -> void:
	var passives: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/passives.json"))
	var found := []
	_find(passives, "summon_boost", found)
	assert_eq(found.size(), 1, "CONTROL: summon_boost is authored once")
	if found.size() != 1:
		return
	var entry: Dictionary = found[0]
	var turns := int((entry.get("meta_effects", {}) as Dictionary).get("summon_duration_bonus", 0))
	assert_gt(turns, 0, "CONTROL: it extends a summon by whole turns")
	assert_string_contains(str(entry["description"]), "%d turn" % turns)
	assert_false(str(entry["description"]).contains("damage and duration"), "the duration is not a share of the percentage")


func _find(node: Variant, id: String, out: Array) -> void:
	if node is Dictionary:
		if node.has(id) and node[id] is Dictionary:
			out.append(node[id])
		for k in node:
			_find(node[k], id, out)


func test_every_declared_number_is_still_stated() -> void:
	var seen: Dictionary = _census(SOURCES)["seen"]
	var stale := []
	for key in DECLARED:
		if not seen.has(key):
			stale.append(key)
	assert_eq(stale, [], "a DECLARED number no description states any more")
