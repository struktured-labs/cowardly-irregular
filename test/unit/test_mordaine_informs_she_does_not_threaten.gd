extends GutTest

## Mordaine's persona told the model to be contemptuous. The novella says she stopped.
##
## cowir-story's ruling (DM msg-3144, superseded by msg-3148), decided against the
## throne-room prose: "Her posture was the posture of someone who has long since
## stopped needing to perform power because the power is simply there." The shipped
## persona instructed a "formal, contemptuous political register" and an opening of
## "You stand in MY throne room and presume to threaten ME?" — which IS performing
## power, the exact thing the novella says she no longer needs to do.
##
## Landed here: 2 opening lines, 1 aggress taunt, 1 persona block. cowir-story's
## words verbatim; the register call is theirs, not mine.
##
## ⚠️ WHAT THIS FILE DEFENDS IS NOT THE PROSE. Authored lines are cowir-story's to
## revise and a test that pins their sentences would go red on their next correct
## edit. It pins the two RELATIONSHIPS the ruling turns on, both of which break
## silently:
##
##   1. THE WOUND AND ITS MECHANIC. The persona's closing clause — moved by a true
##      observation, not at all by force — is what makes `expose_calibrant` behave
##      under sampling. Clause without the jailbreak entry is flavour; jailbreak
##      without the clause fires against a model that was never told force bounces.
##      Neither half alone is detectable by reading its own file.
##
##   2. BOTH PATHS, ONE CHARACTER. `persona` steers the LLM; `opening_lines` and
##      `taunt_lines` are what an LLM-off player hears. cowir-story caught their own
##      first draft dropping the 'cowardly'/'predictable' vocabulary from the
##      scripted path while the persona kept instructing it — LLM-on and LLM-off
##      players meeting two different characters, "in the direction nobody notices
##      because testing happens on one path." That is CLAUDE.md's two-sources trap
##      with the consumer split by a settings toggle.
##
## Corroboration that the ruling describes the character rather than imposing a new
## one: automation_lines, victory_lines and defeat_lines were ALREADY administrative
## ("an absent subject is a DATA QUALITY problem, which is colder than contempt").
## The persona and the openings were the stragglers.

const PATH := "res://data/boss_dialogue.json"


func _collect_gd(dir_path: String, out: PackedStringArray) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var n: String = d.get_next()
	while n != "":
		var full: String = dir_path + "/" + n
		if d.current_is_dir():
			if not n.begins_with("."):
				_collect_gd(full, out)
		elif n.ends_with(".gd"):
			out.append(full)
		n = d.get_next()
	d.list_dir_end()


func _entry() -> Dictionary:
	var raw: String = FileAccess.get_file_as_string(PATH)
	assert_false(raw.is_empty(), "CONTROL: boss_dialogue.json must load")
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "CONTROL: it must be a JSON object")
	if not (parsed is Dictionary):
		return {}
	return (parsed as Dictionary).get("chancellor_mordaine", {})


func _intent(id: String) -> Dictionary:
	for i in _entry().get("scripted_intents", []):
		if str((i as Dictionary).get("id", "")) == id:
			return i as Dictionary
	return {}


# ── relationship 1: the wound and the mechanic that spends it ─────────────────

func test_the_persona_keeps_the_wound_that_makes_the_jailbreak_work() -> void:
	var persona: String = str(_entry().get("persona", ""))
	assert_true(persona.to_lower().contains("true observation"),
		"the persona must say a true observation moves her — this is what expose_calibrant spends")
	assert_true(persona.to_lower().contains("force"),
		"and that force does not, or threats land as well as naming her and the jailbreak stops being the only door")


func test_the_mechanic_the_wound_serves_is_still_wired() -> void:
	## The other half. A persona clause describing a vulnerability no jailbreak
	## implements is flavour text that reads like a feature.
	var ids: Array = []
	for j in _entry().get("jailbreak_vulnerabilities", []):
		ids.append(str((j as Dictionary).get("id", "")))
	assert_true("expose_calibrant" in ids,
		"expose_calibrant must exist — the persona's closing clause exists to make it behave")


# ── relationship 2: the LLM path and the scripted path are one character ──────

