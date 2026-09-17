extends GutTest

## _start_monster_music used to probe `assets/audio/music/battle_<type>.ogg` by hand before
## falling back to proc-gen. That probe was dead twice over and has been deleted:
##
##   1. every route in is a play_music match arm, so _try_play_from_manifest("battle_<type>") has
##      already run for the SAME key — arriving here means that load failed, and re-testing the
##      same path cannot change the answer;
##   2. ⛔ I ORIGINALLY GAVE A SECOND REASON AND IT WAS MEASURED FALSE THE SAME HOUR. I wrote that
##      ResourceLoader.exists() is unreliable for imported resources, citing SoundManager :1777
##      and :1846. cowir-main then built a real .pck on godot 4.4.1 and probed INSIDE it:
##          res://tex.png · res://snd.ogg   exists() TRUE   file_exists() FALSE   load() TRUE
##      exists() reads the PACKED .import sidecar and is CORRECT for imported resources;
##      FileAccess.file_exists() is the one that is wrong for them. The 2026-03-30 comment named
##      both and was right about one, and I repeated the wrong half twice before checking it.
##      Kept here rather than deleted, because a reason that was published needs a visible
##      retraction and not a quiet edit.
##
## 🔑 THIS FILE IS WHAT MAKES THE DELETION SAFE, and it is a ratchet rather than a list. The probe
## was a silent fallback for an OGG on disk that NO manifest key names. Zero such files exist for
## these types today; if one ever ships, the manifest — not a hand-built path — is where it has to
## be declared, and the arm below says so out loud instead of the bed quietly not playing.

const MANIFEST := "res://data/music_manifest.json"
const SM_PATH := "res://src/audio/SoundManager.gd"


func _manifest_keys() -> Dictionary:
	var raw: String = FileAccess.get_file_as_string(MANIFEST)
	assert_gt(raw.length(), 1000, "SCOPE control: manifest read back %d chars" % raw.length())
	return (JSON.parse_string(raw) as Dictionary).get("tracks", {})


## \u26d4 DERIVED FROM THE WHOLE TREE, NOT FROM ONE FILE, AND THAT IS THE POINT. The first version
## scanned SoundManager.gd alone -- which names a LOCATION while the thing it watches for (a new
## dispatch) can arrive anywhere. `_start_monster_music` is private BY CONVENTION only; GDScript
## does not enforce the underscore and SoundManager is an autoload, so any script can call it.
## Measured when this was written: 0 call sites outside SoundManager.gd, so the gap was latent --
## which is exactly when it is cheap to close. A declaration naming a future trigger has to name
## the trigger's LOCATION, and "the tree" is the only location a behaviour cannot escape.
func _dispatched_types() -> Array[String]:
	var files: Array[String] = []
	_gd_files("res://src", files)
	assert_gt(files.size(), 50,
		"SCOPE control: the src walk found %d .gd files — a zero-hit result below would be vacuous" % files.size())
	## Comments STRIPPED: a commented-out dispatch is not a dispatch, and widening the corpus from
	## one file to the tree multiplies the prose this regex can see. The one-file version had the
	## same hole and a smaller surface.
	const GdSource := preload("res://test/unit/helpers/gd_source.gd")
	var joined: String = ""
	for f in files:
		joined += GdSource.strip_comments(FileAccess.get_file_as_string(f))
	assert_gt(joined.length(), 100000, "SCOPE control: the walk read back %d chars" % joined.length())
	var out: Array[String] = []
	var re := RegEx.create_from_string("_start_monster_music\\(\"([a-z_]+)\"\\)")
	for m in re.search_all(joined):
		if not out.has(m.get_string(1)):
			out.append(m.get_string(1))
	out.sort()
	return out


func _gd_files(root: String, out: Array[String]) -> void:
	var d := DirAccess.open(root)
	if d == null:
		return
	d.list_dir_begin()
	var n: String = d.get_next()
	while n != "":
		var p: String = root + "/" + n
		if d.current_is_dir():
			_gd_files(p, out)
		elif n.ends_with(".gd"):
			out.append(p)
		n = d.get_next()
	d.list_dir_end()


func test_every_monster_theme_is_named_by_the_manifest() -> void:
	var types: Array[String] = _dispatched_types()
	assert_gt(types.size(), 5,
		"SCOPE control: parsed only %d dispatched monster types — a green below would be vacuous" % types.size())
	var keys: Dictionary = _manifest_keys()

	var unnamed: Array[String] = []
	for t in types:
		if not keys.has("battle_%s" % t):
			unnamed.append(str(t))
	assert_eq(unnamed.size(), 0,
		"monster types dispatched to the procedural theme with no battle_<type> manifest key (%s) — an authored bed for one of these can only be reached by declaring it in the manifest, and the hand-built path probe that used to find it is gone" % [unnamed])


