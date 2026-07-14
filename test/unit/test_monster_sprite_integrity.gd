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
##   - All monster sheets have the dimensions the manifest says they have
##     (manifest-derived, NOT a hard-coded 2048x256 — that ossified the old
##     AI sheet shape and broke when the artist bat landed at 1664x128).
##   - idle_0 and idle_1 are non-empty (not fully transparent)
##   - idle_0 ≠ idle_1 (real animation, not a static duped frame)
##
## Manifest path: data/sprite_manifest.json → monster_sheets.<id> → {
##   frame_width, frame_height, animations.idle.{start,end}
## }. The expected sheet width is frame_width * (total_frames), where total
## is derived by inspecting the file dimensions and dividing by frame_width.
## We don't infer total frames from the manifest because the manifest only
## declares per-animation ranges (idle/attack/hit/dead), not the global count;
## the file dimensions are the source of truth for "the sheet shape the
## loader will actually try to slice".

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

## (2026-07-01) IDLE_STATIC_ALLOWLIST removed: cowir-sprites' uniform
## breathing-bob pass (7e9420eb) gave every T2 monster genuinely
## differing idle frames, and the regen tool now bakes the bob so the
## static-dupe defect class can't return. The idle-diff test below is
## live for the whole roster again.


func _load_monster_image(monster_id: String) -> Image:
	var path = "res://assets/sprites/monsters/%s.png" % monster_id
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	if tex == null:
		return null
	return tex.get_image()


func _load_manifest_entry(monster_id: String) -> Dictionary:
	# Returns {} if the monster isn't declared in sprite_manifest.json.
	var f := FileAccess.open("res://data/sprite_manifest.json", FileAccess.READ)
	if f == null:
		return {}
	var raw := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return {}
	var sheets: Variant = (parsed as Dictionary).get("monster_sheets", {})
	if not (sheets is Dictionary):
		return {}
	var entry: Variant = (sheets as Dictionary).get(monster_id, {})
	return entry if entry is Dictionary else {}


func test_all_fixed_monsters_exist() -> void:
	for monster_id in AFFECTED_MONSTERS:
		var path = "res://assets/sprites/monsters/%s.png" % monster_id
		assert_true(ResourceLoader.exists(path),
			"Monster sprite '%s' should exist at %s" % [monster_id, path])


func test_all_fixed_monsters_match_manifest_dimensions() -> void:
	# Sheet width must be a whole multiple of the manifest's frame_width and
	# the height must equal frame_height — these are the slicing parameters
	# the loader uses, so any mismatch silently bakes garbage into animation.
	for monster_id in AFFECTED_MONSTERS:
		var entry := _load_manifest_entry(monster_id)
		assert_false(entry.is_empty(),
			"sprite_manifest.json must declare '%s' under monster_sheets" % monster_id)
		var fw := int(entry.get("frame_width", 0))
		var fh := int(entry.get("frame_height", 0))
		assert_gt(fw, 0, "'%s' frame_width must be positive" % monster_id)
		assert_gt(fh, 0, "'%s' frame_height must be positive" % monster_id)
		var img := _load_monster_image(monster_id)
		if img == null:
			assert_true(false, "Could not load sprite for '%s'" % monster_id)
			continue
		assert_eq(img.get_height(), fh,
			"'%s' sheet height (%d) must equal manifest frame_height (%d)" %
			[monster_id, img.get_height(), fh])
		assert_eq(img.get_width() % fw, 0,
			"'%s' sheet width (%d) must be a whole multiple of manifest frame_width (%d)" %
			[monster_id, img.get_width(), fw])
		var total_frames := img.get_width() / fw
		# Every declared animation range must fit inside the actual frame count.
		var anims: Variant = entry.get("animations", {})
		if anims is Dictionary:
			for anim_name in (anims as Dictionary).keys():
				var range_: Variant = (anims as Dictionary)[anim_name]
				if range_ is Dictionary:
					var end_idx := int((range_ as Dictionary).get("end", -1))
					assert_lt(end_idx, total_frames,
						"'%s' animation '%s' end frame %d exceeds total frames %d" %
						[monster_id, anim_name, end_idx, total_frames])


func test_idle_frames_have_content() -> void:
	# Each idle frame must have at least SOME non-transparent pixels. Stride
	# the sample grid by frame_width/64 so the test scales with frame size.
	for monster_id in AFFECTED_MONSTERS:
		var entry := _load_manifest_entry(monster_id)
		if entry.is_empty():
			continue
		var fw := int(entry.get("frame_width", 0))
		var fh := int(entry.get("frame_height", 0))
		if fw <= 0 or fh <= 0:
			continue
		var idle_range: Variant = (entry.get("animations", {}) as Dictionary).get("idle", {})
		if not (idle_range is Dictionary):
			continue
		var start := int((idle_range as Dictionary).get("start", 0))
		var end := int((idle_range as Dictionary).get("end", start))
		var img := _load_monster_image(monster_id)
		if img == null:
			continue
		var stride := maxi(1, fw / 64)  # ~64 samples per axis regardless of frame size
		# Sample the first two idle frames (or just the first if only one exists).
		var sample_indices: Array[int] = [start]
		if end > start:
			sample_indices.append(start + 1)
		for frame_idx in sample_indices:
			var frame_x: int = frame_idx * fw
			var opaque_count := 0
			for y in range(0, fh, stride):
				for x in range(frame_x, frame_x + fw, stride):
					var c = img.get_pixel(x, y)
					if c.a > 0.1:
						opaque_count += 1
			assert_gt(opaque_count, 10,
				"'%s' idle frame %d should have visible content (got %d opaque samples)" %
				[monster_id, frame_idx, opaque_count])


func test_idle_frames_differ() -> void:
	# idle_0 and idle_1 should have at least some pixel differences (not a
	# static 1-frame dupe). Sample a coarse grid in MANIFEST frame coordinates
	# so the test handles both the 256-stride AI sheets and the 128-stride
	# artist sheets without ossifying either shape.
	for monster_id in AFFECTED_MONSTERS:
		var entry := _load_manifest_entry(monster_id)
		if entry.is_empty():
			continue
		var fw := int(entry.get("frame_width", 0))
		var fh := int(entry.get("frame_height", 0))
		if fw <= 0 or fh <= 0:
			continue
		var idle_range: Variant = (entry.get("animations", {}) as Dictionary).get("idle", {})
		if not (idle_range is Dictionary):
			continue
		var start := int((idle_range as Dictionary).get("start", 0))
		var end := int((idle_range as Dictionary).get("end", start))
		# Need at least two idle frames to do a diff at all — single-frame idle
		# is a legitimate authoring choice and isn't the bug we're catching.
		if end <= start:
			continue
		var img := _load_monster_image(monster_id)
		if img == null:
			continue
		var f0_x := start * fw
		var f1_x := (start + 1) * fw
		var stride := maxi(1, fw / 32)  # ~32 samples per axis regardless of frame size
		var differences := 0
		for y in range(0, fh, stride):
			for x in range(0, fw, stride):
				var c0: Color = img.get_pixel(f0_x + x, y)
				var c1: Color = img.get_pixel(f1_x + x, y)
				# Small tolerance for encoder noise
				if abs(c0.r - c1.r) + abs(c0.g - c1.g) + abs(c0.b - c1.b) + abs(c0.a - c1.a) > 0.05:
					differences += 1
		assert_gt(differences, 3,
			"'%s' idle frames %d and %d should differ (only %d differing samples — likely static dupe)" %
			[monster_id, start, start + 1, differences])
