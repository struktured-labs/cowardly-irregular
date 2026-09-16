extends GutTest

## ⛔ FIVE AUTHORED DIALOGUE LINES PROMISE PLAYSTYLE GATING AND NOTHING GATES THEM.
## `"_condition"` occurs on 5 lines across the two world-transition scenes and has ZERO readers
## anywhere in src/ (measured 2026-09-16), so all five play to every player. In world2_transition
## that is THREE CONSECUTIVE LINES each telling the player they played a different way:
##
##   world1_transition   playstyle_autobattle · playstyle_completionist
##   world2_transition   playstyle_autobattle · playstyle_grinder · playstyle_completionist
##
## ⚠️ AND IT CANNOT SIMPLY BE WIRED. `_detect_playstyle()` returns automator · manual · grinder ·
## exploiter · balanced. `playstyle_autobattle` is not `automator`, and `playstyle_completionist` is
## not a value the detector can EVER return — so a naive wiring would fire 1 of the 3 conditions and
## silently drop the rest, which is the state we are already in wearing a fix's clothes.
##
## So this file does NOT fix it. Per the rule this fleet converged on today (cowir-music 11556,
## matched by cowir-main 11564: wiring an authored-but-dead key is a content decision wearing a bug's
## clothes), it HOLDS THE STATE until struktured chooses: gate them (needs a name mapping AND a
## definition of "completionist"), or retire the keys and accept the lines unconditionally.
##
## 🔑 The guard is on the INVISIBILITY, not the collision (CLAUDE.md's case b): an authored key must
## either be READ by the runtime or be DECLARED here with a note saying why it is not. You cannot
## silence it green, only explain it green.

const CUTSCENE_DIR := "res://data/cutscenes"
## ⛔ THIS WAS A HAND-LIST OF FIVE PATHS and that is the hole cowir-controller found in their own
## shoulder-caption guard the same day (11649): the class was guarded, the corpus was curated, and a
## sixth surface carrying the defect redded nothing. Mine had the same shape one day old — a NEW file
## consuming dialogue lines would not be scanned, so a DECLARED-inert key could gain a reader there
## and the declaration would outlive its fact in silence.
##
## TWO corpora now, derived, because the two arms ask different questions:
##   LINE_CONSUMER_DIR   every .gd in the cutscene lane — "does the code that consumes a line read
##                       this key?" is a question about that code, and new files join automatically
##   SRC_ROOT            the whole tree — "has a declared-inert key gained ANY reader?" is the claim
##                       the declaration makes, and it is tree-wide
const LINE_CONSUMER_DIR := "res://src/cutscene"
const EXTRA_LINE_CONSUMERS := ["res://src/save/ChapterTitles.gd"]
const SRC_ROOT := "res://src"

## key -> why it is inert and who holds the decision. An empty note is not a declaration.
const DECLARED_INERT := {
	"_condition": "Playstyle gating for 5 lines in world1/world2_transition. No reader in src/, and the authored vocabulary (playstyle_autobattle/grinder/completionist) does not match _detect_playstyle's (automator/manual/grinder/exploiter/balanced), with no 'completionist' value at all. Held for struktured: gate with a mapping + a definition of completionist, or retire the keys.",
}

## The files carrying an undeclared-but-inert key today. A SIXTH site must red this file rather than
## join a growing pile — that is the point of holding the state.
const CONDITION_SITES := ["world1_transition.json", "world2_transition.json"]


## The lane's own consumers, derived from the directory rather than named.
func _sources() -> String:
	var all: String = ""
	var paths: Array = _gd_files_in(LINE_CONSUMER_DIR, false)
	for p in EXTRA_LINE_CONSUMERS:
		if not paths.has(p):
			paths.append(p)
	for p in paths:
		all += FileAccess.get_file_as_string(p)
	return all


## Every .gd under src/, for the tree-wide claim a declaration makes.
func _all_sources() -> String:
	var all: String = ""
	for p in _gd_files_in(SRC_ROOT, true):
		all += FileAccess.get_file_as_string(p)
	return all


func _gd_files_in(dir_path: String, recurse: bool) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append("%s/%s" % [dir_path, f])
	if recurse:
		for d in dir.get_directories():
			out.append_array(_gd_files_in("%s/%s" % [dir_path, d], true))
	out.sort()
	return out


## Every line-level key any authored dialogue uses, with the files that use it.
func _authored_line_keys() -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open(CUTSCENE_DIR)
	if dir == null:
		return out
	var names: Array = []
	for f in dir.get_files():
		if f.ends_with(".json"):
			names.append(f)
	names.sort()
	for f in names:
		var d = JSON.parse_string(FileAccess.get_file_as_string(CUTSCENE_DIR + "/" + f))
		if not (d is Dictionary):
			continue
		for s in d.get("steps", []):
			if not (s is Dictionary):
				continue
			var lines = s.get("lines", null)
			if not (lines is Array):
				continue
			for it in lines:
				if not (it is Dictionary):
					continue
				for k in (it as Dictionary).keys():
					if not out.has(k):
						out[k] = []
					var files: Array = out[k]
					if not files.has(f):
						files.append(f)
	return out


