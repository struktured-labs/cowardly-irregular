extends GutTest

## `AudioServer.get_bus_effect(bus, n)` EMITS AN ENGINE ERROR when the bus has fewer than n+1
## effects, and it emits it BEFORE returning null — so an `if amp == null: return` below the call
## is correct logic that arrives one line too late. The error is non-fatal and never fails a test,
## which is why two of these lived in SoundManager unnoticed.
##
## ⛔ MEASURED, and the count is what identified them: the duck-latch guard deliberately strips the
## duck bus, and every full-suite run carried exactly 2 `is out of bounds` errors from
## `servers/audio_server.cpp` — one per unguarded site. Patching both took the run to 0 with the
## guard still 4/4 green. cowir-main reported the pair while gating .466 and flagged them as
## non-regressive; they were mine, and they were a defect rather than noise.
##
## 🔑 ONE OF THREE SITES WAS ALREADY CORRECT. `get_kill_duck_db` carries
## `get_bus_effect_count(idx) <= KILL_DUCK_EFFECT_SLOT`, so the pattern existed in this very file
## and had not travelled to its two siblings — the fix-hides-its-own-siblings shape, which is why
## this guard derives every call site instead of naming the two that were wrong.

const SM_PATH := "res://src/audio/SoundManager.gd"
const READ := "AudioServer.get_bus_effect("
const COUNT := "get_bus_effect_count("
## How far above a read a guard may sit. The three live sites guard on the line before or two above.
const LOOKBACK := 4


func test_no_bus_effect_read_runs_without_a_count_check() -> void:
	var code: String = GdSource.code_of(SM_PATH)
	assert_gt(code.length(), 50000,
		"SCOPE control: %s read back %d chars" % [SM_PATH, code.length()])

	var lines: PackedStringArray = code.split("\n")
	var reads: Array[int] = []
	for i in lines.size():
		var l: String = str(lines[i])
		## ⛔ NO `not l.contains(COUNT)` CLAUSE. `AudioServer.get_bus_effect_count(` does NOT contain
		## `AudioServer.get_bus_effect(` — the `_` breaks it — so READ already discriminates, and the
		## exclusion I wrote first DISCARDED the one site whose guard sits inline on the same line.
		if l.contains(READ):
			reads.append(i)

	## ANTI-VACUITY: an empty set passes by construction, and renaming the accessor is exactly how
	## it would empty. Three sites today.
	## A LOOSE floor: its job is "the accessor still appears", not "there are exactly 3 sites".
	assert_gt(reads.size(), 1,
		"ANTI-VACUITY: found only %d `%s` reads in %s — the accessor was renamed and this guard is about nothing" % [reads.size(), READ, SM_PATH])

	var unguarded: Array[String] = []
	for idx in reads:
		var guarded: bool = false
		for back in range(0, LOOKBACK + 1):
			var j: int = idx - back
			if j < 0:
				break
			if str(lines[j]).contains(COUNT):
				guarded = true
				break
		if not guarded:
			unguarded.append("%s:%d  %s" % [SM_PATH, idx + 1, str(lines[idx]).strip_edges()])
	unguarded.sort()

	assert_eq(unguarded, [],
		"a bus-effect read runs with no `%s` above it, so it emits an engine error on a bus that is empty or short BEFORE returning null — a null check below it cannot prevent the error: %s" % [COUNT, str(unguarded)])
