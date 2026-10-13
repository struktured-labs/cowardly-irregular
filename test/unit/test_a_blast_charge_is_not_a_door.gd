extends GutTest

## BLOWING A CRACKED WALL OPEN SOUNDED LIKE A WOODEN DOOR CREAKING.
##
## `DungeonMechanics.try_open` serves two lock kinds — `G`/key and `Z`/bomb (RESOURCE_FOR_LOCK) — and
## played `door_open` for both. The function already knows which: its FAILURE toast says "You need a
## key" or "Cracked, but solid. You need a blast charge", and its sprite picks `_door_texture()` or
## `_crack_texture()`. So the text and the art differentiated the two and the audio was the one
## surface that did not. @cowir-music found it and left the cue choice to this lane.
##
## ⛔ AND IT IS ONE OF FOUR. `door_open` is played at FOUR sites in that file, for four different
## physical events — this lock path, a TIMED PRESSURE PLATE (`_on_timed_plate_entered`), a MIRROR
## ROTATING (`toggle_mirror`) and a BLOCK PUSHED ONTO A TARGET (`mark_block_on_target`). Three now
## have their own voice — wall_blast, plate_engage, mirror_turn — authored ONE PER TICK so each was
## separately vetoable by ear rather than landing as a batch. The block is the one still creaking.
## The ledger arm below pins the COUNT so that fixing another one is a deliberate act, not a drift.

const SRC := "res://src/exploration/DungeonMechanics.gd"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")

## ⛔ THE LENGTHS OF ALL FOUR, BECAUSE A TOLERANCE WIDER THAN THE GAP IS NOT A DISCRIMINATOR.
## Each "is it really my file" arm below first read `assert_almost_eq(len, <mine>, 0.06)` — and the
## nearest neighbour is 0.05 away (0.55 plate / 0.60 mirror, 0.95 blast / 1.00 door), so EVERY arm
## admitted a different cue of the same family. The number was right and the window was wider than
## the thing it had to separate. Asking which of the four is NEAREST cannot drift that way: it is
## the relationship, and adding a fifth cue of a similar length tightens it instead of loosening it.
const CUE_SECS := {"door_open": 1.00, "wall_blast": 0.95, "mirror_turn": 0.60, "plate_engage": 0.55}
const NEAR_ENOUGH := 0.08


func test_the_length_oracle_can_actually_separate_the_set() -> void:
	## ⛔ THE PREMISE THE THREE PLAYBACK ARMS REST ON, and the exact thing that was broken before:
	## a window wider than the set's own minimum pairwise gap cannot tell two members apart. The gap
	## is 0.05s today (0.55/0.60 and 0.95/1.00). Nearest-member classification does not CARE about
	## the gap — it is why that form was chosen — but the second, plausibility bound does, and a fifth
	## cue authored at 0.58 would quietly make NEAR_ENOUGH loose enough to admit its neighbour.
	## This arm is what makes adding a cue of a similar length a deliberate act.
	var worst: float = 1e9
	var pair: String = ""
	var keys: Array = CUE_SECS.keys()
	for i in range(keys.size()):
		for j in range(i + 1, keys.size()):
			var gap: float = absf(float(CUE_SECS[keys[i]]) - float(CUE_SECS[keys[j]]))
			if gap < worst:
				worst = gap
				pair = "%s/%s" % [keys[i], keys[j]]
	assert_gt(keys.size(), 3, "VOID: CUE_SECS holds %d members, so the gap below is about almost nothing" % keys.size())
	assert_gt(worst, 0.03,
		"%s are %.3fs apart, which is inside the length jitter a re-encode can produce — the nearest-cue oracle can no longer identify them, so give one of them a distinguishable length or judge that pair some other way" % [pair, worst])
	assert_lt(NEAR_ENOUGH, worst * 2.0,
		"NEAR_ENOUGH is %.2f but the closest pair (%s) is only %.3fs apart: the plausibility bound now reaches past a sibling, which is the defect this file was repaired for" % [NEAR_ENOUGH, pair, worst])


