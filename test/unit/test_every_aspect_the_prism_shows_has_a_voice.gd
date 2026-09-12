extends GutTest

## Two of the Prismatic Construct's three aspects could never be looked up.
##
## The mage spotlight duel rotates one live element per round —
## `BattleManager._apply_weakness_cycles` reads `weakness_cycle` from
## monsters.json — and `boss_dialogue.json` authors an `aspect_labels` block
## giving each aspect a sprite tag, a colour and the lines the Construct speaks
## as it shifts. The two files disagreed on the vocabulary:
##
##     weakness_cycle  (engine)     fire · ice   · lightning
##     aspect_labels   (authored)   fire · frost · storm
##
## One of three resolved. `frost` and `storm` are the FLAVOUR names; `ice` and
## `lightning` are the element ids the engine actually cycles. So a lookup keyed
## by the live element found an entry on fire rounds and nothing on the other two.
##
## ⛔ REDUNDANT BY DISCARD, and that is why it survived two months: `aspect_labels`
## has no consumer in src/ yet — its own `_comment` assigns the engine hook to
## cowir-main — so nothing could observe the mismatch. **The commit that wires the
## hook is the commit that exposes it**, and it would have exposed it as silence on
## two rounds in three rather than as an error.
##
## FIXED IN THE DATA, not in a lookup: the keys are now engine element ids and the
## flavour name lives in `tag`, which is what a player actually reads (FROST, STORM).
## A fix in the consumer would have had to know both vocabularies, and the next
## consumer would have had to know them too.
##
## ⚠️ NOT WIRED HERE. Whoever wires the hook gets a resolution they can trust; this
## guard is what makes that true. Deliberately no "has no consumer yet" tripwire —
## the ratchet below makes wiring safe, so a red on the day someone wires it would
## be noise rather than a review prompt.

const BOSS_DIALOGUE := "res://data/boss_dialogue.json"
const MONSTERS := "res://data/monsters.json"


## Parsed once per test. The first draft called _load() inside the loops, which
## re-parsed monsters.json per boss — 1446 asserts and 1.4s for a 7-arm file, and
## an assert count that could no longer be compared against what was authored.
var _cycling: Dictionary = {}
var _labelled: Dictionary = {}


func before_each() -> void:
	_cycling = _cycling_bosses()
	_labelled = _labelled_bosses()


func _load(path: String) -> Dictionary:
	var raw: String = FileAccess.get_file_as_string(path)
	if raw.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw)
	return parsed as Dictionary if parsed is Dictionary else {}


## Every boss the ENGINE cycles: id -> the elements it rotates through.
func _cycling_bosses() -> Dictionary:
	var out: Dictionary = {}
	var db: Dictionary = _load(MONSTERS)
	for mid in db:
		var row: Variant = db[mid]
		if not (row is Dictionary):
			continue
		var cyc: Variant = (row as Dictionary).get("weakness_cycle", [])
		if cyc is Array and (cyc as Array).size() > 0:
			out[str(mid)] = cyc
	return out


## Every boss with an AUTHORED label block: id -> aspect key -> entry.
func _labelled_bosses() -> Dictionary:
	var out: Dictionary = {}
	var db: Dictionary = _load(BOSS_DIALOGUE)
	for bid in db:
		var row: Variant = db[bid]
		if not (row is Dictionary):
			continue
		var al: Variant = (row as Dictionary).get("aspect_labels", null)
		if not (al is Dictionary):
			continue
		var clean: Dictionary = {}
		for k in (al as Dictionary):
			if not str(k).begins_with("_"):
				clean[str(k)] = (al as Dictionary)[k]
		out[str(bid)] = clean
	return out


# ── the defect ────────────────────────────────────────────────────────────────

func test_every_element_the_engine_cycles_has_an_aspect_entry() -> void:
	## THE ARM. `ice` and `lightning` were authored as `frost` and `storm`, so a
	## lookup by the live element found nothing on two rounds in three.
	var labelled: Dictionary = _labelled
	var missing: Array[String] = []
	for bid in _cycling:
		if not labelled.has(bid):
			continue
		for element in (_cycling[bid] as Array):
			if not (labelled[bid] as Dictionary).has(str(element)):
				missing.append("%s/%s" % [bid, str(element)])
	assert_eq(missing, ([] as Array[String]),
		("these cycled elements have no aspect_labels entry, so the boss says nothing on "
		+ "those rounds: %s. Key aspect_labels by the ENGINE element id (weakness_cycle); "
		+ "the flavour name belongs in `tag`.") % ", ".join(missing))


func test_no_aspect_is_authored_for_an_element_that_never_comes_up() -> void:
	## The reverse, and the shape the bug actually had: `frost`/`storm` were
	## authored for elements the engine never sets, so the content was unreachable
	## rather than merely unused.
	var cycling: Dictionary = _cycling
	var orphans: Array[String] = []
	for bid in _labelled:
		if not cycling.has(bid):
			continue
		for key in (_labelled[bid] as Dictionary):
			if not (cycling[bid] as Array).has(str(key)):
				orphans.append("%s/%s" % [bid, str(key)])
	assert_eq(orphans, ([] as Array[String]),
		("these aspects are authored for elements the engine never cycles to, so no "
		+ "player can reach them: %s") % ", ".join(orphans))


