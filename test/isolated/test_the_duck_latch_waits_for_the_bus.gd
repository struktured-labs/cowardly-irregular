extends GutTest

## ⛔ QUARANTINED FROM test/unit BY cowir-main 2026-09-19 — THIS FILE WEDGES THE FULL SUITE.
## NOT a judgement on the guard, which is correct and defends a real defect. It is quarantined
## because it hangs the FLEET'S GATE, and a hang is worse than a red: it is not a verdict at all.
##
## Measured, twice, identically:
##   .461 gate  wedged here, 1h57m before a human noticed  (nothing bounded the run then)
##   .462 gate  PASSED — 13,018 tests green, this file included
##   .463 gate  wedged here again, killed at 726s by the new bound
## => ~2 of 3 full-suite runs. In ISOLATION it is clean: 8/8 consecutive single-file runs.
##
## The signature is identical both times and rules out this file's own GDScript:
##   one NON-MAIN thread at 100% CPU, main thread BLOCKED (S), log frozen, 31 threads.
## GUT runs tests on main, and the fleet authors no threads at all (`Thread.new` /
## `WorkerThreadPool` = 0 files; `HTTPRequest.use_threads` false; no threaded ResourceLoader).
## So the spinner is engine-internal — consistent with main blocked on the AudioServer lock while
## the audio thread spins, which is what `_strip_effects()` below provokes by removing every
## effect from a LIVE bus mid-run. @cowir-music flagged runtime bus-graph mutation independently.
## UNCONFIRMED: a per-thread backtrace needs ptrace privileges not taken during a live capture.
##
## TO BRING IT BACK: make the arms not mutate a live AudioServer bus graph — a scratch bus, or
## AudioServer.lock()/unlock() around the strip — then move the file back to test/unit. Do NOT
## simply move it back; two of three gates is not flake, it is a blocker with a 67% rate.
## Owner: @cowir-music. Quarantine is reversible and nothing here was weakened.

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
func _strip_effects() -> int:
	var idx: int = AudioServer.get_bus_index(SoundManager.MUSIC_DUCK_BUS)
	if idx == -1:
		return -1
	_saved.clear()
	while AudioServer.get_bus_effect_count(idx) > 0:
		_saved.append(AudioServer.get_bus_effect(idx, 0))
		AudioServer.remove_bus_effect(idx, 0)
	return idx


func _restore_effects() -> void:
	var idx: int = AudioServer.get_bus_index(SoundManager.MUSIC_DUCK_BUS)
	if idx == -1 or _saved.is_empty():
		return
	for e in _saved:
		AudioServer.add_bus_effect(idx, e)
		AudioServer.set_bus_effect_enabled(idx, AudioServer.get_bus_effect_count(idx) - 1, true)
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
