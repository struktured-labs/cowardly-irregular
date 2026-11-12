extends GutTest

## An ability's description is the player's only statement of its numbers ("for 3 turns", "by 50%", "1.5x damage").
## Balance values move; the sentence beside them is typed by hand. Each number a description states is tied here to
## the field that enforces it, and a number no rule reads must be declared with a reason, so a new one is a decision.

## [pattern with ONE capture, the field it states, how: "eq" field == n · "pct" field × 100 == n · "mod" |field − 1| × 100 == n]
const RULES := [
	["(\\d+) turns?", "duration", "eq"],
	["by (\\d+)%", "stat_modifier", "mod"],
	["(\\d+(?:\\.\\d+)?)x damage", "damage_multiplier", "eq"],
	["(\\d+)% chance", "effect_chance", "pct"],
	["with (\\d+)% HP", "revive_percentage", "eq"],
	["volatility to (\\d+(?:\\.\\d+)?)", "stat_modifier", "eq"],
	["below (\\d+)% HP", "threshold", "pct"],
	["Summons (\\d+) ", "summon_count", "eq"],
	["(\\d+)% max MP", "mp_restore_percent", "pct"],
	["\\+(\\d+) AP", "ap_gain", "eq"],
	["bank (\\d+) AP", "bp_gain", "eq"],
	["up to (\\d+) deep", "max_depth", "eq"],
	["take (\\d+)% max HP", "recoil_pct", "pct"],
]

## "<ability id>:<number as written>" -> why no data field backs it
const DECLARED := {
	"regen:5": "the regen status's own default tick, 5% of max HP, lives in Combatant, not on the ability",
	"summon_shiva:3": "flavour: 'Retrieval takes 3-5 business ages'",
	"summon_shiva:5": "flavour: 'Retrieval takes 3-5 business ages'",
	"circuit_breaker:1": "the band step and the AP gain are the handler's constants",
	"press_the_edge:1": "the band level consumed is the handler's constant",
	"brave:2": "judged against the handler's own grant by test_all_in_says_what_it_grants",
}


func _abilities() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	return parsed if parsed is Dictionary else {}


## {"wrong": [...], "covered": {start offset: true}} for one ability's description.
func _judge(id: String, ability: Dictionary) -> Dictionary:
	var desc := str(ability.get("description", ""))
	var wrong := []
	var covered := {}
	for rule in RULES:
		var field := str(rule[1])
		if not ability.has(field):
			continue
		var re := RegEx.create_from_string(str(rule[0]))
		for m in re.search_all(desc):
			var stated := float(m.get_string(1))
			var value := float(ability[field])
			var want := value
			match str(rule[2]):
				"pct":
					want = value * 100.0
				"mod":
					want = absf(value - 1.0) * 100.0
			covered[m.get_start(1)] = true
			if absf(stated - want) > 0.001:
				wrong.append("%s says %s, its %s gives %s: \"%s\"" % [id, m.get_string(1), field, str(want), desc])
	return {"wrong": wrong, "covered": covered}


func test_a_stated_number_is_the_fields_number() -> void:
	var wrong := []
	var checked := 0
	var abilities := _abilities()
	for id in abilities:
		var a = abilities[id]
		if not a is Dictionary:
			continue
		var j := _judge(str(id), a)
		checked += (j["covered"] as Dictionary).size()
		wrong.append_array(j["wrong"])
	assert_gt(checked, 25, "CONTROL: the rules read the numbers the descriptions state (%d read)" % checked)
	assert_eq(wrong, [], "a description states a number its data does not give")


func test_every_stated_number_is_read_or_declared() -> void:
	var number := RegEx.create_from_string("\\d+(?:\\.\\d+)?")
	var loose := []
	var used := {}
	var abilities := _abilities()
	for id in abilities:
		var a = abilities[id]
		if not a is Dictionary:
			continue
		var covered: Dictionary = _judge(str(id), a)["covered"]
		for m in number.search_all(str(a.get("description", ""))):
			if covered.has(m.get_start()):
				continue
			var key := "%s:%s" % [id, m.get_string()]
			if DECLARED.has(key):
				used[key] = true
			else:
				loose.append("%s in \"%s\"" % [key, a.get("description", "")])
	assert_eq(loose, [], "a description states a number no rule reads: add a rule for its field, or declare it with a reason")
	var stale := []
	for key in DECLARED:
		if not used.has(key):
			stale.append(key)
		if str(DECLARED[key]).strip_edges() == "":
			stale.append("%s has no reason" % key)
	assert_eq(stale, [], "a declared number that no description states any more (or has no reason)")
