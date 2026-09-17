extends GutTest

## An ambience bed loops because its .ogg.import says so — NOT because the manifest says so.
## _try_play_sfx_from_manifest never reads "loop"; the only entry.get("loop", true) is at :1841,
## inside _try_play_from_manifest, which is the MUSIC path and takes a track_id.
## So the manifest's 18 loop keys are DOCUMENTATION of intent that no SFX code consumes.
## Both sources agree today (18 ↔ 18, measured 2026-09-17) and nothing keeps them agreeing:
## re-import one bed with loop off and a cave goes silent after one pass while the manifest
## still claims it loops. CLAUDE.md's redundant-sources rule says assert AGREEMENT rather than
## model precedence — if they agree the question of which wins is moot.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const MANIFEST := "res://data/sfx_manifest.json"
const SFX_DIR := "res://assets/audio/sfx/"


func _manifest_sfx() -> Dictionary:
	var f = FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return {}
	var sfx = parsed.get("sfx", {})
	return sfx if sfx is Dictionary else {}


## The basename a key's file resolves to, so a repointed entry is compared against what it NAMES.
func _base_of(key: String, entry: Dictionary) -> String:
	var f: String = str(entry.get("file", ""))
	if f.ends_with(".ogg"):
		return f.get_file().substr(0, f.get_file().length() - 4)
	return key


func _declares_loop(entry: Dictionary) -> bool:
	return entry.has("loop") and bool(entry["loop"])


## Reads the .import rather than the .ogg: loop is an IMPORT setting, invisible in the bytes.
func _import_loops(basename: String) -> bool:
	var f = FileAccess.open(SFX_DIR + basename + ".ogg.import", FileAccess.READ)
	if f == null:
		return false
	var text: String = f.get_as_text()
	f.close()
	for line in text.split("\n"):
		var bare: String = line.replace(" ", "")
		if bare.begins_with("loop="):
			return bare == "loop=true"
	return false


func _loops_on_disk() -> Array[String]:
	var out: Array[String] = []
	var d = DirAccess.open(SFX_DIR)
	if d == null:
		return out
	d.list_dir_begin()
	var n: String = d.get_next()
	while n != "":
		if not d.current_is_dir() and n.ends_with(".ogg.import"):
			var base: String = n.substr(0, n.length() - 11)
			if _import_loops(base):
				out.append(base)
		n = d.get_next()
	d.list_dir_end()
	out.sort()
	return out


func test_every_declared_loop_actually_loops_on_disk() -> void:
	var sfx: Dictionary = _manifest_sfx()
	assert_gt(sfx.size(), 0, "VOID, not clean: the sfx manifest read back 0 entries")
	var declared: Array[String] = []
	var broken: Array[String] = []
	for k in sfx.keys():
		var entry = sfx[k]
		if not (entry is Dictionary) or not _declares_loop(entry):
			continue
		var base: String = _base_of(str(k), entry)
		declared.append(str(k))
		if not _import_loops(base):
			broken.append("%s -> %s.ogg" % [str(k), base])
	assert_gt(declared.size(), 0,
		"CONTROL: no manifest entry declares loop, so this arm checked nothing")
	assert_eq(broken, [],
		"declared looping but the .import does not loop (%d) — these beds play ONCE and stop while the manifest still says they loop: %s" % [broken.size(), broken])
	print("[loop-parity] %d manifest entries declare loop" % declared.size())


func test_every_loop_on_disk_is_declared_in_the_manifest() -> void:
	var sfx: Dictionary = _manifest_sfx()
	assert_gt(sfx.size(), 0, "VOID, not clean: the sfx manifest read back 0 entries")
	var declared_bases := {}
	for k in sfx.keys():
		var entry = sfx[k]
		if entry is Dictionary and _declares_loop(entry):
			declared_bases[_base_of(str(k), entry)] = true
	var on_disk: Array[String] = _loops_on_disk()
	assert_gt(on_disk.size(), 0,
		"CONTROL: no sfx .import carries loop=true, so this arm cannot fire — the reader is broken or the dir moved")
	var undeclared: Array[String] = []
	for base in on_disk:
		if not declared_bases.has(base):
			undeclared.append(base)
	assert_eq(undeclared, [],
		"loop on disk with no manifest declaration (%d) — a cue loops and nothing records that it is meant to: %s" % [undeclared.size(), undeclared])
	print("[loop-parity] %d sfx .import files carry loop=true" % on_disk.size())


func test_the_two_sets_are_the_same_size() -> void:
	## The pair above can both pass on empty sets; this one cannot.
	var sfx: Dictionary = _manifest_sfx()
	assert_gt(sfx.size(), 0, "VOID, not clean: the sfx manifest read back 0 entries")
	var declared: int = 0
	for k in sfx.keys():
		var entry = sfx[k]
		if entry is Dictionary and _declares_loop(entry):
			declared += 1
	var on_disk: int = _loops_on_disk().size()
	assert_gt(declared, 0, "CONTROL: nothing declares loop, so parity is vacuous")
	assert_eq(declared, on_disk,
		"%d manifest entries declare loop but %d files loop on disk — the two sources disagree in a direction the arms above may not name" % [declared, on_disk])


func test_the_loop_key_is_still_unread_by_the_sfx_path() -> void:
	## The premise of this whole file. If SFX playback ever DOES read "loop", these arms become a
	## behavioural question rather than a documentation one, and this pin says so by going red.
	## Comment-stripped: read raw and a future `# reads the "loop" key` comment reds correct code.
	var code: String = GdSource.code_of("res://src/audio/SoundManager.gd")
	assert_ne(code, "", "CONTROL: SoundManager source must survive the comment strip")
	var start: int = code.find("func _try_play_sfx_from_manifest(")
	assert_gt(start, -1, "CONTROL: _try_play_sfx_from_manifest is gone — this file no longer describes the SFX path")
	var nxt: int = code.find("\nfunc ", start + 1)
	var body: String = code.substr(start, nxt - start) if nxt > start else code.substr(start)
	assert_false(body.contains("\"loop\""),
		"the SFX play path now reads a loop key — the manifest stopped being documentation and became a second source that can disagree at RUNTIME")