func _nearest_cue(secs: float) -> String:
	var best: String = ""
	var bd: float = 1e9
	for k in CUE_SECS:
		var d: float = absf(secs - float(CUE_SECS[k]))
		if d < bd:
			bd = d
			best = str(k)
	return best


func _assert_stream_is(key: String) -> void:
	## Plays the cue and judges the stream LENGTH, which is what separates the authored file from the
	## procedural fallback and from its three siblings. Registration is not playback: a key whose file
	## will not load falls through to the procedural path with every manifest assertion still green.
	##
	## ⚠️ A HELPER ABSORBS AN ABORT, so a renamed `SoundManager` member kills this frame and lets the
	## caller score whatever it already asserted. TWO of the three callers (plate, mirror) reach here
	## with NOTHING asserted yet, so they go Risky and `run_tests.sh` exits 4 — loud. The blast caller
	## has three manifest asserts above and would pass silently on its own. Do not hoist a precondition
	## above the plate or mirror call: that is the whole cover, and it is a property of their emptiness.
	SoundManager._sfx_cooldowns.erase(key)
	SoundManager.play_ui(key)
	assert_true(SoundManager._sfx_cooldowns.has(key),
		"play_ui(\"%s\") did not reach the manifest entry, so it fell through to the procedural path" % key)
	var p: AudioStreamPlayer = SoundManager._ui_player
	assert_not_null(p, "CONTROL: the UI player must exist")
	if p == null or p.stream == null:
		assert_true(false, "%s stamped its cooldown but left no stream on the UI player" % key)
		return
	var secs: float = p.stream.get_length()
	assert_eq(_nearest_cue(secs), key,
		"the stream on the UI player is %.2fs, which is nearest %s, not %s — a sibling cue's file answers to this key (%s)" % [secs, _nearest_cue(secs), key, CUE_SECS])
	assert_lt(absf(secs - float(CUE_SECS[key])), NEAR_ENOUGH,
		"the stream is %.2fs where %s is %.2fs: nearest of the four, but far enough off that it is some other file entirely" % [secs, key, float(CUE_SECS[key])])
	SoundManager._sfx_cooldowns.erase(key)


func test_the_two_lock_kinds_do_not_share_a_cue() -> void:
	var code: String = GdSource.code_of(SRC)
	assert_ne(code, "", "CONTROL: DungeonMechanics code must survive the comment strip")
	var at: int = code.find("func try_open")
	assert_gt(at, -1, "CONTROL: try_open is gone — re-point this guard rather than deleting it")
	if at < 0:
		return
	var nxt: int = code.find("\nfunc ", at + 1)
	var body: String = code.substr(at, nxt - at) if nxt > at else code.substr(at)
	assert_true(body.contains("wall_blast"),
		"try_open no longer plays wall_blast, so a blast charge sounds like a wooden door again")
	assert_true(body.contains("resource == \"key\""),
		"try_open plays a cue without branching on the lock kind — the two kinds would share it")


func test_the_blast_cue_is_authored_and_plays() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sfx_manifest.json"))
	assert_true(parsed is Dictionary, "VOID: manifest did not parse")
	var sfx: Dictionary = (parsed as Dictionary).get("sfx", {}) if parsed is Dictionary else {}
	assert_true(sfx.has("wall_blast"), "wall_blast is no longer authored")
	_assert_stream_is("wall_blast")


