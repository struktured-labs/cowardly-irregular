extends GutTest

## The behavioural half of "the long ambient beds actually play".
##
## ⛔ EVERY OTHER GUARD ON THIS IS A SOURCE PIN. Four files assert things about the TEXT of
## play_ambient — that it contains `_music_manifest`, that BaseVillage is allowed to route a
## variable, that the beds left a census. Measured 2026-09-16: ZERO tests in the corpus touched
## `_ambient_player` at all, so nothing asked what the player actually loads. A refactor that
## keeps the word `_music_manifest` in the function and resolves the wrong store passes all four.
##
## ambient_cave/forest/village exist in BOTH manifests under one key pointing at DIFFERENT FILES:
## a 145-214s composed bed in assets/audio/music, a 30-40 KB sting in assets/audio/sfx. Which one
## _ambient_player ends up holding IS the feature, and it is one assert away.

const MUSIC_DIR := "assets/audio/music/"
const SFX_DIR := "assets/audio/sfx/"
const SELF_PATH := "res://test/unit/test_the_ambient_layer_plays_the_composed_bed.gd"

## In both stores, and reached by a real zone or village route.
const DUAL_STORE_WIRED := ["ambient_cave", "ambient_forest", "ambient_village"]


func after_each() -> void:
	SoundManager.stop_ambient()


func _loaded_path(key: String) -> String:
	SoundManager.play_ambient(key)
	var s: AudioStream = SoundManager._ambient_player.stream
	return s.resource_path if s else ""


func test_a_dual_store_key_loads_the_composed_bed_not_the_sting() -> void:
	for key in DUAL_STORE_WIRED:
		var path: String = _loaded_path(str(key))
		assert_true(path.contains(MUSIC_DIR),
			"%s loaded %s — the ambient layer is holding the %s sting again, so the composed bed is unplayed exactly as it was for six months" % [key, path, SFX_DIR])
		assert_false(path.contains(SFX_DIR),
			"%s resolved into %s" % [key, SFX_DIR])


func test_the_bed_it_loads_is_the_long_one() -> void:
	## ⛔ THE PATH ALONE IS NOT THE POINT — the sting and the bed differ by two orders of
	## magnitude in length, and that difference is what a player hears. A path check would pass on
	## a 5 s file that happened to sit in the music directory.
	for key in DUAL_STORE_WIRED:
		SoundManager.play_ambient(str(key))
		var s: AudioStream = SoundManager._ambient_player.stream
		assert_not_null(s, "CONTROL: %s loaded no stream at all" % key)
		assert_gt(s.get_length(), 100.0,
			"%s is %.1f s — the composed beds are 145-214 s and the SFX twins are seconds, so this is the sting" % [key, s.get_length()])


func test_a_single_store_key_still_resolves_from_sfx() -> void:
	## The fallback is not decoration: ambient_coast/plains/dungeon and every weather_* key live
	## ONLY in the SFX manifest. Preferring music must not strand them.
	var path: String = _loaded_path("ambient_coast")
	assert_true(path.contains(SFX_DIR),
		"ambient_coast loaded %s — it exists only in the SFX manifest, so the music-first preference has broken the fallback and three zones plus all weather have gone silent" % path)


func test_an_unknown_key_leaves_nothing_audible() -> void:
	## ⛔ THE CONTRACT IS SILENCE, NOT A NULL STREAM, and my first version of this arm asserted
	## the wrong one. stop_ambient() stops the player without clearing `stream`, so the previous
	## resource stays ASSIGNED — harmless, because a stopped player emits nothing and `finished`
	## never fires to re-loop it. Asserting null here failed against correct pre-existing code and
	## would have read as a bug in the music-first change that shipped beside it.
	SoundManager.play_ambient(str(DUAL_STORE_WIRED[0]))
	assert_true(SoundManager._ambient_player.playing, "CONTROL: a real bed is playing before the bad key")
	SoundManager.play_ambient("zzq_not_in_either_store")
	assert_false(SoundManager._ambient_player.playing,
		"an unknown key left the ambient player RUNNING — the previous zone's bed keeps sounding over the new area")


