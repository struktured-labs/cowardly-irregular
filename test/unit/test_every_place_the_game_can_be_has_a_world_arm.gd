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
	assert_gt(files.size(), 100, "FLOOR: walked only %d .gd files under %s" % [files.size(), SRC_ROOT])
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
	assert_gt(at, -1, "FLOOR: _arms() found no `match _current_area:` in %s" % SM_PATH)
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


## ⛔ THE HOLE THE ARM ABOVE CANNOT SEE, FOUND BY READING ITS OWN GREEN: A VILLAGE THAT DECLARES
## NOTHING IS NOT IN THE PRODUCER CORPUS AT ALL. Five of thirteen village scripts have no
## `_get_music_area_id()` override — Eldertree, Frosthold, Grimhollow, Ironhaven, Sandrift — so they
## inherit BaseVillage's `"village"`, which resolves to MEDIEVAL. All five are World 1, so all five
## are correct today, and they are correct BY ACCIDENT OF WHICH WORLD THEY ARE IN.
##
## A W2-W6 village that forgets the override is silent to the producer walk and plays medieval music
## — the tick-359 defect again, arriving by OMISSION rather than by a missing arm. So the corpus for
## this arm is every village the game can LOAD, not every village that declares an id.
##
## 🔑 And the property is stronger than "an arm exists": the suffix a village produces must match the
## world its own map id NAMES. That compares two independent sources and needs no hand list.
const GAMELOOP := "res://src/GameLoop.gd"
const BASE_VILLAGE_DEFAULT := "village"


func _world_prefixes(code: String) -> Array:
	## GameLoop's id->world table. Sorted longest-first so a specific prefix beats a shorter one.
	var at: int = code.find("[\"futuristic_\", 5]")
	assert_gt(at, -1, "FLOOR: no world-prefix table (`[\"futuristic_\", 5]`) in %s" % GAMELOOP)
	var seg: String = code.substr(max(0, at - 900), 1500)
	var out: Array = []
	for m in RegEx.create_from_string("\\[\"([a-z0-9_]+)\",\\s*(\\d)\\]").search_all(seg):
		out.append([m.get_string(1), int(m.get_string(2))])
	out.sort_custom(func(a, b): return str(a[0]).length() > str(b[0]).length())
	return out


func _world_of(map_id: String, prefixes: Array) -> int:
	for pair in prefixes:
		if map_id.begins_with(str(pair[0])):
			return int(pair[1])
	return 0


## arm -> suffix, walking the resolver's match and attaching each `return "x"` to the ids above it.
func _arm_suffixes(code: String) -> Dictionary:
	var at: int = code.find("\tmatch _current_area:")
	assert_gt(at, -1, "FLOOR: _arm_suffixes() found no `match _current_area:` in %s" % SM_PATH)
	var out: Dictionary = {}
	var pending: Array[String] = []
	var ids := RegEx.create_from_string("\"([a-z0-9_]+)\"")
	var ret := RegEx.create_from_string("^return \"([a-z]+)\"$")
	for line in code.substr(at, 2200).split("\n"):
		var t: String = str(line).strip_edges()
		if t.ends_with(":") and not t.begins_with("match"):
			pending = []
			for m in ids.search_all(t):
				pending.append(m.get_string(1))
		var r := ret.search(t)
		if r != null and not pending.is_empty():
			for a in pending:
				out[a] = r.get_string(1)
			pending = []
	return out


## ⛔ CANONICAL `<world>_overworld` FORMS ONLY, AND THE LEGACY FORM IS WHY. The resolver accepts BOTH
## spellings, and `"overworld_suburban".begins_with("overworld")` is TRUE — so feeding the legacy ids
## to GameLoop's prefix table files all five other worlds under World 1. My first derivation did
## exactly that and reported W1 -> [abstract, digital, industrial, medieval, steampunk, suburban]
## without failing anything. GameLoop's own table carries the warning in a comment.
func _world_suffixes(arm_suffix: Dictionary, prefixes: Array) -> Dictionary:
	var out: Dictionary = {}
	for arm in arm_suffix.keys():
		var a: String = str(arm)
		if a != "overworld" and not a.ends_with("_overworld"):
			continue
		var w: int = _world_of(a, prefixes)
		if w == 0:
			continue
		assert_true(not out.has(w) or out[w] == arm_suffix[arm],
			"world %d resolves to two suffixes (%s and %s) — the derivation is ambiguous and this arm would compare against a coin flip" % [w, str(out.get(w, "")), str(arm_suffix[arm])])
		out[w] = arm_suffix[arm]
	return out


