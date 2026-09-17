extends GutTest

## An authored key must be READ by the runtime or DECLARED inert with a note naming who holds it.
## cowir-music's rule, endorsed by cowir-main 2026-09-16, after a day in which four authored keys
## across three lanes turned out to promise behaviour nothing implemented — `reflect_damage_element`
## (a boss move doing half what it says), `_condition` (five dialogue lines gating on nothing),
## `session_scope`, `corruption_threshold`. The manifest is this lane's version of that surface.
##
## ⛔ THE FIRST VERSION OF THIS FILE SEARCHED ALL OF src/ FOR A QUOTED KEY AND SAID SO: crude, and
## trusted ONLY on zeroes, because `"tier"` matches autogrind's grind tier and `"attack"` matches
## every animation name in the codebase. That was honest and it was also blind — 9 fields with 504
## authored instances sat in the gap where a name appears but nothing reads it, `tier` (315 entries)
## and `source` (165) among them.
##
## 🔑 cowir-battle's refinement (2026-09-16, `2d14d92d`) is what closes it: a key can have a reader
## and still be dead on the path its data takes. So the census now answers in THREE states, and the
## third is the one that earns its place:
##
##   READ       a literal key access — get("k"), ["k"], has("k") — inside a file that PARSES the
##              manifest. A hit here is real: that file holds the entry dictionaries.
##   UNREAD     the quoted name appears nowhere in src/ at all. Nothing can read what is not named.
##   UNDECIDED  the name appears, but no literal access in a parsing file. Either a collision, or a
##              key supplied by a VARIABLE. THE INSTRUMENT CANNOT TELL, so a human must, once, in
##              writing — which is what _field_provenance / _field_indirect_readers / _section_
##              provenance are for.
##
## ⚠️ BOTH SINGLE-INSTRUMENT ANSWERS ARE WRONG IN OPPOSITE DIRECTIONS, measured on this manifest:
## a bare-name search calls `idle`/`attack` read (they are weapon_sheets keys colliding with
## animation names) and a key-access search calls `cliff`/`overlay` unread (they ARE read, passed
## as a section argument by EnvironmentTileSets). Neither is trustworthy alone; the third state is
## the honest shape, the same three-state discipline tools/run_tests.sh uses for its own vacuity.
const MANIFEST := "res://data/sprite_manifest.json"
const SRC_ROOT := "res://src"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")

## The file the corpus is DISCOVERED by. A hand-list would have to be updated by whoever adds the
## next parser, which is the failure three lanes hit today in their own guards.
const MANIFEST_FILENAME := "sprite_manifest.json"


func _manifest() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	return parsed if parsed is Dictionary else {}


func _gd_files() -> Array[String]:
	var out: Array[String] = []
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
				out.append(full)
			n = d.get_next()
		d.list_dir_end()
	return out


## Stripped of BOTH comment kinds. My own probe for this change used a `#`-only strip and pulled
## BattleScene into the corpus on the strength of a `"""` docstring mentioning the manifest — the
## defect gd_source.gd's header records, reproduced by the person who read that header.
func _code_of_all() -> String:
	var parts: PackedStringArray = []
	for f in _gd_files():
		parts.append(GdSource.code_of(f))
	return "\n".join(parts)


func _corpus() -> String:
	var parts: PackedStringArray = []
	for f in _gd_files():
		var code: String = GdSource.code_of(f)
		if code.contains(MANIFEST_FILENAME):
			parts.append(code)
	return "\n".join(parts)


func _key_accessed(field: String, blob: String) -> bool:
	return blob.contains("get(\"%s\"" % field) \
		or blob.contains("[\"%s\"]" % field) \
		or blob.contains("has(\"%s\")" % field)


## Every field name in any entry of any section -> how many entries carry it.
func _fields() -> Dictionary:
	var out := {}
	for section in _manifest():
		if str(section).begins_with("_"):
			continue
		var node = _manifest()[section]
		if not (node is Dictionary):
			continue
		for key in node:
			var entry = node[key]
			if not (entry is Dictionary):
				continue
			for f in entry:
				out[str(f)] = int(out.get(str(f), 0)) + 1
	return out


