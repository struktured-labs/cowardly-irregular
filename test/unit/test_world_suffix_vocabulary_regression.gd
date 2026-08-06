extends GutTest

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
	var body: String = src.substr(fn_start, next_fn - fn_start)
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
	var body: String = src.substr(fn_start, next_fn - fn_start)

	var non_literal: Array[String] = []
	var re := RegEx.create_from_string("(?m)^\\s*return\\s+(.+?)\\s*$")
	var total: int = 0
	for m in re.search_all(body):
		total += 1
		var expr: String = m.get_string(1)
		if not RegEx.create_from_string("^\"[a-z_]+\"$").search(expr):
			non_literal.append(expr)
	assert_gt(total, 5, "control: parsed %d returns — implausibly few, the extraction is wrong" % total)
	assert_eq(non_literal, ["_current_world_suffix"] as Array[String],
		"the resolver's non-literal returns are %s. The coverage test parses LITERALS only, so any new one is a suffix arm it cannot see — pin it here or make it literal." % [non_literal])

	var seed_re := RegEx.create_from_string("var _current_world_suffix: String = \"([a-z_]+)\"")
	var seed_m := seed_re.search(src)
	assert_not_null(seed_m, "could not find the _current_world_suffix declaration — it was renamed or its type changed")
	assert_true(RUNTIME_VOCABULARY.has(seed_m.get_string(1)),
		"_current_world_suffix is seeded with '%s', which is outside the vocabulary — the cached arm can emit a suffix nothing else expects" % seed_m.get_string(1))

	var writes := RegEx.create_from_string("(?m)^\\s*_current_world_suffix\\s*=").search_all(src)
	assert_eq(writes.size(), 1,
		"_current_world_suffix has %d assignment sites. It is safe ONLY as a cache of this function's own output; a second writer (save-load, settings restore, a test helper) breaks that invariant from outside the function the coverage parser reads." % writes.size())


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