func test_every_loadable_village_sounds_like_its_own_world() -> void:
	var gl: String = GdSource.code_of(GAMELOOP)
	var sm: String = GdSource.code_of(SM_PATH)
	var prefixes: Array = _world_prefixes(gl)
	var arm_suffix: Dictionary = _arm_suffixes(sm)
	var world_suffix: Dictionary = _world_suffixes(arm_suffix, prefixes)

	assert_gt(prefixes.size(), 15, "FLOOR: derived only %d world prefixes from %s" % [prefixes.size(), GAMELOOP])
	assert_eq(world_suffix.size(), 6,
		"FLOOR: derived a suffix for %d worlds, not 6 (%s) — a world with no canonical overworld arm cannot be checked" % [world_suffix.size(), str(world_suffix)])

	## The villages the game can actually LOAD, from GameLoop's own dispatch.
	var villages: Dictionary = {}
	for m in RegEx.create_from_string("\"([a-z0-9_]+)\":\\s*\\n\\s*exploration_scene\\s*=\\s*(\\w+)Script\\.new\\(\\)").search_all(gl):
		var script_name: String = m.get_string(2)
		if script_name.contains("Village") or script_name.contains("Plaza") or script_name.contains("StripMall"):
			villages[m.get_string(1)] = script_name
	assert_gt(villages.size(), 8,
		"ANTI-VACUITY: derived only %d loadable villages from GameLoop's dispatch (%s) — the dispatch was reshaped and this arm is about nothing" % [villages.size(), str(villages.keys())])

	## What each village's script declares, or BaseVillage's default when it declares nothing.
	var declared: Dictionary = {}
	var dir := DirAccess.open("res://src/maps/villages")
	assert_not_null(dir, "FLOOR: res://src/maps/villages did not open, so no village declares anything")
	var inherited: int = 0
	for file in dir.get_files():
		if not file.ends_with(".gd"):
			continue
		var code: String = GdSource.code_of("res://src/maps/villages/" + file)
		var at: int = code.find(PRODUCER)
		var id: String = ""
		if at != -1:
			var r := RegEx.create_from_string("return\\s+\"([a-z0-9_]+)\"").search(code.substr(at, 300))
			if r != null:
				id = r.get_string(1)
		declared[file.get_basename()] = id

	var wrong: Array[String] = []
	for map_id in villages.keys():
		var script_name: String = str(villages[map_id])
		var area_id: String = str(declared.get(script_name, ""))
		if area_id == "":
			area_id = BASE_VILLAGE_DEFAULT
			inherited += 1
		var want: String = str(world_suffix.get(_world_of(str(map_id), prefixes), ""))
		var got: String = str(arm_suffix.get(area_id, ""))
		if want == "" or got == "" or want != got:
			wrong.append("%s (%s) -> area '%s' -> '%s', but its id names world %d whose suffix is '%s'" % [map_id, script_name, area_id, got, _world_of(str(map_id), prefixes), want])
	wrong.sort()

	## ANTI-VACUITY on the half that is the whole point: if nothing inherits, this arm has stopped
	## covering the case the producer walk cannot see and is merely a slower copy of it.
	assert_gt(inherited, 2,
		"ANTI-VACUITY: only %d villages inherit BaseVillage's default, so the inheritance hole this arm exists for is not being exercised" % inherited)

	assert_eq(wrong, [],
		"a village resolves to a world it is not in, so it plays another world's bed: %s" % str(wrong))