# ── the entries must be usable once they resolve ──────────────────────────────

func test_every_aspect_carries_what_the_hook_will_read() -> void:
	## Resolution is not enough — an entry that resolves to an empty tag or no
	## lines is the same silence one step later.
	var gaps: Array[String] = []
	for bid in _labelled:
		for key in (_labelled[bid] as Dictionary):
			var e: Variant = (_labelled[bid] as Dictionary)[key]
			if not (e is Dictionary):
				gaps.append("%s/%s is not a Dictionary" % [bid, key])
				continue
			var d: Dictionary = e as Dictionary
			if str(d.get("tag", "")).strip_edges().is_empty():
				gaps.append("%s/%s tag" % [bid, key])
			if str(d.get("color", "")).strip_edges().is_empty():
				gaps.append("%s/%s color" % [bid, key])
			var lines: Variant = d.get("announce_lines", [])
			if not (lines is Array) or (lines as Array).is_empty():
				gaps.append("%s/%s announce_lines" % [bid, key])
	assert_eq(gaps, ([] as Array[String]),
		"aspect entries missing what the hook reads: %s" % ", ".join(gaps))


func test_an_aspect_says_its_own_name_at_least_once() -> void:
	## The legibility floor the block exists for. Not EVERY line — measured, 2 of 3
	## name the tag and the third names the colour in prose, which is correct
	## authoring. One plain statement per aspect is the property worth pinning.
	var mute: Array[String] = []
	for bid in _labelled:
		for key in (_labelled[bid] as Dictionary):
			var d: Dictionary = (_labelled[bid] as Dictionary)[key] as Dictionary
			var tag: String = str(d.get("tag", ""))
			var named: bool = false
			for line in (d.get("announce_lines", []) as Array):
				if str(line).find(tag) != -1:
					named = true
					break
			if not named:
				mute.append("%s/%s (tag %s)" % [bid, key, tag])
	assert_eq(mute, ([] as Array[String]),
		("no announce line names the aspect, so the player cannot tell which one is "
		+ "live from the dialogue alone: %s") % ", ".join(mute))


# ── controls ──────────────────────────────────────────────────────────────────

func test_the_two_corpora_are_non_empty_and_overlap() -> void:
	## CONTROL. Both arms above loop over an intersection. If either side were
	## empty — a renamed key, a parse failure, a boss id that stopped matching —
	## every arm would pass by iterating nothing.
	var cycling: Dictionary = _cycling
	var labelled: Dictionary = _labelled
	assert_gt(cycling.size(), 0, "no boss declares a weakness_cycle — the engine side is empty")
	assert_gt(labelled.size(), 0, "no boss declares aspect_labels — the authored side is empty")
	var shared: int = 0
	for bid in cycling:
		if labelled.has(bid):
			shared += 1
	assert_gt(shared, 0,
		("no boss appears in BOTH files, so every arm here iterates nothing. The ids "
		+ "diverged: cycling=%s labelled=%s") % [str(cycling.keys()), str(labelled.keys())])


func test_the_construct_is_still_the_case_this_was_written_for() -> void:
	## CONTROL on the fixture: the arms are generic, but they were measured against
	## this boss. If it stops cycling three elements the header's numbers are stale.
	var cycling: Dictionary = _cycling
	assert_true(cycling.has("mage_prismatic_construct"),
		"the mage duel no longer declares a weakness_cycle — re-read this file's header")
	assert_eq((cycling["mage_prismatic_construct"] as Array).size(), 3,
		"the Construct cycles %d elements, not the 3 this file was measured against"
		% (cycling["mage_prismatic_construct"] as Array).size())


func test_the_engine_really_reads_the_cycle_key_this_file_derives_from() -> void:
	## THE PREMISE. Every arm treats `weakness_cycle` as the engine's vocabulary.
	## If BattleManager stopped reading that key, this guard would be comparing
	## authored content against a field nothing consumes.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_false(src.is_empty(), "CONTROL: BattleManager must load")
	assert_true(_code_only(src, "func _apply_weakness_cycles() -> void:").find("\"weakness_cycle\"") != -1,
		("BattleManager no longer reads \"weakness_cycle\", so the element vocabulary this "
		+ "file checks against is not the one the engine cycles."))


func _code_only(src: String, must_survive: String) -> String:
	var out: PackedStringArray = PackedStringArray()
	var in_doc: bool = false
	for line in src.split("\n"):
		var hash_at: int = line.find("#")
		var code: String = line if hash_at == -1 else line.substr(0, hash_at)
		var trimmed: String = code.strip_edges()
		if in_doc:
			if trimmed.ends_with("\"\"\""):
				in_doc = false
			continue
		if trimmed.begins_with("\"\"\""):
			if trimmed.count("\"\"\"") % 2 == 1:
				in_doc = true
			continue
		out.append(code)
	var stripped: String = "\n".join(out)
	assert_true(stripped.find(must_survive) != -1,
		"STRIPPER CONTROL: '%s' must survive stripping" % must_survive)
	return stripped
