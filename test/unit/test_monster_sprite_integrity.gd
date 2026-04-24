extends GutTest

## Regression tests for monster sprite integrity.
##
## Covers commit 4bda9e7 ("fix(sprites): replace duplicated-instance idle
## frames on 10 monsters") — where 10 monster sprite sheets had idle frames
## showing TWO figures instead of one (generator bug). The fix replaced
## frames 0/1 with de-duplicated versions pulled from frames 3/5 of the
## original sheets.
##
## Structural checks only — we can't easily detect "two figures" without a
## vision model, but we can enforce:
##   - All monster sheets have the expected 2048x256 dimensions
##   - idle_0 and idle_1 are non-empty (not fully transparent)
##   - idle_0 ≠ idle_1 (real animation, not a static duped frame)

const AFFECTED_MONSTERS = [
	"bat",
	"giant_bat",
	"adaptive_slime",
	"blood_wolf_alpha",
	"cave_rat",
	"conveyor_gremlin",
	"elder_mushroom",
	"meta_knight",
	"steam_rat",
	"treasure_mimic",
]

const EXPECTED_WIDTH = 2048  # 8 frames x 256px
const EXPECTED_HEIGHT = 256


func _load_monster_image(monster_id: String) -> Image:
	var path = "res://assets/sprites/monsters/%s.png" % monster_id
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	if tex == null:
		return null
	return tex.get_image()


func test_all_fixed_monsters_exist() -> void:
	for monster_id in AFFECTED_MONSTERS:
		var path = "res://assets/sprites/monsters/%s.png" % monster_id
		assert_true(ResourceLoader.exists(path),
			"Monster sprite '%s' should exist at %s" % [monster_id, path])


func test_all_fixed_monsters_have_expected_dimensions() -> void:
	for monster_id in AFFECTED_MONSTERS:
		var img = _load_monster_image(monster_id)
		if img == null:
			assert_true(false, "Could not load sprite for '%s'" % monster_id)
			continue
		assert_eq(img.get_width(), EXPECTED_WIDTH,
			"'%s' sheet width should be %d (8 frames × 256px)" % [monster_id, EXPECTED_WIDTH])
		assert_eq(img.get_height(), EXPECTED_HEIGHT,
			"'%s' sheet height should be %d" % [monster_id, EXPECTED_HEIGHT])


func test_idle_frames_have_content() -> void:
	# Each idle frame must have at least SOME non-transparent pixels
	for monster_id in AFFECTED_MONSTERS:
		var img = _load_monster_image(monster_id)
		if img == null:
			continue
		for frame_idx in [0, 1]:
			var frame_x = frame_idx * 256
			var opaque_count = 0
			for y in range(0, 256, 4):  # stride to save time
				for x in range(frame_x, frame_x + 256, 4):
					var c = img.get_pixel(x, y)
					if c.a > 0.1:
						opaque_count += 1
			assert_gt(opaque_count, 10,
				"'%s' idle frame %d should have visible content (got %d opaque samples)" %
				[monster_id, frame_idx, opaque_count])


func test_idle_frames_differ() -> void:
	# idle_0 and idle_1 should have at least some pixel differences (not a
	# static 1-frame dupe). Sample a coarse grid instead of full byte compare
	# to keep assertion messages small.
	for monster_id in AFFECTED_MONSTERS:
		var img = _load_monster_image(monster_id)
		if img == null:
			continue
		var differences = 0
		for y in range(0, 256, 8):
			for x in range(0, 256, 8):
				var c0 = img.get_pixel(x, y)
				var c1 = img.get_pixel(x + 256, y)
				# Compare with small tolerance to ignore JPEG-style noise
				if abs(c0.r - c1.r) + abs(c0.g - c1.g) + abs(c0.b - c1.b) + abs(c0.a - c1.a) > 0.05:
					differences += 1
		# Need at least 3 differing sampled pixels to count as "not static"
		assert_gt(differences, 3,
			"'%s' idle_0 and idle_1 should differ (only %d differing samples — likely static dupe)" %
			[monster_id, differences])