## field -> the sections that author it, so a field covered by a SECTION declaration is resolved.
func _field_sections() -> Dictionary:
	var out := {}
	for section in _manifest():
		if str(section).begins_with("_"):
			continue
		var node = _manifest()[section]
		if not (node is Dictionary):
			continue
		for key in node:
			var entry = node[key]
			if not (entry is Dictionary):
				continue
			for f in entry:
				if not out.has(str(f)):
					out[str(f)] = {}
				out[str(f)][str(section)] = true
	return out


func _declared_anywhere(field: String) -> bool:
	var m := _manifest()
	if (m.get("_field_provenance", {}) as Dictionary).has(field):
		return true
	if (m.get("_field_indirect_readers", {}) as Dictionary).has(field):
		return true
	var sections: Dictionary = (_field_sections().get(field, {}) as Dictionary)
	var declared_sections: Dictionary = m.get("_section_provenance", {})
	if sections.is_empty():
		return false
	for s in sections:
		if not declared_sections.has(s):
			return false
	return true   # every section that authors this field is itself declared inert


## ⛔ THE INSTRUMENT, FIRST AND BOTH WAYS. Every arm below is satisfied by a corpus that found
## nothing, so the corpus is proven to contain a key we KNOW is read and to reject a key we know
## is not, before any field is judged.
func test_the_census_corpus_is_real_and_controls_both_ways() -> void:
	var all_src := _code_of_all()
	assert_gt(all_src.length(), 100000,
		"ANTI-VACUITY: only %d chars of src/ were read — a short corpus makes every field look unread" % all_src.length())
	var corpus := _corpus()
	assert_gt(corpus.length(), 5000,
		"ANTI-VACUITY: the manifest-reading corpus is %d chars — discovery found nothing to census against" % corpus.length())
	assert_true(_key_accessed("frame_width", corpus),
		"CONTROL: frame_width is read by the sheet loader — if the corpus cannot see it, every 'unread' below is false")
	assert_true(_key_accessed("path", corpus),
		"CONTROL: path is read by every loader in the corpus")
	assert_false(_key_accessed("__no_such_manifest_field__", corpus),
		"CONTROL: a fabricated key must NOT read as accessed, or the instrument says yes to everything")
	assert_gt(_fields().size(), 10,
		"ANTI-VACUITY: only %d distinct fields parsed out of the manifest" % _fields().size())


## The original arm, kept: a name that appears NOWHERE in src/ cannot be read by anything, so an
## undeclared one is an unwired promise. This is the half the crude instrument always got right.
func test_no_manifest_field_is_an_unwired_promise() -> void:
	var all_src := _code_of_all()
	var undeclared: Array = []
	var named := 0
	for f in _fields():
		if all_src.contains("\"%s\"" % f):
			named += 1
			continue
		if _declared_anywhere(str(f)):
			continue
		undeclared.append("%s (%d entries) is named nowhere in src/ and is declared nowhere" % [f, _fields()[f]])
	assert_gt(named, 3,
		"ANTI-VACUITY: only %d fields matched anywhere in src/ — the search is broken" % named)
	undeclared.sort()
	assert_eq(undeclared, [],
		("an authored manifest field promises something no runtime reads. Either wire it, or declare it " +
		 "with a line saying what it records and who holds the call: %s") % [undeclared])


