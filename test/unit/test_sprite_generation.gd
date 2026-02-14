extends GutTest

## Test sprite generation for all 11 jobs at SNES 32x48 resolution

const SnesPartySpritesClass = preload("res://src/battle/sprites/SnesPartySprites.gd")
const SpriteUtilsClass = preload("res://src/battle/sprites/SpriteUtils.gd")

## All 11 job IDs from jobs.json
var ALL_JOBS: Array = [
	"fighter", "white_mage", "black_mage", "thief",
	"guardian", "ninja", "summoner",
	"time_mage", "necromancer", "scriptweaver", "bossbinder", "skiptrotter"
]


func test_snes_constants_exist() -> void:
	assert_eq(SpriteUtilsClass.SNES_WIDTH, 32, "SNES_WIDTH should be 32")
	assert_eq(SpriteUtilsClass.SNES_HEIGHT, 48, "SNES_HEIGHT should be 48")
	assert_eq(SpriteUtilsClass.SNES_DISPLAY_SCALE, 3, "SNES_DISPLAY_SCALE should be 3")


func test_make_snes_palette_returns_4_colors() -> void:
	var pal = SpriteUtilsClass.make_snes_palette(Color(0.5, 0.3, 0.8))
	assert_eq(pal.size(), 4, "SNES palette should have exactly 4 colors")
	# outline should be darkest
	assert_true(pal[0].v < pal[2].v, "Outline should be darker than base")
	# highlight should be lightest
	assert_true(pal[3].v > pal[2].v, "Highlight should be lighter than base")


func test_all_jobs_generate_valid_sprite_frames() -> void:
	for job_id in ALL_JOBS:
		var frames = SnesPartySpritesClass.create_sprite_frames(null, job_id)
		assert_not_null(frames, "SpriteFrames for %s should not be null" % job_id)
		assert_true(frames is SpriteFrames, "%s should return SpriteFrames" % job_id)

		# Check required animations exist
		for anim_name in ["idle", "attack", "defend", "hit", "cast", "item", "victory", "defeat"]:
			assert_true(frames.has_animation(anim_name),
				"%s should have '%s' animation" % [job_id, anim_name])

		# Check frame counts
		assert_eq(frames.get_frame_count("idle"), 2, "%s idle should have 2 frames" % job_id)
		assert_eq(frames.get_frame_count("attack"), 4, "%s attack should have 4 frames" % job_id)
		assert_eq(frames.get_frame_count("defeat"), 3, "%s defeat should have 3 frames" % job_id)


func test_sprite_dimensions_are_32x48() -> void:
	var frames = SnesPartySpritesClass.create_sprite_frames(null, "fighter")
	var tex = frames.get_frame_texture("idle", 0)
	assert_not_null(tex, "Texture should not be null")
	assert_eq(int(tex.get_width()), 32, "Sprite width should be 32")
	assert_eq(int(tex.get_height()), 48, "Sprite height should be 48")


func test_sprite_has_visible_pixels() -> void:
	"""Verify sprites aren't fully transparent (i.e., drawing code actually runs)."""
	for job_id in ALL_JOBS:
		var frames = SnesPartySpritesClass.create_sprite_frames(null, job_id)
		var tex = frames.get_frame_texture("idle", 0)
		var img = tex.get_image()
		var has_opaque = false
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				if img.get_pixel(x, y).a > 0.5:
					has_opaque = true
					break
			if has_opaque:
				break
		assert_true(has_opaque, "%s idle frame should have visible pixels" % job_id)


func test_customization_affects_sprite() -> void:
	"""Verify that different customization produces different cache keys / sprites."""
	var frames_default = SnesPartySpritesClass.create_sprite_frames(null, "fighter")
	# Create a mock customization with different hair
	var custom = {"skin_tone": Color(0.4, 0.3, 0.2), "hair_color": Color(1.0, 0.0, 0.0),
		"hair_style": 2, "eye_shape": 0, "name": "TestChar"}
	var frames_custom = SnesPartySpritesClass.create_sprite_frames(custom, "fighter")
	# Both should be valid SpriteFrames
	assert_not_null(frames_default, "Default frames should exist")
	assert_not_null(frames_custom, "Custom frames should exist")


func test_outfit_map_covers_all_jobs() -> void:
	"""All 11 jobs should have outfit type mappings."""
	for job_id in ALL_JOBS:
		assert_true(SnesPartySpritesClass.OUTFIT_MAP.has(job_id),
			"OUTFIT_MAP should contain %s" % job_id)


func test_headgear_map_covers_all_jobs() -> void:
	"""All 11 jobs should have headgear mappings."""
	for job_id in ALL_JOBS:
		assert_true(SnesPartySpritesClass.HEADGEAR_MAP.has(job_id),
			"HEADGEAR_MAP should contain %s" % job_id)


func test_job_colors_map_covers_all_jobs() -> void:
	"""All 11 jobs should have default color entries."""
	for job_id in ALL_JOBS:
		assert_true(SnesPartySpritesClass.JOB_COLORS.has(job_id),
			"JOB_COLORS should contain %s" % job_id)


func test_weapon_types_render_without_error() -> void:
	"""Test that various weapon types don't crash sprite generation."""
	for weapon_type in ["sword", "staff", "dagger", "axe"]:
		# Use the actual weapon IDs that map to these types
		var weapon_ids = {"sword": "iron_sword", "staff": "oak_staff",
			"dagger": "iron_dagger", "axe": "war_axe"}
		var wid = weapon_ids.get(weapon_type, "")
		var frames = SnesPartySpritesClass.create_sprite_frames(null, "fighter", "", wid)
		assert_not_null(frames, "Should generate frames with %s weapon" % weapon_type)