func test_the_members_this_file_reaches_still_exist() -> void:
	## Same floor as the other music guards, derived from this file's own stripped source.
	const GdSource := preload("res://test/unit/helpers/gd_source.gd")
	var src: String = FileAccess.get_file_as_string(SELF_PATH)
	assert_gt(src.length(), 1000, "CONTROL: this arm read its own source back — %d chars" % src.length())
	var methods := {}
	var props := {}
	var re := RegEx.create_from_string("SoundManager\\.([A-Za-z_][A-Za-z0-9_]*)(\\()?")
	var code: String = GdSource.strip_comments(src)
	for line in code.split("\n"):
		for m in re.search_all(str(line)):
			if m.get_string(2) == "(":
				methods[m.get_string(1)] = true
			else:
				props[m.get_string(1)] = true
	## ⛔ THE DERIVATION ASSUMES DIRECT NAMING, and that assumption is now ASSERTED rather than
	## implied. The regex above matches `SoundManager.<name>`; a file that binds an alias — cowir-sfx
	## write `var sm := SoundManager` and derive from `sm.<name>(` — would have its reaches silently
	## uncounted, and the floor would report success about a smaller set. That is @cowir-controller's
	## shape exactly: their ledger searched only `ui_up`/`ui_down`, so a horizontal-only file read as
	## converted — the instrument and the work shared a blind spot, so the instrument could not
	## report it.
	##
	## Measured 2026-09-17 before writing this: exactly ONE line in the whole corpus binds an alias
	## (test_sfx_volume_reaches_all_players_regression.gd:158) and it is in a file with no floor. So
	## this is NOT a defence against a live hazard — it is a precondition that announces itself the
	## day someone adopts the style here, which costs one assert instead of an alias-aware parser.
	## ⛔ `(?m)` IS LOAD-BEARING. Without it `$` anchors at END OF STRING, not end of line, so
	## this pattern could only ever match an alias on the file's LAST line — the assert was vacuous
	## and the mutation that should have redded it passed EC=0. Found by planting `var sm :=
	## SoundManager` rather than by reading the regex.
	assert_false(RegEx.create_from_string("(?m)^[\\t ]*(var|const)[\\t ]+\\w+[\\t ]*:?=[\\t ]*SoundManager[\\t ]*$").search(code) != null,
		"this file now binds an alias to SoundManager — the derivation above reads `SoundManager.<name>` only, so reaches through that alias are NOT in the floor and it is quietly guarding less than it claims")
	assert_gt(methods.size(), 1, "CONTROL: derived %d method reaches" % methods.size())
	assert_gt(props.size(), 0, "CONTROL: derived %d property reaches" % props.size())
	for name in methods:
		assert_true(SoundManager.has_method(name), "SoundManager has no method %s()" % name)
	for name in props:
		assert_true(name in SoundManager, "SoundManager has no property %s" % name)


