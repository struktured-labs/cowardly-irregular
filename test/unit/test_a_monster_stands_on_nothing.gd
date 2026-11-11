extends GutTest

## struktured, .788 playtest: "giant spider sprite is not good, has weird background of white/yellow below its body."
## A gpt-image regen paints its subject on a light ground; background removal flood-fills from the frame edge, so ground
## fenced in by the spider's legs survived as an opaque cream blob under the body (747 px in one region, frames 0-5).
## tools/clear_enclosed_floor.py cleared it, alpha only. A census over all 117 sheets found 26 with cream low in the figure,
## but most are drawn white (ghost, specter, a ring), so this is a REVIEWED list, judged by eye: add a sheet once its
## floor is confirmed and cleared. Measured: the spider's largest region was 747 before and 10 after.

const MAX_GROUND_REGION := 40
## Sheets whose generated ground was cleared, judged by eye. Re-review an entry when its art is redrawn.
const CLEARED_OF_GROUND := ["spider", "the_coordinator", "the_regulator"]


static func is_ground(c: Color) -> bool:
	## The regen's warm cream ground: very light, warm, nearly colourless.
	return c.a > 0.0 and c.r8 >= 235 and c.g8 >= 225 and c.b8 >= 205 and (maxi(maxi(c.r8, c.g8), c.b8) - mini(mini(c.r8, c.g8), c.b8)) < 25


## The largest connected ground region in the LOWER 45% of the frame's figure: where a floor sits under a body.
static func largest_ground_region(frame: Image) -> int:
	var used := frame.get_used_rect()
	if used.size.x <= 0:
		return 0
	var low := used.position.y + int(float(used.size.y) * 0.55)
	var seen := {}
	var worst := 0
	for y in range(low, used.end.y):
		for x in range(used.position.x, used.end.x):
			var key := Vector2i(x, y)
			if seen.has(key) or not is_ground(frame.get_pixel(x, y)):
				continue
			var size := 0
			var stack: Array[Vector2i] = [key]
			seen[key] = true
			while not stack.is_empty():
				var p: Vector2i = stack.pop_back()
				size += 1
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = p + d
					if n.x >= used.position.x and n.x < used.end.x and n.y >= low and n.y < used.end.y \
							and not seen.has(n) and is_ground(frame.get_pixel(n.x, n.y)):
						seen[n] = true
						stack.append(n)
			worst = maxi(worst, size)
	return worst


func _sheet_image(id: String) -> Image:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	var e: Dictionary = (manifest["monster_sheets"] as Dictionary).get(id, {})
	assert_false(e.is_empty(), "CONTROL: %s is a monster sheet" % id)
	var img: Image = (load(str(e["path"])) as Texture2D).get_image().duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


func test_the_detector_finds_a_floor_under_a_body() -> void:
	## CONTROL: a dark body with a cream patch below it reads as ground; the same body without it reads 0.
	var f := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	f.fill_rect(Rect2i(10, 4, 44, 56), Color8(30, 30, 34))
	assert_eq(largest_ground_region(f), 0, "a dark body alone has no ground")
	f.fill_rect(Rect2i(20, 46, 20, 8), Color8(243, 240, 231))
	assert_gt(largest_ground_region(f), MAX_GROUND_REGION, "a 20x8 cream floor under the body is found")


func test_no_cleared_monster_stands_on_its_generated_ground() -> void:
	var standing: Array = []
	for id in CLEARED_OF_GROUND:
		var img := _sheet_image(id)
		var h := img.get_height()
		for i in range(img.get_width() / h):
			var r := largest_ground_region(img.get_region(Rect2i(i * h, 0, h, h)))
			if r > MAX_GROUND_REGION:
				standing.append("%s frame %d: %d px of ground" % [id, i, r])
	assert_eq(standing, [], "monsters still standing on their generated ground: %s" % [standing])
