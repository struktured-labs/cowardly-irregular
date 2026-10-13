extends GutTest

## test_advance_ladders_keep_their_shape_regression pins each ladder's ASSET rms from a sha256-
## verified fixture, and its header says "Nothing else in the repo records that intent as an
## enforceable property." What a player hears is asset + MIX, and the mix is a second layer:
## SoundManager._BATTLE_VOLUME_TRIM_DB adds a per-cue dB offset at playback.
##
## ⛔ 2026-10-12: a branch adding `advance_rogue_4: +6.0` / `advance_rogue_5: +4.0` was QUEUED for a
## fold. It flattens the rogue's authored inversion IN PLAY, the .ogg bytes never change, every
## sha256 still matches, and the load-bearing asset guard stays GREEN. Only a hand-read of five
## manifest prompts stopped it. Measured census at the time: 5 test files read the rms baseline,
## 7 read the trim table, ZERO composed the two.
##
## cowir-sfx measured that the advance rungs do route through _battle_player, so the trim is the
## table that reaches them -- the composition below is the level the player actually gets.

const BASELINE := "res://test/fixtures/sfx_whoop_baseline.json"
const SOUND_MANAGER := "res://src/audio/SoundManager.gd"
## Rungs 3..5, matching the asset guard: advance_mage_2 is deliberately unpinned, so a level for it
## would assert a number nothing measures.
const ASCENDING := ["fighter", "cleric", "mage", "bard"]


func _baseline() -> Dictionary:
	var raw := FileAccess.get_file_as_string(BASELINE)
	var parsed: Variant = JSON.parse_string(raw)
	return ((parsed as Dictionary).get("cues", {}) as Dictionary) if parsed is Dictionary else {}


## Read as a CONST through the class: no delimiter is searched, so no type annotation or nested
## value can be mistaken for the table's own brackets.
func _trims() -> Dictionary:
	var s: Variant = load(SOUND_MANAGER)
	if s == null:
		return {}
	return (s.get_script_constant_map().get("_BATTLE_VOLUME_TRIM_DB", {}) as Dictionary)


func _effective(job: String) -> Array:
	var cues := _baseline()
	var trims := _trims()
	var out: Array = []
	for n in range(3, 6):
		var k := "advance_%s_%d" % [job, n]
		if not cues.has(k):
			return []
		var asset := float((cues[k] as Dictionary).get("rms_db", 0.0))
		out.append(asset + float(trims.get(k, 0.0)))
	return out


func test_both_layers_are_actually_readable() -> void:
	## FLOOR. Without this, a rename on either side yields {} and every shape arm below reads 0.0
	## and passes trivially -- the exact vacuity the asset guard's own premise arm defends against.
	var cues := _baseline()
	assert_gt(cues.size(), 15, "the rms baseline did not load (%d cues) — run tools/audit_whoop.py --write" % cues.size())
	var trims := _trims()
	assert_true(trims.has("advance_undo"),
		("CONTENT FLOOR: _BATTLE_VOLUME_TRIM_DB must be readable through the class and must contain "
		+ "advance_undo (+6.0, its documented pre-attenuation case). Got keys %s. A size-only floor "
		+ "would pass on any one surviving row.") % [trims.keys()])
	for job in ASCENDING + ["rogue"]:
		assert_eq(_effective(job).size(), 3, "%s rungs 3-5 are not pinned — the composition cannot be formed" % job)


func test_a_trim_does_not_flatten_an_ascending_ladder() -> void:
	for job in ASCENDING:
		var e := _effective(job)
		if e.size() < 3:
			continue
		assert_gt(e[1], e[0],
			"%s press 4 is %.1f dB EFFECTIVE (asset+trim) and press 3 is %.1f — a trim has inverted an ascending ladder" % [job, e[1], e[0]])
		assert_gt(e[2], e[1],
			"%s press 5 is %.1f dB EFFECTIVE and press 4 is %.1f — a trim has inverted an ascending ladder" % [job, e[2], e[1]])


func test_a_trim_does_not_flatten_the_rogue_INVERSION() -> void:
	## THE ONE THE NEAR-MISS WOULD HAVE HIT. All five rogue prompts name the inversion and rungs
	## 4-5 carry hand-set RMS targets ("MASTERED: gain to -26.5 / -31.0 dBFS rms").
	var e := _effective("rogue")
	assert_eq(e.size(), 3, "control: rogue rungs 3-5 incomplete")
	if e.size() < 3:
		return
	assert_lt(e[1], e[0],
		"rogue press 4 is %.1f dB EFFECTIVE (asset+trim) and press 3 is %.1f — a trim has undone the authored inversion; see the five advance_rogue_* prompts" % [e[1], e[0]])
	assert_lt(e[2], e[1],
		"rogue press 5 is %.1f dB EFFECTIVE and press 4 is %.1f — a trim has undone the authored inversion" % [e[2], e[1]])


func test_no_advance_rung_carries_a_trim_today() -> void:
	## ⚠️ NAMED FOR WHAT IT ESTABLISHES. An earlier name claimed this proved the composition was
	## wired; it does NOT, and the mutation says so: dropping the `+ trims.get(k)` term from
	## _effective() leaves this file GREEN, because with no trim on any advance rung
	## `asset + 0.0 == asset`. The wiring is proven only by planting a trim and watching the SHAPE
	## arms red -- measured, `advance_rogue_4: +6.0` reds the inversion arm.
	##
	## What this arm really is: a TRIPWIRE. A trim on an advance rung is a level decision about a
	## ladder whose shape is authored in its prompts, so it must be re-justified rather than added.
	var cues := _baseline()
	var trims := _trims()
	var trimmed_rungs: Array = []
	for job in ASCENDING + ["rogue"]:
		for n in range(3, 6):
			var k := "advance_%s_%d" % [job, n]
			if trims.has(k):
				trimmed_rungs.append(k)
			var asset := float((cues.get(k, {}) as Dictionary).get("rms_db", 0.0))
			assert_almost_eq(_effective(job)[n - 3], asset + float(trims.get(k, 0.0)), 0.001,
				"%s: the composition does not equal asset+trim" % k)
	assert_eq(trimmed_rungs.size(), 0,
		("no advance rung carries a trim today, so any entry here is a LEVEL DECISION that must be "
		+ "re-justified against that ladder's prompts: %s") % [trimmed_rungs])
