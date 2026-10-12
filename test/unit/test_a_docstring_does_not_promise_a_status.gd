extends GutTest

## `play_status`'s docstring read "(poison, sleep, confuse, paralyze, etc.)" and NOTHING in the
## game applies paralyze — 0 abilities author the effect, 0 add_status literals in src/, 0 entries
## in Combatant.STATUS_ALIASES (three axes, confirmed independently by cowir-battle). And
## status_paralyze.ogg was composed anyway.
##
## So the defect is not an extractor being fooled by prose — it is prose steering an AUTHOR into
## rendering an asset for a status that does not exist. A docstring example is an authoring
## instruction, and an unreachable one costs audio nobody can hear.
##
## ⚠️ THIS GUARD READS THE FILE RAW, DELIBERATELY, AND THAT IS THE OPPOSITE OF TONIGHT'S RULE.
## The usual hazard is prose reaching an extractor that wanted code; here the SUBJECT IS THE
## DOCSTRING, so `GdSource.code_of()` would strip the evidence and the guard would pass over any
## wording at all. The one case where raw is correct is when the thing asserted IS the prose.

const SM_SRC := "res://src/audio/SoundManager.gd"
const ABILITIES := "res://data/abilities.json"


## The docstring of play_status, bounded by the function that owns it — not a character window,
## which reds on an unrelated insertion and names the wrong file.
func _play_status_docstring() -> String:
	var raw: String = FileAccess.get_file_as_string(SM_SRC)
	var i: int = raw.find("func play_status(status_name")
	if i < 0:
		return ""
	var j: int = raw.find("\nfunc ", i + 10)
	var body: String = raw.substr(i, (j - i) if j > i else raw.length() - i)
	var a: int = body.find("\"\"\"")
	if a < 0:
		return ""
	var b: int = body.find("\"\"\"", a + 3)
	return body.substr(a + 3, (b - a - 3) if b > a else body.length() - a - 3)


## Statuses the engine can actually apply: an ability effect, or an add_status literal in src/.
func _reachable() -> Dictionary:
	var out := {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(ABILITIES))
	var ab: Dictionary = (parsed.get("abilities", parsed) if parsed is Dictionary else {}) as Dictionary
	for a in ab.values():
		if a is Dictionary:
			for k in ["effect", "secondary_effect"]:
				var e := str((a as Dictionary).get(k, "")).to_lower()
				if e != "":
					out[e] = true
	var re := RegEx.create_from_string("add_status\\(\\s*\"([a-z_]+)\"")
	for f in _gd_files("res://src"):
		for l in FileAccess.get_file_as_string(f).split("\n"):
			var t := str(l).strip_edges()
			if t.begins_with("#"):
				continue
			for m in re.search_all(l):
				out[m.get_string(1)] = true
	return out


func _gd_files(root: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(root)
	if d == null:
		return out
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		var p: String = root + "/" + n
		if d.current_is_dir():
			out += _gd_files(p)
		elif n.ends_with(".gd"):
			out.append(p)
		n = d.get_next()
	d.list_dir_end()
	return out


func test_the_docstring_only_names_statuses_the_engine_can_apply() -> void:
	var doc: String = _play_status_docstring()
	assert_ne(doc, "", "CONTROL: play_status's docstring not found, so this arm read nothing")
	## The example list is the parenthesised group on the summary line.
	var re := RegEx.create_from_string("\\(([a-z_, ]+), etc\\.\\)")
	var m := re.search(doc)
	assert_not_null(m, "CONTROL: the docstring no longer carries a '(a, b, c, etc.)' example list — if the wording changed, re-point this arm rather than deleting it")
	if m == null:
		return
	var named: Array = []
	for part in m.get_string(1).split(","):
		var t := str(part).strip_edges()
		if t != "":
			named.append(t)
	assert_gt(named.size(), 1, "CONTROL: derived %d example(s); a list this short means the scan narrowed" % named.size())
	var reachable: Dictionary = _reachable()
	assert_gt(reachable.size(), 40, "CONTROL: only %d reachable statuses derived — the corpus is wrong and a zero below would prove nothing" % reachable.size())
	var unreachable: Array = []
	for s in named:
		if not reachable.has(str(s)):
			unreachable.append(str(s))
	assert_eq(unreachable.size(), 0,
		"play_status's docstring names %s, which the engine cannot apply — 0 ability effects and 0 add_status literals. A docstring example is an authoring instruction, and status_paralyze.ogg was composed from exactly this: %s" % [str(unreachable), str(named)])


func test_the_reachable_set_is_not_vacuously_wide() -> void:
	## If _reachable() accepted anything, the arm above could never red. Two controls: a status the
	## engine really applies must be in it, and an invented one must not.
	var r: Dictionary = _reachable()
	assert_true(r.has("poison"), "CONTROL: poison is applied by 11 abilities and must be reachable, or the derivation is broken")
	assert_true(r.has("stun"), "CONTROL: stun is applied by 18 abilities and must be reachable")
	assert_false(r.has("qqq_not_a_real_status"),
		"the reachable set accepts an invented status, so it cannot refuse anything the docstring names")
	assert_false(r.has("paralyze"),
		"paralyze is now reachable — if it was deliberately wired, say so and update the docstring; status_paralyze.ogg already exists for it")


func test_the_docstring_survives_the_stripper_this_guard_must_not_use() -> void:
	## Proves the deliberate raw read is load-bearing rather than careless: the shared stripper
	## removes the very text this file asserts on, so a GdSource read here would pass over any
	## wording at all. Named so nobody "fixes" this file by routing it through GdSource.
	var GdSource = load("res://test/unit/helpers/gd_source.gd")
	assert_not_null(GdSource, "CONTROL: the shared stripper must exist for this comparison")
	if GdSource == null:
		return
	var stripped: String = GdSource.code_of(SM_SRC)
	assert_false(stripped.contains("Play sound for a status effect application"),
		"GdSource no longer strips docstrings, so the raw read in this file is no longer necessary — re-point it and delete this arm")
	assert_true(FileAccess.get_file_as_string(SM_SRC).contains("Play sound for a status effect application"),
		"CONTROL: the raw read must see the docstring the stripped read cannot")