func test_both_paths_classify_the_party_in_the_same_words() -> void:
	## cowir-story's own near-miss: their first draft dropped the pun from the
	## scripted line while the persona kept instructing it. The shared vocabulary
	## is what keeps an LLM-on and an LLM-off player in the same scene.
	var persona: String = str(_entry().get("persona", "")).to_lower()
	var scripted: String = " ".join(PackedStringArray(_entry().get("opening_lines", []))).to_lower()
	for word in ["cowardly", "predictable"]:
		assert_true(persona.contains(word),
			"the persona must keep '%s' so the model still reaches for it" % word)
		assert_true(scripted.contains(word),
			"and the scripted opening must carry '%s' so the LLM-off player hears the same classification" % word)


func test_the_title_still_arrives_in_the_final_bosss_mouth() -> void:
	## Both words of the game's title are said by Mordaine in her opening. That is
	## authored intent cowir-story protected explicitly when reworking the line.
	var scripted: String = " ".join(PackedStringArray(_entry().get("opening_lines", []))).to_lower()
	assert_true(scripted.contains("cowardly"), "'cowardly' must survive any rewording of the opening")
	assert_true(scripted.contains("irregular"), "and 'irregulars' with it — together they are the title")


# ── the retired register must not drift back ──────────────────────────────────

func test_the_persona_no_longer_instructs_contempt() -> void:
	## The defect itself: the model was TOLD to be contemptuous, so it was.
	var persona: String = str(_entry().get("persona", ""))
	assert_eq(persona.find("contemptuous political register"), -1,
		"the retired instruction must not return — it is what produced the drift")
	assert_eq(persona.find("seize power through subterfuge"), -1,
		"and the narrator's sneer at her must stay out of her own character sheet")


func test_she_informs_rather_than_threatens() -> void:
	var scripted: String = " ".join(PackedStringArray(_entry().get("opening_lines", [])))
	assert_eq(scripted.find("presume to threaten"), -1,
		"performing outrage at intruders is the register the ruling retired")
	var agg: Array = _intent("aggress").get("taunt_lines", [])
	assert_eq(" ".join(PackedStringArray(agg)).find("crush vermin"), -1,
		"contempt-as-insult is retired; the line now reports rather than sneers")


# ── controls: the ruling was four edits, not a rewrite ────────────────────────

func test_only_the_named_aggress_line_changed() -> void:
	## cowir-story: "replace only 'I do not require subtlety to crush vermin.'"
	## The other two were explicitly fine, and a wider edit would exceed the ruling.
	var agg: Array = _intent("aggress").get("taunt_lines", [])
	assert_eq(agg.size(), 3, "aggress must still offer three taunts")
	var joined: String = " ".join(PackedStringArray(agg))
	assert_true(joined.contains("Every blow is a verdict"), "the second line was not mine to touch")
	assert_true(joined.contains("this will be brief"), "nor the third")


func test_everything_else_the_ruling_left_alone_is_intact() -> void:
	var e: Dictionary = _entry()
	assert_eq((e.get("scripted_intents", []) as Array).size(), 9,
		"all nine intents must survive — the ruling changed one LINE inside one of them")
	assert_eq((e.get("victory_lines", []) as Array).size(), 4, "victory set stands")
	assert_eq((e.get("defeat_lines", []) as Array).size(), 3, "defeat set stands")
	assert_eq((e.get("jailbreak_vulnerabilities", []) as Array).size(), 3, "every jailbreak entry stands")


## Each line cut at the first `#` OUTSIDE a string literal; line count preserved.
## Blanking only whole-line comments was not enough — a TRAILING comment walked
## straight through and the guard scored green with the real line gone
## (cowir-controller msg-9672, measured here as ARM3 before this).
func _code_only(src: String) -> String:
	var out: PackedStringArray = PackedStringArray()
	for line in src.split("\n"):
		out.append(_strip_comment(line))
	return "\n".join(out)


## Quote-aware, because a naive cut at the first `#` truncates real code carrying a
## quoted one — over-stripping is the other way a stripper is wrong (cowir-music).
func _strip_comment(line: String) -> String:
	var quote: String = ""
	var i: int = 0
	while i < line.length():
		var c: String = line[i]
		if quote != "":
			if c == "\\":
				i += 2
				continue
			if c == quote:
				quote = ""
		elif c == "\"" or c == "'":
			quote = c
		elif c == "#":
			return line.substr(0, i)
		i += 1
	return line


