extends GutTest

## ⛔ THE DESCRIPTION IS THE CONTRACT WITH THE PLAYER, and nothing checked it against the data.
## `test_an_authored_key_reaches_the_path_its_ability_takes` asks whether an authored key is READ.
## This asks the mirror question: whether a promised BEHAVIOUR is authored at all. An ability whose
## text says it drains MP and which authors no `drain_mp` is not a wiring gap — there is nothing to
## wire. It reads as complete from every angle except the sentence the player sees.
##
## Found by sweeping descriptions for mechanic words against the keys that would make them real.
## The sweep's first pass produced five hits and FOUR were false positives, which is why the map
## below lists every key that can satisfy a promise rather than the obvious one — `drain_life` says
## "steal HP" and authors `drain_percentage`, not `steals`.
##
## ⚠️ NOT A CLAIM THAT THE SURVIVOR SHOULD BE WIRED. It makes a boss stronger, which is struktured's
## call exactly like the other balance items this lane is holding.
##
## ⛔ AND THE STALE-DECLARATION ARM FIRED ON MY OWN FIRST DRAFT. I declared `shadow_step:crit` as
## "delivered through the status rather than the key" — true, and not a finding under this map:
## shadow_step authors `effect`, which is one of the keys "crit" accepts, so the sweep never flagged
## it and the declaration described nothing. A declaration for a case the instrument does not produce
## is worse than none, because the next reader takes it as evidence the instrument produced it.

const ABILITIES := "res://data/abilities.json"

## promise word in the description -> EVERY key that could honour it. A word is satisfied if the
## ability authors ANY of them, so a narrow map is what produces false positives rather than findings.
const PROMISES := {
	"poison": ["effect"],
	"stun": ["effect"],
	"blind": ["effect"],
	"silence": ["effect"],
	"sleep": ["effect"],
	"confus": ["effect"],
	"steal": ["steals", "drain_percentage", "effect"],
	"crit": ["crit_chance", "effect"],
	"revive": ["revive_percentage", "effect"],
	"twice": ["hits"],
	"three times": ["hits"],
	"drains mp": ["drain_mp", "mp_amount"],
	"drains magical energy": ["drain_mp", "mp_amount"],
	"restoring mp": ["drain_mp", "mp_amount", "mp_restore_percent"],
}

## A promise the data does not author, with who holds the call. Every entry is a BALANCE decision or
## a declared flavour reading — never a defect someone forgot.
const DECLARED := {
	"masterite_mana_drain:drains magical energy": "magic; authors NO drain_mp while the mechanic exists and two abilities use it (data_drain 20, memory_drain 15). Cast by all six masterite_curator_* bosses, whose whole theme is attacking resources — CLAUDE.md's Curator Lens is an MP tithe. Wiring it restores the boss's own MP and makes the fight longer. struktured's call, not a repair",
}


func _abilities() -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ABILITIES))
	return data.get("abilities", data)


## Every (ability, promise) whose description makes a claim the data authors no key for.
func _unhonoured() -> Dictionary:
	var out: Dictionary = {}
	var abilities: Dictionary = _abilities()
	for id in abilities:
		var d = abilities[id]
		if not (d is Dictionary):
			continue
		var desc: String = str(d.get("description", "")).to_lower()
		if desc == "":
			continue
		for word in PROMISES:
			if not desc.contains(str(word)):
				continue
			var honoured: bool = false
			for key in PROMISES[word]:
				if d.has(key):
					honoured = true
					break
			if not honoured:
				out["%s:%s" % [id, word]] = desc
	return out


func test_the_sweep_reads_a_real_corpus() -> void:
	## CONTROL and anti-vacuity: an empty abilities file, or a promise map nothing matches, would make
	## every arm below pass over nothing.
	var abilities: Dictionary = _abilities()
	assert_gt(abilities.size(), 200, "VOID, not clean: abilities.json read back %d entries" % abilities.size())
	var described: int = 0
	for id in abilities:
		if abilities[id] is Dictionary and str(abilities[id].get("description", "")) != "":
			described += 1
	assert_gt(described, 200, "and %d of them carry a description, which is what this file reads" % described)
	assert_gt(PROMISES.size(), 5, "the promise map must be wide enough to be about something")


func test_a_promise_word_matches_something_in_the_corpus() -> void:
	## NAMED-MEMBER control: if no description contained any promise word, the sweep would return
	## empty for a reason that has nothing to do with the data being honest.
	var abilities: Dictionary = _abilities()
	var matched: Array = []
	for word in PROMISES:
		for id in abilities:
			var d = abilities[id]
			if d is Dictionary and str(d.get("description", "")).to_lower().contains(str(word)):
				matched.append(word)
				break
	assert_gt(matched.size(), 5, "most promise words must appear somewhere, or the map describes another game: %s" % str(matched))
	assert_true(matched.has("poison"), "NAMED MEMBER: 'poison' is promised by real descriptions")


func test_no_description_promises_what_the_data_never_authors() -> void:
	var found: Dictionary = _unhonoured()
	var undeclared: Array = []
	for k in found:
		if not DECLARED.has(k):
			undeclared.append("%s — \"%s\"" % [k, found[k]])
	assert_eq(undeclared.size(), 0,
		"an ability's text promises a mechanic its data does not author. Author the key, reword the description, or DECLARE it with who holds the call: " + str(undeclared))


func test_a_declaration_does_not_outlive_the_thing_it_declares() -> void:
	## The same arm the axis-2 ledger carries: the moment a promise is honoured, the declaration
	## becomes a lie the next reader trusts. Reds in the GOOD direction.
	var found: Dictionary = _unhonoured()
	var stale: Array = []
	for declared in DECLARED:
		if not found.has(declared):
			stale.append(declared)
	assert_eq(stale.size(), 0,
		"GOOD NEWS: these promises are honoured now — delete the line(s) from DECLARED: " + str(stale))


func test_the_declared_set_names_who_decides() -> void:
	## Every entry is a balance call or a declared reading, and must say which. A bare exemption is
	## the suppression flag CLAUDE.md refuses: you cannot silence it green, only explain it green.
	for k in DECLARED:
		var reason: String = str(DECLARED[k])
		assert_gt(reason.length(), 60, "%s needs a real reason, not a tag" % k)
		assert_true(reason.contains("struktured") or reason.contains("declared"),
			"%s must name whose call it is, or record that the behaviour is delivered another way" % k)
