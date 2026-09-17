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


## Derived from the dispatch itself, so a new monster arm cannot be added without being covered.
func _dispatched_types() -> Array[String]:
	var src: String = FileAccess.get_file_as_string(SM_PATH)
	assert_gt(src.length(), 10000, "SCOPE control: SoundManager read back %d chars" % src.length())
	var out: Array[String] = []
	var re := RegEx.create_from_string("_start_monster_music\\(\"([a-z_]+)\"\\)")
	for m in re.search_all(src):
		if not out.has(m.get_string(1)):
			out.append(m.get_string(1))
	out.sort()
	return out


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
	assert_false(body.contains("ResourceLoader.exists"),
		"the hand-built path probe is back — the manifest has already been consulted for this key before this function runs, so the probe cannot change the answer. (It is NOT about ResourceLoader.exists being broken: measured correct inside a real .pck, 2026-09-17.)")
