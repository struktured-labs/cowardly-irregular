extends GutTest

## The Rogue's Advance ladder ran BACKWARDS. `rung := clampi(depth, 1, 5)` (Win98Menu:651) makes the
## rung the Advance DEPTH and BattleScene calls them "five escalating cues", so 4 and 5 are the big
## moments — the ones struktured asked for ("we need a new sound for 4th time you advance",
## 2026-09-09). Measured peak over all 37 `advance_*` cues: median -1.8 dB, band -0.2..-6.1, and
## the two QUIETEST of the 37 were `advance_rogue_4` (-11.2) and `advance_rogue_5` (-8.0). The
## Rogue's climax was its faintest cue — rung 1 peaks -1.5, rung 5 peaks -8.0.
##
## Fixed by trim, following `advance_undo: 6.0`'s precedent for a pre-attenuated asset, rather than
## re-rendering art that is otherwise fine.
##
## ⚠️ WHAT THIS FILE CAN AND CANNOT CHECK. GDScript has no meter, so the LEVELS are measured by hand
## (above, and reproducible with ffmpeg `volumedetect`). What is checkable, and what a wrong edit
## would actually break, is that a trim REACHES its cue: a trim naming a key nothing plays is inert,
## and the table has no other guard on it.

const SM := "res://src/audio/SoundManager.gd"
const MANIFEST := "res://data/sfx_manifest.json"


func _src() -> String:
	var s := FileAccess.get_file_as_string(SM)
	assert_gt(s.length(), 0, "VOID: SoundManager.gd read empty")
	return s


## {key: trim} for one of the two tables, read from source — the tables are consts the test cannot
## reach through the autoload without instancing it, and their CONTENT is the subject here.
func _trims(const_name: String) -> Dictionary:
	var src := _src()
	var at: int = src.find("const %s: Dictionary = {" % const_name)
	assert_gt(at, -1, "VOID: %s is gone, so this arm has no subject" % const_name)
	if at < 0:
		return {}
	## Bounded at the declaration's own closing brace at column 0 — not the first `}` (a comment or
	## a nested value could carry one), and the open anchored on `= {` so a bracketed TYPE cannot
	## capture it. Both halves of the anchor hazard four lanes measured on 2026-10-12.
	var end: int = src.find("\n}", at)
	assert_gt(end, at, "VOID: %s has no closing brace at column 0" % const_name)
	var body: String = src.substr(at, end - at)
	var out := {}
	var re := RegEx.create_from_string("\"([a-z_0-9]+)\"\\s*:\\s*(-?[0-9.]+)")
	for m in re.search_all(body):
		out[m.get_string(1)] = float(m.get_string(2))
	return out


func _manifest_keys() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert_true(parsed is Dictionary, "VOID: manifest did not parse")
	return (parsed as Dictionary).get("sfx", {}) if parsed is Dictionary else {}


func test_no_trim_names_a_cue_that_does_not_exist() -> void:
	## A trim keyed to a cue nothing plays is inert, and nothing else would say so. It reads as a
	## level decision that has been made.
	var sfx := _manifest_keys()
	var src := _src()
	var dead: Array[String] = []
	var checked := 0
	for table in ["_UI_VOLUME_TRIM_DB", "_BATTLE_VOLUME_TRIM_DB"]:
		for key in _trims(table):
			checked += 1
			## Either an authored cue or a procedural SOUNDS entry — both are real play targets.
			if not sfx.has(key) and not src.contains("\t\"%s\": {" % key):
				dead.append("%s in %s" % [key, table])
	assert_gt(checked, 5, "VOID: only %d trims derived from the two tables — the extraction has broken" % checked)
	assert_eq(dead, [],
		"these trims name a cue that is neither authored nor procedural, so the level they describe is never applied: %s" % dead)


func test_the_rogue_ladders_top_rungs_are_lifted() -> void:
	## The fix itself, pinned by VALUE: a trim that drifts to 0 silently restores the defect, and the
	## only other evidence is a measurement nobody re-runs.
	var battle := _trims("_BATTLE_VOLUME_TRIM_DB")
	for key in ["advance_rogue_4", "advance_rogue_5"]:
		assert_true(battle.has(key),
			"%s has no trim — it peaks 6-9 dB under the advance ladder's median, so the Rogue's biggest Advance is its quietest cue" % key)
		assert_gt(float(battle.get(key, 0.0)), 0.0,
			"%s's trim is not POSITIVE; these are pre-attenuated assets and a cut makes the backwards ladder worse" % key)
	## And not over-lifted past the band they were brought into — +6.0/+4.0 land at -5.2/-4.0 against
	## a ladder band of -0.2..-6.1. A much larger trim would make the Rogue the loudest instead.
	for key in ["advance_rogue_4", "advance_rogue_5"]:
		assert_lt(float(battle.get(key, 0.0)), 9.0,
			"%s's trim would push it past the top of the ladder's own band; the fix was parity, not dominance" % key)


func test_the_trim_actually_reaches_the_battle_channel() -> void:
	## ⛔ THE TRIM TABLE IS ONLY WORTH ANYTHING IF THE PLAY PATH CONSULTS IT. `_battle_level` is the
	## single owner and `play_battle` passes it on EVERY call — which is also what makes a POSITIVE
	## trim safe here, since volume_db persists on the shared player and a following cue sets its own
	## level. Until this change every trim reaching this player was NEGATIVE, so the loud direction
	## was (in the function's own words) "guarded, not observed".
	var src := _src()
	assert_true(src.contains("return SFX_BATTLE_BASE_DB + float(_BATTLE_VOLUME_TRIM_DB.get(sound_key, 0.0))"),
		"_battle_level no longer folds the trim table into the channel base, so every battle trim is inert")
	assert_true(src.contains("var level: float = _battle_level(sound_key)"),
		"play_battle no longer computes an explicit level per call — a trimmed cue would then leak its level onto the next battle sound")


func test_the_advance_ladder_keys_exist_for_every_rung_that_is_trimmed() -> void:
	## A trim on rung 4 is pointless if rung 4 was never authored: Win98Menu WALKS DOWN from the
	## pressed depth to the highest rung the job actually has, so a missing rung silently plays a
	## lower one and the trim never fires.
	var sfx := _manifest_keys()
	for key in ["advance_rogue_1", "advance_rogue_3", "advance_rogue_4", "advance_rogue_5"]:
		assert_true(sfx.has(key),
			"%s is not authored, so Win98Menu's walk-down reaches a lower rung and any trim on it is unreachable" % key)
