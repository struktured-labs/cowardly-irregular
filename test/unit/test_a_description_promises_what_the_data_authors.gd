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

## ⛔ KEY PRESENCE IS NOT ENOUGH FOR A STATUS, and my first version checked only presence. An ability
## promising POISON while authoring `effect: "defense_down"` has an `effect` key, so a presence test
## calls it honoured. Mutation-proved: I rewrote acid_splash's description to promise poison and the
## sweep stayed GREEN. Status promises now check the VALUE.
##
## Word must appear in the authored `effect` / `secondary_effect` VALUE.
const STATUS_PROMISES := ["poison", "blind", "silence", "sleep", "confus", "stun", "doom", "charm"]

## Word is honoured by the PRESENCE of any of these keys — none of them carries a name to match.
const KEY_PROMISES := {
	"steal": ["steals", "drain_percentage"],
	"crit": ["crit_chance"],
	"revive": ["revive_percentage"],
	"twice": ["hits"],
	"three times": ["hits"],
	"drains mp": ["drain_mp", "mp_amount"],
	"drains magical energy": ["drain_mp", "mp_amount"],
	"restoring mp": ["drain_mp", "mp_amount", "mp_restore_percent"],
}

## A promise the data does not author, with who holds the call. Every entry is a BALANCE decision or
## a declared flavour reading — never a defect someone forgot.
const DECLARED := {
	"shadow_step:crit": "support; the guaranteed crit IS delivered, through the shadow_step STATUS rather than a crit_chance key (_calculate_crit_chance returns 1.0 for it, BattleManager:5272). The description is honest and the key is simply not how — declared so nobody 'fixes' a working ability. ⚠️ This entry was DELETED and restored within one pass: under the loose map `effect` satisfied 'crit' and the stale-declaration arm correctly removed it; under the value-checking map it is a finding again. The declaration follows the instrument, which is the point of having the arm both ways",
	"masterite_haste:blind": "support; FLAVOUR, declared rather than pattern-matched away. \"Accelerates to BLINDING speed\" is an adverb, not the blind status. A boundary at the word START is required — descriptions legitimately say \"blinds the target\" — so a stem match cannot separate the two and a human reading is the only instrument. Declared, not silenced",
	"masterite_time_tax:steal": "support; FLAVOUR, same shape. \"STEALS moments from every opponent\" is a speed debuff written in the Curator's voice; the ability authors stat_modifier and means it. Declared",
	"masterite_mana_drain:drains magical energy": "magic; authors NO drain_mp while the mechanic exists and two abilities use it (data_drain 20, memory_drain 15). Cast by all six masterite_curator_* bosses, whose whole theme is attacking resources — CLAUDE.md's Curator Lens is an MP tithe. Wiring it restores the boss's own MP and makes the fight longer. struktured's call, not a repair",
}


func _abilities() -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ABILITIES))
	return data.get("abilities", data)


## ⛔ SUBSTRING MATCHING ON PROSE FINDS FLAVOUR. "accelerates to BLINDING speed" is not the blind
## status; "STEALS moments" is a speed debuff. My first tightening produced three such hits out of
## four. A promise is a WHOLE WORD (or a word stem at a word start) — checked with a boundary rather
## than declared away one adjective at a time, because the next flavour word would need another line.
func _promised(desc: String, word: String) -> bool:
	var re := RegEx.create_from_string("\\b" + word)
	return re.search(desc) != null


## Every (ability, promise) whose description makes a claim the data does not honour.
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
		var authored_effects: String = "%s %s" % [
			str(d.get("effect", "")).to_lower(), str(d.get("secondary_effect", "")).to_lower()]
		for word in STATUS_PROMISES:
			if _promised(desc, word) and not authored_effects.contains(word):
				out["%s:%s" % [id, word]] = desc
		for word in KEY_PROMISES:
			if not _promised(desc, str(word)):
				continue
			if authored_effects.contains(str(word)):
				continue  ## "steal" is honoured by effect: "steal" as well as by the steals flag
			var honoured: bool = false
			for key in KEY_PROMISES[word]:
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
	assert_gt(STATUS_PROMISES.size() + KEY_PROMISES.size(), 10,
		"the promise map must be wide enough to be about something")


func test_a_promise_word_matches_something_in_the_corpus() -> void:
	## NAMED-MEMBER control: if no description contained any promise word, the sweep would return
	## empty for a reason that has nothing to do with the data being honest.
	var abilities: Dictionary = _abilities()
	var matched: Array = []
	var all_words: Array = STATUS_PROMISES.duplicate()
	for w in KEY_PROMISES:
		all_words.append(w)
	for word in all_words:
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
		## ⚠️ CASE-INSENSITIVE, because my first version was not and fired on a reason ending
		## "Declared". The arm was wrong, not the declaration — @cowir-controller's rule from this
		## morning: when you are checking for the presence of a token, use the loosest pattern that
		## can match. A capital letter is not a missing reason.
		var lowered: String = reason.to_lower()
		assert_true(lowered.contains("struktured") or lowered.contains("declared") or lowered.contains("flavour"),
			"%s must name whose call it is, or record that the behaviour is delivered another way" % k)
