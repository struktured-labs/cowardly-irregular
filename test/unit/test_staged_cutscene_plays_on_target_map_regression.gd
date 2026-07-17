extends GutTest

## struktured cap 2026-07-16: "cutscene is borked on the village return
## victory puppet scene — it never entered the village, it just stayed
## in mode 7 overworld."
##
## Root: _start_exploration's pending-cutscene check EARLY-RETURNED
## before the destination scene was built, so a map-gated STAGED
## cutscene (world1_harmonia_after_cave) played over whatever was still
## loaded — the Mode 7 overworld. Dialogue-only scenes tolerated this;
## staged puppetry cannot.
##
## Fix: destination scene builds FIRST; the cutscene fires at the tail
## of _start_exploration; the finish path light-resumes
## (_resume_exploration_after_cutscene) instead of rebuilding.

const GAME_LOOP := "res://src/GameLoop.gd"


func _body_of(fn: String) -> String:
	var src := FileAccess.get_file_as_string(GAME_LOOP)
	var i := src.find("func %s" % fn)
	assert_gt(i, -1, "%s must exist" % fn)
	var next: int = src.find("\nfunc ", i + 1)
	return src.substr(i, (next - i) if next > -1 else 4000)


func test_pending_check_no_longer_early_returns_before_scene_build() -> void:
	var body := _body_of("_start_exploration")
	assert_false("await _play_story_cutscene(pending)" in body,
		"the early-return play was the bug — staged scenes rendered over the OLD map")
	assert_true("pending_story_cutscene = _get_pending_story_cutscene()" in body,
		"pending id captured at top, played at tail")
	# The play must come AFTER scene creation (anchor: the prewarm deferred call precedes it).
	var prewarm_at := body.find("_prewarm_area_sprites")
	var play_at := body.find("_play_story_cutscene(pending_story_cutscene)")
	assert_gt(play_at, prewarm_at,
		"cutscene fires at the TAIL, after the destination scene is fully built")


func test_finish_path_light_resumes_not_rebuilds() -> void:
	var src := FileAccess.get_file_as_string(GAME_LOOP)
	assert_true("_resume_exploration_after_cutscene()" in src,
		"finish handler must light-resume — a rebuild after the tail-play pattern would double-build the scene")
	var body := _body_of("_resume_exploration_after_cutscene")
	assert_true("_cutscene_cooldown = false" in body,
		"resume must consume the cooldown the play set — the old rebuild path consumed it; leaving it set eats the NEXT map entry's gate check")
	assert_true("InputLockManager.pop_all()" in body,
		"resume must clear cutscene locks")
	assert_true("_start_exploration()" in body,
		"fallback full rebuild must remain for battle-step cutscenes that tore scenes down")
