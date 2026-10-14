extends GutTest

## chest_open CONTRADICTS ITS OWN PROMPT. The prompt asks for a "satisfying metal latch clicking
## open … physical mechanical feeling"; measured, it is the QUIETEST world-event cue in the game.
##
## ⚠️ THE INSTRUMENT MATTERED MORE THAN THE GAP. Mean rms put it 11.5 dB under its group — and mean
## rms is the wrong measure for a 1.48s cue whose own prompt authors a "brief pause": most of the
## duration is deliberately quiet, which drags the mean down without the player hearing it quieter.
## On the loudest 250ms window it is 7.0 dB under, which is the number this trim is sized from. The
## first figure would have over-corrected by 4.5 dB.
##     loudest-250ms, world-event cues:  median -15.1 across 12
##     chest_open                        -22.2   the quietest, 1.6 under chalk_tap (a chalk tap)
##     the five dungeon cues authored this week all sit AT that median
##
## ⛔ WHY A TRIM AND NOT A RE-RENDER: the asset is approved and its provenance note is true of it.
## +7.0 restores parity without touching it and reverts by deleting one line — the same shape and
## magnitude as `advance_undo` and `status_cannot_act`, both pre-attenuated assets restored to their
## family. Headroom verified rather than assumed: asset peak -1.7 dBFS, base -16 + 7 = -9 on the
## player, so the peak lands at -10.7 dBFS.
##
## ⚠️ WHAT THIS GUARD CANNOT DO, stated rather than implied: it does NOT assert the dB. GUT cannot
## measure audio, and the whoop baseline that could is read by four other guards and pins 82 cues —
## regenerating it for one entry is not a thing to do. So the measurement lives in the trim's own
## comment and this pins the MECHANISM and the DIRECTION: the entry exists, it is positive, and the
## path that plays the cue is the path the table reaches.

const SOUND_MANAGER := "res://src/audio/SoundManager.gd"
const SFX_MANIFEST := "res://data/sfx_manifest.json"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const CUE := "chest_open"


## Read as a CONST through the class: no delimiter searched, so no nested value can be mistaken for
## the table's own brackets.
func _trims() -> Dictionary:
	var s: Variant = load(SOUND_MANAGER)
	if s == null:
		return {}
	return (s.get_script_constant_map().get("_UI_VOLUME_TRIM_DB", {}) as Dictionary)


func _manifest() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SFX_MANIFEST))
	if not (parsed is Dictionary):
		return {}
	return ((parsed as Dictionary).get("sfx", {}) as Dictionary)


func test_the_floor_this_guard_stands_on() -> void:
	## A CONTENT floor, not a size one: naming the table's other documented pre-attenuation case
	## means a read that returned some unrelated dictionary cannot satisfy it.
	var trims: Dictionary = _trims()
	assert_true(trims.has("menu_error"),
		"CONTENT FLOOR: _UI_VOLUME_TRIM_DB must be readable through the class and hold its documented pre-attenuation case. Got %s — a size-only floor would pass on any one row." % [trims.keys()])
	assert_true(_manifest().has(CUE),
		"CONTROL: %s must be in the sfx manifest, or the trim applies to nothing" % CUE)


func test_the_chest_carries_its_restoring_trim() -> void:
	var trims: Dictionary = _trims()
	assert_true(trims.has(CUE),
		"%s lost its trim, so a reward beat is back to being the quietest world-event cue in the game — 7.0 dB under its group median on the loudest-250ms measure" % CUE)
	if not trims.has(CUE):
		return
	assert_gt(float(trims[CUE]), 0.0,
		"%s's trim is %.1f — a NEGATIVE or zero trim is the opposite of the measured defect, which is that the asset is pre-attenuated" % [CUE, float(trims[CUE])])


func test_the_trim_cannot_clip_the_cue_it_raises() -> void:
	## The one thing a positive trim can break, and it is arithmetic rather than audio: the asset's
	## own peak plus the channel level must stay under 0 dBFS. Both numbers are authored constants.
	var src: String = GdSource.code_of(SOUND_MANAGER)
	assert_true(src.contains("SFX_UI_BASE_DB"),
		"CONTROL: the UI base constant is gone, so the headroom below is computed from nothing")
	var m := RegEx.create_from_string("SFX_UI_BASE_DB: float = (-?[0-9.]+)")
	var e := m.search(src)
	assert_not_null(e, "CONTROL: could not read SFX_UI_BASE_DB")
	if e == null:
		return
	var base: float = float(e.get_string(1))
	var trim: float = float(_trims().get(CUE, 0.0))
	## -1.7 dBFS is chest_open.ogg's measured true peak; if the asset is re-rendered hotter this
	## arm is what says so, and the number has to move with it.
	var asset_peak := -1.7
	assert_lt(asset_peak + base + trim, 0.0,
		"base %.1f + trim %.1f puts %s's -1.7 dBFS peak at %.1f dBFS, which clips" % [base, trim, CUE, asset_peak + base + trim])


func test_the_path_that_plays_the_chest_is_the_path_the_table_reaches() -> void:
	## The trim is read in play_ui. If a caller moved the chest to another channel the entry would
	## still be present and would silently stop applying — the inert-data failure one surface over.
	var src: String = GdSource.code_of(SOUND_MANAGER)
	var at: int = src.find("func play_ui")
	assert_gt(at, -1, "CONTROL: play_ui is gone — re-point this arm")
	if at < 0:
		return
	var nxt: int = src.find("\nfunc ", at + 1)
	var body: String = src.substr(at, nxt - at) if nxt > at else src.substr(at)
	assert_true(body.contains("_UI_VOLUME_TRIM_DB") or body.contains("_ui_level"),
		"play_ui no longer reaches _UI_VOLUME_TRIM_DB, so every UI trim is inert data")
	var callers: String = GdSource.code_of("res://src/exploration/TreasureChest.gd")
	assert_true(callers.contains("play_ui(\"chest_open\")"),
		"TreasureChest no longer plays chest_open through play_ui, so the UI trim no longer reaches it")
