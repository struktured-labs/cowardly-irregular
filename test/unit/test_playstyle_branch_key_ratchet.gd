extends GutTest

## Every authored playstyle branch key must be a value the classifier can return.
##
## THE DEFECT THIS EXISTS FOR: `CutsceneDirector` resolves a playstyle branch with
##   cases.get(playstyle, cases.get("default", []))
## so a key the classifier never returns doesn't error, doesn't warn, and doesn't
## show up in any log — it silently takes the default branch forever. The authored
## content simply never plays.
##
## FOUND LIVE (cowir-ai, 2026-07-28): "completionist" is authored in all FOUR
## Masterite encounter cutscenes — warden, arbiter, curator, tempo — and
## `_detect_playstyle()` returns exactly five values, none of which is that. Those
## are the four-axis PROFILING encounters, so a completionist branch is thematically
## the whole point there; this reads as an unimplemented playstyle rather than a
## typo. Either way the branches have never rendered.
##
## Same class as cowir-overworld's typo'd `target_map` (silently dumps the player on
## the overworld) and my own persona/boss-id joins: a reference that is PRESENT BUT
## UNRESOLVABLE fails differently from one that's absent, and every cheap check
## passes.
##
## DERIVED, NOT LISTED. The valid set is parsed out of `_detect_playstyle`'s own
## `return` statements rather than hardcoded here, so adding a playstyle to the
## classifier automatically widens what authors may use — no table to fall out of
## date, which is the failure mode that retired the hand-maintained canon tables
## elsewhere in this suite.

const DIRECTOR_PATH: String = "res://src/cutscene/CutsceneDirector.gd"
const CUTSCENE_DIR: String = "res://data/cutscenes"

## Always legal — the explicit fallback arm, not a playstyle.
const RESERVED_KEYS: Array[String] = ["default"]


## Parse the classifier's reachable outputs from its own source.
func _classifier_returns() -> Array:
	var src: String = FileAccess.get_file_as_string(DIRECTOR_PATH)
	assert_false(src.is_empty(), "CutsceneDirector must be readable")
	var start: int = src.find("func _detect_playstyle")
	assert_gt(start, -1, "_detect_playstyle must exist — if it was renamed, this ratchet is measuring nothing")
	# Bound at the next top-level func so we never absorb a neighbour's returns.
	var end: int = src.find("\nfunc ", start + 1)
	if end == -1:
		end = src.length()
	var body: String = src.substr(start, end - start)
	var out: Array = []
	var re := RegEx.new()
	re.compile('return\\s+"([a-z_]+)"')
	for m in re.search_all(body):
		var v: String = m.get_string(1)
		if not out.has(v):
			out.append(v)
	return out


## Every {condition:"playstyle"} step's case keys, with the file they came from.
func _authored_keys() -> Array:
	var found: Array = []
	var dir := DirAccess.open(CUTSCENE_DIR)
	assert_not_null(dir, "cutscene dir must be readable")
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.ends_with(".json"):
			var path: String = CUTSCENE_DIR.path_join(fname)
			var json := JSON.new()
			if json.parse(FileAccess.get_file_as_string(path)) == OK:
				_collect(json.data, fname, found)
		fname = dir.get_next()
	dir.list_dir_end()
	return found


func _collect(node: Variant, fname: String, out: Array) -> void:
	if node is Dictionary:
		var d: Dictionary = node
		if str(d.get("condition", "")) == "playstyle":
			var cases: Variant = d.get("cases", {})
			if cases is Dictionary:
				for k in (cases as Dictionary).keys():
					out.append({"file": fname, "key": str(k)})
		for v in d.values():
			_collect(v, fname, out)
	elif node is Array:
		for v in node:
			_collect(v, fname, out)


# ── Positive controls — a vacuous pass must be impossible ────────────────────

func test_scan_actually_finds_the_classifier_outputs() -> void:
	# cowir-cutscenes' point: a sweep returning zero and a sweep that iterated
	# nothing are indistinguishable without this.
	var returns: Array = _classifier_returns()
	assert_gt(returns.size(), 2,
		"parsed only %d classifier returns — the parse has broken, so an empty offender list would prove nothing" % returns.size())


func test_scan_actually_finds_authored_branches() -> void:
	var keys: Array = _authored_keys()
	assert_gt(keys.size(), 2,
		"found only %d authored playstyle keys — the JSON walk has broken" % keys.size())


# ── The guard ────────────────────────────────────────────────────────────────

