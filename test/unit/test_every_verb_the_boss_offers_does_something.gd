extends GutTest

## ⛔ FIVE OF THE 24 VERBS A BOSS OFFERS THE PLAYER DID NOTHING. The command menu presents each
## boss's authored `verbs` as labelled actions — Parley, Concede, Outlast, Race, Persist — and
## BattleCommandMenu's own comment says they "can BACKFIRE, by design (see
## jailbreak_vulnerabilities)". Measured 2026-10-12 through BossDialogue.check_jailbreak itself:
##
##   cave_rat_king/parley · pyrroth/concede · glacius/outlast
##   voltharion/race      · umbraxis/persist        -> null, every time
##
## Each boss carries FOUR verbs and THREE vulnerabilities, so the fourth was inert by construction.
## Mordaine is the apparent exception and fires only by accident of wording: `plead` happens to
## contain a keyword of `appeal_old_loyalty`. So the 4-and-3 shape was never "the fourth is
## deliberately silent" — it was unfinished, and one boss's wording hid it.
##
## 🔑 FIXED AS KEYWORDS, NOT AS NEW MECHANICS. Each dead verb's own directive already names the
## vulnerability it is plainly aiming at — "name your terms" at the tribute that adjourns court,
## "realest fight / burn us cleanly" at honest-combat respect, "defer and stall / outlast a glacier"
## at the you-are-predictable stagger, "out-Advance you / bet we can" at the overcharge that takes
## the bait, "remember you / persist in memory" at the comfort that dissolves the dread. Phrases
## rather than bare words, because the matcher treats a spaced phrase as a plain substring and a
## single word with word boundaries — so a phrase cannot fire on an unrelated free-text directive.
##
## 📌 This asks the REAL function, never a replica of its matcher: check_jailbreak also enforces a
## CONSEQUENCE_ALLOWLIST, so a verb can match an authored vulnerability and still correctly return
## null. A reimplementation of `_keyword_present` would have scored those as live.

const DATA := "res://data/boss_dialogue.json"
const MIN_BOSSES := 4
const MIN_VERBS := 16


func _bosses() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	assert_true(parsed is Dictionary, "CONTROL: %s must parse" % DATA)
	return parsed


## [[boss_id, verb_id, directive], …] — every verb the menu can offer a player.
func _offered() -> Array:
	var out: Array = []
	for boss_id in _bosses():
		var entry: Variant = _bosses()[boss_id]
		if not (entry is Dictionary):
			continue
		for v in ((entry as Dictionary).get("verbs", []) as Array):
			if v is Dictionary and str((v as Dictionary).get("directive", "")) != "":
				out.append([str(boss_id), str((v as Dictionary).get("id", "")), str((v as Dictionary).get("directive", ""))])
	return out


## ⛔ ONLY the keys that are actually a boss. `boss_dialogue.json` carries a top-level `_comment`
## STRING, and `BossDialogue.has_entry` returns TRUE for it (it only asks `_data.has(id)`), so
## `check_jailbreak("_comment", …)` reaches `var entry: Dictionary = _data[boss_id]` and throws
## "Trying to assign value of type 'String' to a variable of type 'Dictionary'" — measured, three
## times, in the first run of this file. Not reachable from the live caller, which passes a real
## boss id; reported to the file's owner rather than patched from a content branch.
func _boss_ids() -> Array[String]:
	var out: Array[String] = []
	for key in _bosses():
		if _bosses()[key] is Dictionary:
			out.append(str(key))
	return out


func test_a_non_boss_key_is_declared_and_never_queried() -> void:
	## The data file is content; this arm is what stops a second `_comment` from reaching a consumer
	## that types the entry as a Dictionary. Every top-level key is a boss or one of these.
	const NON_BOSS: Array[String] = ["_comment"]
	var surprises: Array[String] = []
	for key in _bosses():
		if not (_bosses()[key] is Dictionary) and not NON_BOSS.has(str(key)):
			surprises.append("%s (%s)" % [key, type_string(typeof(_bosses()[key]))])
	assert_eq(surprises, ([] as Array[String]),
		"a non-Dictionary top-level key will throw in any consumer that types the entry: %s" % [surprises])
	for key in NON_BOSS:
		assert_true(_bosses().has(key), "CONTROL: %s must still exist, or this declaration is an excuse for nothing" % key)
		assert_true(BossDialogue.has_entry(key),
			"CONTROL: has_entry still admits %s — the fragility this arm documents is still live" % key)


func test_the_corpora_are_real() -> void:
	assert_gt(_boss_ids().size(), MIN_BOSSES, "CONTROL: only %d bosses read" % _boss_ids().size())
	assert_gt(_offered().size(), MIN_VERBS, "CONTROL: only %d verbs read" % _offered().size())
	## The matcher must be able to say NO, or "everything fires" means nothing.
	assert_null(BossDialogue.check_jailbreak("cave_rat_king", "we attack with a sword and say nothing of note"),
		"CONTROL: an unrelated directive must fire no vulnerability")


func test_every_offered_verb_fires_a_vulnerability() -> void:
	## ⛔ THE ARM. A labelled action that resolves to null is a promise the menu makes and the engine
	## does not keep — and nothing else in the suite compares the two tables.
	var dead: Array[String] = []
	for row in _offered():
		if BossDialogue.check_jailbreak(str(row[0]), str(row[2])) == null:
			dead.append("%s/%s" % [row[0], row[1]])
	assert_eq(dead, ([] as Array[String]),
		"these verbs are offered to the player and resolve to nothing: %s" % [dead])


func test_a_verb_lands_a_consequence_the_allowlist_permits() -> void:
	## check_jailbreak returns null for a consequence outside CONSEQUENCE_ALLOWLIST, so a verb could
	## be authored, matched, and still silent. This proves what each one LANDS, not merely that it hit.
	var kinds: Array[String] = []
	for row in _offered():
		var got: Variant = BossDialogue.check_jailbreak(str(row[0]), str(row[2]))
		assert_not_null(got, "%s/%s resolves to nothing" % [row[0], row[1]])
		var ctype: String = str(((got as Dictionary).get("consequence", {}) as Dictionary).get("type", ""))
		assert_true(BossDialogue.CONSEQUENCE_ALLOWLIST.has(ctype),
			"%s/%s lands '%s', which the allowlist does not permit" % [row[0], row[1], ctype])
		if not kinds.has(ctype):
			kinds.append(ctype)
	assert_gt(kinds.size(), 1, "CONTROL: the verbs must land more than one kind of consequence, saw %s" % [kinds])


func test_a_phrase_keyword_does_not_fire_on_an_unrelated_directive() -> void:
	## The cost of widening keywords is a false trigger on free text, so the added keywords are
	## PHRASES. A phrase is matched as a plain substring, so it cannot fire on a directive that does
	## not contain it — which is what keeps "Parley" from arming the tribute for anyone who says
	## "terms of service".
	var decoys: Array[String] = [
		"I accept your terms of service and move on",
		"we remember the way out of this cave",
		"the fight is real but we are tired",
	]
	var fired: Array[String] = []
	for boss_id in _boss_ids():
		for decoy in decoys:
			if BossDialogue.check_jailbreak(str(boss_id), decoy) != null:
				fired.append("%s <- %s" % [boss_id, decoy])
	assert_eq(fired, ([] as Array[String]), "an unrelated directive armed a vulnerability: %s" % [fired])
