extends GutTest

## ⛔ A SECTION WHOSE FIELDS ARE ALL READ ELSEWHERE IS INVISIBLE TO A FIELD CENSUS.
##
## `test_a_manifest_field_is_read_or_declared` asks whether each KEY has a reader. `frame_width` is
## read — by the battle sheet loader — so a section that nothing ever opens passes that guard on the
## strength of another section's consumers. I named this gap in the roaming-monster guard's header
## an hour before writing it down here; this is the arm.
##
## Measured on this tree: SIX sections are read and FOUR are not, holding 153 entries.
##
##   npc_sheets            SIX conversational sheets, 1326 KB as of 2026-09-16 — the COUNT is
##                         pinned by the disk arm below, the byte figure is not — 2048x256, eight 256px frames
##                         animating idle/talk/gesture/react. No path form in src/ reaches them: the
##                         live convention is `npcs/<archetype>/overworld.png`, a DIRECTORY, and four
##                         of the six have a twin there. The characters ship; the talking art does
##                         not. I first reported FOUR — the other two were on disk with no manifest
##                         entry, so this file's own census could not see them (see the disk arm).
##   overworld_npc_sheets  145 entries whose ART IS LIVE — reached by path convention, never through
##                         the manifest. An audit ledger, not a route, and the opposite error to the
##                         one above: a zero here is not unreachable art.
##   weapon_sheets         4 T2_artist_draft weapons, declared in hour 10.
##   party_sheets          empty, and empty on purpose.
##
## 🔑 THE TWO ZEROES MEAN OPPOSITE THINGS AND NO COUNT SEPARATES THEM. `npc_sheets` unread means the
## art cannot render; `overworld_npc_sheets` unread means the runtime reaches the art another way.
## That is why the deliverable is a DECLARATION naming which, rather than a number to drive down.
const MANIFEST := "res://data/sprite_manifest.json"
const SRC_ROOT := "res://src"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")


func _manifest() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	return parsed if parsed is Dictionary else {}


## Comment-stripped so a section named only in PROSE cannot read as a consumer — this repo's own
## headers name manifest sections constantly, and `test_overworld_sheet_manifest_audit` documents
## `overworld_monster_sheets` in a comment while reading nothing.
func _src_code() -> String:
	var parts: PackedStringArray = []
	var stack: Array[String] = [SRC_ROOT]
	while not stack.is_empty():
		var cur: String = stack.pop_back()
		var d := DirAccess.open(cur)
		if d == null:
			continue
		d.list_dir_begin()
		var n := d.get_next()
		while n != "":
			var full: String = "%s/%s" % [cur, n]
			if d.current_is_dir():
				if not n.begins_with("."):
					stack.append(full)
			elif n.ends_with(".gd"):
				parts.append(GdSource.code_of(full))
			n = d.get_next()
		d.list_dir_end()
	return "\n".join(parts)


func _sections() -> Array[String]:
	var out: Array[String] = []
	for k in _manifest():
		if str(k).begins_with("_"):
			continue
		if _manifest()[k] is Dictionary:
			out.append(str(k))
	out.sort()
	return out


## ⛔ THE INSTRUMENT FIRST, BOTH WAYS — an empty corpus reports every section unread, which reads as
## a spectacular finding rather than as a broken scan.
func test_the_section_scan_controls_both_ways() -> void:
	var code := _src_code()
	assert_gt(code.length(), 100000,
		"ANTI-VACUITY: only %d chars of stripped src/ were read — every section would look unread" % code.length())
	assert_true(code.contains("\"monster_sheets\""),
		"CONTROL: monster_sheets IS read by HybridSpriteLoader — if the scan cannot see it, every zero below is false")
	assert_false(code.contains("\"__no_such_section__\""),
		"CONTROL: a fabricated section must not read as consumed")
	assert_gt(_sections().size(), 5, "ANTI-VACUITY: only %d sections parsed out of the manifest" % _sections().size())


## Every section is READ by src/, or DECLARED with a line saying what it is for.
func test_every_section_is_read_or_declared() -> void:
	var code := _src_code()
	var declared: Dictionary = _manifest().get("_section_provenance", {})
	var undeclared: Array = []
	var read_count := 0
	for s in _sections():
		if code.contains("\"%s\"" % s):
			read_count += 1
			continue
		if declared.has(s):
			continue
		var n: int = (_manifest()[s] as Dictionary).size()
		undeclared.append("%s (%d entries)" % [s, n])
	assert_gt(read_count, 3,
		"ANTI-VACUITY: only %d sections matched in src/ — the search is broken, so every section reads as unread" % read_count)
	undeclared.sort()
	assert_eq(undeclared, [],
		("a manifest section is opened by nothing in src/ and explained by nothing in _section_provenance. "
		+ "Either it is art the runtime cannot reach, or the runtime reaches it another way — and the "
		+ "difference is invisible in the data, which is why the line is required: %s") % [undeclared])


