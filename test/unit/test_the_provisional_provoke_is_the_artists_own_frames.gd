extends GutTest

## struktured, .788: "the Fighter's Provoke animation is jank; ask my artist to make a custom Provoke." Until the artist
## delivers, he approved a PROVISIONAL built only from the artist's own Fighter frames: no generated or edited pixels,
## just idle 0 and Celebration 2/5/2/1 re-sequenced into point-at-the-foe -> flourish -> point -> settle. The old provoke
## was a 2026-03 composite in a different stance (the jank), never artist art.
## ⚠️ EXPECTED TO RED WHEN THE ARTIST'S PROVOKE LANDS: their frames are new pixels. Then this file is deleted with the
## delivery (docs/art/fighter-provoke-brief.md says so), not loosened.

const DIR := "res://assets/sprites/jobs/fighter/"


func _strip(anim: String) -> Image:
	var img: Image = (load(DIR + anim + ".png") as Texture2D).get_image().duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _frames(img: Image) -> Array:
	var h := img.get_height()
	var out: Array = []
	for i in range(img.get_width() / h):
		out.append(img.get_region(Rect2i(i * h, 0, h, h)).get_data())
	return out


func _artist_frames() -> Array:
	return _frames(_strip("idle")) + _frames(_strip("victory"))


func test_every_provoke_frame_is_an_artist_frame() -> void:
	var artist := _artist_frames()
	assert_gt(artist.size(), 10, "CONTROL: the artist's idle + Celebration frames load")
	var provoke := _frames(_strip("provoke"))
	assert_gt(provoke.size(), 2, "CONTROL: provoke has frames")
	var foreign: Array = []
	for i in provoke.size():
		if not artist.has(provoke[i]):
			foreign.append(i)
	assert_eq(foreign, [], "provoke frames that are not the artist's own pixels: %s" % [foreign])


func test_the_check_can_see_a_foreign_frame() -> void:
	## CONTROL: a frame with one pixel changed is not an artist frame, so the arm above can red.
	var artist := _artist_frames()
	var img := _strip("idle").get_region(Rect2i(0, 0, 256, 256))
	var c := img.get_pixel(128, 128)
	img.set_pixel(128, 128, Color(1.0 - c.r, 1.0 - c.g, 1.0 - c.b, 1.0))
	assert_false(artist.has(img.get_data()), "a one-pixel edit reads as foreign")


func test_provoke_is_timed_per_frame() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	var ms: Array = ((manifest["sheets"]["fighter"] as Dictionary)["frame_durations_ms"] as Dictionary)["provoke"]
	assert_eq(ms.size(), _frames(_strip("provoke")).size(), "one duration per provoke frame")
