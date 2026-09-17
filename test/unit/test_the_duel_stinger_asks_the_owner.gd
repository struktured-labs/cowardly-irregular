extends GutTest

## ⛔ A CALL SITE REBUILT A PATH THE MANIFEST OWNS. `BattleScene`'s Limit Break stinger built
## `res://assets/audio/music/job_%s_special.ogg` itself — duplicating the manifest's knowledge of
## where the file lives — and gated it with its own existence check.
##
## ⚠️ THE ORIGINAL REASON FOR THIS FIX WAS WRONG AND IS KEPT HERE AS A RETRACTION RATHER THAN
## EDITED AWAY, because it was published twice in the fleet channel and a silent edit would let the
## next reader restore it. I wrote that `SoundManager` documents `ResourceLoader.exists()` TWICE as
## reporting FALSE for resources present in a web PCK. Traced by cowir-music: that is ONE
## speculative 2026-03-30 comment ("THIS SHOULD FIX…", no test, no repro) and one later citation of
## it. Then cowir-main MEASURED it inside a real exported PCK on godot 4.4.1:
##
##     res://tex.png · res://snd.ogg     exists() TRUE · file_exists() FALSE · load() TRUE
##
## `ResourceLoader.exists()` is CORRECT for imported resources — it resolves through the packed
## `.import` sidecar. `FileAccess.file_exists()` is the predicate that is genuinely wrong for them.
## The old comment named both and was right about one.
##
## ⛔ SO THE FIX STANDS ON THE OTHER HALF, WHICH NEVER DEPENDED ON ANY OF THAT: a call site should
## not re-derive a path the manifest owns. `music_is_available()` reads the manifest for the path,
## which is why `BattleScene` now contains no hand-built music path at all. It costs nothing —
## `_try_play_from_manifest` loads the same path one line later and Godot caches by path.

const GdSourceHelper = preload("res://test/unit/helpers/gd_source.gd")
const BS_PATH := "res://src/battle/BattleScene.gd"
const SM_PATH := "res://src/audio/SoundManager.gd"


func test_the_stinger_asks_the_owner_rather_than_building_a_path() -> void:
	var code: String = GdSourceHelper.code_of(BS_PATH)
	assert_true(code.contains("SoundManager.music_is_available(stinger_key)"),
		"the Limit Break stinger must ask the manifest's owner whether the track is available")
	assert_false(code.contains("assets/audio/music/"),
		"and must not rebuild a music path — the manifest owns where the file lives")
	assert_false(code.contains("ResourceLoader.exists"),
		"ResourceLoader.exists is the predicate SoundManager documents as unreliable for audio in a web PCK")


func test_the_owner_still_uses_load_for_the_reason_this_depends_on() -> void:
	## ⛔ THE PREMISE ARM, AND THE MEASUREMENT CHANGED ITS REASON WITHOUT CHANGING ITS CONTRACT.
	## It was written because an existence check was thought to be wrong on web. It is not — but
	## `music_is_available` still owes its caller the AUTHORITATIVE answer, and `load()` is what
	## gives it: the same load the play path takes one line later, cached by path. cowir-music kept
	## it for that reason after correcting the comment, and this arm reds if it ever becomes a
	## cheaper check that answers a different question.
	var sm: String = GdSourceHelper.code_of(SM_PATH)
	var at: int = sm.find("func music_is_available(")
	assert_gt(at, -1, "CONTROL: the owner survives comment stripping")
	var body: String = sm.substr(at, sm.find("\nfunc ", at + 1) - at)
	assert_true(body.contains("load(path)"),
		"music_is_available must test with load(), which is why the stinger may rely on it")
	assert_false(body.contains("ResourceLoader.exists"),
		"and must not fall back to the existence check this call site was moved off")


func test_the_stinger_key_matches_what_the_manifest_authors() -> void:
	## Anti-coincidence: the key is built from a job id, so it is only correct while the manifest
	## uses that spelling. Derived from the manifest rather than pinned.
	var raw: String = FileAccess.get_file_as_string("res://data/music_manifest.json")
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "CONTROL: the music manifest parses")
	var keys: Array = []
	var stack: Array = [parsed]
	while not stack.is_empty():
		var node: Variant = stack.pop_back()
		if node is Dictionary:
			for k in (node as Dictionary):
				if str(k).begins_with("job_") and str(k).ends_with("_special"):
					keys.append(str(k))
				stack.append((node as Dictionary)[k])
	assert_gt(keys.size(), 4,
		"CONTROL: the manifest authors job_*_special tracks at all; found %d" % keys.size())
	assert_true(keys.has("job_fighter_special"),
		"the key shape the call site builds must be one the manifest actually authors")


func test_the_owner_answers_for_a_real_track() -> void:
	## Runtime, not source: the swap is only safe if music_is_available says YES for a track that
	## ships. A predicate that answered NO everywhere would silence the stinger just as thoroughly.
	assert_true(SoundManager.music_is_available("job_fighter_special"),
		"a manifest-backed track that exists on disk must read as available")
