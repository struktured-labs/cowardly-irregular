extends GutTest

## play_music() tore down the bed ~60 lines before discovering it had nothing to replace it with.
##
## The crossfade block hands the outgoing stream to B and stops A; the `match` that decides what to
## play next runs AFTER it, and its final `else` only push_warning()s. Measured on the shipped code:
##
##     after play_music("no_such_bed"):  _music_playing=true  A.playing=false  B.playing=true
##
## So the bed is not silenced instantly — B carries it for CROSSFADE_DURATION and then stops, which
## is why this reads on screen as the music simply ending rather than as a failed call.
##
## 🔑 NOT A SPECULATIVE SHAPE. CutsceneDirector._step_play_music already carried the finding as a
## comment and guarded it AT ITS OWN CALL SITE: "An unresolvable id is NOT a no-op: play_music
## crossfades the current track out, then warns and plays nothing, leaving the scene in silence."
## 26 call sites across 10 files reach play_music. TWO carried a pre-check, and they do not check
## the same thing: CutsceneDirector tests has_music_track AND _cue_is_available, BattleScene:3864
## tests ResourceLoader.exists on the file it is about to name. 24 had nothing.
##
## ⛔ THE THIRD CONSEQUENCE IS THE WORST AND WAS FOUND BY AN ARM THAT PASSED WHEN IT SHOULD NOT
## HAVE. The cache write at the foot of play_music stores `_music_player.stream` under `track`, and
## A's stream survives the stop — so the unknown id is cached holding the PREVIOUS bed. The second
## call then plays battle_medieval.ogg under a name that does not exist, which made this file's own
## flag arm order-dependent: red alone, green after an earlier arm had poisoned the cache.
##
## THE GUARD IS THREE TERMS, and each is load-bearing under its own mutation:
##     not _music_cache.has(track)          a cached stream plays whatever the manifest says now
##     and (not has_music_track(track)      membership, incl. the generic world rewrite
##          or not music_is_available(track))  the FILE, which web drops for W4-W6
## It is not a hand-list, because a guard that refuses too much silences a track that would have
## played. Measured: every literal call site (15), every cutscene-authored id (33), the jukebox
## corpus, and all 165 manifest ids -- 0 refused.

const REAL := "battle_medieval"
const UNKNOWN := "no_such_bed_is_authored_anywhere"
const GHOST := "listed_in_the_manifest_but_absent_from_this_build"


func before_each() -> void:
	SoundManager.stop_music()
	## The poisoning this file measures is cross-arm state; clear it so each arm stands alone.
	SoundManager._music_cache.erase(UNKNOWN)


func after_each() -> void:
	SoundManager.stop_music()
	SoundManager._music_cache.erase(UNKNOWN)
	SoundManager._music_manifest.erase(GHOST)
	SoundManager._music_cache.erase(GHOST)


## \u26d4 THE CASE THAT ACTUALLY SHIPS, and has_music_track alone does NOT cover it: on web the
## preset drops the W4-W6 OGGs, so the manifest LISTS an id whose file is absent from the build.
## Membership is true, the load fails, and the function falls through to the same else. This arm
## models that by naming a manifest entry whose file does not exist -- the one form of "listed but
## unplayable" a desktop test can construct. CutsceneDirector guards it at its own call site with
## _cue_is_available; music_is_available is the same predicate, and it keeps the procedural
## battle_/boss arms playable because those make sound without a file.
func test_a_manifest_id_whose_file_is_absent_keeps_the_bed() -> void:
	SoundManager._load_music_manifest()
	SoundManager._music_manifest[GHOST] = {"file": "assets/audio/music/does_not_exist_on_any_build.ogg"}
	assert_true(SoundManager.has_music_track(GHOST), "CONTROL: membership is true, which is the trap")
	assert_false(SoundManager.music_is_available(GHOST), "CONTROL: availability is false")

	SoundManager.play_music(REAL)
	assert_true(SoundManager._music_player.playing, "CONTROL: the bed is playing")
	SoundManager.play_music(GHOST)
	assert_true(SoundManager._music_player.playing,
		"a manifest id with no file in this build took the bed with it — this is the web case, 21 authored cues")


