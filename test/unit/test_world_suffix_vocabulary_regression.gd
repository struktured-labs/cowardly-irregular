extends GutTest

const TRIPLE := '"""'

## The world vocabulary is ONE function and three lanes now read it (2026-08-06).
##
## Per-world job sprites need `<sheet>_<world_suffix>`. The only implementation of world
## identity is SoundManager's, and it was private — so sprite/puppet code either reached into
## an underscore method or copied the area->suffix map, and a copy drifts into SILENT failure:
## a wrong suffix falls back to base art, which looks correct and is never filed.
##
## The trap this pins: monster ids and map ids say "futuristic", and the resolver NEVER returns
## it — W5 is "digital". `"futuristic" in <function body>` is TRUE (39 occurrences), so grepping
## the function reassures you and is wrong. A sheet named fighter_futuristic passes every
## presence check ever written and can never load.
##
## SECOND CONVENTION, and the next thing someone gets wrong (cowir-music, msg 4253): MEDIEVAL IS
## THE UNSUFFIXED BASE. Callers do `if suffix != "" and suffix != "medieval"` before trying
## `<id>_<suffix>`, so a `<thing>_medieval` asset is DEAD ON ARRIVAL — the base file already is
## the medieval art. That is why a per-world batch is 5 worlds per subject, not 6.
##
## THIRD, for anyone adopting this outside audio — and BOTH halves matter, because the first
## draft of this note carried only the second and would have steered consumers away from the
## right answer. The `_:` arm returns `_current_world_suffix`, which is written at exactly ONE
## site (SoundManager ~4433) and written THROUGH THIS FUNCTION, so it carries the last
## IDENTIFIED world forward. That is a memory, not a staleness — and which one it behaves like
## depends entirely on the input class:
##
##   INTERIORS   neither resolver knows a shared interior id. This one persists the world you
##               came from (CORRECT). GameState.current_world prefix-matches nothing and yields
##               W1 — the bug where the party changes into chainmail entering a Brasston inn.
##   BATTLE      `play_music` clears `_current_area` for battle/victory, so this can report the
##               PREVIOUS world. `current_world` is recomputed per map transition and is fresher.
##
## Neither source is universally right. Overworld/interior resolution wants this one; anything
## battle-adjacent should prefer `current_world` (an int 1..6, so it needs its own mapping).
## (Direction verified: current_world is "where you are", NOT "furthest reached".)
## A fallback's value is the set of inputs its owner did not enumerate — judge it on those too.

const RUNTIME_VOCABULARY: Array[String] = [
	"medieval", "suburban", "steampunk", "industrial", "digital", "abstract",
]

## Area ids -> the suffix the resolver must produce. Drawn from its own match arms.
const AREA_EXPECTATIONS: Dictionary = {
	"overworld": "medieval",
	"whispering_cave": "medieval",
	"castle_harmonia": "medieval",
	"suburban_underground": "suburban",
	"steampunk_mechanism": "steampunk",
	"assembly_core": "industrial",
	"root_process": "digital",
	"null_chamber": "abstract",
}


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func test_public_accessor_exists() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "SoundManager autoload must exist")
	assert_true(sm.has_method("get_current_world_suffix"),
		"get_current_world_suffix() is the supported entry point for sprite/puppet lookups — without it those lanes call the private _get_current_world_suffix or copy the map")


func test_public_and_private_agree() -> void:
	## Both are consumed, so assert AGREEMENT — a delegating accessor that drifted from its
	## own implementation would be the two-corpora defect inside one file.
	var sm: Node = _sm()
	var saved: Variant = sm._current_area
	for area in AREA_EXPECTATIONS.keys():
		sm._current_area = area
		assert_eq(sm.get_current_world_suffix(), sm._get_current_world_suffix(),
			"public and private disagree for area '%s'" % area)
	sm._current_area = saved


func test_every_known_area_maps_into_the_runtime_vocabulary() -> void:
	var sm: Node = _sm()
	var saved: Variant = sm._current_area
	var checked: int = 0
	for area in AREA_EXPECTATIONS.keys():
		sm._current_area = area
		var got: String = sm.get_current_world_suffix()
		checked += 1
		assert_eq(got, str(AREA_EXPECTATIONS[area]),
			"area '%s' resolved to '%s'" % [area, got])
		assert_true(RUNTIME_VOCABULARY.has(got),
			"area '%s' produced '%s', which is outside the documented vocabulary %s — any asset named for it can never load" % [area, got, RUNTIME_VOCABULARY])
	sm._current_area = saved
	assert_eq(checked, AREA_EXPECTATIONS.size(),
		"control: the loop skipped areas — %d of %d checked" % [checked, AREA_EXPECTATIONS.size()])