## Read = the key appears as a string literal in the code that consumes dialogue lines.
func _is_read(key: String, src: String) -> bool:
	return ('"%s"' % key) in src


func test_every_authored_line_key_is_read_or_declared() -> void:
	var keys: Dictionary = _authored_line_keys()
	assert_gt(keys.size(), 3, "PRECONDITION: the corpus must load its line keys")
	var src: String = _sources()
	var undeclared: Array = []
	for k in keys.keys():
		var key: String = str(k)
		if _is_read(key, src):
			continue
		if DECLARED_INERT.has(key) and str(DECLARED_INERT[key]).length() > 40:
			continue
		undeclared.append("%s (in %s)" % [key, str(keys[k])])
	assert_eq(undeclared.size(), 0,
		"authored line keys that neither the runtime reads nor this file explains: %s" % str(undeclared))


## CONTROL, both directions: the instrument must find a key the runtime really reads and miss one
## nothing does, or the arm above passes on anything.
func test_control_the_reader_check_discriminates() -> void:
	var lane: Array = _gd_files_in(LINE_CONSUMER_DIR, false)
	assert_gt(lane.size(), 3,
		"ANTI-VACUITY: the lane corpus must be derived and non-trivial (%d files)" % lane.size())
	var src: String = _sources()
	assert_true(_is_read("portrait", src), "the runtime demonstrably reads `portrait`")
	assert_false(_is_read("zzq_fabricated_line_key", src), "and does not read a key nobody authored")


## The declaration must EXPLAIN, not merely exist — a bare `true` would make this file a rubber stamp.
func test_an_inert_declaration_carries_its_reasoning() -> void:
	for k in DECLARED_INERT.keys():
		var note: String = str(DECLARED_INERT[k])
		assert_gt(note.length(), 40, "%s: a declaration must say why, not just that" % k)
		assert_true("struktured" in note or "retire" in note,
			"%s: and must name who holds the decision or what closing it looks like" % k)


## ⚠️ A DECLARATION THAT OUTLIVES ITS FACT is worse than none, because the next reader trusts it.
## The moment the runtime starts reading a key this file calls inert, the declaration is the lie.
## (cowir-sprites' third arm in b058b6ac, applied here — same hazard, different authored surface.)
func test_a_declared_key_that_gained_a_reader_is_no_longer_inert() -> void:
	var files: Array = _gd_files_in(SRC_ROOT, true)
	assert_gt(files.size(), 150,
		"ANTI-VACUITY: the tree-wide corpus must actually load (%d files) — a short corpus reports every key unread" % files.size())
	var src: String = _all_sources()
	for k in DECLARED_INERT.keys():
		assert_false(_is_read(str(k), src),
			"%s is DECLARED inert and something in src/ now mentions it — wire it and delete the declaration, or record why that hit is a coincidence" % k)


## The state is held to the sites that exist today: a NEW conditional line must red this, not pile on.
func test_no_new_conditional_line_joins_the_pile() -> void:
	var keys: Dictionary = _authored_line_keys()
	assert_true(keys.has("_condition"),
		"PRECONDITION: _condition is still authored — if it is gone, delete this file, do not weaken it")
	var files: Array = keys["_condition"]
	files.sort()
	var expected: Array = CONDITION_SITES.duplicate()
	expected.sort()
	assert_eq(files, expected,
		"the set of scenes gating lines by playstyle changed (%s) — wire it or retire it before adding more" % str(files))


## ⚠️ THE MISMATCH THAT MAKES IT UNDECIDABLE, pinned so a future half-wiring cannot hide in it:
## the authored vocabulary is not the engine's, and one authored value has no engine value at all.
func test_the_authored_vocabulary_does_not_match_the_detector() -> void:
	var src := FileAccess.get_file_as_string("res://src/cutscene/CutsceneDirector.gd")
	var i := src.find("func _detect_playstyle")
	assert_gt(i, -1, "the detector must exist")
	var next: int = src.find("\nfunc ", i + 1)
	var body := src.substr(i, (next - i) if next > -1 else 2000)
	assert_true('"automator"' in body, "the detector's own vocabulary: automator")
	assert_true('"grinder"' in body, "and grinder")
	assert_false('"completionist"' in body,
		"if the detector has learned what a completionist is, the held decision is answerable — wire _condition and delete this arm")
	assert_false('"playstyle_autobattle"' in src,
		"the authored name is not the engine's name; a mapping is part of any wiring")
