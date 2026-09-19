extends GutTest

## A player scripted "use a Potion below 30% HP", ran out of potions, and the character DEFERRED
## every turn with nothing in the log. `_convert_autobattle_action`'s caller swaps a bare `{}` for a
## defer, so a refusal here is indistinguishable from the player scripting a defer.
##
## The ability arm 36 lines up has FOUR refusals and reports three of them — including the ROUTINE
## one, insufficient MP — staying silent only on the deliberate empty-`targets` case below. The item
## arm has THREE and reported none, including the two that are its exact counterparts. An asymmetry
## between two arms of ONE function, against the author's own established convention.
##
## ⛔ THE INVARIANT IS A RELATIONSHIP, NOT A LIST OF APPROVED SITES. Exactly one refusal kind is
## allowed to stay silent: the explicit empty-`targets` case, which is silent in BOTH arms BY DESIGN
## (Tick 111 — an autobattle rule that resolved to nobody must defer rather than re-target a Phoenix
## Down at an enemy). It is identified here by what its condition TESTS, so a newly added silent
## refusal reds instead of being absorbed by an allowlist that grows one entry per incident.
##
## Source-level by necessity: the only observable difference a diagnostic makes is the log line, and
## a behavioural arm would pass either way. Both floors are ANTI-VACUITY with headroom, never a
## pinned count — measured either side: removing the two item diagnostics reds the claim alone,
## stripping all five reds the floor alone.

const SRC := "res://src/battle/BattleManager.gd"
const FUNC := "func _convert_autobattle_action"
const ARMS := ["ability", "item"]

## The one refusal permitted to be silent, identified by its condition rather than its position.
const DELIBERATELY_SILENT := "targets"


func _refusals() -> Array[Dictionary]:
	var text := FileAccess.get_file_as_string(SRC)
	var lines: PackedStringArray = text.split("\n")
	var start := -1
	for i in range(lines.size()):
		if lines[i].begins_with(FUNC):
			start = i
			break
	var out: Array[Dictionary] = []
	if start < 0:
		return out
	var arm := ""
	for i in range(start + 1, lines.size()):
		var raw: String = lines[i]
		if raw.begins_with("func "):
			break
		var arm_match := raw.strip_edges()
		if raw.begins_with("\t\t\"") and arm_match.ends_with("\":"):
			arm = arm_match.trim_prefix("\"").trim_suffix("\":").trim_suffix("\"")
		if arm not in ARMS:
			continue
		if raw.strip_edges() != "return {}":
			continue
		## The guarding condition and whether anything between it and the return reports.
		var cond := ""
		var reports := false
		for j in range(i - 1, max(start, i - 4), -1):
			var prev: String = lines[j].strip_edges()
			if prev.is_empty():
				continue
			if prev.contains("print("):
				reports = true
			if prev.begins_with("if ") or prev.begins_with("elif "):
				cond = prev
				break
		out.append({"arm": arm, "line": i + 1, "cond": cond, "reports": reports})
	return out


func test_the_parse_found_both_arms_and_their_refusals() -> void:
	var found := _refusals()
	var arms_seen: Dictionary = {}
	for r in found:
		arms_seen[str(r["arm"])] = true
	assert_eq(arms_seen.keys().size(), ARMS.size(),
		"FLOOR: both the ability and item arms must be parsed, or every claim below is about an "
		+ "empty list. Saw: %s" % str(arms_seen.keys()))
	assert_gt(found.size(), 4,
		"FLOOR: %d refusal(s) parsed in those two arms. The file had 7; a number this low means the "
		% found.size() + "parse broke or the subject was deleted, either of which must red here")


func test_every_refusal_says_why_unless_it_is_the_designed_silence() -> void:
	var mute: Array[String] = []
	var spoke := 0
	for r in _refusals():
		var cond: String = str(r["cond"])
		if bool(r["reports"]):
			spoke += 1
			continue
		if cond.contains(DELIBERATELY_SILENT):
			continue
		mute.append("%s arm, :%d — %s" % [str(r["arm"]), int(r["line"]), cond])
	## Anti-vacuity only. A THRESHOLD here would pin today's count: consolidating two diagnostics
	## into one is a correct change this must not red, and the arm below carries the real claim.
	assert_gt(spoke, 0,
		"FLOOR: not one refusal reports, so `mute` being empty would mean the parse found nothing "
		+ "rather than that the arms agree")
	assert_eq(mute, [],
		"a refusal that returns a bare {} becomes a DEFER in the caller, so a silent one is "
		+ "indistinguishable from the player scripting a defer. The ability arm reports even its "
		+ "routine MP case; these do not: %s" % str(mute))
