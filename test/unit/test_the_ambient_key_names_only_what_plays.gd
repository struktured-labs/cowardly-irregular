extends GutTest

## `_current_ambient_key` is the record of what the ambient layer is playing. It was set at the
## TOP of `play_ambient`, above four returns — so four different failures left it naming a bed
## that is not playing, and one of them is a key that does not exist at all.
##
## ⛔ I FIXED THE FOURTH AND LEFT THE OTHER THREE. On 2026-09-17 the music-collision return got a
## clear-on-exit; the key-absent, empty-`file` and load-failed returns kept the leak. That is the
## third time in one day that "was the first instance the only one" found more — after
## play_area_music found play_music — and twice it was a fix of mine that covered its own siblings.
##
## The repair is not a fourth clear-on-exit: the key is now assigned once, AFTER `play()`, so it
## is set where it becomes true and no future return above it can leak.
##
## 🔑 WHY IT MATTERS RATHER THAN BEING TIDY: the top of play_ambient reads
## `if sound_key == _current_ambient_key and _ambient_player.playing: return`. The `playing` term
## is what keeps a lying key from wedging the layer — so the leak was covered by a second
## condition rather than being harmless, and anything that reads the field alone gets a lie.

const REAL := "ambient_cave"


func after_each() -> void:
	SoundManager.stop_ambient()
	SoundManager.stop_music()


func test_a_key_in_neither_manifest_leaves_no_name_behind() -> void:
	SoundManager.play_ambient("zzq_absent_from_both_stores")
	assert_false(SoundManager._ambient_player.playing, "CONTROL: nothing is playing after an unknown key")
	assert_eq(SoundManager._current_ambient_key, "",
		"the field names %s while the ambient layer is silent" % SoundManager._current_ambient_key)


func test_a_failed_start_leaves_no_name_behind() -> void:
	## Drives the same leak through the MUSIC-collision return, which is the one that already had
	## a clear-on-exit — kept so the retirement of that patch is covered rather than assumed.
	SoundManager.play_music(REAL, true)
	await get_tree().create_timer(0.2).timeout
	SoundManager.play_ambient(REAL)
	assert_false(SoundManager._ambient_player.playing, "CONTROL: the ambient layer yielded to the music player")
	assert_eq(SoundManager._current_ambient_key, "",
		"the field names %s after the ambient layer declined to start" % SoundManager._current_ambient_key)


func test_a_real_start_does_name_itself() -> void:
	## The other direction, so the fix cannot be "always clear it".
	SoundManager.play_ambient(REAL)
	assert_true(SoundManager._ambient_player.playing, "CONTROL: the bed actually started")
	assert_eq(SoundManager._current_ambient_key, REAL,
		"a bed that IS playing must be named, or the early-return guard at the top of play_ambient stops working")


func test_the_idempotent_return_still_works() -> void:
	## The top return needs the field to be accurate; with the assignment moved, prove the second
	## call is still recognised as a repeat rather than restarting the bed.
	## ⛔ STREAM IDENTITY CANNOT ANSWER THIS, and my first version used it. Godot's `load()`
	## returns the CACHED resource, so `assert_same(stream, stream_before)` holds whether the bed
	## returned early or was stopped and restarted from the same file. Measured: delete the early
	## return entirely and all four arms stayed GREEN — an arm that could not fail for the reason
	## it states (@cowir-sfx's shape, same hour, one lane over).
	##
	## PLAYBACK POSITION is the discriminator: a restart runs stop_ambient() and play(), which
	## resets it to zero. Position only ever advances on the early-return path.
	SoundManager.play_ambient(REAL)
	await get_tree().create_timer(0.4).timeout
	assert_true(SoundManager._ambient_player.playing, "CONTROL: playing before the repeat")
	var pos_before: float = SoundManager._ambient_player.get_playback_position()
	assert_gt(pos_before, 0.1,
		"CONTROL: the bed had advanced to %.2f s — without real playback a reset is indistinguishable from no reset" % pos_before)

	SoundManager.play_ambient(REAL)
	assert_gte(SoundManager._ambient_player.get_playback_position(), pos_before - 0.01,
		"the repeat RESTARTED the bed (position fell from %.2f to %.2f) instead of returning early — the moved assignment broke the idempotence guard" % [pos_before, SoundManager._ambient_player.get_playback_position()])