func test_my_areas_COVER_EVERY_ARM_the_resolver_can_return() -> void:
	## COVERAGE, DERIVED. AREA_EXPECTATIONS is a hand-list, and a hand-list pins only the arms
	## it happens to name — 8 areas is a corpus SIZE, not coverage. Today all 6 arms are hit,
	## but that is true by luck, not by construction: add a seventh world and every assertion
	## above stays green while its suffix is pinned by nothing. So derive the resolver's own
	## return set from source and demand the two sets match. (cowir-autogrind, msg 4248.)
	var src: String = FileAccess.get_file_as_string("res://src/audio/SoundManager.gd")
	assert_gt(src.length(), 0, "control: source read returned nothing")

	var fn_start: int = src.find("func _get_current_world_suffix")
	assert_gt(fn_start, -1, "control: the resolver was renamed — this test can no longer find it")
	var next_fn: int = src.find("\nfunc ", fn_start + 1)
	if next_fn < 0:
		next_fn = src.length()
	var body: String = _code_only(src.substr(fn_start, next_fn - fn_start))
	assert_gt(body.length(), 200,
		"control: the extracted body is implausibly short — a boundary, not a line window, or the arms get truncated")

	var can_emit: Dictionary = {}
	var re := RegEx.create_from_string("return \"([a-z_]+)\"")
	for m in re.search_all(body):
		can_emit[m.get_string(1)] = true
	assert_gt(can_emit.size(), 1, "control: parsed fewer than 2 return values — the regex or the body is wrong")

	var covered: Dictionary = {}
	for area in AREA_EXPECTATIONS.keys():
		covered[str(AREA_EXPECTATIONS[area])] = true

	var unpinned: Array[String] = []
	for suffix in can_emit.keys():
		if not covered.has(suffix):
			unpinned.append(str(suffix))
	assert_eq(unpinned.size(), 0,
		"the resolver can return %s, and no area in AREA_EXPECTATIONS produces it — those arms are pinned by nothing. Add an area id that maps to each." % [unpinned])

	var phantom: Array[String] = []
	for suffix in covered.keys():
		if not can_emit.has(suffix):
			phantom.append(str(suffix))
	assert_eq(phantom.size(), 0,
		"AREA_EXPECTATIONS claims suffix(es) %s that the resolver can no longer return — the hand-list has drifted from the code" % [phantom])


func test_the_cached_return_cannot_smuggle_an_unseen_suffix() -> void:
	## The coverage test above parses LITERAL returns out of source. There is already ONE
	## non-literal return — the `_:` arm's `return _current_world_suffix` — and a literal scan
	## is blind to it (cowir-autogrind, msg 4250/4252). It is safe only because that cache has
	## a literal seed AND exactly one writer, fed from this function's own output. Both halves
	## are load-bearing, and the second breaks OUTSIDE the function the parser reads, so nothing
	## else here would see it. `status_durations` declared one writer and had two.
	var src: String = FileAccess.get_file_as_string("res://src/audio/SoundManager.gd")
	assert_gt(src.length(), 0, "control: source read returned nothing")

	var fn_start: int = src.find("func _get_current_world_suffix")
	var next_fn: int = src.find("\nfunc ", fn_start + 1)
	if next_fn < 0:
		next_fn = src.length()
	var body: String = _code_only(src.substr(fn_start, next_fn - fn_start))

	var non_literal: Array[String] = []
	var re := RegEx.create_from_string("(?m)^\\s*return\\s+(.+?)\\s*$")
	var total: int = 0
	for m in re.search_all(body):
		total += 1
		var expr: String = m.get_string(1)
		if not RegEx.create_from_string("^\"[a-z_]+\"$").search(expr):
			non_literal.append(expr)
	assert_gt(total, 5, "control: parsed %d returns — implausibly few, the extraction is wrong" % total)
	non_literal.sort()
	assert_eq(non_literal, ["_current_world_suffix", "room"] as Array[String],
		"the resolver's non-literal returns are %s. The coverage test parses LITERALS only, so any new one is a suffix arm it cannot see — pin it here AND prove its range, or make it literal." % [non_literal])


