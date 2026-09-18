extends GutTest

## An area id must be matched TWICE, in two hand-written `match` blocks that nothing keeps in step:
##
##     _start_area_music_deferred   picks the BED
##     _get_current_world_suffix    picks the WORLD, which battle/boss/danger/victory compose onto
##
## ⛔ SO THE VertexApex FAILURE SPLITS IN HALF, AND HALF OF IT IS INVISIBLE TO EVERY GUARD WE HAVE.
## An id with a dispatcher arm and no suffix arm plays the RIGHT bed in the map and falls to `_:`
## for the world — which returns the stale cached suffix, i.e. wherever the player last was. The
## `_:` arm's own docstring records that happening: "every battle in suburban/steampunk/industrial/
## futuristic/abstract overworlds used MEDIEVAL battle music regardless of where the player
## actually was." test_a_village_says_which_world_it_is_in checks the dispatcher half only, and the
## dungeon guard checks neither — this is the missing half for both, over every map that produces
## an id rather than one directory.
##
## 🔑 INTERIORS ARE EXCLUDED BY MECHANISM, NOT BY LIST, AND THE ARM BELOW PINS THE MECHANISM.
## `interior_*` never reaches either match: the suffix resolver short-circuits to
## _interior_world_suffix(), which reads GameState.current_world, and the dispatcher branches to
## _start_interior_music before its own match. A new W6 room is correct with no arm and no entry
## anywhere (@cowir-sfx measured 32 of 32). Delete that short-circuit and the exclusion here stops
## being justified, so the arm reds rather than quietly widening.

const SM_PATH := "res://src/audio/SoundManager.gd"
const MAP_DIRS := ["res://src/maps/villages/", "res://src/maps/dungeons/", "res://src/exploration/"]


func _sm() -> String:
	return FileAccess.get_file_as_string(SM_PATH)


func _fn_body(src: String, header: String) -> String:
	var i: int = src.find("func " + header)
	if i < 0:
		return ""
	var j: int = src.find("\nfunc ", i + 1)
	return src.substr(i, (j - i) if j > i else src.length() - i)


## Labels of a `match` block's arms: every quoted string on a line that ends in ':'.
func _arm_labels(body: String) -> Array[String]:
	var out: Array[String] = []
	var k: int = body.find("match ")
	if k < 0:
		return out
	for raw in body.substr(k).split("\n"):
		var line: String = raw.strip_edges()
		if not line.ends_with(":") or not line.begins_with("\""):
			continue
		var parts: PackedStringArray = line.split("\"")
		for n in range(1, parts.size(), 2):
			if not out.has(parts[n]):
				out.append(parts[n])
	return out


## Every id a placed map can hand to play_area_music, read from the maps rather than listed here.
func _produced_ids() -> Dictionary:
	var out: Dictionary = {}
	for d in MAP_DIRS:
		var dir := DirAccess.open(d)
		if dir == null:
			continue
		for f in dir.get_files():
			if not f.ends_with(".gd"):
				continue
			var src: String = FileAccess.get_file_as_string(d + f)
			var i: int = src.find("func _get_music_area_id")
			if i < 0:
				continue
			var seg: String = src.substr(i, 300)
			var r: int = seg.find("return \"")
			if r < 0:
				continue
			var rest: String = seg.substr(r + 8)
			var id: String = rest.substr(0, rest.find("\""))
			if id != "" and not id.begins_with("interior_"):
				out[id] = f
	return out


func test_control_both_matches_and_the_corpus_extracted() -> void:
	## All three arms below are about set membership, so an empty set on either side reads as
	## perfect agreement. Floor each one from a different read.
	var src: String = _sm()
	assert_gt(src.length(), 1000, "CONTROL: SoundManager read back %d chars" % src.length())
	var disp := _arm_labels(_fn_body(src, "_start_area_music_deferred"))
	var suff := _arm_labels(_fn_body(src, "_get_current_world_suffix"))
	var produced := _produced_ids()
	assert_gt(disp.size(), 20, "CONTROL: only %d dispatcher arms extracted" % disp.size())
	assert_gt(suff.size(), 25, "CONTROL: only %d suffix arms extracted" % suff.size())
	assert_gt(produced.size(), 20, "CONTROL: only %d ids produced by maps" % produced.size())


func test_every_produced_id_has_a_bed_arm() -> void:
	var disp := _arm_labels(_fn_body(_sm(), "_start_area_music_deferred"))
	var missing: Array[String] = []
	for id in _produced_ids():
		if not disp.has(id):
			missing.append("%s (%s) has no arm in _start_area_music_deferred, so it falls to `_:` and plays the OVERWORLD bed" % [id, _produced_ids()[id]])
	assert_eq(missing.size(), 0, "\n".join(missing))


func test_every_produced_id_has_a_world_arm() -> void:
	## The half nothing else checks. A miss here is silent in the map — the bed is right — and
	## wrong in every battle, boss, danger and victory cue the world suffix composes.
	var suff := _arm_labels(_fn_body(_sm(), "_get_current_world_suffix"))
	var missing: Array[String] = []
	var produced := _produced_ids()
	for id in produced:
		if not suff.has(id):
			missing.append("%s (%s) has no arm in _get_current_world_suffix, so it falls to `_:` and returns the STALE CACHED suffix — the right bed in the map and the wrong world in every battle" % [id, produced[id]])
	assert_eq(missing.size(), 0, "\n".join(missing))


func test_interiors_are_excluded_by_a_mechanism_that_is_still_there() -> void:
	## The arms above skip interior_* ids. That is only sound while the resolver short-circuits them
	## to GameState; without it they would need arms like everything else and the skip would be a
	## silencer. Pinned inside the function body, not file-wide — the prose above mentions both names.
	var body: String = _fn_body(_sm(), "_get_current_world_suffix")
	assert_ne(body, "", "CONTROL: _get_current_world_suffix must exist")
	assert_true(body.contains("_current_area.begins_with(\"interior_\")"),
		"_get_current_world_suffix no longer short-circuits interior_* ids, so excluding them above is no longer justified")
	assert_true(body.contains("_interior_world_suffix()"),
		"the interior short-circuit must still resolve through _interior_world_suffix(), which reads the MAP's world rather than whatever bed is playing")
	var disp: String = _fn_body(_sm(), "_start_area_music_deferred")
	assert_true(disp.contains("_start_interior_music("),
		"_start_area_music_deferred no longer routes interior_* before its match, so they would need bed arms too")