## A declaration must EXPLAIN. An empty string silences the arm above while recording nothing.
func test_every_section_declaration_says_something() -> void:
	var declared: Dictionary = _manifest().get("_section_provenance", {})
	assert_gt(declared.size(), 2, "ANTI-VACUITY: _section_provenance carries almost nothing")
	assert_gt(str(declared.get("_why", "")).length(), 80,
		"_section_provenance must carry its own rationale — a reader arriving at it needs to know what a zero means here")
	var thin: Array = []
	for s in declared:
		if str(s) == "_why":
			continue
		if str(declared[s]).strip_edges().length() < 60:
			thin.append(str(s))
	assert_eq(thin, [], "a section declaration has to say what the section is for and who holds it: %s" % [thin])


## ⛔ THE DECLARATION MUST NOT OUTLIVE THE FACT. A section declared unread that GAINS a reader is no
## longer provenance — and the note would then tell the next reader the opposite of the truth.
## My hours 11 and 12 moved two sections out of this block by wiring them; this is what made that
## visible rather than something I had to remember.
func test_no_declared_section_is_actually_read() -> void:
	var code := _src_code()
	var declared: Dictionary = _manifest().get("_section_provenance", {})
	var now_read: Array = []
	for s in declared:
		if str(s) == "_why":
			continue
		if code.contains("\"%s\"" % str(s)):
			now_read.append(str(s))
	assert_eq(now_read, [],
		("a section declared unread is now opened by src/ — delete the declaration, because it is a "
		+ "licence to leave the section alone and that licence has expired: %s") % [now_read])


## ⛔ AND THE DECLARED SECTIONS MUST STILL EXIST. A declaration for a section someone removed is a
## note about nothing, and it silently satisfies the arm above forever.
func test_no_declaration_names_a_section_that_is_gone() -> void:
	var declared: Dictionary = _manifest().get("_section_provenance", {})
	var present := {}
	for s in _sections():
		present[s] = true
	var phantom: Array = []
	for s in declared:
		if str(s) == "_why":
			continue
		if not present.has(str(s)):
			phantom.append(str(s))
	assert_eq(phantom, [],
		("_section_provenance names a section the manifest no longer has — a declaration about nothing: %s") % [phantom])


## ⛔ EVERY GUARD ABOVE WALKS THE MANIFEST, SO ART WITH NO ENTRY IS INVISIBLE TO ALL OF THEM.
## I reported npc_sheets as 4 sheets / 937 KB. It is SIX / 1326 KB — cowir-cutscenes checked the
## DISK and found `brigadier_flux` and `elder_theron` on it, imported, shipping, and named by no
## entry. A section census cannot see art the section does not mention; that is not a tuning
## problem, it is the direction the instrument faces.
##
## 🔑 SCOPED TO `npcs/` ON PURPOSE, and the reason is a measurement — MEASURED 2026-09-16 AND NOT
## PINNED BY ANY ARM, so read it as a dated observation rather than a live claim: 868 PNGs lived
## under assets/sprites and 301 were named by a manifest path. The other 567 are overwhelmingly FINE
## — a job's animation frames sit inside a directory registered as `sheets[job].path`, and
## portraits resolve through portrait_path() — so a tree-wide "unregistered means unreachable"
## census would report 567 false positives and be worse than nothing.
##
## What makes `npcs/` different is that ONE DIRECTORY CARRIES TWO MEANINGS: a flat `<name>.png` is
## a talking sheet, `<name>/overworld.png` is a walk sheet, and nothing distinguishes them.
## CutsceneDialogue:1271 records a lane having to correct a portrait registered against the
## directory form believing it was portrait art. So the ambiguity is measured, not anticipated.
func test_every_flat_npc_sheet_is_visible_to_the_census() -> void:
	var dir := DirAccess.open("res://assets/sprites/npcs")
	assert_not_null(dir, "PRECONDITION: the npcs sprite dir must be scannable")
	if dir == null:
		return
	var registered := {}
	var section: Dictionary = _manifest().get("npc_sheets", {})
	for k in section:
		var e = section[k]
		if e is Dictionary:
			registered[str(e.get("path", ""))] = true
	assert_gt(registered.size(), 3, "ANTI-VACUITY: npc_sheets names almost nothing, so every file below would read as invisible")

	var invisible: Array = []
	var found := 0
	dir.list_dir_begin()
	var n := dir.get_next()
	while n != "":
		if not dir.current_is_dir() and n.ends_with(".png"):
			found += 1
			var path := "res://assets/sprites/npcs/%s" % n
			if not registered.has(path):
				invisible.append(n)
		n = dir.get_next()
	dir.list_dir_end()
	assert_gt(found, 3,
		"ANTI-VACUITY: only %d flat png files walked under npcs/ — the scan is measuring nothing" % found)
	invisible.sort()
	assert_eq(invisible, [],
		("a flat npcs/<name>.png ships with no manifest entry, so no census in this lane can see it — "
		+ "register it (which does not make it reachable, it makes the unreachability countable) or "
		+ "remove it: %s") % [invisible])


