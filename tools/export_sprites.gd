extends SceneTree

## Export procedural SnesPartySprites to PNG sprite sheets for all starter jobs.
## Usage: godot --headless -s tools/export_sprites.gd
##
## Produces 80x100-per-frame sprite strips in assets/sprites/jobs/<job_id>/
## matching the existing fighter sprite format.

const _SnesPartySprites = preload("res://src/battle/sprites/SnesPartySprites.gd")

## Per-frame size in the output (matches existing fighter sheets)
const FRAME_W: int = 80
const FRAME_H: int = 100

## Source procedural sprite size
const SRC_W: int = 32
const SRC_H: int = 48

## Scale factor (nearest-neighbor upscale from 32x48 to ~80x100)
## We'll center the 32x48 sprite scaled by 2x (64x96) inside an 80x100 frame
const SCALE: int = 2

## Jobs to export
const STARTER_JOBS: Array = ["fighter", "mage", "cleric", "rogue", "bard"]

## Default weapon types per job (for visual consistency)
const JOB_WEAPONS: Dictionary = {
	"fighter": "sword",
	"mage": "staff",
	"cleric": "staff",
	"rogue": "dagger",
	"bard": "sword",  # Bard gets a sword by default (lute is part of outfit)
}

## Animation definitions: name -> frame count
## These match what HybridSpriteLoader expects from the sprite sheets
const ANIMATIONS: Dictionary = {
	"idle": 2,
	"walk": 2,
	"attack": 3,
	"hit": 1,
	"dead": 1,
}

## Map export animation names to SnesPartySprites animation names and frame indices
const ANIM_MAPPING: Dictionary = {
	"idle": {"anim": "idle", "frames": [0, 1]},
	"walk": {"anim": "idle", "frames": [0, 1]},  # Use idle frames with slight variation
	"attack": {"anim": "attack", "frames": [0, 1, 2]},  # 3 of 4 attack frames
	"hit": {"anim": "hit", "frames": [0]},
	"dead": {"anim": "defeat", "frames": [2]},  # Final defeat frame (on ground)
}


func _init():
	print("=== Sprite Sheet Exporter ===")
	print("Exporting %d starter jobs..." % STARTER_JOBS.size())

	for job_id in STARTER_JOBS:
		_export_job(job_id)

	print("\n=== Export Complete ===")
	quit()


func _export_job(job_id: String) -> void:
	print("\n--- Exporting: %s ---" % job_id)

	# Create output directory
	var dir_path = "res://assets/sprites/jobs/%s" % job_id
	var dir = DirAccess.open("res://")
	if dir:
		dir.make_dir_recursive("assets/sprites/jobs/%s" % job_id)

	# Build the sprite context - use null customization for default look
	var ctx = _SnesPartySprites._build_context(null, job_id, "", "", "", "")

	for anim_name in ANIMATIONS:
		var frame_count = ANIMATIONS[anim_name]
		var mapping = ANIM_MAPPING[anim_name]
		var src_anim = mapping["anim"]
		var src_frames = mapping["frames"]

		# Create the strip image (frame_count * FRAME_W x FRAME_H)
		var strip_w = frame_count * FRAME_W
		var strip = Image.create(strip_w, FRAME_H, false, Image.FORMAT_RGBA8)
		strip.fill(Color(0, 0, 0, 0))  # Transparent

		for i in range(frame_count):
			var src_frame_idx = src_frames[i] if i < src_frames.size() else src_frames[src_frames.size() - 1]

			# Render the procedural frame at native 32x48
			var src_img = Image.create(SRC_W, SRC_H, false, Image.FORMAT_RGBA8)
			src_img.fill(Color(0, 0, 0, 0))

			# For walk animation, add a slight horizontal offset to differentiate from idle
			if anim_name == "walk":
				# Render walk using idle animation but with a leg-stride offset
				var walk_ctx = ctx.duplicate(true)
				_render_walk_frame(src_img, walk_ctx, src_anim, src_frame_idx, i)
			else:
				# Directly invoke the rendering
				_render_frame_to_image(src_img, ctx, src_anim, src_frame_idx)

			# Scale up with nearest-neighbor interpolation
			var scaled = _scale_nearest(src_img, SCALE)

			# Center in the frame
			var offset_x = (FRAME_W - scaled.get_width()) / 2
			var offset_y = (FRAME_H - scaled.get_height()) / 2

			# Blit scaled image into strip at position i
			var strip_offset_x = i * FRAME_W + offset_x
			for y in range(scaled.get_height()):
				for x in range(scaled.get_width()):
					var px = scaled.get_pixel(x, y)
					if px.a > 0.01:
						var dst_x = strip_offset_x + x
						var dst_y = offset_y + y
						if dst_x >= 0 and dst_x < strip_w and dst_y >= 0 and dst_y < FRAME_H:
							strip.set_pixel(dst_x, dst_y, px)

		# Save the strip
		var out_path = "res://assets/sprites/jobs/%s/%s.png" % [job_id, anim_name]
		var err = strip.save_png(out_path)
		if err == OK:
			print("  Saved: %s (%dx%d, %d frames)" % [out_path, strip_w, FRAME_H, frame_count])
		else:
			print("  ERROR saving %s: %d" % [out_path, err])