## ⛔ MEASURED AFTER LANDING, AND IT QUALIFIES THE WHOLE FILE: the two opening lines
## above currently reach NO PLAYER. `opening_lines` is read in exactly one place —
## BossDialogue.get_opening_lines (:119) — and that function has zero production
## callers and zero internal ones; the only other src/ mention is a doc comment
## listing it (:9). A comment naming a function is not a caller. Nothing else in
## src/ reads the key, and the boss_intro cutscene step takes its name/title from
## the step, not from this file.
##
## It is not Mordaine-specific: ten bosses carry 25 authored opening lines this way
## — all five W1 bosses and all five spotlight-duel minibosses.
##
## NOT WIRED HERE. Reviving a dormant path is what finally tests the assumptions it
## preserved, and wiring this would put 25 lines no player has ever heard on screen
## at once. That is cowir-story's call on the prose and struktured's on whether
## bosses should speak at battle start at all.
##
## The tripwire below is what keeps this from being a paragraph that goes stale:
## if someone wires a consumer, it REDS and says to review the lines first.

func test_opening_lines_have_no_consumer_yet_tripwire() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/llm/BossDialogue.gd")
	assert_false(src.is_empty(), "CONTROL: source must load")
	assert_true(_code_only(src).contains("func get_opening_lines("),
		"CONTROL: the accessor must still exist, or this tripwire is measuring nothing")
	## Walks ALL of src/, not a hand-listed set of likely files. The shipped version
	## scanned four named files, so a consumer wired anywhere else — including inside
	## BossDialogue itself — left this green. Measured before the fix: 13 passing with
	## a real caller present. A tripwire whose whole job is to notice a change cannot
	## carry a corpus that can miss it (cowir-controller: derive it, do not list it).
	var files: PackedStringArray = []
	_collect_gd("res://src", files)
	## A FLOOR catches a totally broken walk and is blind to PARTIAL loss — drop one
	## subtree and 100+ files still pass while a caller in the lost half goes unseen
	## (cowir-adhoc). So: floor AND named membership. If the walk cannot see the file
	## that DEFINES the accessor, it certainly cannot see a call to it.
	assert_gte(files.size(), 100,
		"CONTROL: the walker found %d .gd files under src/ — it is broken, and an empty walk "
		% files.size() + "makes the caller count 0 and this whole test vacuous")
	for must in ["res://src/llm/BossDialogue.gd", "res://src/battle/BattleManager.gd"]:
		assert_true(must in files,
			"CONTROL: the walk missed %s — a subtree is being dropped, so a caller there would be invisible" % must)
	var callers: Array[String] = []
	for f in files:
		var lines: PackedStringArray = _code_only(FileAccess.get_file_as_string(f)).split("\n")
		for i in lines.size():
			var ln: String = lines[i]
			if ln.contains("get_opening_lines(") and not ln.strip_edges().begins_with("func "):
				callers.append("%s:%d" % [f, i + 1])
	assert_eq(callers, [] as Array[String],
		"SOMEONE WIRED BOSS OPENING LINES at %s — that is good, and it puts 25 previously-unheard "
		% [", ".join(callers)]
		+ "lines across 10 bosses on screen at once. ⚠️ It also pre-empts struktured's "
		+ "two-loss spotlight-hint cadence (GameLoop:239) for the five duel minibosses. "
		+ "Review with cowir-story, confirm with struktured, then delete this test.")


func test_the_persona_still_reaches_the_model() -> void:
	## EXECUTION IS NOT SELECTION: editing the persona is worthless if nothing reads
	## it. BattleManager lifts it off this entry into the boss-intent context.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_false(src.is_empty(), "CONTROL: source must load")
	assert_true(_code_only(src).contains("ctx.persona = str(entry.get(\"persona\", \"\"))"),
		"the authored persona must still be the one handed to the prompt builder")


