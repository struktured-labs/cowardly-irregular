extends GutTest

const SoundState := preload("res://test/unit/helpers/sound_state.gd")

## ⛔ `duck_music_for_dialogue` COMMITS ITS STATE BEFORE IT KNOWS THE BUS CAN CARRY IT. The holder is
## appended and `_duck_active` is set, and only THEN does it resolve the Amplify — with an
## `if amp == null: return` that leaves the latch claiming a duck nobody applied.
##
## 🔑 THE CONSEQUENCE IS NOT A MISSING DUCK, IT IS A SILENT ONE THEREAFTER. The function is
## deliberately idempotent (`if want == _duck_active: return`), so once the latch lies, the NEXT real
## `duck_music_for_dialogue(true)` is a no-op and that conversation plays at full volume with the
## system reporting it as ducked.
##
## ⚠️ LATENT, AND BILLED AS LATENT: `_ensure_music_duck_bus` always builds both slots, so nothing
## reaches the null branch today. It is here because the SIBLING ALREADY HAS THE CORRECT SHAPE —
## `duck_music_for_kill` resolves `idx` and `amp` and returns before touching anything — and because
## the bus's own comment records worrying about exactly this: "creating it lazily made the bus's SHAPE
## depend on whether a kill had happened yet".
##
## @cowir-autogrind's `.422` shape, in audio: a mutation performed before the thing that authorises it.

var _saved: Array = []


func before_each() -> void:
	SoundState.restore()
	SoundManager.duck_music_for_dialogue(false)


## ⛔ REMOVES THE EFFECTS, NOT THE BUS. Deleting and re-adding the bus would change its index and its
## name-based routing (`MusicNight` sends into it), so the teardown could leave the chain altered for
## every later file. Stripping the effects reproduces `amp == null` with the bus identity untouched.
## ⛔ UNDER `AudioServer.lock()`. Removing every effect from a LIVE bus mutates the graph the audio
## thread is reading, and this file wedged 2 of 3 full-suite runs (.461, .463) with main blocked and a
## non-main thread at 100% — never in isolation, 8/8. Mechanism UNCONFIRMED (no per-thread backtrace),
## but lock/unlock is the documented way to touch audio state from main and costs nothing if it is not
## the cause. A scratch bus cannot substitute: the subject resolves MUSIC_DUCK_BUS by name.
func _strip_effects() -> int:
	var idx: int = AudioServer.get_bus_index(SoundManager.MUSIC_DUCK_BUS)
	if idx == -1:
		return -1
	_saved.clear()
	AudioServer.lock()
	while AudioServer.get_bus_effect_count(idx) > 0:
		_saved.append(AudioServer.get_bus_effect(idx, 0))
		AudioServer.remove_bus_effect(idx, 0)
	AudioServer.unlock()
	return idx


func _restore_effects() -> void:
	var idx: int = AudioServer.get_bus_index(SoundManager.MUSIC_DUCK_BUS)
	if idx == -1 or _saved.is_empty():
		return
	AudioServer.lock()
	for e in _saved:
		AudioServer.add_bus_effect(idx, e)
		AudioServer.set_bus_effect_enabled(idx, AudioServer.get_bus_effect_count(idx) - 1, true)
	AudioServer.unlock()
	_saved.clear()


func after_each() -> void:
	_restore_effects()
	SoundManager.duck_music_for_dialogue(false)
	SoundState.restore()


func test_control_the_bus_normally_carries_the_duck() -> void:
	## Without this the arm below could pass because ducking never works at all.
	var holder := Node.new()
	add_child_autofree(holder)
	SoundManager.duck_music_for_dialogue(true, holder)
	assert_true(bool(SoundManager.is_music_ducked_for_dialogue()),
		"CONTROL: an intact duck bus must latch, or the arm below is about a feature that does not run")
	assert_eq(SoundManager._duck_holders.size(), 1, "CONTROL: and record the holder")


func test_the_duck_latch_waits_for_the_bus() -> void:
	var idx: int = _strip_effects()
	assert_gt(idx, -1, "CONTROL: the duck bus must exist to be stripped")
	assert_eq(AudioServer.get_bus_effect_count(idx), 0,
		"CONTROL: the bus must carry no effects, or this arm never reaches the null branch")

	var holder := Node.new()
	add_child_autofree(holder)
	SoundManager.duck_music_for_dialogue(true, holder)

	assert_false(bool(SoundManager.is_music_ducked_for_dialogue()),
		"the latch says ducked with no Amplify to duck — and because this function is idempotent, the next real duck request is then a no-op and that conversation plays at full volume")
	assert_eq(SoundManager._duck_holders.size(), 0,
		"a holder was recorded for a duck that never applied (%d) — it keeps the set non-empty, so nobody else's release can lift the duck either" % SoundManager._duck_holders.size())


func test_the_bus_still_carries_a_duck_after_the_failure() -> void:
	## ⛔ THE POINT OF THE REPAIR, not just the absence of a lie: once the bus is back, a duck must
	## still arrive. An early return that ALSO poisoned the latch would pass the arm above and fail here.
	var idx: int = _strip_effects()
	assert_gt(idx, -1, "CONTROL: stripped")
	var holder := Node.new()
	add_child_autofree(holder)
	SoundManager.duck_music_for_dialogue(true, holder)
	_restore_effects()

	SoundManager.duck_music_for_dialogue(true, holder)
	assert_true(bool(SoundManager.is_music_ducked_for_dialogue()),
		"after the bus came back, a duck request must take effect — a poisoned latch makes it a no-op forever")