func _render_frame_to_image(img: Image, ctx: Dictionary, anim: String, frame_idx: int) -> void:
	"""Render a single frame using SnesPartySprites' internal rendering."""
	var cx = SRC_W / 2  # 16
	var base_y = 36  # Feet baseline

	# Calculate pose offsets (duplicated from SnesPartySprites._render_frame)
	var y_off = 0
	var x_off = 0
	var lean = 0

	match anim:
		"idle":
			y_off = -1 if frame_idx == 1 else 0
		"attack":
			match frame_idx:
				0: lean = -2
				1: lean = 4; x_off = -3
				2: lean = 6; x_off = -5
				3: lean = 0
		"defend":
			lean = -1
		"hit":
			match frame_idx:
				0: x_off = 3; lean = -4
				1: x_off = 2; lean = -2
				2: x_off = 0
		"cast":
			match frame_idx:
				0: y_off = -1
				1: y_off = -2
				2: y_off = 0
		"item":
			match frame_idx:
				0: lean = 2
				1: lean = 0
		"victory":
			y_off = -1 if frame_idx == 1 else 0
		"defeat":
			match frame_idx:
				0: lean = -3; y_off = 2
				1: lean = -5; y_off = 5
				2: lean = -6; y_off = 8

	var draw_cx = cx + x_off
	var draw_by = base_y + y_off

	# Draw all layers
	_SnesPartySprites._draw_body(img, ctx, draw_cx, draw_by, lean, anim, frame_idx)
	_SnesPartySprites._draw_hair(img, ctx, draw_cx, draw_by, lean)
	_SnesPartySprites._draw_face(img, ctx, draw_cx, draw_by, lean, anim, frame_idx)
	_SnesPartySprites._draw_outfit(img, ctx, draw_cx, draw_by, lean)
	_SnesPartySprites._draw_headgear(img, ctx, draw_cx, draw_by, lean)
	_SnesPartySprites._draw_weapon(img, ctx, draw_cx, draw_by, lean, anim, frame_idx)


func _render_walk_frame(img: Image, ctx: Dictionary, _anim: String, _src_frame_idx: int, walk_frame: int) -> void:
	"""Render a walk frame - based on idle but with alternating leg positions."""
	var cx = SRC_W / 2
	var base_y = 36

	# Walk uses slight body lean and alternating leg positions
	var lean = 1 if walk_frame == 0 else -1
	var y_off = 0

	var draw_cx = cx
	var draw_by = base_y + y_off

	# Draw all layers with walk lean
	_SnesPartySprites._draw_body(img, ctx, draw_cx, draw_by, lean, "idle", walk_frame)
	_SnesPartySprites._draw_hair(img, ctx, draw_cx, draw_by, lean)
	_SnesPartySprites._draw_face(img, ctx, draw_cx, draw_by, lean, "idle", walk_frame)
	_SnesPartySprites._draw_outfit(img, ctx, draw_cx, draw_by, lean)
	_SnesPartySprites._draw_headgear(img, ctx, draw_cx, draw_by, lean)
	_SnesPartySprites._draw_weapon(img, ctx, draw_cx, draw_by, lean, "idle", walk_frame)


func _scale_nearest(src: Image, factor: int) -> Image:
	"""Scale an image using nearest-neighbor interpolation."""
	var dst_w = src.get_width() * factor
	var dst_h = src.get_height() * factor
	var dst = Image.create(dst_w, dst_h, false, Image.FORMAT_RGBA8)
	dst.fill(Color(0, 0, 0, 0))

	for y in range(dst_h):
		for x in range(dst_w):
			var src_x = x / factor
			var src_y = y / factor
			dst.set_pixel(x, y, src.get_pixel(src_x, src_y))

	return dst
