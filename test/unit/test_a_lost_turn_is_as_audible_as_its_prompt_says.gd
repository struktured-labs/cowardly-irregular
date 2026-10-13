extends GutTest

## status_cannot_act CONTRADICTED ITS OWN PROMPT. The prompt asks for "present and forceful, not
## distant"; measured mono-summed rms across all 23 status_* cues it was the SECOND QUIETEST at
## -27.2, against a family median of -21.7 and 13.5 dB under the three cues carrying an explicit
## ~-14 LUFS target (doom / curse / silence, all three hitting it).
##
## It marks LOSING A TURN, and the fleet had already judged that cue worth protecting: the call in
## BattleScene._cue_if_turn_skipped sits ABOVE the animator guard deliberately, "losing a turn is
## exactly as audible either way". Reachability was defended; level was not.
##
## ⚠️ WHAT THIS GUARD CANNOT DO, stated rather than implied: it does NOT assert the dB. GUT cannot
## measure audio. The established way is tools/audit_whoop.py measuring into
## test/fixtures/sfx_whoop_baseline.json and a GUT arm reading the fixture -- that baseline pins 82
## cues and only 3 status_* ones, and extending it means regenerating a fixture FOUR other guards
## read, which is not a thing to do for one entry. So the measurement lives in the trim's comment
## and this pins the MECHANISM and the DIRECTION: the entry exists, it is positive, and the path
## that plays the cue is the path the table reaches.

const SOUND_MANAGER := "res://src/audio/SoundManager.gd"
const BATTLE_SCENE := "res://src/battle/BattleScene.gd"
const SFX_MANIFEST := "res://data/sfx_manifest.json"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const CUE := "status_cannot_act"


## Read as a CONST through the class: no delimiter searched, so no type annotation or nested value
## can be mistaken for the table's own brackets.
func _trims() -> Dictionary:
	var s: Variant = load(SOUND_MANAGER)
	if s == null:
		return {}
	return (s.get_script_constant_map().get("_BATTLE_VOLUME_TRIM_DB", {}) as Dictionary)


func _manifest() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SFX_MANIFEST))
	if not (parsed is Dictionary):
		return {}
	return ((parsed as Dictionary).get("sfx", {}) as Dictionary)


func test_the_floor_this_guard_stands_on() -> void:
	var trims: Dictionary = _trims()
	assert_true(trims.has("advance_undo"),
		("CONTENT FLOOR: _BATTLE_VOLUME_TRIM_DB must be readable through the class and hold its "
		+ "documented pre-attenuation case. Got %s. A size-only floor would pass on any one row.") % [trims.keys()])
	assert_true(_manifest().has(CUE),
		"FLOOR: %s is no longer authored in the sfx manifest — a trim for an absent cue is dead weight" % CUE)


func test_the_lost_turn_cue_carries_a_positive_trim() -> void:
	var trims: Dictionary = _trims()
	assert_true(trims.has(CUE),
		("%s has no entry in _BATTLE_VOLUME_TRIM_DB, so it plays at the bare battle base while its "
		+ "own prompt asks for \"present and forceful, not distant\" — measured second quietest of "
		+ "23 status cues.") % CUE)
	if not trims.has(CUE):
		return
	assert_gt(float(trims[CUE]), 0.0,
		"%s's trim is %s — a non-positive trim cannot lift a cue that measures 13.5 dB under its loud siblings" % [CUE, trims[CUE]])


func test_the_trim_actually_reaches_the_path_that_plays_it() -> void:
	## THE MECHANISM. A positive entry is inert unless the function that plays this cue takes its
	## level from the table. BattleScene calls play_status_if_authored, which must use _battle_level.
	var sm: String = GdSource.code_of(SOUND_MANAGER)
	var i: int = sm.find("func play_status_if_authored")
	assert_gt(i, -1, "FLOOR: play_status_if_authored is gone — the caller below would not resolve")
	if i < 0:
		return
	var j: int = sm.find("\nfunc ", i + 30)
	var body: String = sm.substr(i, (j - i) if j > i else 400)
	assert_true(body.contains("_battle_level("),
		("play_status_if_authored does not take its level from _battle_level, so every entry in "
		+ "_BATTLE_VOLUME_TRIM_DB is inert for this path and the trim above does nothing"))
	var bl: int = sm.find("func _battle_level")
	assert_gt(bl, -1, "FLOOR: _battle_level is gone")
	if bl < 0:
		return
	var bj: int = sm.find("\nfunc ", bl + 20)
	assert_true(sm.substr(bl, (bj - bl) if bj > bl else 300).contains("_BATTLE_VOLUME_TRIM_DB"),
		"_battle_level no longer reads _BATTLE_VOLUME_TRIM_DB — the table is disconnected from the level it sets")


func test_the_cue_is_still_reached_when_a_turn_is_lost() -> void:
	## The trim defends a cue nothing would hear if this call were removed. Pins the REACH, not the
	## wording: BattleScene must still ask for this exact key on the turn-skip path.
	var bs: String = GdSource.code_of(BATTLE_SCENE)
	assert_true(bs.contains('play_status_if_authored("%s")' % CUE),
		"BattleScene no longer cues %s — the trim defends a cue nothing plays" % CUE)
	var i: int = bs.find("func _cue_if_turn_skipped")
	assert_gt(i, -1, "FLOOR: _cue_if_turn_skipped is gone")
	if i < 0:
		return
	var j: int = bs.find("\nfunc ", i + 25)
	assert_true(bs.substr(i, (j - i) if j > i else 300).contains(CUE),
		"the turn-skip cue moved out of _cue_if_turn_skipped — check it is still above the animator guard")
