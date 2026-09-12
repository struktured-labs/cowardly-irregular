extends GutTest

## `stinger_level_up` is shipped, loopless, correctly declared — and a player has never heard it.
##
## VictoryOverlay._level_up_flare prefers an SFX flourish and falls back to the music stinger:
##
##     if SoundManager._sfx_manifest.has("levelup_flourish"):
##         SoundManager.play_battle("levelup_flourish")
##     else:
##         SoundManager.play_music("stinger_level_up")
##
## `levelup_flourish` is in sfx_manifest.json, so the else has never run. The bed is ROUTED and
## not REACHED, and the distinction is invisible to every instrument in this lane: the
## reachability sweep finds the literal in src/ and marks it consumed. One `git grep` says the
## stinger is wired; the data says the branch holding it cannot execute.
##
## 🔑 MEASURED BY CALLING THE REAL FUNCTION, not by reading the branch. A source arm here would
## assert the shape of the very code whose reachability is the question, and this lane spent
## today learning what a presence assert is worth (a docstring naming an expression kept 119
## composed ids excused, 2026-09-12). So: call `_level_up_flare`, ask what is playing — then
## erase the SFX key from the LOADED manifest and call it again. Same call, opposite verdict.
## That second half is the control: without it "nothing played" could equally mean the probe
## cannot see a bed start at all.
##
## ⛔ THIS FILE DECIDES NOTHING ABOUT THE BED. Delete it (37 KB, one Jukebox row) or rewire it
## (a 3.2 s music stinger over the battle bed, where the 24 KB SFX flourish sits today) is
## @struktured's open call and has been since 2026-09-11. What was missing from that call is the
## mechanism, which is what this pins: it fails the day the gate changes in either direction, so
## whoever removes `levelup_flourish` learns they just turned the stinger on.

const OVERLAY := preload("res://src/battle/VictoryOverlay.gd")
const BED := "stinger_level_up"
const GATE := "levelup_flourish"

var _saved_gate: Variant = null


func before_each() -> void:
	SoundManager._load_sfx_manifest() if SoundManager.has_method("_load_sfx_manifest") else null
	_saved_gate = SoundManager._sfx_manifest.get(GATE, null)


func after_each() -> void:
	## Put the gate back however this test left it — the manifest is autoload state.
	if _saved_gate != null:
		SoundManager._sfx_manifest[GATE] = _saved_gate
	else:
		SoundManager._sfx_manifest.erase(GATE)
	SoundManager.stop_music()


## A bare overlay is enough: _level_up_flare's tween and sprite work is guarded by
## is_instance_valid(fill) and a null _scene, so nulls skip straight to the audio branch.
func _flare() -> String:
	var overlay: Node = OVERLAY.new()
	add_child_autofree(overlay)
	SoundManager.stop_music()
	overlay._level_up_flare(null, null, 0)
	await get_tree().process_frame
	return SoundManager._current_music


func test_a_level_up_does_not_reach_the_music_stinger() -> void:
	assert_true(SoundManager._sfx_manifest.has(GATE),
		"PREMISE: sfx_manifest carries %s — if it ever stops, this whole file is stale" % GATE)
	var with_gate: String = await _flare()
	assert_ne(with_gate, BED,
		"the SFX flourish is supposed to win while it exists; %s played instead" % with_gate)

	## THE CONTROL, and it is the arm that makes the line above mean anything: take the gate away
	## and the SAME call must reach the bed. Without this, a probe that can never see a bed start
	## reports the identical pass.
	SoundManager._sfx_manifest.erase(GATE)
	var without_gate: String = await _flare()
	assert_eq(without_gate, BED,
		"CONTROL: with %s gone the fallback must play %s — it played '%s', so this probe cannot see the bed start and the verdict above is worthless" % [GATE, BED, without_gate])


func test_the_unreached_bed_is_still_shipped_and_playable() -> void:
	## Unreached is not broken, and the difference decides what @struktured is choosing between:
	## deleting a working 3.2 s bed versus removing dead weight.
	assert_true(SoundManager.has_music_track(BED), "%s left the manifest" % BED)
	var raw: String = FileAccess.get_file_as_string("res://data/music_manifest.json")
	var tracks: Dictionary = (JSON.parse_string(raw) as Dictionary).get("tracks", {})
	assert_gt(tracks.size(), 100, "SCOPE control: manifest carries %d tracks" % tracks.size())
	var entry: Dictionary = tracks.get(BED, {})
	var f: String = str(entry.get("file", ""))
	assert_ne(f, "", "%s has no file key" % BED)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://" + f)
	## The defended relationship is "real audio, not an LFS pointer" (~130 bytes of text), NOT a
	## size. A 50 KB floor copied from the full-bed guards fails this correctly-shipped 4.9 s
	## stinger at 37 KB — the coincidental-magnitude shape CLAUDE.md names, and it red first.
	assert_eq(bytes.slice(0, 4), "OggS".to_ascii_buffer(), "%s is not Ogg audio — LFS pointer?" % BED)
	assert_gt(bytes.size(), 1000, "%s read back only %d bytes" % [BED, bytes.size()])
	assert_false(bool(entry.get("loop", true)), "a stinger must not loop — that was the 2026-05-02 bug")
	assert_true(bool(entry.get("stinger", false)),
		"%s must declare stinger:true or its resume is never armed and a level-up ends in silence" % BED)
