extends GutTest

## ⛔ A CALL SITE RE-DERIVED AUDIO AVAILABILITY WITH THE PREDICATE ITS OWNER DOCUMENTS AS WRONG.
## `BattleScene`'s Limit Break stinger built `res://assets/audio/music/job_%s_special.ogg` itself
## — duplicating the manifest's knowledge of where the file lives — and gated on
## `ResourceLoader.exists()`. `SoundManager` says twice, at :1777 and :1846, that the call reports
## FALSE for resources that ARE present in a web PCK.
##
## So the failure is a FALSE NEGATIVE: the file ships, the check says no, and the Limit Break's
## job stinger is silent on web while desktop is fine. Handed over by cowir-music, who own the
## predicate and measured that 0 of the 14 `job_*_special` tracks are dropped from the web build —
## the file is there, only the question was wrong.
##
## ⚠️ SEVERITY IS LOW AND STATED AS SUCH: nobody has reproduced a web PCK false negative from here.
## The evidence is the owner's own twice-written comment, not a reproduction. What this arm pins is
## that the call site ASKS THE OWNER rather than re-deriving — which is true regardless of how
## often the underlying predicate actually misfires.

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
	## ⛔ THE PREMISE ARM. Re-pointing at `music_is_available` is only an improvement while that
	## function tests with load(). If it is ever changed back to an existence check, this call site
	## inherits the bug it was moved away from and nothing else would say so.
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