func test_the_interior_return_cannot_smuggle_a_suffix_either() -> void:
	## `return room` is the SECOND non-literal return (2026-09-12, interiors resolve
	## their world from the map rather than the cache). The cache argument above does
	## not cover it: its value comes from WeatherSystem.WORLD_IDS, a table outside this
	## function and outside the cache's one-writer proof.
	##
	## Making it literal would be a fourth copy of the world vocabulary, which this
	## file's subject exists to prevent. So the range is proved instead: every value
	## that table can yield must already be a LITERAL arm here, which is what makes it
	## visible to the coverage test above.
	var src: String = FileAccess.get_file_as_string("res://src/audio/SoundManager.gd")
	var fn_start: int = src.find("func _get_current_world_suffix")
	var next_fn: int = src.find("\nfunc ", fn_start + 1)
	var body: String = _code_only(src.substr(fn_start, next_fn - fn_start))

	var emitted: Array[String] = []
	for w in WeatherSystem.WORLD_IDS.keys():
		emitted.append(str(WeatherSystem.WORLD_IDS[w]))
	assert_gt(emitted.size(), 5,
		"CONTROL FAILED: WORLD_IDS yielded %d values — the table moved and this proves nothing" % emitted.size())

	var unseen: Array[String] = []
	for suffix in emitted:
		if not body.contains("return \"%s\"" % suffix):
			unseen.append(suffix)
	assert_eq(unseen.size(), 0,
		"WeatherSystem.WORLD_IDS can yield %s, which `return room` would hand back, and they are not literal arms in the resolver — so the coverage test above cannot see them and an interior could play a world nothing pins" % [unseen])

	var seed_re := RegEx.create_from_string("var _current_world_suffix: String = \"([a-z_]+)\"")
	var seed_m := seed_re.search(src)
	assert_not_null(seed_m, "could not find the _current_world_suffix declaration — it was renamed or its type changed")
	assert_true(RUNTIME_VOCABULARY.has(seed_m.get_string(1)),
		"_current_world_suffix is seeded with '%s', which is outside the vocabulary — the cached arm can emit a suffix nothing else expects" % seed_m.get_string(1))

	var writes := RegEx.create_from_string("(?m)^\\s*_current_world_suffix\\s*=").search_all(src)
	assert_eq(writes.size(), 1,
		"_current_world_suffix has %d assignment sites. It is safe ONLY as a cache of this function's own output; a second writer (save-load, settings restore, a test helper) breaks that invariant from outside the function the coverage parser reads." % writes.size())

	## The count above catches a writer APPEARING; this catches the writer MOVING (konsolai, 2026-08-09).
	assert_eq(src.split("\n").count("func play_area_music(area_type: String) -> void:"), 1,
		"SCOPE control: the play_area_music declaration must occur exactly once or the bounds below are arbitrary")
	var pam: int = src.find("func play_area_music(area_type: String) -> void:")
	var pam_end: int = src.find("\nfunc ", pam + 1)
	if pam_end < 0:
		pam_end = src.length()
	var w_at: int = writes[0].get_start() if writes.size() > 0 else -1
	assert_true(w_at > pam and w_at < pam_end,
		"the sole _current_world_suffix write is OUTSIDE play_area_music. size()==1 holds when the write MOVES, so the count cannot defend get_current_world_suffix's docstring, which names play_area_music as the only refresher and derives the divergence window from it: play_music clears _current_area WITHOUT refreshing, and a write relocated there would report the CURRENT area's world, making the documented window wrong in the opposite direction.")


func test_futuristic_is_NEVER_returned() -> void:
	## THE LOAD-BEARING GUARD. W5's monster ids and map ids say "futuristic"; the resolver
	## says "digital". Assets named from the ids are unreachable and nothing else notices.
	var sm: Node = _sm()
	var saved: Variant = sm._current_area
	var offenders: Array[String] = []
	for area in ["root_process", "overworld_futuristic", "futuristic_overworld", "node_prime_village", "digital_dungeon"]:
		sm._current_area = area
		if sm.get_current_world_suffix() == "futuristic":
			offenders.append(area)
	sm._current_area = saved
	assert_eq(offenders.size(), 0,
		"area(s) %s returned 'futuristic' — W5 must resolve to 'digital'; a sheet or track named _futuristic passes every presence check and never loads" % [offenders])


func test_the_word_futuristic_IS_in_the_body_which_is_why_grep_lies() -> void:
	## Pins WHY the naive check fails, so the next lane reads this instead of re-deriving it.
	var src: String = FileAccess.get_file_as_string("res://src/audio/SoundManager.gd")
	assert_gt(src.length(), 0, "control: source read returned nothing")
	assert_true(src.contains("futuristic"),
		"PREMISE: 'futuristic' must still appear in the file, else this test no longer explains anything")
	assert_false(src.contains("return \"futuristic\""),
		"a `return \"futuristic\"` was added — either W5's vocabulary changed everywhere, or an asset is about to be named for a suffix nothing else expects")


