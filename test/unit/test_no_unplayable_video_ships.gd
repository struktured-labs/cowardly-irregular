extends GutTest

## The cutscene backdrop VIDEOS are retired, and they stay retired: each backdrop key is its PNG still.
##
## History. `assets/cutscene_videos/` held every backdrop twice, a `.ogv` the engine played and a `.mp4` it could not
## decode, and CutsceneDirector tried the `.ogv` BEFORE the still. So a redrawn PNG was invisible behind its video
## (found 2026-10-31 by cowir-cutscenes and cowir-sprites independently), and this file guarded which video format
## shipped. cowir-main ruled the videos retired on 2026-11-01 under struktured's reversible-call rule; git keeps them.
## Seven stills were placeholders whose scenery lived only in the video; cowir-sprites redrew them from their own
## video frames in the same fold, so no scene went dark.
##
## WHAT REDS HERE. A video put back on disk, or the director composing a video path again. Either one brings back
## the precedence trap: a still that is edited and never seen. Restoring video is a decision, so it should be loud.
const VIDEO_DIR := "res://assets/cutscene_videos"
const DIRECTOR := "res://src/cutscene/CutsceneDirector.gd"
const STILL_DIR := "res://assets/cutscene_backdrops"


func test_no_backdrop_video_ships() -> void:
	var found: Array = []
	var d := DirAccess.open(VIDEO_DIR)
	if d != null:
		for f in d.get_files():
			if f.ends_with(".ogv") or f.ends_with(".mp4") or f.ends_with(".webm"):
				found.append(f)
	assert_eq(found, [], "backdrop videos are retired; a video on disk ships weight the director no longer plays: %s" % str(found))


func test_the_director_loads_the_still_and_no_video() -> void:
	const GdSource := preload("res://test/unit/helpers/gd_source.gd")
	var code := GdSource.code_of(DIRECTOR)
	assert_true(code.contains("cutscene_backdrops/%s.png"),
		"CONTROL: the director must still compose the backdrop still's path, or this file is reading the wrong source")
	assert_false(code.contains("cutscene_videos"),
		"the director composes a video path again: a redrawn still would be invisible behind it. Restore video deliberately, and rewrite this guard")
	assert_false(code.contains("VideoStreamPlayer"),
		"the director builds a VideoStreamPlayer again; backdrop video is retired")


func test_the_still_corpus_is_whole() -> void:
	var stills: Array = []
	var d := DirAccess.open(STILL_DIR)
	if d != null:
		for f in d.get_files():
			if f.ends_with(".png"):
				stills.append(f)
	assert_gt(stills.size(), 15, "CONTROL: only %d backdrop stills found; with video gone they are the only backdrops" % stills.size())