func test_a_bed_does_not_play_against_itself() -> void:
	## ⛔ A CONSEQUENCE OF THE MUSIC-FIRST CHANGE, NOT A PRE-EXISTING BUG. While the ambient
	## layer resolved from the SFX store the Jukebox could only ever double a 187s bed against a
	## 5s sting — obviously two things. Now both players can hold the SAME FILE at an arbitrary
	## offset, 16 dB apart, which is comb filtering rather than layering. Reachable: the Jukebox
	## opens from the overworld menu, and "Dripping Stone" is a row in it while an ice zone is
	## running that exact bed.
	##
	## ⚠️ DECLARED RESIDUAL, AND IT IS THE EXISTING DESIGN RATHER THAN A NEW COST — checked
	## before writing it down, because the first draft of this note implied the fix introduced it.
	## The ambient player is ONE SLOT and only a zone CHANGE re-asserts a key
	## (OverworldScene:579, inside `if new_zone != _current_zone`). WeatherSystem already contends
	## for the same slot the same way: rain replaces zone ambience, and when weather clears it
	## calls stop_ambient() without restoring what was there. So "ambience stays off until you
	## cross a boundary" predates this change; auditioning a bed in the Jukebox is one more way in.
	## The trade is still deliberate — silence beats a flanged double — and if the single slot ever
	## becomes worth fixing, it is one fix for weather and this together, not two.
	##
	## The suppression has a MIRROR of the same residual (@cowir-adhoc): walk into the ice zone
	## while the music player already holds that bed and ambience is suppressed, and if the
	## music then changes while you STAY in the zone it does not come back either. One class,
	## two doors, one fix if the single slot is ever worth re-asserting.
	SoundManager.play_ambient("ambient_cave")
	assert_true(SoundManager._ambient_player.playing, "CONTROL: the zone ambience is running before the Jukebox asks")
	var amb_path: String = SoundManager._ambient_player.stream.resource_path
	SoundManager.play_music("ambient_cave", true)
	await get_tree().create_timer(0.2).timeout
	assert_true(SoundManager._music_player.stream != null and SoundManager._music_player.stream.resource_path == amb_path,
		"CONTROL: the music player took the same file — without that there is no collision to defend against")
	assert_false(SoundManager._ambient_player.playing,
		"%s is running on BOTH players at once — one file, two offsets, 16 dB apart" % amb_path)
	SoundManager.stop_music()


func test_the_collision_is_blocked_in_the_other_order_too() -> void:
	## ⛔ THE FIRST FIX WAS ONE-DIRECTIONAL AND SO WAS THE ARM THAT PROVED IT. The guard sat in
	## _try_play_from_manifest — the MUSIC load path — so it only won when music started second.
	## The arm above drives exactly the order I happened to find the bug in, and swapping its two
	## lines failed against the shipped fix. Green about one direction and silent about the other,
	## which is the 64-green-radius mistake one layer in (@cowir-adhoc, who walked every caller).
	##
	## Latent rather than live at the time: nothing in the tree passes an ambient_* id to
	## play_music, so only the Jukebox reaches it, and that opens where a player cannot walk into
	## a zone. The reverse door was held shut by a UI accident, not by the fix.
	SoundManager.play_music(str(DUAL_STORE_WIRED[0]), true)
	await get_tree().create_timer(0.2).timeout
	assert_true(SoundManager._music_player.playing, "CONTROL: the music player holds the bed first in this order")
	var mus_path: String = SoundManager._music_player.stream.resource_path
	SoundManager.play_ambient(str(DUAL_STORE_WIRED[0]))
	assert_false(SoundManager._ambient_player.playing,
		"the ambient layer started %s while the music player was already playing it — same file, two players, the collision the other arm blocks in the opposite order" % mus_path)
	SoundManager.stop_music()


func test_the_current_key_never_names_a_bed_that_is_not_playing() -> void:
	## ⛔ THE TWO SUPPRESSION PATHS LEFT DIFFERENT STATE and only one of them was truthful.
	## Direction one calls stop_ambient(), which clears the field. Direction two returned early
	## with _current_ambient_key already assigned at the top of play_ambient, so the field named a
	## bed that was not playing. Inert when found — every reader was checked — but this field IS
	## the record of what is live, and one that lies on one of two paths is the kind nobody
	## re-checks. Asserted rather than noted, because "does the field match reality" is checkable.
	var bed: String = str(DUAL_STORE_WIRED[0])
	SoundManager.play_music(bed, true)
	await get_tree().create_timer(0.2).timeout
	SoundManager.play_ambient(bed)
	assert_false(SoundManager._ambient_player.playing, "CONTROL: the ambient layer is suppressed in this order")
	assert_eq(SoundManager._current_ambient_key, "",
		"_current_ambient_key is \"%s\" while nothing is playing on the ambient layer — a reader asking what ambience is live gets a bed that was refused" % SoundManager._current_ambient_key)
	SoundManager.stop_music()
