extends GutTest

## `assets/cutscene_videos/` holds each backdrop TWICE: a `.ogv` the engine plays and a `.mp4`
## it cannot. `CutsceneDirector` composes `res://assets/cutscene_videos/%s.ogv` — the `.mp4`
## extension appears nowhere in `src/` or `data/`, and Godot has no mp4 decoder at all.
##
## The Web preset already excluded `*.mp4`; the four desktop presets did not, so every desktop
## download carried 10.40 MB of video that cannot be decoded. Web being right first is the
## evidence that the exclusion is intended rather than a judgement call.
##
## ⛔ THE DANGEROUS DIRECTION IS EXCLUDING `.ogv`. That is the format the game plays, so a filter
## that catches it removes cutscene video from the build — the arm below fails on it. (The scenes
## still render: every video has a `cutscene_backdrops/` PNG twin, 20 of 20. That fallback is why
## dropping `.ogv` on WEB is a real option for the cache line — but it is a content decision for
## struktured, not something a filter should do by accident.)
const PRESETS := "res://export_presets.cfg"
const VIDEO_DIR := "res://assets/cutscene_videos"
const DIRECTOR := "res://src/cutscene/CutsceneDirector.gd"


func _exclude_filters() -> Array:
	var out: Array = []
	var preset := "?"
	for line in FileAccess.get_file_as_string(PRESETS).split("\n"):
		var l := str(line).strip_edges()
		if l.begins_with("name="):
			preset = l.substr(5).replace("\"", "")
		elif l.begins_with("exclude_filter="):
			var inner := l.substr("exclude_filter=".length()).strip_edges().trim_prefix("\"").trim_suffix("\"")
			var pats: Array[String] = []
			for p in inner.split(","):
				var s := str(p).strip_edges()
				if s != "":
					pats.append(s)
			out.append({"preset": preset, "patterns": pats})
	return out


func _matches(patterns: Array, path: String) -> bool:
	for p in patterns:
		if path.matchn(str(p)):
			return true
	return false


func _files(ext: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(VIDEO_DIR)
	if d == null:
		return out
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if not d.current_is_dir() and n.ends_with(ext):
			out.append(n)
		n = d.get_next()
	d.list_dir_end()
	out.sort()
	return out


## The premise: the engine asks for .ogv. If that ever changes, every arm here is measuring a
## format the game no longer plays, so it is pinned rather than assumed.
func test_the_engine_still_asks_for_ogv() -> void:
	const GdSource := preload("res://test/unit/helpers/gd_source.gd")
	var code := GdSource.code_of(DIRECTOR)
	assert_true(code.contains("cutscene_videos/%s.ogv"),
		"CutsceneDirector no longer composes a .ogv path — re-derive which format ships before trusting the filters")
	assert_false(code.contains(".mp4"),
		"CutsceneDirector now names .mp4 — the engine cannot decode it, so this is a bug, not a reason to ship them")


func test_no_preset_ships_video_the_engine_cannot_decode() -> void:
	var mp4 := _files(".mp4")
	assert_gt(mp4.size(), 0,
		"ANTI-VACUITY: no .mp4 sits in cutscene_videos any more — this guard is defending nothing, check whether the filters are stale")
	var shipped: Array = []
	for f in _exclude_filters():
		for name in mp4:
			if not _matches(f["patterns"], "assets/cutscene_videos/%s" % name):
				shipped.append("%s ships in the %s build and cannot be decoded" % [name, f["preset"]])
				break
	assert_eq(shipped, [], "an undecodable video is in a player's download: %s" % [shipped])


## ⛔ THE SAFETY ARM. `.ogv` is what the game plays; a filter catching it removes cutscene video.
func test_no_preset_excludes_the_format_the_game_plays() -> void:
	var ogv := _files(".ogv")
	assert_gt(ogv.size(), 0, "ANTI-VACUITY: no .ogv on disk, so this arm cannot see an over-broad filter")
	var lost: Array = []
	for f in _exclude_filters():
		for name in ogv:
			if _matches(f["patterns"], "assets/cutscene_videos/%s" % name):
				lost.append("%s would be excluded from the %s build — that removes cutscene video" % [name, f["preset"]])
				break
	assert_eq(lost, [], "an export filter catches the playable video format: %s" % [lost])


## Every video has a backdrop PNG, which is what makes dropping .ogv on web a real OPTION rather
## than a loss. Pinned so the option stays costed correctly if a video is added without a twin.
func test_every_video_has_a_still_backdrop_fallback() -> void:
	var missing: Array = []
	for name in _files(".ogv"):
		var stem := name.get_basename()
		if not FileAccess.file_exists("res://assets/cutscene_backdrops/%s.png" % stem):
			missing.append(stem)
	assert_eq(missing, [], "a cutscene video has no still fallback, so excluding video would lose the scene: %s" % [missing])
