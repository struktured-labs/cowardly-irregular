extends GutTest

## An authored key must be READ by the runtime or DECLARED inert with a note naming who holds it.
## cowir-music's rule, endorsed by cowir-main 2026-09-16, after a day in which four authored keys
## across three lanes turned out to promise behaviour nothing implemented — `reflect_damage_element`
## (a boss move doing half what it says), `_condition` (five dialogue lines gating on nothing),
## `session_scope`, `corruption_threshold`. The manifest is this lane's version of that surface.
##
## ⛔ THE INSTRUMENT IS CRUDE AND IS ONLY TRUSTED ON ZEROES. A quoted-key search credits `"tier"`
## to autogrind's grind tiers and `"attack"` to every animation name in the codebase, so a HIT
## proves nothing. A ZERO is the signal: no file in src/ mentions the key at all, so no rung can
## be reading it. That asymmetry is the whole design — this arm fires only on zeroes.
const MANIFEST := "res://data/sprite_manifest.json"
const SRC_ROOT := "res://src"


func _manifest() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	return parsed if parsed is Dictionary else {}


func _all_src() -> String:
	var parts: PackedStringArray = []
	var stack: Array[String] = [SRC_ROOT]
	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		d.list_dir_begin()
		var n := d.get_next()
		while n != "":
			var full := "%s/%s" % [dir_path, n]
			if d.current_is_dir():
				if not n.begins_with("."):
					stack.append(full)
			elif n.ends_with(".gd"):
				parts.append(FileAccess.get_file_as_string(full))
			n = d.get_next()
		d.list_dir_end()
	return "\n".join(parts)


## Every field name appearing in any entry of any section, with how many entries carry it.
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


func test_no_manifest_field_is_an_unwired_promise() -> void:
	var src := _all_src()
	assert_gt(src.length(), 100000,
		"ANTI-VACUITY: only %d chars of src/ were read — a short corpus makes every field look unread and every field look declared" % src.length())
	var declared: Dictionary = _manifest().get("_field_provenance", {})
	assert_gt(declared.size(), 1, "ANTI-VACUITY: _field_provenance is empty, so this arm cannot distinguish declared from undeclared")
	var undeclared: Array = []
	var read_count := 0
	for f in _fields():
		if src.contains("\"%s\"" % f):
			read_count += 1
			continue
		if declared.has(f):
			continue
		undeclared.append("%s (%d entries) is read by nothing in src/ and is not in _field_provenance" % [f, _fields()[f]])
	assert_gt(read_count, 3,
		"ANTI-VACUITY: only %d fields matched in src/ — the search is broken, so every field would look unread" % read_count)
	undeclared.sort()
	assert_eq(undeclared, [],
		("an authored manifest field promises something no runtime reads. Either wire it, or add it to " +
		 "_field_provenance with a line saying what it records and who holds the call: %s") % [undeclared])


## A declaration must EXPLAIN, not just list. An empty string silences the arm above while
## recording nothing — which is the "you cannot silence it green, only explain it green" half.
func test_every_provenance_declaration_says_something() -> void:
	var declared: Dictionary = _manifest().get("_field_provenance", {})
	var thin: Array = []
	for f in declared:
		if str(f) == "_why":
			continue
		if str(declared[f]).strip_edges().length() < 30:
			thin.append(str(f))
	assert_eq(thin, [], "a provenance declaration has to say what the field records and who holds it: %s" % [thin])
	assert_true(str(declared.get("_why", "")).length() > 60, "_field_provenance must carry its own rationale for the next reader")


## ⛔ THE DECLARATION MUST NOT OUTLIVE THE FACT. A field listed as provenance that the runtime
## later starts reading is no longer provenance, and the note becomes a lie the next reader trusts.
func test_no_declared_field_is_actually_read() -> void:
	var src := _all_src()
	var declared: Dictionary = _manifest().get("_field_provenance", {})
	var now_read: Array = []
	for f in declared:
		if str(f) == "_why":
			continue
		if src.contains("\"%s\"" % f):
			now_read.append(str(f))
	assert_eq(now_read, [],
		("a field declared as provenance is now named in src/ — if the runtime reads it, delete the " +
		 "declaration; if that hit is a coincidence, say so in the note: %s") % [now_read])
