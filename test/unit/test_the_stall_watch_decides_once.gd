extends GutTest

## SoundManager._process asks _mixer_stall_watch_active() every frame on every player's machine. It
## used to recompute the answer each time: a DisplayServer name check, a command-line scan and a
## ProjectSettings read. None of those can change after boot. The answer is now decided once and cached,
## and the test overrides (_mixer_stall_watch_force) still win over the cache.

var _saved_force: int
var _saved_runtime: int


func before_each() -> void:
	_saved_force = SoundManager._mixer_stall_watch_force
	_saved_runtime = SoundManager._mixer_stall_watch_runtime


func after_each() -> void:
	SoundManager._mixer_stall_watch_force = _saved_force
	SoundManager._mixer_stall_watch_runtime = _saved_runtime


func test_control_this_suite_is_a_runtime_that_arms() -> void:
	SoundManager._mixer_stall_watch_force = -1
	SoundManager._mixer_stall_watch_runtime = -1
	assert_true(SoundManager._mixer_stall_watch_active(),
		"CONTROL: the suite runs headless on the Dummy driver, so the watch must arm here")
	assert_eq(SoundManager._mixer_stall_watch_runtime, 1, "the first ask must record its answer")


func test_the_cached_answer_is_read_not_recomputed() -> void:
	SoundManager._mixer_stall_watch_force = -1
	SoundManager._mixer_stall_watch_runtime = 0
	assert_false(SoundManager._mixer_stall_watch_active(),
		"the watch recomputed its runtime every call (live answer here is true) instead of reading the cached decision")


func test_the_test_overrides_still_win() -> void:
	SoundManager._mixer_stall_watch_runtime = 0
	SoundManager._mixer_stall_watch_force = 1
	assert_true(SoundManager._mixer_stall_watch_active(), "force=1 must arm whatever the cache says")
	SoundManager._mixer_stall_watch_runtime = 1
	SoundManager._mixer_stall_watch_force = 0
	assert_false(SoundManager._mixer_stall_watch_active(), "force=0 must disarm whatever the cache says")
