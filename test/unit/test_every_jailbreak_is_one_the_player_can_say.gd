extends GutTest

## A jailbreak vulnerability is only content if some line the player can actually
## PICK trips it. The player never types: "Address the Boss" offers that boss's
## authored `verbs`, and their `directive` text is what reaches check_jailbreak.
##
## ⛔ Umbraxis's `dissolve_the_dread` was unreachable in the whole game, and not for
## a missing phrase. Its verb exists and was written for it — `console` says "the
## fear is real to you. That counts." which carries TWO of its keywords. But
## `question_the_fight` is authored FIRST and listed "authored", which that same
## line also contains ("Even if it's authored…"), and check_jailbreak returns the
## first match. So the comforting line tripped the wrong vulnerability — a stronger
## consequence (skip_turn) than the one the author wrote (taunt_softens) — and one
## of the game's fifteen vulnerabilities could never fire.
##
## Measured before the fix: 14 of 15 reachable. After: 15 of 15.
##
## This guards REACHABILITY, which is what shadowing breaks. A keyword collision
## does not make any rule invalid — both entries stay well-formed — so no data
## integrity test can see it.

const BOSS_DATA := "res://data/boss_dialogue.json"

var _bd = null


func before_each() -> void:
	_bd = get_tree().root.get_node_or_null("BossDialogue")
	assert_not_null(_bd, "CONTROL: BossDialogue autoload must be reachable")


func _bosses() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(BOSS_DATA))
	assert_not_null(parsed, "CONTROL: boss_dialogue.json must parse")
	return (parsed as Dictionary).get("bosses", parsed)


## vulnerability_id -> the verb id whose directive trips it, via the LIVE matcher.
func _reachable_for(boss_id: String, entry: Dictionary) -> Dictionary:
	var hits: Dictionary = {}
	for v in entry.get("verbs", []):
		if not (v is Dictionary):
			continue
		var res: Variant = _bd.check_jailbreak(boss_id, str((v as Dictionary).get("directive", "")))
		if res is Dictionary:
			var vid: String = str((res as Dictionary).get("vulnerability_id", ""))
			if not hits.has(vid):
				hits[vid] = str((v as Dictionary).get("id", "?"))
	return hits


func test_every_authored_vulnerability_is_reachable() -> void:
	var total: int = 0
	var unreachable: Array = []
	for boss_id in _bosses():
		var entry: Variant = _bosses()[boss_id]
		if not (entry is Dictionary):
			continue
		var vulns: Array = (entry as Dictionary).get("jailbreak_vulnerabilities", [])
		if vulns.is_empty():
			continue
		var hits: Dictionary = _reachable_for(str(boss_id), entry as Dictionary)
		for vu in vulns:
			total += 1
			var vid: String = str((vu as Dictionary).get("id", ""))
			if not hits.has(vid):
				unreachable.append("%s/%s" % [str(boss_id), vid])
	assert_gt(total, 0, "CONTROL: some boss must author vulnerabilities, or this measures nothing")
	assert_eq(unreachable, [],
		"every vulnerability needs a verb the player can pick that trips IT — unreachable: %s" % str(unreachable))
	gut.p("  %d authored vulnerabilities, all reachable" % total)


func test_the_consoling_line_trips_the_consoling_vulnerability() -> void:
	## The specific regression. `console` carries two of dissolve_the_dread's phrases;
	## it must not be captured by an earlier entry that happens to share a word.
	var entry: Dictionary = _bosses()["umbraxis"]
	var directive: String = ""
	for v in entry.get("verbs", []):
		if str((v as Dictionary).get("id", "")) == "console":
			directive = str((v as Dictionary).get("directive", ""))
	assert_false(directive.is_empty(), "CONTROL: umbraxis must still author a 'console' verb")
	var res: Variant = _bd.check_jailbreak("umbraxis", directive)
	assert_true(res is Dictionary, "the consoling line must still land as a jailbreak")
	assert_eq(str((res as Dictionary).get("vulnerability_id", "")), "dissolve_the_dread",
		"it must trip the vulnerability it was written for, not whichever is authored first")


func test_the_consequence_the_player_gets_is_the_authored_one() -> void:
	## Why the shadowing mattered beyond a tally: the two entries carry DIFFERENT
	## consequences, so the wrong one is a different effect on the boss's turn.
	var entry: Dictionary = _bosses()["umbraxis"]
	var authored: String = ""
	for vu in entry.get("jailbreak_vulnerabilities", []):
		if str((vu as Dictionary).get("id", "")) == "dissolve_the_dread":
			authored = str(((vu as Dictionary).get("consequence", {}) as Dictionary).get("type", ""))
	assert_eq(authored, "taunt_softens", "CONTROL: dissolve_the_dread's authored consequence")
	var directive: String = ""
	for v in entry.get("verbs", []):
		if str((v as Dictionary).get("id", "")) == "console":
			directive = str((v as Dictionary).get("directive", ""))
	var res: Variant = _bd.check_jailbreak("umbraxis", directive)
	assert_eq(str(((res as Dictionary).get("consequence", {}) as Dictionary).get("type", "")), authored,
		"the player must get the consequence the author wrote for the line they picked")


func test_the_other_umbraxis_verbs_still_reach_their_own() -> void:
	## The fix removed a keyword. This is the arm that would catch removing too much:
	## question_the_fight must still be reachable, by the verb written for IT.
	var entry: Dictionary = _bosses()["umbraxis"]
	var hits: Dictionary = _reachable_for("umbraxis", entry)
	assert_eq(str(hits.get("question_the_fight", "")), "unreal",
		"the 'unreal' verb must still trip question_the_fight")
	assert_eq(str(hits.get("absurdity_stagger", "")), "absurd",
		"and 'absurd' must still trip absurdity_stagger")


func test_a_line_that_should_miss_still_misses() -> void:
	## Anti-vacuity: if the matcher said yes to everything, every arm above would pass
	## while meaning nothing. Umbraxis authors a fourth verb that trips nothing.
	var res: Variant = _bd.check_jailbreak("umbraxis", "I have no idea what you are.")
	assert_false(res is Dictionary, "an unrelated line must not land as a jailbreak")