func test_every_authored_key_is_reachable() -> void:
	var valid: Array = _classifier_returns()
	for entry in _authored_keys():
		var key: String = str(entry["key"])
		if RESERVED_KEYS.has(key):
			continue
		assert_true(valid.has(key),
			("%s authors playstyle branch '%s', which _detect_playstyle() can never return " +
			"(reachable: %s). CutsceneDirector resolves via cases.get(playstyle, default), so this " +
			"branch silently takes the default arm and its content has NEVER played — no error, no warning.")
			% [entry["file"], key, str(valid)])


## Mirror of _detect_playstyle's arms, for reachability analysis only.
## Kept in test-land deliberately: this is not a second implementation anyone
## ships against, it exists so the arms can be exercised over an input grid.
## If it drifts from the real function, test_mirror_matches_source_arm_order
## fails and this file stops being trustworthy — which is the honest outcome.
func _mirror_classify(ratio: float, total: int) -> String:
	if ratio > 0.7 and total >= 20:
		return "automator"
	if total > 100:
		return "grinder"
	if total > 0 and total < 40:
		return "exploiter"
	if ratio < 0.3 and total >= 20:
		return "manual"
	return "balanced"


func test_mirror_matches_source_arm_order() -> void:
	# The mirror is only evidence if it still reflects the source. Pin the
	# thresholds textually so a change to the real function invalidates it
	# loudly rather than letting the reachability tests below quietly lie.
	var src: String = FileAccess.get_file_as_string(DIRECTOR_PATH)
	for needle in [
		"ratio > 0.7 and total_battles >= 20",
		"total_battles > 100",
		"total_battles > 0 and total_battles < 40",
		"autobattle_ratio < 0.3 and total_battles >= 20",
	]:
		assert_true(src.find(needle) != -1,
			("_detect_playstyle no longer contains `%s`. The reachability mirror in this file is " +
			"now stale — update it before trusting any reachability result here.") % needle)


func test_every_classifier_output_is_reachable_by_some_input() -> void:
	# STATIC key-validity (above) is not runtime reachability. An arm can be a
	# legal return value and still be shadowed into unreachability by an earlier
	# arm — which is a different defect, invisible to a key check, and the one
	# that actually bit: two of W6's four authored endings never play.
	#
	# This guards the total case only: an output no input can ever produce.
	# It does NOT assert reachability within any particular battle-count band —
	# see the note below, which is a KNOWN OPEN issue, not something this covers.
	var produced: Dictionary = {}
	for total in range(0, 260, 1):
		for r10 in range(0, 11):
			produced[_mirror_classify(float(r10) / 10.0, total)] = true
	for value in _classifier_returns():
		assert_true(produced.has(value),
			("_detect_playstyle can return '%s' but NO (ratio, battles) input produces it — an earlier arm " +
			"shadows it completely. Any cutscene branching on it is dead content.") % value)


func test_endgame_reachability_is_documented_not_silently_lost() -> void:
	# NOT asserting all five are reachable at endgame — they are not, and that
	# is a live open issue owned by cowir-cutscenes (cowir-battle msg 3207,
	# cowir-story msg 3209: `manual` dies above 100 battles and `exploiter`
	# above 40, so two of the four authored W6 endings can never play).
	#
	# What this pins is that the situation does not get WORSE unnoticed: at a
	# W6-era battle count at least the two known-reachable outputs must remain
	# reachable. If that ever drops to one, the ending collapses to a single
	# branch and someone should be told immediately.
	var endgame: Dictionary = {}
	for r10 in range(0, 11):
		endgame[_mirror_classify(float(r10) / 10.0, 150)] = true
	assert_gte(endgame.size(), 2,
		("at 150 battles only %d playstyle output(s) are reachable (%s). W6's ending branches on this; " +
		"dropping below two collapses it to a single branch for every player.")
		% [endgame.size(), str(endgame.keys())])


func test_classifier_outputs_are_not_silently_unauthored() -> void:
	# The reverse direction. A playstyle the classifier can return but which no
	# cutscene ever branches on isn't a defect — it's just unused — so this is
	# informational rather than strict. It fails only if NOTHING authors ANY of
	# them, which would mean the whole mechanism is dead.
	var valid: Array = _classifier_returns()
	var authored: Dictionary = {}
	for entry in _authored_keys():
		authored[str(entry["key"])] = true
	var used: int = 0
	for v in valid:
		if authored.has(v):
			used += 1
	assert_gt(used, 0,
		"no cutscene branches on ANY classifier output (%s) — the playstyle mechanism would be entirely dead" % str(valid))
