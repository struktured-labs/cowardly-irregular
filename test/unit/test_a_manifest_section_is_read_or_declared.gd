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
##   npc_sheets            4 conversational sheets, 937 KB — 2048x256, eight 256px frames animating
##                         idle/talk/gesture/react. No path form in src/ reaches them: the live
##                         convention is `npcs/<archetype>/overworld.png`, a DIRECTORY, and three of
##                         the four have a twin there. The characters ship; the talking art does not.
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