## ⛔ A NUMBER IN PROSE DECAYS AND A NUMBER IN AN ARM CANNOT. Every load-bearing figure in this
## file's header is derived live by an arm below — the six/four split, the sheet count, the
## declaration/disk agreement. The two that are NOT pinned are labelled with the date they were
## measured, because cowir-music spent this evening finding a header that said "54 excluded, 33
## unbacked" when the truth was 42 and 21, and the fix that actually held was deriving both in the
## arm rather than correcting the sentence. Correcting it would have bought about eight days.
##
## ⚠️ SO: DO NOT COPY THE ARM'S OUTPUT BACK INTO THE COMMENT. That is the move that created every
## stale header any lane found today, including the five-days-stale one I corrected an hour ago in
## test_overworld_sheet_manifest_audit — which claimed a section had zero readers after my own
## commit gave it one.
## ⛔ TWO FALSE STARTS ON THIS ARM, AND BOTH ARE THIS LANE'S OWN DOCUMENTED CLASSES.
##
## v1 searched the WHOLE file for the dated strings — and the assert lines below CONTAIN them, so it
## passed with the prose deleted entirely. Measured: strip the prose occurrence, leave the arm, still
## 7 passing. A presence assert whose needle also appears in the assert is a tautology.
##
## v2 "fixed" that by searching only the text before the first `func` — and the scoping figure does
## not live there. It sits in the docstring above the disk arm, MID-FILE. So v2 red on correct code,
## which is the louder failure and the one I would rather have: it announced itself immediately.
##
## 🔑 v3 COUNTS. Each dated string must appear at least TWICE — once in the prose that carries the
## figure, once in the assert that demands it. Delete the prose and the count falls to one. The
## arm's own line can no longer satisfy the arm, because the arm's own line is what makes the
## floor two rather than one.
func test_the_headers_unpinned_numbers_are_dated() -> void:
	var src := FileAccess.get_file_as_string("res://test/unit/test_a_manifest_section_is_read_or_declared.gd")
	assert_gt(src.length(), 500, "VOID: this guard could not read its own source")
	for needle in ["MEASURED 2026-09-16 AND NOT", "1326 KB as of"]:
		assert_gte(src.count(needle), 2,
			("an unpinned figure lost the date that makes it readable as an observation rather than a "
			+ "live claim — `%s` now appears %d time(s), and one of those is this assert: %s")
			% [needle, src.count(needle), needle])


## ⛔ THE PREMISE EVERY "UNREAD" VERDICT ABOVE RESTS ON, AND IT WAS NEVER ENFORCED.
##
## This file decides "read" by searching stripped src/ for the LITERAL section name. That is only
## sound while no consumer BUILDS a section name — @cowir-battle's DERIVED KEY shape, where the
## read never spells the key (`element + "_resistance"`, zero literal occurrences, fully consumed).
##
## 🔑 I MEASURED ZERO CONSTRUCTED SECTION NAMES AND CALLED THE VERDICT SAFE. That proved something
## about today's corpus, not about this guard — true tonight and kept true by nothing. The cost of
## being wrong is not a re-check: `npc_sheets` (1326 KB), `weapon_sheets` and `party_sheets` are
## declared unread, and that declaration is what a RETIRE-OR-WIRE ruling on artist work rests on.
## A section that gained a concatenated reader would go on reading as unread, silently.
##
## ⚠️ LIVENESS, because an empty scan and a clean one are the same result: the patterns must be
## shown to match a section name that IS built, or "0 constructed" means "the scan saw nothing".
func test_no_consumer_builds_a_section_name() -> void:
	var code := _src_code()
	assert_gt(code.length(), 20000,
		"ANTI-VACUITY: only %d chars of stripped src/ were read — every check below is void" % code.length())

	var re := RegEx.new()
	# ⛔ NARROW TO WHAT COULD PRODUCE A SECTION NAME, not to any built string. Every real
	# section ends in `sheets`, `effects` or `provenance`, so only a construction ending in
	# one of those can name one. A first version matched any `"..._%s" %` and returned four
	# hits — "hero_%s", "overworld_walk_%s", "taunted_%s", "thief_%s" — all entry ids and
	# flags, no section among them. A guard whose red is routinely wrong gets read as noise.
	re.compile('(\\+\\s*"[a-z_]*(sheets|effects|provenance)")|("[a-z_]*%s[a-z_]*(sheets|effects|provenance)")')
	var built: Array = []
	for m in re.search_all(code):
		built.append(m.get_string(0))

	# LIVENESS: the same patterns, against text that DOES build one.
	var probe := 'var s = kind + "_sheets"\nvar t = "overworld_%s_sheets" % kind\n'
	assert_gt(re.search_all(probe).size(), 0,
		("the construction patterns match NOTHING even in text written to contain one, so a zero "
		+ "below is the scan failing rather than the corpus being clean"))

	built.sort()
	assert_eq(built, [],
		("a section name is BUILT rather than written, so the literal search this file uses can no "
		+ "longer see that section's reader and every unread verdict above is unsafe — including "
		+ "the ones a retire-or-wire ruling on artist work rests on: %s") % [built])
