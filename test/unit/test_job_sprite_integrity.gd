extends GutTest

## Regression tests for job sprite integrity.
##
## Protects against common accidental breakage:
##   - Per-animation PNGs go missing or get zeroed
##   - Frame dimensions drift from the 256x256 standard
##   - Frame strips get truncated (e.g. width not divisible by 256)
##   - Manifest-declared animations don't exist as files
##
## Checks all 5 starter jobs (fighter, mage, cleric, rogue, bard). Advanced
## and meta jobs are intentionally excluded since they may be procedurally
## generated at runtime.

const STARTER_JOBS = ["fighter", "mage", "cleric", "rogue", "bard"]
const EXPECTED_FRAME_SIZE = 256


func _read_manifest() -> Dictionary:
	var f = FileAccess.open("res://data/sprite_manifest.json", FileAccess.READ)
	if f == null:
		return {}
	var json = JSON.new()
	json.parse(f.get_as_text())
	f.close()
	return json.data if json.data else {}


func test_manifest_loads() -> void:
	var manifest = _read_manifest()
	assert_true(manifest.has("sheets"),
		"sprite_manifest.json must have a 'sheets' key")


func test_all_starter_jobs_in_manifest() -> void:
	var manifest = _read_manifest()
	var sheets = manifest.get("sheets", {})
	for job in STARTER_JOBS:
		assert_true(sheets.has(job),
			"Starter job '%s' must be registered in sprite_manifest.json sheets" % job)


func test_manifest_animations_have_files() -> void:
	# Every animation declared in the manifest must have a corresponding PNG
	# (manifest drift → sprites fail to load silently at runtime).
	var manifest = _read_manifest()
	var sheets = manifest.get("sheets", {})
	for job in STARTER_JOBS:
		var entry = sheets.get(job, {})
		var path_prefix: String = entry.get("path", "")
		var animations: Array = entry.get("animations", [])
		for anim in animations:
			var png_path = "%s/%s.png" % [path_prefix, anim]
			assert_true(ResourceLoader.exists(png_path),
				"Manifest declares '%s/%s' but file not found: %s" %
				[job, anim, png_path])


func test_all_job_idle_is_256_tall() -> void:
	# Frame height must be exactly 256px (horizontal strip convention)
	for job in STARTER_JOBS:
		var path = "res://assets/sprites/jobs/%s/idle.png" % job
		var tex = load(path) as Texture2D
		if tex == null:
			continue
		var img = tex.get_image()
		assert_eq(img.get_height(), EXPECTED_FRAME_SIZE,
			"'%s' idle.png height must be %d (got %d)" %
			[job, EXPECTED_FRAME_SIZE, img.get_height()])


func test_all_job_idle_width_divisible_by_256() -> void:
	# Width must be a multiple of 256 (n frames × 256 each)
	for job in STARTER_JOBS:
		var path = "res://assets/sprites/jobs/%s/idle.png" % job
		var tex = load(path) as Texture2D
		if tex == null:
			continue
		var img = tex.get_image()
		assert_eq(img.get_width() % EXPECTED_FRAME_SIZE, 0,
			"'%s' idle.png width %d must be a multiple of %d" %
			[job, img.get_width(), EXPECTED_FRAME_SIZE])
		# Sanity: at least 1 frame
		assert_gte(img.get_width(), EXPECTED_FRAME_SIZE,
			"'%s' idle.png must have at least 1 frame (width >= 256)" % job)


func test_all_job_attack_is_valid_strip() -> void:
	# attack.png must exist and be a proper horizontal strip
	for job in STARTER_JOBS:
		var path = "res://assets/sprites/jobs/%s/attack.png" % job
		assert_true(ResourceLoader.exists(path),
			"'%s/attack.png' must exist" % job)
		var tex = load(path) as Texture2D
		if tex == null:
			continue
		var img = tex.get_image()
		assert_eq(img.get_height(), EXPECTED_FRAME_SIZE,
			"'%s' attack.png height must be %d" % [job, EXPECTED_FRAME_SIZE])
		assert_eq(img.get_width() % EXPECTED_FRAME_SIZE, 0,
			"'%s' attack.png width must be a multiple of %d" % [job, EXPECTED_FRAME_SIZE])


func test_idle_frames_are_not_fully_transparent() -> void:
	# A common breakage mode: the sheet exists but all pixels are alpha=0
	for job in STARTER_JOBS:
		var path = "res://assets/sprites/jobs/%s/idle.png" % job
		var tex = load(path) as Texture2D
		if tex == null:
			continue
		var img = tex.get_image()
		# Sample frame 0 only
		var opaque_count = 0
		for y in range(0, 256, 8):
			for x in range(0, 256, 8):
				if img.get_pixel(x, y).a > 0.1:
					opaque_count += 1
					if opaque_count > 20:
						break
			if opaque_count > 20:
				break
		assert_gt(opaque_count, 20,
			"'%s' idle frame 0 must have visible content (found %d opaque samples)" %
			[job, opaque_count])


func test_cleric_has_artist_cast_and_walk() -> void:
	# Specific regression: cleric now has artist-sourced cast.png and walk.png
	# from Cleric_extended.aseprite (tags idle/cast/walk). These should be
	# real N-frame strips, not 1-frame placeholders.
	for anim in ["cast", "walk"]:
		var path = "res://assets/sprites/jobs/cleric/%s.png" % anim
		assert_true(ResourceLoader.exists(path),
			"cleric/%s.png must exist (artist-extracted from aseprite)" % anim)
		var tex = load(path) as Texture2D
		if tex == null:
			continue
		var img = tex.get_image()
		# Should be 6 frames (1536x256) per aseprite walk/cast tags
		assert_eq(img.get_width(), 1536,
			"cleric/%s.png should be 6 frames = 1536px wide (regression: aseprite extraction)" % anim)


func test_mage_attack_is_real_multi_frame_animation() -> void:
	# Specific regression: mage/attack was previously a 1-frame dupe.
	# cowir-sprites replaced it with the artist's 8-frame animation.
	var path = "res://assets/sprites/jobs/mage/attack.png"
	var tex = load(path) as Texture2D
	assert_not_null(tex, "mage/attack.png must exist")
	var img = tex.get_image()
	# 8 frames × 256 = 2048
	assert_eq(img.get_width(), 2048,
		"mage/attack.png should be 8 frames = 2048px (regression: previously 1-frame dupe)")