## ⛔ THE ARM THIS REVISION EXISTS FOR. A field whose name appears in src/ but which no file that
## PARSES the manifest actually accesses is not resolved by either search — and 9 fields, 504
## authored instances, were sitting in exactly that gap reading as "consumed".
func test_every_undecided_field_is_resolved_in_writing() -> void:
	var corpus := _corpus()
	var all_src := _code_of_all()
	var unresolved: Array = []
	var undecided := 0
	for f in _fields():
		var field := str(f)
		if _key_accessed(field, corpus):
			continue                      # READ
		if not all_src.contains("\"%s\"" % field):
			continue                      # UNREAD — the arm above owns it
		undecided += 1
		if not _declared_anywhere(field):
			unresolved.append("%s (%d entries)" % [field, _fields()[field]])
	assert_gt(undecided, 3,
		("ANTI-VACUITY: only %d fields landed in the UNDECIDED state. That bucket is the whole point of " +
		 "this arm; if it is empty the census has collapsed back to two states and cannot see a collision") % undecided)
	unresolved.sort()
	assert_eq(unresolved, [],
		("a field is named in src/ but no file that parses the manifest accesses it — so it is either a " +
		 "name collision or read through a variable, and the instrument cannot tell. Resolve it ONCE in " +
		 "_field_provenance (inert), _field_indirect_readers (read via a symbol, name the call path), or " +
		 "_section_provenance (its whole section is unconsumed): %s") % [unresolved])


## A declaration must EXPLAIN, not just list. An empty string silences the arms above while
## recording nothing — the "you cannot silence it green, only explain it green" half.
func test_every_declaration_says_something() -> void:
	var m := _manifest()
	var thin: Array = []
	var blocks := 0
	for block_name in ["_field_provenance", "_field_indirect_readers", "_section_provenance"]:
		var block: Dictionary = m.get(block_name, {})
		assert_gt(block.size(), 1, "%s must exist and carry entries, or the arms above cannot distinguish declared from not" % block_name)
		blocks += 1
		assert_gt(str(block.get("_why", "")).length(), 60,
			"%s must carry its own rationale for the next reader" % block_name)
		for f in block:
			if str(f) == "_why":
				continue
			if str(block[f]).strip_edges().length() < 30:
				thin.append("%s.%s" % [block_name, f])
	assert_eq(blocks, 3, "all three declaration blocks must be present")
	assert_eq(thin, [], "a declaration has to say what it records and who holds it: %s" % [thin])


## ⛔ THE DECLARATION MUST NOT OUTLIVE THE FACT. A field listed as INERT that the runtime later
## starts reading is no longer provenance, and the note becomes a lie the next reader trusts.
##
## Upgraded with the rest: the old version redded on the field's NAME appearing anywhere in src/,
## which would now fire on `tier` and `source` for autogrind's and AbilityVFX's unrelated keys.
## It asks for a real key access in a real parser instead — the same distinction that made this
## revision necessary, applied to the arm that polices its own output.
func test_no_field_declared_inert_is_actually_read() -> void:
	var corpus := _corpus()
	var inert: Dictionary = _manifest().get("_field_provenance", {})
	var now_read: Array = []
	for f in inert:
		if str(f) == "_why":
			continue
		if _key_accessed(str(f), corpus):
			now_read.append(str(f))
	assert_eq(now_read, [],
		("a field declared INERT is now read by a file that parses the manifest — delete the declaration, " +
		 "or move it to _field_indirect_readers if it was always read and the census could not see it: %s") % [now_read])


## The mirror: a field declared as READ-VIA-A-SYMBOL must name an accessor that still exists. A
## call path recorded in prose decays exactly like a line number, and this one is load-bearing —
## it is the reason those fields are NOT treated as unwired promises.
func test_an_indirect_reader_declaration_names_a_live_call_path() -> void:
	var all_src := _code_of_all()
	var indirect: Dictionary = _manifest().get("_field_indirect_readers", {})
	var stale: Array = []
	for f in indirect:
		if str(f) == "_why":
			continue
		var note := str(indirect[f])
		assert_true(note.contains("("),
			"%s's indirect-reader note must name the function that supplies the key" % [f])
		if not all_src.contains("\"%s\"" % str(f)):
			stale.append("%s: declared read-via-a-symbol, but the literal is gone from src/" % f)
	assert_gt(indirect.size(), 1, "ANTI-VACUITY: no indirect readers declared, so this arm guards nothing")
	assert_eq(stale, [],
		("an indirect-reader declaration outlived its call path — the field is now genuinely unread and " +
		 "belongs in _field_provenance: %s") % [stale])
