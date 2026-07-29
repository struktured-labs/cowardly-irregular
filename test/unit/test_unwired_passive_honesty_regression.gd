extends GutTest

## Four passives promised capabilities the game cannot perform, on an equip button. 2026-07-29.
##
## Found by cowir-story sweeping all 46 effect keys across 44 passives against a full src/ walk
## (controls: attack_multiplier and healing_multiplier both resolve). Four meta_effects have zero
## consumers:
##   double_jump        Ninja        "Jump over gaps and obstacles on the overworld"
##   wall_climb         Ninja        "Scale walls to reach hidden shortcuts"
##   optional_detector  Skiptrotter  "Highlights skippable vs required content"
##   debug_mode         Scriptweaver "See internal game variables and error logs in battle"
##
## A passive description is not dormant data — MenuScene:898 renders it WHILE THE PLAYER IS
## CHOOSING. All four sit on jobs that unlock in JobMenu under debug mode, which defaults on.
##
## RULING (cowir-main): label, do not reword, and do not wire. The codebase already contains the
## right precedent — `death_sentence` reads "Files a formal death sentence. The Bureau of
## Inevitability has a backlog. (Currently no effect)". It keeps the full promise AND discloses the
## status, diegetically. Rewording "jump over gaps" into something smaller would launder a planned
## feature (cowir-story's objection, and correct); wiring overworld traversal mid-playtest is a
## feature, not a fix. The marker costs nothing and stops the description being a lie today.
##
## Both prior instances of this class were fixed with a CONSUMER, not a reword — death_resistance
## (Combatant:371, "pure decoration") and the +50% healing passive (Combatant:444, "players
## equipped the passive seeing it in the description and got nothing"). So the marker is explicitly
## an interim, and the guard below is built to expire rather than to persist.


const MARK := "(Currently no effect)"
const UNWIRED := ["double_jump", "wall_climb", "optional_detector", "debug_mode",
	"undead_affinity"]
## Passives that WORK but ignore one authored parameter. Materially different: the promise is
## kept, a knob is unread. Not disclosed, because the description is true.
##   time_sense      live preview_enemy_actions   dead preview_turns
##   speedrun_timer  live show_splits             dead track_personal_best
const PARTIAL := ["time_sense", "speedrun_timer"]


func _passives() -> Dictionary:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/passives.json"))
	return raw.get("passives", raw)


func _meta_keys(pid: String) -> Array:
	var p: Dictionary = _passives()
	if not p.has(pid):
		return []
	var me: Variant = (p[pid] as Dictionary).get("meta_effects")
	return (me as Dictionary).keys() if me is Dictionary else []


func _src_reads(key: String) -> bool:
	# Walks src/ for the key as an authored string, the way any consumer would name it.
	var dirs: Array = ["res://src"]
	while not dirs.is_empty():
		var d: String = dirs.pop_back()
		var da := DirAccess.open(d)
		if da == null:
			continue
		for sub in da.get_directories():
			dirs.append(d + "/" + sub)
		for f in da.get_files():
			if not f.ends_with(".gd"):
				continue
			if FileAccess.get_file_as_string(d + "/" + f).contains('"%s"' % key):
				return true
	return false


func test_the_walk_can_find_a_key_that_IS_consumed() -> void:
	# Positive control. A walk that returns false for everything makes every assertion below pass
	# for the wrong reason, and "no consumers found" is exactly the answer this file is about.
	assert_true(_src_reads("healing_multiplier"),
		"the src walk must find a key known to be live — otherwise its negatives mean nothing")


func test_every_unwired_passive_discloses_its_status() -> void:
	var p: Dictionary = _passives()
	var offenders: Array = []
	for pid in UNWIRED:
		if not p.has(pid):
			continue
		var desc: String = str((p[pid] as Dictionary).get("description", ""))
		if not desc.contains(MARK):
			offenders.append("%s: \"%s\"" % [pid, desc])
	assert_eq(offenders, [],
		"these are rendered on the equip button while the player chooses, and nothing performs "
		+ "them:\n  %s" % "\n  ".join(offenders))


func test_the_marker_comes_OFF_the_moment_a_passive_is_wired() -> void:
	# The carve-out expires by failing rather than by being reread — cowir-story's self-destructing
	# exclusion. If someone implements overworld_double_jump, this goes red and forces the
	# "(Currently no effect)" off the description. It cannot outlive its reason.
	var stale: Array = []
	for pid in UNWIRED:
		var keys: Array = _meta_keys(pid)
		var wired: bool = false
		for k in keys:
			if _src_reads(str(k)):
				wired = true
		if wired:
			stale.append("%s is now consumed — remove '%s' from its description and from UNWIRED"
				% [pid, MARK])
	assert_eq(stale, [], "the disclosure has outlived its reason:\n  %s" % "\n  ".join(stale))


func test_a_FIFTH_unwired_passive_cannot_appear_unnoticed() -> void:
	# The other direction, so the list cannot quietly widen. Derived from the corpus rather than
	# maintained: every meta_effects key on every passive must either be consumed in src/ or belong
	# to a passive already disclosed. No suppression entries — the four are the whole exemption and
	# they are named in UNWIRED, which the test above forces empty as they get wired.
	var p: Dictionary = _passives()
	var offenders: Array = []
	var scanned: int = 0
	for pid in p:
		if UNWIRED.has(str(pid)) or PARTIAL.has(str(pid)):
			continue
		var me: Variant = (p[pid] as Dictionary).get("meta_effects")
		if not (me is Dictionary):
			continue
		for key in (me as Dictionary):
			scanned += 1
			if not _src_reads(str(key)):
				offenders.append("%s.%s has no consumer in src/" % [pid, key])
	assert_gt(scanned, 10, "positive control — meta_effects keys must actually be walked")
	assert_eq(offenders, [],
		"a passive promising something nothing performs, undisclosed:\n  %s" % "\n  ".join(offenders))


func test_a_PARTIAL_passive_still_has_a_working_key() -> void:
	# The severity distinction, asserted rather than asserted-in-a-comment. A passive on the PARTIAL
	# list is exempt from disclosure ONLY because a sibling key is consumed — the promise is kept and
	# a knob is unread. If its last live key goes away it becomes a false promise and must move to
	# UNWIRED. Derived, so the exemption cannot outlive its reason.
	var p: Dictionary = _passives()
	var offenders: Array = []
	for pid in PARTIAL:
		var keys: Array = _meta_keys(pid)
		var live: int = 0
		for k in keys:
			if _src_reads(str(k)):
				live += 1
		if live == 0:
			offenders.append("%s has no consumed key left — it is now a false promise, move it to "
				% pid + "UNWIRED and disclose it")
	assert_eq(offenders, [], "a PARTIAL exemption has expired:\n  %s" % "\n  ".join(offenders))
