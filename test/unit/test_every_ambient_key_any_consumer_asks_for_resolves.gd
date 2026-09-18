extends GutTest

const GdSource := preload("res://test/unit/helpers/gd_source.gd")

## test_overworld_ambient_keys_resolve guards ONE consumer and is honest about it — the file is
## named for the overworld and parses OverworldScene. Its header states the hazard in general
## terms though: "play_ambient returns EARLY and SILENTLY on a key the manifest lacks... a zone
## with a typo'd or retired key is indistinguishable from a zone deliberately left quiet."
##
## Measured 2026-09-18: play_ambient has FIVE consumer files and that guard reaches one of them.
##   OverworldScene:931        7 zone keys          <- covered there
##   WeatherSystem:198-203     6 literal keys       <- uncovered
##   BaseVillage:101,712       _get_ambient_key()   <- uncovered
##   BaseInterior:52           _get_ambient_key()   <- uncovered, 7 rooms override it
##   SoundManager:1192         NIGHT_AMBIENCE_KEY   <- uncovered
## All 19 resolve today. Rename ambient_forge and the blacksmith goes quiet with nothing red.
##
## ⚠️ SoundManager:1196 replays _pre_night_ambient_key, a RUNTIME variable holding a key that
## already played. Not a literal and not in this corpus — it is safe by construction, not by check.

const SFX_MANIFEST := "res://data/sfx_manifest.json"
const MUSIC_MANIFEST := "res://data/music_manifest.json"
## Every file in src/ that calls play_ambient, derived below and asserted against this floor so a
## SIXTH consumer cannot appear without someone noticing the corpus grew.
const KNOWN_CONSUMERS := 5


func _manifest(path: String, root_keys: Array) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return {}
	for r in root_keys:
		var inner: Variant = (parsed as Dictionary).get(r, null)
		if inner is Dictionary:
			return inner
	return parsed


## Walks src/ and returns {key: [where, ...]} for every literal that can reach play_ambient:
## a literal argument at a call site, a _get_ambient_key() return, or SoundManager's night const.
func _requested_keys() -> Dictionary:
	var out: Dictionary = {}
	var call_re := RegEx.create_from_string("play_ambient\\(\\s*\"([a-z_0-9]+)\"")
	var ret_re := RegEx.create_from_string("func _get_ambient_key\\(\\)[^\\n]*\\n\\s*return \"([a-z_0-9]+)\"")
	## ⛔ AND THE CONST FORM. SoundManager passes NIGHT_AMBIENCE_KEY, not a literal — a literal-only
	## pattern reports the night bed as UNAUDITED while looking like a clean sweep. Resolved against
	## the same file's own declaration, so a const in any future consumer is covered too.
	var const_call_re := RegEx.create_from_string("play_ambient\\(\\s*([A-Z][A-Z_0-9]+)\\s*\\)")
	for path in _gd_files("res://src"):
		var code: String = GdSource.code_of(path)
		if code == "":
			continue
		for m in call_re.search_all(code):
			_add(out, m.get_string(1), path)
		for m in ret_re.search_all(code):
			_add(out, m.get_string(1), path)
		for m in const_call_re.search_all(code):
			var decl := RegEx.create_from_string("const %s[^=\\n]*=\\s*\"([a-z_0-9]+)\"" % m.get_string(1))
			var hit := decl.search(code)
			if hit != null:
				_add(out, hit.get_string(1), path)
	return out


func _add(out: Dictionary, key: String, where: String) -> void:
	if not out.has(key):
		out[key] = []
	var short: String = where.replace("res://src/", "")
	if not (out[key] as Array).has(short):
		(out[key] as Array).append(short)


func _gd_files(dir_path: String) -> Array:
	var found: Array = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return found
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full: String = dir_path + "/" + name
		if d.current_is_dir():
			found.append_array(_gd_files(full))
		elif name.ends_with(".gd"):
			found.append(full)
		name = d.get_next()
	d.list_dir_end()
	return found


func _consumer_files() -> Array:
	var files: Array = []
	for path in _gd_files("res://src"):
		var code: String = GdSource.code_of(path)
		## ⛔ NOT `not code.contains("func play_ambient(")` — that excludes the WHOLE file, and
		## SoundManager both declares play_ambient AND calls it twice (:1192 night bed, :1196 the
		## restore). My first version dropped the declaring file and reported 4 consumers; the
		## corpus control below is the only reason I saw it. Count CALLS, minus the declaration.
		var calls: int = code.count("play_ambient(") - code.count("func play_ambient(")
		if calls > 0:
			files.append(path.replace("res://src/", ""))
	files.sort()
	return files


