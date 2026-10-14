extends GutTest

## 18 legacy monsters IDLED AS A SLASH ARC: frames 0-1 of their battle sheets are a sword-trail crescent or a hollow
## outline with the creature tiny or absent, and the manifest pointed idle at exactly those frames, so in battle the
## Ghost, Specter, Null Entity, Crystal Golem and the futuristic Masterites waited as a swoosh until they acted.
## struktured 2026-10-14: idle on the hit frames (4-5), or the nearest frame that shows the creature where 4-5 is weak.

## Frames 0-1 of each of these sheets are the arc, not the monster (looked at, frame by frame).
const ARC_FRAMES := [0, 1]
const ARC_IDLE_MONSTERS := [
	"ghost", "specter", "forgotten_variable", "null_entity", "the_absence", "empty_set", "crystal_golem",
	"corrupted_guardian", "glitch_entity", "memory_leak", "optimization_itself", "pipe_phantom", "rogue_process",
	"corrupted_sprite", "masterite_arbiter_futuristic", "masterite_tempo_futuristic", "masterite_warden_futuristic",
	"masterite_warden_abstract",
]


func _sheets() -> Dictionary:
	var m = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	return m.get("monster_sheets", {})


func idle_frames(entry: Dictionary) -> Array:
	var idle: Dictionary = entry.get("animations", {}).get("idle", {})
	if idle.is_empty():
		return []
	return range(int(idle.get("start", 0)), int(idle.get("end", idle.get("start", 0))) + 1)


func test_no_arc_monster_idles_on_its_arc() -> void:
	var sheets := _sheets()
	var on_arc: Array = []
	for id in ARC_IDLE_MONSTERS:
		assert_true(sheets.has(id), "%s: still has a battle sheet" % id)
		var frames := idle_frames(sheets.get(id, {}))
		assert_false(frames.is_empty(), "%s: declares an idle" % id)
		for f in frames:
			if f in ARC_FRAMES:
				on_arc.append("%s idles on arc frame %d" % [id, f])
	assert_eq(on_arc, [], "monsters that idle as a slash arc instead of themselves: %s" % str(on_arc))


func test_the_idle_frames_exist_on_the_sheet() -> void:
	var sheets := _sheets()
	for id in ARC_IDLE_MONSTERS:
		var e: Dictionary = sheets.get(id, {})
		var img := Image.load_from_file(ProjectSettings.globalize_path(str(e.get("path", ""))))
		assert_not_null(img, "%s: sheet loads" % id)
		if img == null:
			continue
		var count := img.get_width() / int(e.get("frame_width", 256))
		for f in idle_frames(e):
			assert_lt(f, count, "%s: idle frame %d is on its %d-frame sheet" % [id, f, count])


func test_the_check_sees_an_arc_idle() -> void:
	assert_eq(idle_frames({"animations": {"idle": {"start": 0, "end": 1}}}), [0, 1], "the shipped arc idle reads as frames 0-1")
	assert_eq(idle_frames({"animations": {"idle": {"start": 5, "end": 5}}}), [5], "a one-frame idle is one frame")