## Comment-strip that also drops """ blocks. GDScript docstrings are string
## LITERALS, so a #-only strip leaves them and prose quoting an arm reads AS the
## arm. Measured 2026-09-12: planting "scriptura_village" in the resolver's own
## docstring hid a DELETED arm from the scans here — the source assert fired 0
## times with it and 2 times without, and only a behavioural arm caught it.
##
## Drops the WHOLE line on a triple quote, which can also drop code sharing that
## line. That errs toward reporting an arm MISSING (a loud red) rather than
## present (a silent green), which is the direction a guard should fail in.
## Measured 2026-09-12, for whoever widens the scanned window later — this is the
## note that matters then, and it will not be in tonight's log:
##   SoundManager.gd     164 triple-quote lines · 0 that neither start nor end a line
##                       · 80 with two on one line (single-line docstrings)
##   audit_wrap_seams.py   7 · 0 · 1
## `find(TRIPLE)` rather than `begins_with` is why the 80 are handled: a line holding
## an opened AND closed docstring is dropped without arming in_doc. The one shape that
## would slip a begins_with version — a triple quote mid-line — occurs nowhere in
## either file, and @cowir-battle measured 0 of it across four more.
static func _code_only(body: String) -> String:
	var out: PackedStringArray = []
	var in_doc: bool = false
	for raw in body.split("\n"):
		if in_doc:
			if raw.contains(TRIPLE):
				in_doc = false
			continue
		var q: int = raw.find(TRIPLE)
		if q >= 0:
			if raw.find(TRIPLE, q + 3) < 0:
				in_doc = true
			continue
		out.append(raw.split("#")[0])
	return "\n".join(out)


## ⛔ A CONTROL THAT PROVES THE STRIPPER, because the stripper is what every source
## arm here rests on and nothing tested it. @cowir-battle found their equivalent
## control could not fail — it keyed on a phrase in the doc block ABOVE the `func`
## line while the scanned window starts AT it, so there was never a comment inside
## the window to remove. Two defences against that:
##
##   1. STRUCTURAL, not a phrase. Asserting "no `#` line and no triple quote
##      survives" cannot false-alarm when a comment is reworded — @cowir-battle's
##      other near-miss, where a guard passed only because the prose used backticks
##      where the assert looked for double quotes.
##   2. AN ANTI-VACUITY ASSERT. The RAW window must actually contain what we claim
##      to strip, so the arm cannot pass by having nothing to do.
func test_control_the_stripper_removes_both_comment_syntaxes() -> void:
	## ⛔ FEEDS A SYNTHETIC INPUT, because the scanned window does not contain every shape.
	## Measured 2026-09-12: that window has TWO multi-line delimiters and ZERO one-line
	## docstrings, so blinding the one-line branch left this control GREEN at 9 passing —
	## the code handled the shape and the control could not prove it.
	##
	## @cowir-autogrind hit the same clause harder: their control DID contain a one-liner,
	## in the assert_FALSE position, where blindness and correctness give the same answer.
	## A positive control validates the shapes it contains, and a shape that only appears
	## where absence is expected validates nothing. Both shapes are asserted PRESENT in the
	## raw input below before anything is asserted absent from the output.
	var raw: String = "\n".join([
		"func f() -> void:",
		"\t\"\"\"a one-line docstring mentioning ONELINE_NEEDLE\"\"\"",
		"\t\"\"\"a multi-line docstring",
		"\tmentioning MULTILINE_NEEDLE",
		"\t\"\"\"",
		"\tvar keep := 1  # mentioning HASH_NEEDLE",
		"\treturn"])
	assert_true(raw.contains("ONELINE_NEEDLE"), "ANTI-VACUITY: the synthetic input lost its one-line docstring")
	assert_true(raw.contains("MULTILINE_NEEDLE"), "ANTI-VACUITY: the synthetic input lost its multi-line docstring")
	assert_true(raw.contains("HASH_NEEDLE"), "ANTI-VACUITY: the synthetic input lost its # comment")

	var stripped: String = _code_only(raw)
	assert_false(stripped.contains("ONELINE_NEEDLE"),
		"a ONE-LINE docstring survived _code_only — a line carrying two delimiters must be dropped without arming the block state, or every source assert here can be satisfied by one-line prose")
	assert_false(stripped.contains("MULTILINE_NEEDLE"),
		"a multi-line docstring survived _code_only")
	assert_false(stripped.contains("HASH_NEEDLE"),
		"a # comment survived _code_only")
	assert_true(stripped.contains("var keep := 1"),
		"the stripper removed CODE that shared a line with a # comment — it must cut at the marker, not drop the line")

func _raw_resolver_body() -> String:
	var src: String = FileAccess.get_file_as_string("res://src/audio/SoundManager.gd")
	var a: int = src.find("func _get_current_world_suffix")
	var b: int = src.find("\nfunc ", a + 1)
	if b < 0:
		b = src.length()
	return src.substr(a, b - a)
