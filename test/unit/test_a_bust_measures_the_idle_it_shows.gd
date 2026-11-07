extends GutTest

## A cutscene bust cut from a monster sheet takes its box from figure_rect, which measured FRAME 0, and then offsets
## that box into the frame the idle animation starts on (CutsceneDialogue._create_bust_from_monster_sheet). Those were
## the same frame until idle ranges moved off frame 0: a8eac3de6 moved five, and .785 moved seventeen whose frame 0 is
## an empty void oval. A bust of any of them would be framed around the oval and cut out of the creature beside it.
## Latent on 2026-11-07 (every such monster that speaks wears a drawn portrait), so it is fixed at the measure rather
## than at each speaker: figure_rect reads the frame a monster sheet's idle actually shows.

const RATIO := 0.55


func _sheets() -> Dictionary:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	return manifest["monster_sheets"]


func _idle_start(entry: Dictionary) -> int:
	return int(((entry.get("animations", {}) as Dictionary).get("idle", {}) as Dictionary).get("start", 0))


func _used_rect_of(path: String, index: int) -> Rect2i:
	var img: Image = (load(path) as Texture2D).get_image()
	var h := img.get_height()
	return img.get_region(Rect2i(index * h, 0, h, h)).get_used_rect()


func test_a_monster_whose_idle_moved_is_measured_on_its_idle() -> void:
	var sheets := _sheets()
	var moved := 0
	var differs := 0
	var wrong: Array = []
	for id in sheets:
		var e: Dictionary = sheets[id]
		var start := _idle_start(e)
		if start == 0 or not ResourceLoader.exists(str(e["path"])):
			continue
		moved += 1
		var want := _used_rect_of(str(e["path"]), start)
		if want != _used_rect_of(str(e["path"]), 0):
			differs += 1
		var got := HybridSpriteLoader.figure_rect(str(e["path"]))
		if got != want:
			wrong.append("%s: measured %s, its idle frame %d holds %s" % [id, got, start, want])
	assert_gt(moved, 4, "CONTROL: monsters whose idle does not start at frame 0 were found (%d)" % moved)
	assert_gt(differs, 0, "CONTROL: at least one has a frame 0 unlike its idle, so a frame-0 measure would be wrong")
	assert_eq(wrong, [], "a bust is measured on a frame the monster never idles on: %s" % [wrong])


func test_a_monster_idling_on_frame_0_and_a_job_sheet_are_unchanged() -> void:
	var fire: Dictionary = _sheets()["fire_dragon"]
	assert_eq(_idle_start(fire), 0, "CONTROL: fire_dragon idles from frame 0")
	assert_eq(HybridSpriteLoader.figure_rect(str(fire["path"])), _used_rect_of(str(fire["path"]), 0),
		"a monster idling on frame 0 is measured there")
	var job := HybridSpriteLoader.job_asset_path("fighter", "idle", "")
	assert_true(ResourceLoader.exists(job), "CONTROL: the fighter's idle sheet exists")
	assert_eq(HybridSpriteLoader.figure_rect(job), _used_rect_of(job, 0), "a job sheet is measured on frame 0, as before")