func test_no_authored_battle_bed_is_reachable_only_by_a_hand_built_path() -> void:
	## The other half: an OGG on disk that no key names would have been found by the old probe.
	var keys: Dictionary = _manifest_keys()
	var named: Dictionary = {}
	for k in keys.keys():
		var e = keys[k]
		if e is Dictionary:
			named[str(e.get("file", "")).get_file()] = true

	var d := DirAccess.open("res://assets/audio/music")
	assert_not_null(d, "SCOPE control: could not open the music directory")
	var orphans: Array[String] = []
	d.list_dir_begin()
	var n: String = d.get_next()
	while n != "":
		if n.ends_with(".ogg") and n.begins_with("battle_") and not named.has(n):
			orphans.append(n)
		n = d.get_next()
	d.list_dir_end()
	orphans.sort()
	assert_eq(orphans.size(), 0,
		"battle_*.ogg on disk that no manifest key names (%s) — these were the only files the deleted probe could have found, and nothing reaches them now" % [orphans])


## ⛔ STRIP THE COMMENTS FIRST, AND THIS ARM IS WHY. My own note explaining why the probe was
## deleted NAMES ResourceLoader.exists, so the first version of this guard red against the very
## comment recording the fix — a retraction containing the string it retracts, which is the same
## trap that made me read a retired "33" as a live count an hour earlier. The CODE is the subject.
func test_the_blind_probe_is_gone_and_stays_gone() -> void:
	const GdSource := preload("res://test/unit/helpers/gd_source.gd")
	var src: String = GdSource.strip_comments(FileAccess.get_file_as_string(SM_PATH))
	var at: int = src.find("func _start_monster_music")
	assert_gt(at, -1, "SCOPE control: _start_monster_music was renamed — re-derive this guard")
	var body: String = src.substr(at, src.find("\nfunc ", at + 1) - at)
	assert_true(body.contains("_music_cache"), "CONTROL: the stripper left the function's real body intact")

	## \u26d4 BOTH PREDICATES, AND THE FIRST VERSION REFUSED ONLY THE ONE THAT WORKS. The subject
	## here is a HAND-BUILT PATH PROBE of any spelling: the manifest has already answered for this
	## key before this function runs, so no existence test can change the answer. It is not about
	## either predicate being broken.
	##
	## But if one of them comes back it matters WHICH, and my first version pinned the wrong one.
	## cowir-main measured inside a real .pck (godot 4.4.1): ResourceLoader.exists is CORRECT for
	## imported resources -- it reads the packed .import sidecar -- while FileAccess.file_exists
	## returns FALSE for a present, loadable one. So the spelling this arm originally permitted is
	## the actively dangerous one, and the spelling it refused is fine.
	for probe in ["ResourceLoader.exists", "FileAccess.file_exists"]:
		assert_false(body.contains(probe),
			"a hand-built path probe is back in _start_monster_music (%s) — the manifest was already consulted for this key, so the probe cannot change the answer. NOTE: FileAccess.file_exists is additionally WRONG for an imported resource in a pack (measured 2026-09-17), while ResourceLoader.exists is correct; neither belongs here." % probe)


## ⛔ THE SECOND AXIS, AND IT IS THE SAME SENTENCE WITH A DIFFERENT NOUN (@cowir-sfx, 2026-09-17).
## Widening the corpus to src/**.gd bounds WHERE a dispatch can arrive. It does not bound its
## SHAPE: the derivation above matches `_start_monster_music("literal")` and is blind to
## `_start_monster_music(monster_type)`. The proof sits in its own corpus -- the declaration line
## `func _start_monster_music(monster_type: String)` is an occurrence the regex does not match.
##
## A census of literals cannot see a computed key, so the ratchet's answer would silently narrow
## rather than fail. This is my own KNOWN_UNREACHED lesson one function over: that guard refuses a
## CONCATENATED ambient key for exactly this reason, and this refuses a non-literal dispatch.
##
## Measured before writing: 10 call sites, all literal, 0 computed. Latent -- which is when closing
## it is free, and the same argument I used for the location axis an hour ago.
func test_no_monster_theme_is_dispatched_by_a_computed_key() -> void:
	var files: Array[String] = []
	_gd_files("res://src", files)
	assert_gt(files.size(), 50, "SCOPE control: %d .gd files walked" % files.size())
	const GdSource := preload("res://test/unit/helpers/gd_source.gd")

	var call_re := RegEx.create_from_string("_start_monster_music\\(([^)]*)\\)")
	var literal_re := RegEx.create_from_string("^\"[a-z_]+\"$")
	var seen: int = 0
	var computed: Array[String] = []
	for f in files:
		var code: String = GdSource.strip_comments(FileAccess.get_file_as_string(f))
		for line in code.split("\n"):
			if line.find("_start_monster_music(") < 0:
				continue
			if line.strip_edges().begins_with("func "):
				continue          ## the declaration is not a dispatch
			for m in call_re.search_all(line):
				seen += 1
				if literal_re.search(m.get_string(1).strip_edges()) == null:
					computed.append("%s: %s" % [str(f).get_file(), line.strip_edges()])
	assert_gt(seen, 5,
		"CONTROL: found only %d dispatch sites — if this drops to zero the arm below is vacuous" % seen)
	assert_eq(computed.size(), 0,
		"a monster theme is dispatched by a computed key (%d): %s — the census above reads LITERALS, so a computed one makes its answer silently narrower instead of failing. Either name it literally, or extend the derivation to cover the construction site." % [computed.size(), computed])

