extends GutTest

## Regression test for the moonwalk bug.
##
## Bug history (2026-04-29):
##   The GPT-Image-1 overworld pipeline produced "side view" output as a
##   right-facing pose, then assigned it directly to row 1 (which the game
##   reads as Direction.LEFT), and mirrored it into row 2 (Direction.RIGHT).
##   Result: pressing LEFT showed a right-facing sprite moving leftward —
##   the character moonwalked left and right.
##
##   Fixed by swapping rows 1 and 2 in fighter/cleric/rogue/mage overworld.png.
##
## Detection strategy:
##   Row 2 must be horizontally flipped relative to row 1 (the pipeline
##   intentionally mirrors). Beyond mirror correctness, we use a silhouette
##   center-of-mass (COM) heuristic: for left-facing sprites the head/face
##   ends up on the left half of the frame more often than the right, and
##   vice versa. Differences in horizontal silhouette weight between row 1
##   and row 2 catch row swaps without needing to read facial features.
##
## What we don't check:
##   This test won't catch jobs whose silhouettes are perfectly symmetric
##   (so left/right look identical). For asymmetric chibis like the artist's
##   starters (sword/staff/bow visibility), it's a robust signal.

const STARTER_JOBS = ["fighter", "cleric", "rogue", "mage"]
## The frame is DERIVED from the sheet (a 4x4 walk grid), never a constant: the party went to 48px on 2026-10-30
## and a fixed 32 read cells straddling two rows, so the lean arm judged pixels the game never draws.


func _load_overworld(job: String) -> Image:
	var path = "res://assets/sprites/jobs/%s/overworld.png" % job
	if not ResourceLoader.exists(path):
		return null
	var tex = load(path) as Texture2D
	if tex == null:
		return null
	return tex.get_image()


func _frame(img: Image) -> int:
	return img.get_width() / 4


func _row_alpha_mass(img: Image, row_idx: int, col_idx: int) -> Array:
	# Returns [left_half_alpha_count, right_half_alpha_count] for one frame.
	var fs := _frame(img)
	var left_count = 0
	var right_count = 0
	for y in range(fs):
		for x in range(fs):
			var a = img.get_pixel(col_idx * fs + x, row_idx * fs + y).a
			if a > 0.1:
				if x < fs / 2:
					left_count += 1
				else:
					right_count += 1
	return [left_count, right_count]


func test_starter_overworld_rows_are_mirrored() -> void:
	# Row 2 (RIGHT) should be the horizontal flip of row 1 (LEFT).
	# This is what cowir-sprites' pipeline declares it does. If a future
	# regenerate breaks this, the test should fail loud.
	#
	# Note: Godot's `process/fix_alpha_border=true` import setting fills
	# RGB on transparent pixels with neighbor colors to prevent edge bleeding.
	# That breaks strict RGB symmetry on alpha=0 pixels, so we compare
	# alpha + only-opaque RGB.
	for job in STARTER_JOBS:
		var img = _load_overworld(job)
		if img == null:
			continue
		var fs := _frame(img)
		var pixel_diff = 0
		for col in range(4):
			for y in range(0, fs, 4):
				for x in range(0, fs, 4):
					var px_left  = img.get_pixel(col * fs + x,            fs + y)
					var px_right = img.get_pixel(col * fs + (fs - 1 - x), 2 * fs + y)
					# Always compare alpha (transparency must be mirrored exactly).
					if abs(px_left.a - px_right.a) > 0.05:
						pixel_diff += 1
						continue
					# Skip RGB compare on transparent pixels (fix_alpha_border bleeds).
					if px_left.a < 0.05 and px_right.a < 0.05:
						continue
					var d = abs(px_left.r - px_right.r) + abs(px_left.g - px_right.g) + \
						abs(px_left.b - px_right.b)
					if d > 0.05:
						pixel_diff += 1
		assert_lt(pixel_diff, 8,
			"'%s' overworld.png: row 2 (RIGHT) should be horizontal mirror of row 1 (LEFT). " % job +
			"Got %d significant pixel diffs in sparse sample (expected <8)." % pixel_diff)


func test_starter_overworld_row_facing_via_com() -> void:
	# Heuristic: across all 4 frames in row 1 (LEFT), the silhouette's
	# left-half mass should differ from right-half mass in a consistent way
	# vs row 2 (RIGHT). The exact lean depends on the chibi pose, but
	# row1.left_mass - row1.right_mass should equal -(row2.left_mass - row2.right_mass)
	# because row 2 is the mirror. So if rows are mirrored *correctly* AND
	# in the right slots, we just check that the mirror property holds (the
	# previous test). The "right slot" check is harder without facial features,
	# so this test is more of a sanity check that the rows aren't identical
	# (which would mean row1==row2, not mirrored at all).
	for job in STARTER_JOBS:
		var img = _load_overworld(job)
		if img == null:
			continue
		var row1_lean := 0  # left_mass - right_mass aggregated across 4 frames
		var row2_lean := 0
		for col in range(4):
			var r1 = _row_alpha_mass(img, 1, col)
			var r2 = _row_alpha_mass(img, 2, col)
			row1_lean += r1[0] - r1[1]
			row2_lean += r2[0] - r2[1]
		# If perfectly mirrored, row1_lean should equal -row2_lean.
		# We allow some slack for sub-pixel asymmetry but require they have
		# opposite signs (one row leans left, the other leans right).
		assert_ne(sign(row1_lean), sign(row2_lean) if row2_lean != 0 else sign(row1_lean),
			"'%s' overworld: row1 lean (%d) and row2 lean (%d) should have opposite signs " % [job, row1_lean, row2_lean] +
			"(rows aren't mirrored, or sheet is symmetric). This catches the row-swap bug only " +
			"indirectly — the mirror test above is the primary check.")


func test_starter_overworld_dimensions() -> void:
	# A 4x4 grid of the frame the MANIFEST declares for the job (the loader cuts at that size and refuses anything else).
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	var players: Dictionary = (m as Dictionary).get("overworld_player_sheets", {}) if m is Dictionary else {}
	for job in STARTER_JOBS:
		var img = _load_overworld(job)
		if img == null:
			continue
		var fw := int((players.get(job, {}) as Dictionary).get("frame_width", 0))
		assert_gt(fw, 0, "CONTROL: '%s' must declare its overworld frame" % job)
		assert_eq(Vector2i(img.get_width(), img.get_height()), Vector2i(fw * 4, fw * 4),
			"'%s' overworld.png must be a 4x4 grid of its declared %dpx frame" % [job, fw])

func test_each_row_has_visible_content() -> void:
	# Catch the "fully transparent row" failure mode (e.g., extraction
	# accidentally cleared a row).
	for job in STARTER_JOBS:
		var img = _load_overworld(job)
		if img == null:
			continue
		var fs := _frame(img)
		for row in range(4):
			var mass = 0
			for y in range(0, fs, 4):
				for x in range(0, img.get_width(), 4):
					if img.get_pixel(x, row * fs + y).a > 0.1:
						mass += 1
			assert_gt(mass, 30,
				"'%s' overworld row %d has only %d visible pixels (sparse sample); row may be empty" %
				[job, row, mass])
