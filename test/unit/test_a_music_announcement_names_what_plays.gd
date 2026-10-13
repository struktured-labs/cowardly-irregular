extends GutTest

## play_music() keeps the REQUESTED id in _current_music, so a battle_<monster> with no bed of its
## own leaves it naming the monster while the world bed is what the player hears. BattleScene's
## announcement printed that id, so struktured's 2026-10-05 log says "Playing spider battle theme
## (battle_spider)" on the line after battle_medieval loaded. 27 pool-reachable monsters are in
## that set. playing_track_stem() reports the RESOLVED stream so a diagnostic can tell the truth.

const SOUND_MANAGER := "res://src/audio/SoundManager.gd"
const BATTLE_SCENE := "res://src/battle/BattleScene.gd"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
## A monster with its own bed (request and outcome AGREE) and ones without (they DIFFER).
const WITH_BED := "battle_slime"
const WITHOUT_BED := ["battle_spider", "battle_the_absence"]


func _code(path: String) -> String:
	return GdSource.code_of(path)


func _sm() -> Node:
	return get_tree().root.get_node_or_null("SoundManager")


func after_each() -> void:
	var sm: Node = _sm()
	if sm != null:
		sm.stop_music()


func test_the_symbols_this_guard_reaches_still_exist() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "SoundManager autoload is absent — every arm below would abort silently")
	if sm == null:
		return
	for m in ["playing_track_stem", "play_music", "stop_music", "has_music_track"]:
		assert_true(sm.has_method(m),
			"FLOOR: SoundManager.%s is gone; an arm reaching it aborts its own function and a prior assert makes that a PASS" % m)
	assert_true("_current_music" in sm, "FLOOR: _current_music is gone — the arms compare against it")


func test_the_accessor_reports_the_resolved_bed_not_the_request() -> void:
	var sm: Node = _sm()
	if sm == null or not sm.has_method("playing_track_stem"):
		return
	for key in WITHOUT_BED:
		sm.stop_music()
		await get_tree().process_frame
		sm.play_music(key)
		await get_tree().process_frame
		var stem: String = sm.playing_track_stem()
		var requested: String = str(sm._current_music)
		assert_eq(requested, key,
			"precondition: _current_music holds the REQUEST; if this changed, the arm below is testing something else")
		## PRECONDITION, labelled: an empty stem has TWO causes and this arm cannot tell them apart.
		## Unlabelled it blamed the fallback DERIVATION, when no-playback-in-this-process is just as
		## likely — note_mixer_progress runs from _process and an earlier test can leave the mixer
		## wedged, which is what red the .672 gate on another lane's fixture.
		assert_ne(stem, "",
			("precondition: %s must resolve to SOME playing stream or the arm below judges nothing. "
			+ "An empty stem means no playback in THIS process — not that the fallback derivation "
			+ "is broken.") % key)
		assert_ne(stem, key,
			("%s has no bed of its own, so the stem must name the bed that actually plays, not the "
			+ "request. Got %s, which is the lie the announcement used to print.") % [key, stem])
	## CONTROL: where a bed DOES exist the two must agree, or the accessor is just always different.
	sm.stop_music()
	await get_tree().process_frame
	sm.play_music(WITH_BED)
	await get_tree().process_frame
	assert_eq(sm.playing_track_stem(), WITH_BED,
		"CONTROL: %s has its own bed, so request and outcome must AGREE" % WITH_BED)


func test_the_accessor_is_empty_when_nothing_plays() -> void:
	var sm: Node = _sm()
	if sm == null or not sm.has_method("playing_track_stem"):
		return
	sm.play_music(WITH_BED)
	await get_tree().process_frame
	assert_ne(sm.playing_track_stem(), "", "precondition: a bed is playing before the stop")
	sm.stop_music()
	for _i in range(3):
		await get_tree().process_frame
	assert_eq(sm.playing_track_stem(), "",
		"the stream stays ASSIGNED after a stop, so an ungated accessor names a bed nobody hears")


## The [MUSIC] announcements that interpolate a REQUESTED track id. Hand-listed deliberately: two
## derivations were tried and both were wrong in opposite directions — proximity flagged five prints
## that merely sit below `_base_music_track = ...` (two of which interpolate nothing at all), and
## parsing the `%` args missed the WRAPPED print whose operator is on the next line. Parsing
## GDScript interpolation inside GDScript is more machinery than a diagnostic guard earns. The
## floor below is what keeps this honest: if either text moves, the arm reds and names it.
const ANNOUNCEMENTS := ["battle theme", "party recovered"]


func test_EVERY_music_announcement_derives_from_the_accessor() -> void:
	## SPELLING, not behaviour: the print cannot be observed from here.
	##
	## ⛔ THIS ARM USED TO BE `src.contains("playing_track_stem()")` — FILE-WIDE, so it passed as
	## soon as ONE site asked. The battle-start announcement was fixed and the danger-RECOVERY
	## announcement kept naming the request, with this arm green the whole time. A file-wide
	## contains cannot tell one site from all sites, which is the hole it left.
	var src: String = _code(BATTLE_SCENE)
	for text in ANNOUNCEMENTS:
		var at: int = src.find(text)
		assert_gt(at, -1,
			("FLOOR: no [MUSIC] announcement contains `%s` any more — this arm is stale and would "
			+ "pass on a file that announces nothing.") % text)
		if at < 0:
			continue
		var around: String = src.substr(maxi(0, at - 500), 1000)
		assert_true(around.contains("playing_track_stem()"),
			("the announcement containing `%s` has no playing_track_stem() within 500 chars, so it "
			+ "names the REQUEST — how the 10-05 log came to read \"Switched back to "
			+ "battle_dark_knight music\" on the line after battle_medieval loaded.") % text)
	assert_true(src.contains("requested, %s playing"),
		"the battle announcement must say BOTH names when they differ, or a reader cannot tell a fallback from a hit")
