extends GutTest

## The Jukebox must not claim to play a track this build cannot load.
##
## The Web preset drops 54 music files (`assets/audio/music/*industrial*`,
## `*digital*`, `*abstract*`, `*futuristic*`, `cutscene_w4/5/6*`) while
## data/music_manifest.json — which lists all 165 — ships intact. JukeboxMenu
## builds its list from the manifest with no availability filter, so a third of
## the rows are unbacked on web.
##
## 🔑 THE UI DID NOT JUST GO QUIET, IT REPORTED SUCCESS. _play_selected sets
## _currently_playing and turns the label PLAYING_COLOR *before* the attempt and
## never reconsiders, and play_music fades the previous bed out before it
## discovers the load failed. So the player got: music stops, nothing starts,
## and the screen says "Now Playing: Break Room".
##
## ⚠️ 33 of the 54, not all of them. The Jukebox routes ids starting with
## "overworld" through play_area_music, and play_music's `_:` arm sends
## battle_*/boss* to a procedural generator — both make sound. The 33 with no
## such path are cutscene(16), credits(3), danger(3), dungeon(3), victory(3),
## village(3), ambient(2). Normal gameplay is NOT affected: every area starter
## falls back procedurally after its manifest attempt, which is the documented
## W4-W6 web design. The Jukebox is the one surface that lets a player name an
## arbitrary manifest key, and so the one place the design leaks.
##
## 🛑 THE AVAILABILITY CHECK MUST BE load(), NOT ResourceLoader.exists(). This
## file's own subject documents why: exists() reports FALSE for resources that
## ARE present in a web PCK. A guard built on it would hide tracks that work.

const MANIFEST := "res://data/music_manifest.json"
const PRESETS := "res://export_presets.cfg"

## Not a real id under any naming scheme in this project, so it cannot collide
## with a track that later gets authored.
const FAKE_ID := "zzq_absent_from_this_build"


func after_each() -> void:
	SoundManager._music_manifest.erase(FAKE_ID)


func test_control_a_shipped_track_is_available() -> void:
	## If this fails the probe is broken, not the subject. battle_medieval is a
	## web fallback anchor — it is in every build by construction.
	assert_true(SoundManager.music_is_available("battle_medieval"),
		"CONTROL FAILED: battle_medieval reports unavailable in a desktop test run, so this probe cannot tell present from absent")


func test_a_track_whose_file_is_missing_is_not_available() -> void:
	## The web condition, built rather than reasoned about: a manifest entry
	## naming a file that is not in this build.
	SoundManager._load_music_manifest()
	SoundManager._music_manifest[FAKE_ID] = {
		"file": "assets/audio/music/%s.ogg" % FAKE_ID,
		"duration": 60.0,
	}
	assert_false(SoundManager.music_is_available(FAKE_ID),
		"a manifest entry naming a file this build does not contain reported AVAILABLE — the Jukebox would fade the current bed out and play nothing while claiming to play it")


func test_a_missing_file_with_a_procedural_arm_is_still_available() -> void:
	## The other half, and the reason this is 33 rows and not 54: battle_*/boss*
	## reach a generator from play_music's `_:` arm even with no file. Refusing
	## them would hide rows that work.
	SoundManager._load_music_manifest()
	SoundManager._music_manifest[FAKE_ID] = {"file": "assets/audio/music/%s.ogg" % FAKE_ID}
	assert_false(SoundManager.music_is_available(FAKE_ID),
		"SCOPE control: the non-procedural id must be unavailable, or the arm below proves nothing")

	SoundManager._music_manifest.erase(FAKE_ID)
	var proc_id: String = "battle_" + FAKE_ID
	SoundManager._music_manifest[proc_id] = {"file": "assets/audio/music/%s.ogg" % proc_id}
	var got: bool = SoundManager.music_is_available(proc_id)
	SoundManager._music_manifest.erase(proc_id)
	assert_true(got,
		"a battle_* id with no file reported unavailable — it reaches _start_battle_music via the `_:` arm and does make sound, so refusing it would blank a working row")


func test_a_track_with_no_file_entry_is_available() -> void:
	## Procedural-only ids ("title", "autogrind") carry no file and always play.
	SoundManager._load_music_manifest()
	SoundManager._music_manifest[FAKE_ID] = {"duration": 0.0}
	assert_true(SoundManager.music_is_available(FAKE_ID),
		"an entry with no `file` reported unavailable — those are owned by procedural paths and always make sound")


func test_the_jukebox_consults_the_check_before_playing() -> void:
	## Behaviour above, wiring here: the predicate is useless if the consumer
	## never calls it, and no runtime test can reach a web PCK from here.
	var src: String = FileAccess.get_file_as_string("res://src/ui/JukeboxMenu.gd")
	assert_gt(src.length(), 2000, "SCOPE control: JukeboxMenu.gd read back %d chars" % src.length())
	var guard: int = src.find("music_is_available")
	var play: int = src.find("SoundManager.play_music(track_id)")
	assert_gt(guard, 0, "JukeboxMenu never calls music_is_available — the check exists and nothing consults it")
	assert_gt(play, 0, "SCOPE control: the play_music call site moved; this ordering check is anchored on nothing")
	assert_lt(guard, play,
		"the availability check appears AFTER the play call — play_music has already faded the previous bed out by then, so the guard cannot prevent the silence")


func test_the_excluded_population_is_large_enough_to_be_worth_guarding() -> void:
	## SCOPE control for the whole file. If the Web preset stops excluding music,
	## every arm above still passes while defending nothing — and this file's
	## reason for existing would be gone without anyone noticing.
	var cfg: String = FileAccess.get_file_as_string(PRESETS)
	assert_gt(cfg.length(), 500, "SCOPE control: export_presets.cfg read back %d chars" % cfg.length())
	var web: int = cfg.find("name=\"Web\"")
	assert_gt(web, 0, "SCOPE control: no Web preset found")
	var tail: String = cfg.substr(web, 4000)
	var line_start: int = tail.find("exclude_filter=\"")
	assert_gt(line_start, 0, "SCOPE control: Web preset has no exclude_filter")
	var filt: String = tail.substr(line_start + 16, tail.find("\"", line_start + 16) - line_start - 16)

	var pats: Array[String] = []
	for p in filt.split(","):
		var t: String = p.strip_edges()
		if t.begins_with("assets/audio/music/"):
			pats.append(t)
	assert_gt(pats.size(), 3,
		"the Web preset excludes %d music patterns — if this dropped to zero the guard defends nothing and should be retired deliberately, not left passing" % pats.size())

	var raw: String = FileAccess.get_file_as_string(MANIFEST)
	var tracks: Dictionary = (JSON.parse_string(raw) as Dictionary).get("tracks", {})
	var hit: int = 0
	for k in tracks.keys():
		var f: String = str((tracks[k] as Dictionary).get("file", ""))
		if f == "":
			continue
		for p in pats:
			if f.match(p):
				hit += 1
				break
	assert_gt(hit, 20,
		"only %d manifest tracks match the Web exclusions — expected ~54; either the filter parse broke or the corpus changed shape" % hit)
