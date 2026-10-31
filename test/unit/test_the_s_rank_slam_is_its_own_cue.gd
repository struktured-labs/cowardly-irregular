extends GutTest

## An S-rank one-shot earns its own victory slam (struktured 2026-10-29, via cowir-main 19734).
## The rank already rides in the one_shot bonus BattleManager builds, so nothing new is plumbed —
## and this pins the AGREEMENT between producer and consumer rather than the letter "S", because a
## rank rename would otherwise leave the selector comparing against a value nobody emits and the
## S cue would silently never play. Arm 4 is the control: with the asset present, a lesser rank must
## still take the ordinary slam, which is what separates "the rank selects" from "the manifest does".

const OVERLAY := preload("res://src/battle/VictoryOverlay.gd")
const BM_SRC := "res://src/battle/BattleManager.gd"
const S_CUE := "victory_slam_s"
const BASE_CUE := "victory_slam"

var _overlay = null
var _injected := false
var _saved_s: Variant = null

func before_each() -> void:
	_overlay = OVERLAY.new()
	_injected = false
	_saved_s = null

func after_each() -> void:
	## The manifest is autoload state; a leaked key would hand later tests a cue that has no file.
	if _injected and SoundManager and SoundManager._sfx_manifest.has(S_CUE):
		SoundManager._sfx_manifest.erase(S_CUE)
	if _saved_s != null and SoundManager:
		SoundManager._sfx_manifest[S_CUE] = _saved_s
	if _overlay != null:
		_overlay.free()
	_overlay = null

## Saves a REAL entry before anything touches it, so after_each restores it rather than erasing it.
func _save_real_s_cue() -> void:
	if _saved_s == null and SoundManager._sfx_manifest.has(S_CUE):
		_saved_s = SoundManager._sfx_manifest[S_CUE]

func _inject_s_cue() -> void:
	_save_real_s_cue()
	## A real file, so a leak past after_each degrades to a duplicate pointer rather than a key naming
	## nothing; a real entry, once cowir-sfx's row lands, was saved above and after_each restores it.
	SoundManager._sfx_manifest[S_CUE] = {"file": "assets/audio/sfx/victory_slam.ogg"}
	_injected = true

func _bm_source() -> String:
	var f := FileAccess.open(BM_SRC, FileAccess.READ)
	assert_ne(f, null, "cannot open %s" % BM_SRC)
	if f == null:
		return ""
	var txt := f.get_as_text()
	f.close()
	return txt

func test_the_producer_still_ships_a_rank_with_its_one_shot_bonus() -> void:
	var src := _bm_source()
	assert_ne(src, "", "BattleManager source came back empty")
	var line := ""
	for l in src.split("\n"):
		if l.contains("\"type\": \"one_shot\"") and l.contains("bonuses.append"):
			line = l
			break
	assert_ne(line, "", "no bonuses.append carrying type one_shot — the victory bonus payload moved, and the slam selector reads its rank")
	assert_true(line.contains("\"rank\""), "the one_shot bonus no longer carries a rank, so VictoryOverlay._one_shot_rank_of can never see one: %s" % line.strip_edges())

func test_the_consumer_reads_the_rank_out_of_that_payload() -> void:
	assert_eq(_overlay._one_shot_rank_of([{"type": "one_shot", "multiplier": 1.5, "rank": "S"}]), "S", "the rank in a one_shot bonus did not reach the selector")
	assert_eq(_overlay._one_shot_rank_of([]), "", "no bonuses must mean no rank")
	assert_eq(_overlay._one_shot_rank_of([{"type": "autobattle", "multiplier": 1.1}]), "", "a non-one_shot bonus must not yield a rank")

func test_an_s_rank_takes_its_own_cue_only_once_the_asset_exists() -> void:
	## Derived, not spelled: hardcoding "S" here red this arm on a correct lockstep rank rename.
	_overlay._one_shot_rank = str(BattleManager._get_one_shot_rank(1))
	## The absent case is STATED, not read off today's manifest: the real asset may land (cowir-sfx).
	_save_real_s_cue()
	SoundManager._sfx_manifest.erase(S_CUE)
	assert_eq(_overlay._slam_key(), BASE_CUE, "with no %s in the manifest the ordinary slam must still land — a missing asset may not mean silence" % S_CUE)
	_inject_s_cue()
	assert_eq(_overlay._slam_key(), S_CUE, "with %s registered an S-rank one-shot must take it" % S_CUE)

func test_a_lesser_rank_keeps_the_ordinary_slam() -> void:
	_inject_s_cue()
	for rank in ["A", "B", "C", ""]:
		_overlay._one_shot_rank = rank
		assert_eq(_overlay._slam_key(), BASE_CUE, "rank '%s' must not take the S cue even with the asset present" % rank)

func test_the_letter_the_selector_keys_on_is_the_one_the_producer_emits() -> void:
	## Derived, not spelled: a lockstep rank rename reds here instead of selecting nothing forever.
	assert_true(BattleManager.has_method("_get_one_shot_rank"), "BattleManager._get_one_shot_rank is gone; the slam selector compares against a rank nobody produces")
	var best: String = str(BattleManager._get_one_shot_rank(1))
	var lesser: String = str(BattleManager._get_one_shot_rank(4))
	assert_ne(best, lesser, "the fastest and a slow one-shot must not share a rank, or no rank can select a cue")
	_inject_s_cue()
	_overlay._one_shot_rank = best
	assert_eq(_overlay._slam_key(), S_CUE, "the top rank BattleManager emits ('%s') does not select the S cue — the selector's literal and the producer have diverged" % best)
	_overlay._one_shot_rank = lesser
	assert_eq(_overlay._slam_key(), BASE_CUE, "a lesser rank ('%s') must keep the ordinary slam" % lesser)


func test_a_real_s_cue_survives_this_files_teardown() -> void:
	## cowir-sfx: once the real row exists, inject must not overwrite it and teardown must not erase it.
	var had: bool = SoundManager._sfx_manifest.has(S_CUE)
	var orig: Variant = SoundManager._sfx_manifest.get(S_CUE)
	var stand_in := {"file": "assets/audio/sfx/victory_slam.ogg", "_stand_in_for_the_real_row": true}
	SoundManager._sfx_manifest[S_CUE] = stand_in
	_inject_s_cue()
	assert_ne(SoundManager._sfx_manifest.get(S_CUE), stand_in, "CONTROL: inject did not replace the entry, so the restore below is not being tested")
	after_each()
	var back: Variant = SoundManager._sfx_manifest.get(S_CUE)
	if had:
		SoundManager._sfx_manifest[S_CUE] = orig
	else:
		SoundManager._sfx_manifest.erase(S_CUE)
	_overlay = OVERLAY.new()
	_injected = false
	_saved_s = null
	assert_eq(back, stand_in, "teardown left %s as %s — the real row was overwritten or erased, so every later reader loses the cue" % [S_CUE, str(back)])