func test_the_reaches_the_model_check_cannot_be_satisfied_by_a_comment() -> void:
	## The control for the line above, because a source-text pin that a comment can
	## satisfy defends nothing. Verified by mutation: before this, commenting the
	## real line out and assigning a placeholder scored 9/9 green.
	assert_false(_code_only("\t\t# ctx.persona = str(entry.get(\"persona\", \"\"))").contains("ctx.persona"),
		"a commented-out assignment must not satisfy the check")
	assert_false(_code_only("\t\tctx.persona = \"x\"  # ctx.persona = str(entry.get(\"persona\", \"\"))").contains("entry.get"),
		"nor a TRAILING one — this is the arm that was green before, and trailing is how removals look")
	assert_true(_code_only("\t\tctx.persona = str(entry.get(\"persona\", \"\"))").contains("ctx.persona"),
		"CONTROL: and real code must still satisfy it, or the discriminator refuses everything")
	assert_true(_code_only("\tvar s := \"# not a comment\"").contains("not a comment"),
		"CONTROL the other way: a quoted # must NOT truncate real code — over-stripping reports every subject missing")


func test_the_comment_stripper_itself_is_pinned() -> void:
	## Pinning the INSTRUMENT rather than only reaching it through mutations
	## (cowir-overworld, msg-9682). Five costumes of one hollowness turned up in this
	## helper across the fleet today; a case table is what stops a sixth from being
	## discovered by a guard silently going green.
	var cases: Array = [
		# [line, expected_output, why]
		["\tctx.persona = str(entry.get(\"persona\", \"\"))",
		 "\tctx.persona = str(entry.get(\"persona\", \"\"))",
		 "real code with quotes and no # is untouched"],
		["\tvar x = 1  # ctx.persona = str(entry.get(\"persona\", \"\"))",
		 "\tvar x = 1  ",
		 "a trailing comment is cut"],
		["\tvar _hex := \"#ff0000\"",
		 "\tvar _hex := \"#ff0000\"",
		 "a quoted # alone must survive — cutting here empties the corpus silently"],
		["\tvar _hex := \"#ff0000\"  # ctx.persona gone",
		 "\tvar _hex := \"#ff0000\"  ",
		 "a quoted # FOLLOWED by a real comment cuts only at the comment (the fifth costume)"],
		["\tvar h := '#hash'",
		 "\tvar h := '#hash'",
		 "single quotes count as a string too"],
		["\t# whole line",
		 "\t",
		 "a whole-line comment is emptied but the line survives"],
		["\tvar q := \"a \\\" # still string\"",
		 "\tvar q := \"a \\\" # still string\"",
		 "an escaped quote must not end the string early"],
		["\tvar q := \"a\\\\\"  # gone",
		 "\tvar q := \"a\\\\\"  ",
		 "an escaped BACKSLASH ends the string — a lookbehind escape check reads this as still-open and lets the comment through"],
	]
	## Draining this table is itself the violation. The asserts live INSIDE the loop,
	## so an empty table runs none — measured: EC=0, [Risky] "did not assert", and NO
	## Failing line. A gate reading the exit code or the Failing count passes that.
	## (cowir-sfx's two-magnitude drain; the Risky-not-Failing half is cowir-story's
	## Tests-minus-Passing arithmetic, which I got wrong reading this very run.)
	assert_eq(cases.size(), 8,
		"the stripper case table holds %d rows, not 8 — a drained table asserts NOTHING and "
		% cases.size()
		+ "scores [Risky] with EC=0, not a failure. Add the row back, or change this count deliberately.")
	for c in cases:
		assert_eq(_strip_comment(str(c[0])), str(c[1]), str(c[2]))


func test_the_stripper_preserves_line_count() -> void:
	## substr/ordering windows elsewhere depend on it, and a stripper that drops
	## lines would shift every later assertion without failing anything here.
	var src: String = "a\n# b\nc  # d\n"
	## Both sides of a size-vs-size compare shrink together, so an emptied input reads
	## 1 == 1 and passes trivially — cowir-sfx's self-referential floor, in the one
	## place my guards had it. Pin the input to a LITERAL count first.
	assert_eq(src.split("\n").size(), 4, "PREMISE: the fixture is 3 lines plus a trailing empty")
	assert_eq(_code_only(src).split("\n").size(), 4,
		"blanking must not remove lines")