func test_an_unknown_id_does_not_stop_the_bed_it_cannot_replace() -> void:
	assert_true(SoundManager.has_music_track(REAL), "CONTROL: %s must resolve, or this arm has no subject" % REAL)
	assert_false(SoundManager.has_music_track(UNKNOWN), "CONTROL: the unknown id must not resolve")
	SoundManager.play_music(REAL)
	assert_true(SoundManager._music_player.playing, "CONTROL: the bed is playing before the bad call")

	SoundManager.play_music(UNKNOWN)
	assert_true(SoundManager._music_player.playing,
		"an unresolvable id moved the bed to the fading B player and played nothing in its place")


func test_the_flag_does_not_claim_music_that_is_not_playing() -> void:
	SoundManager.play_music(REAL)
	assert_true(SoundManager._music_playing, "CONTROL: the flag is set by the good call")

	SoundManager.play_music(UNKNOWN)
	assert_eq(SoundManager._music_playing, SoundManager._music_player.playing,
		"_music_playing says %s while the player says %s — CutsceneDirector._should_fade_music_for reads this flag" \
			% [SoundManager._music_playing, SoundManager._music_player.playing])


func test_an_unknown_id_does_not_take_the_name_of_the_living_bed() -> void:
	SoundManager.play_music(REAL)
	assert_eq(SoundManager._current_music, REAL, "CONTROL: the bed owns the name")

	SoundManager.play_music(UNKNOWN)
	assert_eq(SoundManager._current_music, REAL,
		"the unresolvable id renamed the state to itself; a later play_music(%s) would early-return as 'already playing'" % REAL)


func test_an_unknown_id_does_not_poison_the_cache_with_the_living_bed() -> void:
	SoundManager.play_music(REAL)
	var real_stream: AudioStream = SoundManager._music_player.stream
	assert_not_null(real_stream, "CONTROL: the bed has a stream to be stolen")

	SoundManager.play_music(UNKNOWN)
	assert_false(SoundManager._music_cache.has(UNKNOWN),
		"the unknown id was cached holding %s — the next call plays a real bed under a name that does not exist" \
			% (real_stream.resource_path if real_stream else "<none>"))


## ⛔ THE DANGEROUS DIRECTION. A guard that refuses too much is a worse bug than the one it fixes.
func test_a_real_manifest_bed_still_plays() -> void:
	SoundManager.play_music(REAL)
	assert_true(SoundManager._music_player.playing, "the guard refused a bed that is in the manifest")


## \u26d4 THIS ARM PICKS "battle" DELIBERATELY AND MY FIRST VERSION PICKED "title", WHICH IS A
## MANIFEST KEY — so it was vacuous for its stated purpose and a manifest-only predicate survived
## the mutation 6/6 green. "battle" and "boss" are the only two generics absent from the manifest:
## play_music rewrites them to battle_<world> / boss_<world> and plays, so a guard that tested
## _music_manifest.has(track) would silence the commonest bed in the game.
func test_a_generic_name_the_manifest_does_not_hold_still_routes() -> void:
	assert_false(SoundManager._music_manifest.has("battle"),
		"CONTROL: if 'battle' ever becomes a manifest key this arm stops testing the rewrite")
	SoundManager.play_music("battle")
	assert_true(SoundManager._music_playing,
		"the guard refused a generic that resolves by world rewrite, not by direct manifest hit")
	assert_true(SoundManager._music_player.playing, "and nothing is actually playing")


## \u26d4 A TWIN, AND NAMED AS ONE: this evaluates the guard's PREDICATE rather than calling
## play_music 165 times. It defends the dangerous direction across every authored id at once --
## if either term ever refuses a bed the manifest actually holds, this reds. It does NOT follow a
## change to the guard's shape, which is what the behavioural arms above are for.
func test_the_predicate_refuses_nothing_the_manifest_authored() -> void:
	SoundManager._load_music_manifest()
	assert_gt(SoundManager._music_manifest.size(), 100,
		"CONTROL: %d ids, so this arm has a corpus" % SoundManager._music_manifest.size())
	var refused: Array = []
	for id in SoundManager._music_manifest.keys():
		if not SoundManager.has_music_track(id) or not SoundManager.music_is_available(id):
			refused.append(id)
	assert_eq(refused.size(), 0,
		"the guard would silence %d authored bed(s): %s" % [refused.size(), str(refused).left(300)])
