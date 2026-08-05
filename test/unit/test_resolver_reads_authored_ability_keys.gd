extends GutTest

## The same dead-key defect was fixed TWICE in this file, a month apart (2026-08-05).
##
##   765bbc22  06-29  "dispatches on type not category"   fixed ONE site (:658)
##   7597d602  07-31  "enemies never cast and never healed" fixed the TWO helpers
##
## The June fix carried its own regression test and a comment saying `category`
## "no ability authors" — and the two ability-finding helpers went on reading
## `category` for another month, so every autogrind enemy plain-attacked and never
## healed. A point-fix plus a point-test could not see its own siblings.
##
## cowir-autogrind's read (msg 4211): a site fixed twice for one cause wants a
## guard on the CAUSE, not a third fix. The cause is a key read from authored data
## that the data never authors — `.get()` then silently returns the default.
##
## PREDICATE: every ability-dict key this resolver reads must either be authored by
## abilities.json, or appear in a fallback chain that terminates in a key that is.
##
##     ability.get("category", "magic")                  OFFENDER — default always wins
##     ability.get("type", ability.get("category", ""))  FINE — `type` is authored
##     ability.get("power", ability.get("damage_multiplier", 0.0))  FINE
##
## That distinction is the whole guard: it permits the legacy-key-first shape the
## file deliberately uses, and reds on a key with no authored member behind it.

const RESOLVER := "res://src/autogrind/HeadlessBattleResolver.gd"
const ABILITIES := "res://data/abilities.json"


func _authored_keys() -> Dictionary:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ABILITIES))
	var ab: Dictionary = raw.get("abilities", raw)
	var counts: Dictionary = {}
	for id in ab:
		for k in (ab[id] as Dictionary):
			counts[k] = int(counts.get(k, 0)) + 1
	return counts


## Every `ability.get("key"` occurrence, paired with the rest of its expression so a
## nested fallback is visible. Deliberately source-level: the defect is a key that
## resolves to a default, which is indistinguishable from a legitimate value at runtime.
## ⚠️ COMMENTS ARE STRIPPED FIRST, and that is not incidental: the June fix's own
## comment quotes `ability.get("category", "magic")` verbatim to explain the defect.
## The first version of this guard matched that comment and reported the file broken
## — a scanner that does not model comments finds a fix's description and calls it
## the bug. Caught by running it, not by writing it carefully.
func _code_lines() -> PackedStringArray:
	var out := PackedStringArray()
	for raw in FileAccess.get_file_as_string(RESOLVER).split("\n"):
		var line: String = str(raw)
		if line.strip_edges().begins_with("#"):
			continue
		out.append(line)
	return out


func _read_sites() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var re := RegEx.create_from_string('ability\\.get\\(\\s*"([a-z_0-9]+)"')
	for line in _code_lines():
		for m in re.search_all(line):
			out.append({"key": m.get_string(1), "line": str(line).strip_edges()})
	return out


func test_the_corpus_and_the_source_both_load() -> void:
	# POSITIVE CONTROLS. Every assertion below passes vacuously against an empty
	# parse or an unreadable file, which is exactly what a wrong path returns.
	var authored := _authored_keys()
	assert_gt(authored.size(), 10, "abilities.json must parse to a real key set; got %d" % authored.size())
	assert_eq(int(authored.get("type", 0)), 289,
		"NAMED-MEMBER control: `type` is authored by every ability — if this is not 289 the corpus changed and the numbers below mean something else")
	assert_gt(_read_sites().size(), 5,
		"the resolver must contain ability.get() sites; %d found" % _read_sites().size())


func test_every_key_the_resolver_reads_has_an_authored_member_behind_it() -> void:
	# The guard. A key authored by nothing is fine ONLY if the same expression
	# falls back to a key that is authored — which is the shape both prior fixes
	# landed on, and the shape a third regression would break.
	var authored := _authored_keys()
	var offenders: Array[String] = []
	for site in _read_sites():
		var key: String = str(site["key"])
		if int(authored.get(key, 0)) > 0:
			continue
		# unauthored — does anything else on this line rescue it?
		var rescued: bool = false
		for other in authored:
			if int(authored[other]) > 0 and str(site["line"]).contains('"%s"' % other):
				rescued = true
				break
		if not rescued:
			offenders.append("%s  (in: %s)" % [key, str(site["line"])])
	assert_eq(offenders, [] as Array[String],
		"these keys are read from ability data that authors them ZERO times, with no authored fallback in the same expression — .get() will return the default forever and the surrounding logic silently collapses: %s" % str(offenders))


func test_the_two_historically_broken_keys_are_still_chained_not_bare() -> void:
	# Named pins for the exact pair that broke twice. The general guard above would
	# catch a bare re-introduction, but naming them means a failure says WHICH
	# regression came back rather than making the next reader re-derive it.
	# ⚠️ Asserted PER LINE, not by substring count. A bare `ability.get("category", x)`
	# and the inner half of `get("type", get("category", x))` share the same substring,
	# so a count cannot tell the defect from the fix — my first version pinned the count
	# and failed on correct code. The invariant is that the dead key never appears
	# WITHOUT its authored partner on the same line.
	var unpartnered: Array[String] = []
	for line in _code_lines():
		var l: String = str(line)
		if l.contains('ability.get("category"') and not l.contains('ability.get("type"'):
			unpartnered.append(l.strip_edges())
		if l.contains('ability.get("power"') and not l.contains('damage_multiplier'):
			unpartnered.append(l.strip_edges())
	assert_eq(unpartnered, [] as Array[String],
		"a historically-broken key appears without its authored partner — 765bbc22 fixed `category` and 7597d602 fixed it again in two more helpers: %s" % str(unpartnered))


func test_the_guard_can_actually_fail() -> void:
	# The offender list being empty is the success value AND what a broken sweep
	# returns. Prove the predicate discriminates on a synthetic line rather than
	# trusting that it would.
	var authored := _authored_keys()
	var bare_line: String = 'var x = ability.get("category", "magic")'
	var chained_line: String = 'var x = ability.get("type", ability.get("category", "magic"))'
	var bare_rescued: bool = false
	var chained_rescued: bool = false
	for other in authored:
		if int(authored[other]) > 0 and bare_line.contains('"%s"' % other):
			bare_rescued = true
		if int(authored[other]) > 0 and chained_line.contains('"%s"' % other):
			chained_rescued = true
	assert_false(bare_rescued, "a bare unauthored read must NOT be treated as rescued, or the guard permits the defect it exists for")
	assert_true(chained_rescued, "a chained read MUST be treated as rescued, or the guard reds on the file's deliberate legacy-key-first shape")