func test_the_walk_reaches_every_consumer_not_just_the_overworld() -> void:
	## CORPUS control, and the whole point of the file: a walk that silently misses a directory
	## reports a clean sweep of the part it looked at.
	var files: Array = _consumer_files()
	assert_true(files.has("exploration/OverworldScene.gd"), "the walk missed the consumer the sibling guard covers")
	for required in ["exploration/WeatherSystem.gd", "maps/villages/BaseVillage.gd", "maps/interiors/BaseInterior.gd", "audio/SoundManager.gd"]:
		assert_true(files.has(required),
			"the walk never reached %s — its play_ambient keys are unaudited, and a key-presence check on the others still passes" % required)
	assert_eq(files.size(), KNOWN_CONSUMERS,
		"play_ambient now has %d consumer file(s), not %d: %s — a new one is not covered until this floor is updated deliberately" % [
			files.size(), KNOWN_CONSUMERS, files])


func test_every_literal_ambient_key_resolves_to_a_file_on_disk() -> void:
	var sfx: Dictionary = _manifest(SFX_MANIFEST, ["sfx"])
	var music: Dictionary = _manifest(MUSIC_MANIFEST, ["tracks", "music"])
	## CONTROLS on the resolution set, both directions — the sibling guard's own lesson: reading
	## the wrong root key returns {} and every key reads as missing, which is a confident wrong
	## finding rather than an error.
	assert_gt(sfx.size(), 100, "SCOPE control: sfx manifest walked %d entries — wrong root key?" % sfx.size())
	assert_gt(music.size(), 50, "SCOPE control: music manifest walked %d entries — wrong root key?" % music.size())
	assert_true(sfx.has("ambient_forge"), "CONTROL: a known-present key reads as absent")
	assert_false(sfx.has("ambient_definitely_not_real"), "CONTROL: a fabricated key reads as present")

	var requested: Dictionary = _requested_keys()
	assert_gt(requested.size(), 10,
		"SCOPE control: parsed only %d ambient keys from src/ — the patterns are stale and a green would be vacuous" % requested.size())

	var broken: Array = []
	for key in requested.keys():
		## play_ambient reads the MUSIC manifest first, then sfx — ambient_cave/forest/village
		## exist in both, so a check against either store alone answers about the wrong one.
		var entry: Variant = music.get(key, sfx.get(key, null))
		if not (entry is Dictionary):
			broken.append("%s (%s): in NEITHER manifest" % [key, requested[key]])
			continue
		var f: String = str((entry as Dictionary).get("file", ""))
		if f == "":
			broken.append("%s (%s): manifest entry has no file" % [key, requested[key]])
			continue
		if not FileAccess.file_exists(f if f.begins_with("res://") else "res://" + f):
			broken.append("%s (%s): file not on disk at %s" % [key, requested[key], f])
	assert_eq(broken, [],
		"%d ambient key(s) a consumer asks for do not resolve — play_ambient returns early and SILENTLY, so each is a room or zone that is simply quiet with nothing to say why: %s" % [
			broken.size(), broken])


func test_every_silent_return_in_play_ambient_is_either_warned_or_explained() -> void:
	## The other half, and the reason a typo was undetectable at RUNTIME rather than just in a test:
	## play_ambient had five bare `return`s, three of them failures, none of them saying anything —
	## while _load_sfx_manifest twenty lines up surfaces every one of its own failure modes.
	##
	## DERIVED over the body, not a list of branches: each return must carry either a push_warning
	## in its branch or a `SILENT BY DESIGN` note above it. You cannot silence it green, only
	## explain it green, and the explanation is the deliverable.
	var code: String = GdSource.code_of("res://src/audio/SoundManager.gd")
	assert_ne(code, "", "CONTROL: SoundManager code must survive the comment strip")
	var raw: String = FileAccess.get_file_as_string("res://src/audio/SoundManager.gd")
	var start: int = raw.find("func play_ambient(")
	assert_gt(start, -1, "CONTROL: play_ambient is gone — this arm no longer describes anything")
	var nxt: int = raw.find("\nfunc ", start + 1)
	var body: String = raw.substr(start, nxt - start) if nxt > start else raw.substr(start)
	var lines: PackedStringArray = body.split("\n")
	var bare: Array = []
	for i in lines.size():
		if lines[i].strip_edges() != "return" and not lines[i].strip_edges().begins_with("return  #"):
			continue
		## Look back over this branch for either marker. Four lines covers a guard plus its note.
		var covered: bool = false
		for back in range(1, 5):
			if i - back < 0:
				break
			var prev: String = lines[i - back]
			if prev.contains("push_warning") or prev.contains("SILENT BY DESIGN"):
				covered = true
				break
		if not covered:
			bare.append("line %d of play_ambient: %s" % [i, lines[i].strip_edges()])
	assert_gt(lines.size(), 20, "CONTROL: play_ambient body read back %d lines — the slice is wrong" % lines.size())
	assert_eq(bare, [],
		"%d return(s) in play_ambient neither warn nor explain themselves — an area with a bad key is indistinguishable from one deliberately left quiet: %s" % [
			bare.size(), bare])

