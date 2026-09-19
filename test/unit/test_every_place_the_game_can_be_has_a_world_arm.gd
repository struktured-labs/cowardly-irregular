extends GutTest

## `_get_current_world_suffix()`'s `_:` arm returns the CACHED suffix, which is CORRECT for the two
## cases it was written for — `play_music` clears `_current_area` for battle/victory, and a danger
## zone belongs to whatever world you are already in. It is a silent lie for a real place that has
## no arm: that place plays whichever world the player came FROM.
##
## ⛔ THIS EXACT BUG SHIPPED, AND THE RESOLVER'S OWN DOCSTRING RECORDS IT. Tick 359: GameLoop began
## passing the canonical `<world>_overworld` map ids, the match listed only the legacy
## `overworld_<world>` forms, so every canonical call fell through to the cached suffix — and
## **every battle in the suburban / steampunk / industrial / futuristic / abstract overworlds used
## MEDIEVAL battle music regardless of where the player actually was.**
##
## 🔑 WHY THE TWO EXISTING GUARDS CANNOT CATCH THE NEXT ONE, AND IT IS A PROPERTY OF THEIR CORPUS
## RATHER THAN OF THEIR CARE. `test_world_suffix_vocabulary_regression` and
## `test_every_world_fights_to_its_own_bed` both derive their area ids FROM THE RESOLVER'S OWN MATCH
## ARMS. That is the right way to avoid a hand-list going stale, and it means the set of areas they
## test IS the set of areas that are handled — so an area with no arm is not in their corpus and
## cannot fail. A new W2-W6 village added tomorrow reds nothing.
##
## This guard walks the other way: from every place the game can actually BE, to the arms.

const SM_PATH := "res://src/audio/SoundManager.gd"
const SRC_ROOT := "res://src"

## The declared producer. Every map/overworld/village/dungeon script that wants its own bed
## overrides this, and GameLoop hands its return straight to play_area_music.
const PRODUCER := "func _get_music_area_id()"


func _gd_files(root: String, acc: Array[String]) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		var path: String = root + "/" + name
		if dir.current_is_dir():
			_gd_files(path, acc)
		elif name.ends_with(".gd"):
			acc.append(path)
		name = dir.get_next()
	dir.list_dir_end()


## The area ids the game can hand to play_area_music, read from the producers that declare them.
## ⚠️ DELIBERATELY NOT a scan of `play_area_music("literal")` call sites. That is a reference
## census, and GameLoop's site passes a VARIABLE (`_area_key` / `_current_map_id`), so a literal
## scan silently reports a subset while looking exhaustive.
func _produced_ids() -> Dictionary:
	var files: Array[String] = []
	_gd_files(SRC_ROOT, files)
	assert_gt(files.size(), 100, "FLOOR: walked only %d .gd files under src/" % files.size())
	var out: Dictionary = {}
	var re := RegEx.new()
	re.compile("return\\s+\"([a-z0-9_]+)\"")
	for path in files:
		var code: String = GdSource.code_of(path)
		var at: int = code.find(PRODUCER)
		while at != -1:
			var nxt: int = code.find("\nfunc ", at + 1)
			var body: String = code.substr(at, (nxt - at) if nxt != -1 else -1)
			for m in re.search_all(body):
				out[m.get_string(1)] = str(path).get_file()
			at = code.find(PRODUCER, at + 1)
	return out


## The handled set, from the resolver's own match. Same derivation the sibling guards use — here it
## is the thing being CHECKED AGAINST rather than the corpus, which is the whole difference.
func _arms() -> Array[String]:
	var code: String = GdSource.code_of(SM_PATH)
	var at: int = code.find("\tmatch _current_area:")
	assert_gt(at, -1, "FLOOR: the resolver's `match _current_area:` was not found")
	var seg: String = code.substr(at, 2200)
	var out: Array[String] = []
	var re := RegEx.new()
	re.compile("\"([a-z0-9_]+)\"")
	for line in seg.split("\n"):
		var t: String = str(line).strip_edges()
		if not t.ends_with(":") or t.begins_with("match"):
			continue
		for m in re.search_all(t):
			out.append(m.get_string(1))
	return out


func test_every_declared_area_id_reaches_a_real_world_arm() -> void:
	var produced: Dictionary = _produced_ids()
	var arms: Array[String] = _arms()

	## ANTI-VACUITY, both sides. An empty producer set passes by construction, and renaming the
	## override is exactly how it would empty.
	assert_gt(produced.size(), 10,
		"ANTI-VACUITY: derived only %d area ids from `%s` overrides (%s) — the producer was renamed and this guard is about nothing" % [produced.size(), PRODUCER, str(produced.keys())])
	assert_gt(arms.size(), 20,
		"ANTI-VACUITY: derived only %d arms from the resolver (%s) — its match was reshaped" % [arms.size(), str(arms)])

	var stranded: Array[String] = []
	for id in produced.keys():
		var key: String = str(id)
		## Interiors resolve through _interior_world_suffix, a different mechanism with its own guard.
		if key.begins_with("interior_"):
			continue
		if not arms.has(key):
			stranded.append("%s (declared in %s)" % [key, str(produced[key])])
	stranded.sort()

	assert_eq(stranded, [],
		"a place the game can BE has no arm in _get_current_world_suffix, so it falls through to the CACHED suffix and plays whichever world the player came from — the tick-359 defect verbatim: %s" % str(stranded))