func test_the_last_door_open_site_is_still_counted() -> void:
	## A LEDGER over what is left, pinned by COUNT so the next cue arriving is deliberate. One site
	## remains: a BLOCK PUSHED ONTO A TARGET, a stone slab seating into a socket, which a wooden door
	## on hinges is the wrong sound for. If it gains its own cue this reds and the number must come
	## down in the same commit; if a NEW mechanic reaches for door_open it reds too, which is the point.
	##
	## ⚠️ IT COUNTS THE LITERAL `play_ui("door_open")`, WHICH EXCLUDES THE KEY PATH ON PURPOSE. `try_open`
	## spells its choice as a ternary — `play_ui("door_open" if resource == "key" else "wall_blast")` —
	## so the file mentions door_open twice and this says 1. That is correct: a locked DOOR opening with
	## a key is the one site where a wooden door is the right sound. If someone splits that ternary into
	## an if/else, this reds on a legitimate refactor — bring the number up and say why, rather than
	## widening the pattern, because a pattern loose enough to match the ternary also matches the
	## comment above it.
	var code: String = GdSource.code_of(SRC)
	## gd_source.gd's own contract: a caller must assert a known CODE site survives, because
	## over-stripping and a correct strip produce the same green — and here they would produce the
	## same clean LEDGER. Without this, a stripper that ate the file reports 0 door_open sites and
	## reds with "not the 1 declared", which names the wrong cause.
	assert_true(code.contains("func toggle_mirror"),
		"CONTROL: the comment strip ate the code half, so this count is about nothing")
	var n: int = code.count("play_ui(\"door_open\")")
	assert_eq(n, 1,
		"DungeonMechanics plays door_open at %d sites, not the 1 declared. The last one is a BLOCK LANDING ON ITS TARGET, which a heavy wooden door is the wrong sound for; if you fixed it, bring this number to 0, and if you added a site it needs its own cue." % n)


## SECOND OF THE FOUR, authored on @cowir-main's "one per tick" instruction: a stone pressure plate
## underfoot played `door_open`, a heavy wooden door creaking. `_on_timed_plate_entered` fires every
## time a player steps on a timed plate, which makes it the most repeated of the four.
func test_the_timed_plate_has_its_own_voice() -> void:
	var code: String = GdSource.code_of(SRC)
	var at: int = code.find("func _on_timed_plate_entered")
	assert_gt(at, -1, "CONTROL: _on_timed_plate_entered is gone — re-point this arm")
	if at < 0:
		return
	var nxt: int = code.find("\nfunc ", at + 1)
	var body: String = code.substr(at, nxt - at) if nxt > at else code.substr(at)
	assert_true(body.contains("plate_engage"),
		"the timed plate no longer plays plate_engage, so stepping on stone sounds like a wooden door again")
	assert_false(body.contains("door_open"),
		"the timed plate plays door_open again")


func test_the_plate_cue_is_authored_and_plays() -> void:
	_assert_stream_is("plate_engage")


## THIRD OF THE FOUR, and the last before the block. `toggle_mirror` pivots a mounted mirror to its next facing and played
## `door_open`, a wooden door on iron hinges, for glass and metal on a pivot.
##
## ⛔ THE CUE IS NON-MELODIC ON PURPOSE, and that is the constraint that shaped it: all SIX existing
## chime cues are PITCHED FIGURES (save_crystal_activate's arpeggio, clock_chime's bell pair,
## soft_chime, respawn_chime, surprised_chime, secret_found's run). An in-tune mirror would have
## twinned one of them — and `save_crystal_activate` in particular, which would make a puzzle sound
## like a save point. The detuned 2120/2390Hz pair is what keeps it a mechanism rather than music.
func test_the_mirror_has_its_own_voice() -> void:
	var code: String = GdSource.code_of(SRC)
	var at: int = code.find("func toggle_mirror")
	assert_gt(at, -1, "CONTROL: toggle_mirror is gone — re-point this arm")
	if at < 0:
		return
	var nxt: int = code.find("\nfunc ", at + 1)
	var body: String = code.substr(at, nxt - at) if nxt > at else code.substr(at)
	assert_true(body.contains("mirror_turn"),
		"toggle_mirror no longer plays mirror_turn, so a glass mechanism sounds like a wooden door again")
	assert_false(body.contains("door_open"),
		"toggle_mirror plays door_open again")


func test_the_mirror_cue_is_authored_and_plays() -> void:
	_assert_stream_is("mirror_turn")
