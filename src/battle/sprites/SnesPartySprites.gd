class_name SnesPartySprites

## SnesPartySprites - Authentic SNES-style 32x48 party member sprites
## Composable layer system: body → hair → face → outfit → headgear → weapon
## All 11 jobs get distinct silhouettes via 6 outfit types.
## SNES rules: NO anti-aliasing, NO specular, NO alpha blending,
## max 4 colors per region, 1px dark outlines, nearest-neighbor scaling.

const _SU = preload("res://src/battle/sprites/SpriteUtils.gd")

## Outfit type mapping for all 11 jobs
const OUTFIT_MAP: Dictionary = {
	"fighter": "armored",
	"guardian": "armored",
	"white_mage": "robed",
	"summoner": "robed",
	"thief": "cloaked",
	"ninja": "cloaked",
	"black_mage": "dark_robed",
	"necromancer": "dark_robed",
	"scriptweaver": "tech",
	"bossbinder": "tech",
	"skiptrotter": "tech",
	"time_mage": "time",
}

## Headgear per job
const HEADGEAR_MAP: Dictionary = {
	"fighter": "helmet_open",
	"guardian": "full_helmet",
	"white_mage": "hood",
	"summoner": "circlet",
	"thief": "bandana",
	"ninja": "mask",
	"black_mage": "pointed_hat",
	"necromancer": "skull_hood",
	"scriptweaver": "goggles",
	"bossbinder": "visor",
	"skiptrotter": "cap",
	"time_mage": "astral_circlet",
}

## Default outfit colors per job
const JOB_COLORS: Dictionary = {
	"fighter": Color(0.2, 0.4, 0.8),
	"guardian": Color(0.6, 0.55, 0.4),
	"white_mage": Color(0.92, 0.9, 0.96),
	"summoner": Color(0.3, 0.7, 0.5),
	"thief": Color(0.35, 0.28, 0.45),
	"ninja": Color(0.15, 0.15, 0.22),
	"black_mage": Color(0.12, 0.1, 0.25),
	"necromancer": Color(0.25, 0.08, 0.18),
	"scriptweaver": Color(0.2, 0.5, 0.45),
	"bossbinder": Color(0.55, 0.2, 0.2),
	"skiptrotter": Color(0.5, 0.4, 0.15),
	"time_mage": Color(0.25, 0.2, 0.55),
}

## Canvas dimensions
const W: int = 32
const H: int = 48


## =====================
## PUBLIC API
## =====================

static func create_sprite_frames(customization, primary_job_id: String, secondary_job_id: String = "",
		weapon_id: String = "", armor_id: String = "", accessory_id: String = "") -> SpriteFrames:
	"""Generate SpriteFrames for a party member with all animation poses.
	Returns 32x48 frames suitable for TEXTURE_FILTER_NEAREST at 3x scale."""
	var cache_key = "snes_%s_%s_%s_%s_%s_%s" % [
		_customization_hash(customization), primary_job_id, secondary_job_id,
		weapon_id, armor_id, accessory_id]
	return _SU._get_cached_sprite(cache_key, func():
		return _generate_sprite_frames(customization, primary_job_id, secondary_job_id,
			weapon_id, armor_id, accessory_id)
	)


## =====================
## FRAME GENERATION
## =====================

static func _generate_sprite_frames(customization, primary_job_id: String, secondary_job_id: String,
		weapon_id: String, armor_id: String, accessory_id: String) -> SpriteFrames:
	var frames = SpriteFrames.new()
	var ctx = _build_context(customization, primary_job_id, secondary_job_id, weapon_id, armor_id, accessory_id)

	# idle (2 frames, bob)
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 2.0)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _render_frame(ctx, "idle", 0))
	frames.add_frame("idle", _render_frame(ctx, "idle", 1))

	# attack (4 frames)
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 5.0)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _render_frame(ctx, "attack", 0))
	frames.add_frame("attack", _render_frame(ctx, "attack", 1))
	frames.add_frame("attack", _render_frame(ctx, "attack", 2))
	frames.add_frame("attack", _render_frame(ctx, "attack", 3))

	# defend (2 frames)
	frames.add_animation("defend")
	frames.set_animation_speed("defend", 3.0)
	frames.set_animation_loop("defend", false)
	frames.add_frame("defend", _render_frame(ctx, "defend", 0))
	frames.add_frame("defend", _render_frame(ctx, "defend", 1))

	# hit (3 frames)
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 5.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _render_frame(ctx, "hit", 0))
	frames.add_frame("hit", _render_frame(ctx, "hit", 1))
	frames.add_frame("hit", _render_frame(ctx, "hit", 2))

	# cast (3 frames)
	frames.add_animation("cast")
	frames.set_animation_speed("cast", 3.0)
	frames.set_animation_loop("cast", false)
	frames.add_frame("cast", _render_frame(ctx, "cast", 0))
	frames.add_frame("cast", _render_frame(ctx, "cast", 1))
	frames.add_frame("cast", _render_frame(ctx, "cast", 2))

	# item (2 frames)
	frames.add_animation("item")
	frames.set_animation_speed("item", 3.0)
	frames.set_animation_loop("item", false)
	frames.add_frame("item", _render_frame(ctx, "item", 0))
	frames.add_frame("item", _render_frame(ctx, "item", 1))

	# victory (2 frames)
	frames.add_animation("victory")
	frames.set_animation_speed("victory", 1.5)
	frames.set_animation_loop("victory", true)
	frames.add_frame("victory", _render_frame(ctx, "victory", 0))
	frames.add_frame("victory", _render_frame(ctx, "victory", 1))

	# defeat (3 frames)
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 3.0)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _render_frame(ctx, "defeat", 0))
	frames.add_frame("defeat", _render_frame(ctx, "defeat", 1))
	frames.add_frame("defeat", _render_frame(ctx, "defeat", 2))

	return frames


## =====================
## RENDER CONTEXT
## =====================

static func _build_context(customization, primary_job_id: String, secondary_job_id: String,
		weapon_id: String, armor_id: String, accessory_id: String) -> Dictionary:
	"""Build rendering context with all colors and parameters resolved."""
	var job_id = primary_job_id if primary_job_id != "" else "fighter"
	var outfit_type = OUTFIT_MAP.get(job_id, "armored")
	var headgear = HEADGEAR_MAP.get(job_id, "none")
	var outfit_color = JOB_COLORS.get(job_id, Color(0.4, 0.4, 0.5))

	# Try to load visual overrides from jobs.json
	var job_vis = _SU.get_job_visual(job_id)
	if job_vis.has("outfit_color") and job_vis["outfit_color"] is Color:
		outfit_color = job_vis["outfit_color"]
	if job_vis.has("sprite_type"):
		outfit_type = job_vis["sprite_type"]
	if job_vis.has("headgear"):
		headgear = job_vis["headgear"]

	var outfit_pal = _SU.make_snes_palette(outfit_color)

	# Skin and hair from customization
	var skin_color = Color(0.9, 0.72, 0.6)
	var hair_color = Color(0.55, 0.4, 0.3)
	var hair_style = 0
	var eye_shape = 0

	if customization:
		if "skin_tone" in customization and customization.skin_tone is Color:
			skin_color = customization.skin_tone
		if "hair_color" in customization and customization.hair_color is Color:
			hair_color = customization.hair_color
		if "hair_style" in customization:
			hair_style = customization.hair_style
		if "eye_shape" in customization:
			eye_shape = customization.eye_shape

	var skin_pal = _SU.make_snes_palette(skin_color)
	var hair_pal = _SU.make_snes_palette(hair_color)

	# Weapon visual
	var weapon_visual = _SU.get_weapon_visual(weapon_id)
	var weapon_type = weapon_visual.get("type", "sword")

	# Secondary job tint
	var secondary_tint = Color.TRANSPARENT
	if secondary_job_id != "" and JOB_COLORS.has(secondary_job_id):
		secondary_tint = JOB_COLORS[secondary_job_id]

	# Armor and accessory visuals
	var armor_visual = _SU.get_armor_visual(armor_id)
	var accessory_visual = _SU.get_accessory_visual(accessory_id)

	return {
		"job_id": job_id,
		"outfit_type": outfit_type,
		"headgear": headgear,
		"outfit_pal": outfit_pal,  # [outline, dark, base, highlight]
		"skin_pal": skin_pal,
		"hair_pal": hair_pal,
		"hair_style": hair_style,
		"eye_shape": eye_shape,
		"weapon_type": weapon_type,
		"weapon_visual": weapon_visual,
		"secondary_tint": secondary_tint,
		"secondary_job_id": secondary_job_id,
		"armor_visual": armor_visual,
		"accessory_visual": accessory_visual,
	}


static func _customization_hash(customization) -> String:
	if not customization:
		return "default"
	var parts = []
	if "skin_tone" in customization and customization.skin_tone is Color:
		parts.append(customization.skin_tone.to_html())
	if "hair_color" in customization and customization.hair_color is Color:
		parts.append(customization.hair_color.to_html())
	if "hair_style" in customization:
		parts.append(str(customization.hair_style))
	if "eye_shape" in customization:
		parts.append(str(customization.eye_shape))
	if "name" in customization:
		parts.append(customization.name)
	return "_".join(parts) if parts.size() > 0 else "default"


## =====================
## FRAME RENDERING
## =====================

static func _render_frame(ctx: Dictionary, anim: String, frame_idx: int) -> ImageTexture:
	"""Render a single 32x48 frame."""
	var img = Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var cx = W / 2  # 16
	var base_y = 36  # Feet baseline

	# Calculate pose offsets
	var y_off = 0
	var x_off = 0
	var lean = 0

	match anim:
		"idle":
			y_off = -1 if frame_idx == 1 else 0
		"attack":
			match frame_idx:
				0: lean = -2  # Wind up
				1: lean = 4; x_off = -3  # Lunge forward
				2: lean = 6; x_off = -5  # Full swing
				3: lean = 0  # Return
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
				1: y_off = -2  # Arms raised
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
				2: lean = -6; y_off = 8  # On ground

	var draw_cx = cx + x_off
	var draw_by = base_y + y_off

	# Draw layers bottom to top
	_draw_body(img, ctx, draw_cx, draw_by, lean, anim, frame_idx)
	_draw_hair(img, ctx, draw_cx, draw_by, lean)
	_draw_face(img, ctx, draw_cx, draw_by, lean, anim, frame_idx)
	_draw_outfit(img, ctx, draw_cx, draw_by, lean)
	_draw_secondary_accents(img, ctx, draw_cx, draw_by, lean)
	_draw_armor_overlay(img, ctx, draw_cx, draw_by, lean)
	_draw_accessory_visual(img, ctx, draw_cx, draw_by, lean)
	_draw_headgear(img, ctx, draw_cx, draw_by, lean)
	_draw_weapon(img, ctx, draw_cx, draw_by, lean, anim, frame_idx)

	return ImageTexture.create_from_image(img)


## =====================
## LAYER: BODY (chibi proportions)
## =====================

static func _draw_body(img: Image, ctx: Dictionary, cx: int, by: int, lean: int, _anim: String, _frame: int) -> void:
	"""Draw chibi SNES body: large head (~1/3 height), small body, stubby legs."""
	var skin = ctx["skin_pal"]  # [outline, dark, base, highlight]
	var outline_c = Color(0.06, 0.06, 0.1)

	# Head (large, ~10x12 pixels, chibi)
	var head_cx = cx + lean / 3
	var head_cy = by - 28
	var head_rx = 5
	var head_ry = 6

	# Head outline
	for y in range(-head_ry - 1, head_ry + 2):
		for x in range(-head_rx - 1, head_rx + 2):
			var dist_sq = pow(float(x) / (head_rx + 0.5), 2) + pow(float(y) / (head_ry + 0.5), 2)
			if dist_sq >= 0.82 and dist_sq < 1.0:
				_SU._pixel(img, head_cx + x, head_cy + y, outline_c)

	# Head fill with skin shading
	for y in range(-head_ry, head_ry + 1):
		for x in range(-head_rx, head_rx + 1):
			var dist_sq = pow(float(x) / head_rx, 2) + pow(float(y) / head_ry, 2)
			if dist_sq < 0.9:
				var color = skin[2]  # base
				if y < -head_ry * 0.3:
					color = skin[3]  # highlight (forehead)
				elif y > head_ry * 0.4:
					color = skin[1]  # dark (chin)
				elif x > head_rx * 0.5:
					color = skin[1]  # dark (side shadow)
				_SU._pixel(img, head_cx + x, head_cy + y, color)

	# Neck (2px wide, 2px tall)
	for ny in range(by - 21, by - 19):
		for nx in range(-1, 2):
			_SU._pixel(img, cx + nx + lean / 4, ny, skin[2])

	# Torso (body will be covered by outfit, draw skin base)
	for y in range(by - 19, by - 8):
		var w = 5 - abs(y - (by - 14)) / 4
		for x in range(-w, w + 1):
			_SU._pixel(img, cx + x + lean / 4, y, skin[2])

	# Legs (stubby, 6px)
	for leg_side in [-1, 1]:
		var leg_x = cx + leg_side * 3 + lean / 5
		for y in range(by - 8, by + 1):
			for lx in range(-2, 2):
				_SU._pixel(img, leg_x + lx, y, skin[1])
		# Feet
		_SU._pixel(img, leg_x - 1, by, outline_c)
		_SU._pixel(img, leg_x, by, outline_c)
		_SU._pixel(img, leg_x + 1, by, outline_c)


## =====================
## LAYER: HAIR
## =====================

static func _draw_hair(img: Image, ctx: Dictionary, cx: int, by: int, lean: int) -> void:
	var hair = ctx["hair_pal"]  # [outline, dark, base, highlight]
	var head_cx = cx + lean / 3
	var head_cy = by - 28
	var head_rx = 5
	var head_ry = 6
	var style = ctx["hair_style"]

	match style:
		0:  # SHORT
			for y in range(head_cy - head_ry - 1, head_cy - 1):
				var w = head_rx + 1 if y < head_cy - head_ry + 2 else head_rx
				for x in range(-w, w + 1):
					var dist = abs(x) / float(w)
					var c = hair[3] if y < head_cy - head_ry else (hair[1] if dist > 0.7 else hair[2])
					_SU._pixel(img, head_cx + x, y, c)
		1:  # LONG
			# Top cap
			for y in range(head_cy - head_ry - 1, head_cy - 1):
				var w = head_rx + 1
				for x in range(-w, w + 1):
					var c = hair[3] if y < head_cy - head_ry else hair[2]
					if abs(x) > head_rx:
						c = hair[1]
					_SU._pixel(img, head_cx + x, y, c)
			# Side drapes
			for y in range(head_cy - 1, by - 12):
				for side in [-1, 1]:
					for dx in range(0, 3):
						var px = head_cx + side * (head_rx + dx - 1)
						var c = hair[2] if dx < 2 else hair[1]
						_SU._pixel(img, px, y, c)
		2:  # SPIKY
			for y in range(head_cy - head_ry - 5, head_cy - 1):
				var w = head_rx + 2
				for x in range(-w, w + 1):
					var spike = sin(x * 1.5) * 3
					if y < head_cy - head_ry + int(spike):
						_SU._pixel(img, head_cx + x, y, hair[3])
					elif y < head_cy - 1:
						var c = hair[2] if abs(x) < head_rx else hair[1]
						_SU._pixel(img, head_cx + x, y, c)
		3:  # BRAIDED
			# Top cap
			for y in range(head_cy - head_ry - 1, head_cy - 1):
				for x in range(-head_rx - 1, head_rx + 2):
					var c = hair[2] if abs(x) < head_rx else hair[1]
					if y < head_cy - head_ry:
						c = hair[3]
					_SU._pixel(img, head_cx + x, y, c)
			# Braid on right
			for y in range(head_cy, by - 10):
				var bx = head_cx + head_rx + int(sin(y * 0.7) * 1)
				_SU._pixel(img, bx, y, hair[2] if y % 2 == 0 else hair[1])
		4:  # PONYTAIL
			for y in range(head_cy - head_ry - 1, head_cy - 1):
				for x in range(-head_rx - 1, head_rx + 2):
					var c = hair[2]
					if y < head_cy - head_ry:
						c = hair[3]
					_SU._pixel(img, head_cx + x, y, c)
			# Tail
			for y in range(head_cy - head_ry + 3, head_cy + 4):
				var tx = head_cx + head_rx + 1 + (y - head_cy + head_ry) / 3
				_SU._pixel(img, tx, y, hair[2])
				_SU._pixel(img, tx + 1, y, hair[1])
		_:  # MOHAWK / fallback
			# Central strip
			for y in range(head_cy - head_ry - 4, head_cy - 1):
				for x in range(-2, 3):
					var c = hair[3] if y < head_cy - head_ry - 2 else hair[2]
					_SU._pixel(img, head_cx + x, y, c)


## =====================
## LAYER: FACE
## =====================

static func _draw_face(img: Image, ctx: Dictionary, cx: int, by: int, lean: int, anim: String, _frame: int) -> void:
	var head_cx = cx + lean / 3
	var head_cy = by - 28
	var outline_c = Color(0.06, 0.06, 0.1)
	var eye_color = Color(0.15, 0.15, 0.3)
	var eye_white = Color(0.95, 0.95, 1.0)

	# Skip face for defeat (face down)
	if anim == "defeat":
		return

	# Eyes (2-3px each, at head center)
	var eye_y = head_cy + 1
	for side in [-1, 1]:
		var eye_x = head_cx + side * 2
		# Eye white (1px)
		_SU._pixel(img, eye_x, eye_y, eye_white)
		# Pupil
		_SU._pixel(img, eye_x, eye_y, eye_color)
		# Catchlight
		_SU._pixel(img, eye_x - side, eye_y - 1, Color.WHITE)

	# Nose (1px shadow)
	_SU._pixel(img, head_cx, head_cy + 3, ctx["skin_pal"][1])

	# Mouth (2px line)
	_SU._pixel(img, head_cx - 1, head_cy + 4, Color(0.65, 0.38, 0.38))
	_SU._pixel(img, head_cx, head_cy + 4, Color(0.65, 0.38, 0.38))


## =====================
## LAYER: OUTFIT (job-specific silhouette)
## =====================

static func _draw_outfit(img: Image, ctx: Dictionary, cx: int, by: int, lean: int) -> void:
	var pal = ctx["outfit_pal"]  # [outline, dark, base, highlight]
	var outfit_type = ctx["outfit_type"]
	var outline_c = pal[0]

	match outfit_type:
		"armored":
			_draw_armored_outfit(img, pal, cx, by, lean)
		"robed":
			_draw_robed_outfit(img, pal, cx, by, lean)
		"cloaked":
			_draw_cloaked_outfit(img, pal, cx, by, lean)
		"dark_robed":
			_draw_dark_robed_outfit(img, pal, cx, by, lean)
		"tech":
			_draw_tech_outfit(img, pal, cx, by, lean)
		"time":
			_draw_time_outfit(img, pal, cx, by, lean)
		_:
			_draw_armored_outfit(img, pal, cx, by, lean)


static func _draw_armored_outfit(img: Image, pal: Array, cx: int, by: int, lean: int) -> void:
	"""Plate chest, pauldrons (Fighter, Guardian)."""
	var bcx = cx + lean / 4
	# Chest plate
	for y in range(by - 19, by - 8):
		var w = 6 - abs(y - (by - 14)) / 3
		# Outline
		_SU._pixel(img, bcx - w - 1, y, pal[0])
		_SU._pixel(img, bcx + w + 1, y, pal[0])
		for x in range(-w, w + 1):
			var c = pal[2]  # base
			if y < by - 17:
				c = pal[3]  # highlight at top
			elif x > w - 2:
				c = pal[1]  # dark on right side
			_SU._pixel(img, bcx + x, y, c)
	# Bottom outline
	for x in range(-5, 6):
		_SU._pixel(img, bcx + x, by - 8, pal[0])

	# Shoulder pauldrons
	for side in [-1, 1]:
		var sx = bcx + side * 7
		var sy = by - 18
		for py in range(-2, 3):
			for px in range(-2, 3):
				if abs(px) + abs(py) <= 2:
					var c = pal[3] if py < 0 else pal[2]
					_SU._pixel(img, sx + px, sy + py, c)
		# Pauldron outline
		for py in range(-2, 3):
			for px in range(-2, 3):
				if abs(px) + abs(py) == 3:
					_SU._pixel(img, sx + px, sy + py, pal[0])

	# Armored legs
	for leg_side in [-1, 1]:
		var lx = bcx + leg_side * 3
		for y in range(by - 8, by + 1):
			_SU._pixel(img, lx - 1, y, pal[1])
			_SU._pixel(img, lx, y, pal[2])
			_SU._pixel(img, lx + 1, y, pal[1])
		# Boot sole
		_SU._pixel(img, lx - 1, by, pal[0])
		_SU._pixel(img, lx, by, pal[0])
		_SU._pixel(img, lx + 1, by, pal[0])


static func _draw_robed_outfit(img: Image, pal: Array, cx: int, by: int, lean: int) -> void:
	"""Flowing robe with wide sleeves (White Mage, Summoner)."""
	var bcx = cx + lean / 4
	# Robe body (tapers outward toward bottom)
	for y in range(by - 19, by + 1):
		var t = float(y - (by - 19)) / 20.0
		var w = int(4 + t * 6)
		# Outline
		_SU._pixel(img, bcx - w - 1, y, pal[0])
		_SU._pixel(img, bcx + w + 1, y, pal[0])
		for x in range(-w, w + 1):
			var c = pal[2]
			if y < by - 16:
				c = pal[3]
			elif y > by - 4:
				c = pal[1]
			elif abs(x) > w - 2:
				c = pal[1]
			# Fabric fold lines
			if t > 0.3 and x != 0 and abs(x) % 4 == 0:
				c = pal[1]
			_SU._pixel(img, bcx + x, y, c)
	# Bottom hem outline
	var bot_w = int(4 + 6)
	for x in range(-bot_w - 1, bot_w + 2):
		_SU._pixel(img, bcx + x, by, pal[0])

	# Wide sleeves
	for side in [-1, 1]:
		var sx = bcx + side * 6
		for y in range(by - 16, by - 10):
			for dx in range(-3, 4):
				var c = pal[2] if dx * side < 0 else pal[1]
				if y < by - 14:
					c = pal[3]
				_SU._pixel(img, sx + dx, y, c)


static func _draw_cloaked_outfit(img: Image, pal: Array, cx: int, by: int, lean: int) -> void:
	"""Cape, form-fitting (Thief, Ninja)."""
	var bcx = cx + lean / 4
	# Form-fitting torso
	for y in range(by - 19, by - 8):
		var w = 5
		_SU._pixel(img, bcx - w - 1, y, pal[0])
		_SU._pixel(img, bcx + w + 1, y, pal[0])
		for x in range(-w, w + 1):
			var c = pal[2]
			if y < by - 17:
				c = pal[3]
			elif x > w - 2:
				c = pal[1]
			_SU._pixel(img, bcx + x, y, c)
	for x in range(-5, 6):
		_SU._pixel(img, bcx + x, by - 8, pal[0])

	# Cape trailing behind
	for y in range(by - 18, by - 2):
		var cape_x = bcx + 7
		var cape_w = 2 - (y - (by - 18)) / 8
		for dx in range(0, max(1, cape_w + 1)):
			var c = pal[1] if dx == 0 else pal[0]
			_SU._pixel(img, cape_x + dx, y, c)

	# Slim legs
	for leg_side in [-1, 1]:
		var lx = bcx + leg_side * 3
		for y in range(by - 8, by + 1):
			_SU._pixel(img, lx - 1, y, pal[1])
			_SU._pixel(img, lx, y, pal[2])
		_SU._pixel(img, lx - 1, by, pal[0])
		_SU._pixel(img, lx, by, pal[0])

	# Belt
	for x in range(-5, 6):
		_SU._pixel(img, bcx + x, by - 10, Color(0.45, 0.3, 0.2))


static func _draw_dark_robed_outfit(img: Image, pal: Array, cx: int, by: int, lean: int) -> void:
	"""Pointed hat, long robe (Black Mage, Necromancer). Hat is in headgear layer."""
	# Reuse robed body but darker zones
	var bcx = cx + lean / 4
	for y in range(by - 19, by + 1):
		var t = float(y - (by - 19)) / 20.0
		var w = int(4 + t * 5)
		_SU._pixel(img, bcx - w - 1, y, pal[0])
		_SU._pixel(img, bcx + w + 1, y, pal[0])
		for x in range(-w, w + 1):
			var c = pal[1]  # Darker overall than regular robe
			if y < by - 16:
				c = pal[2]
			elif y > by - 3:
				c = pal[0]
			_SU._pixel(img, bcx + x, y, c)
	var bot_w = int(4 + 5)
	for x in range(-bot_w - 1, bot_w + 2):
		_SU._pixel(img, bcx + x, by, pal[0])


static func _draw_tech_outfit(img: Image, pal: Array, cx: int, by: int, lean: int) -> void:
	"""Asymmetric modern look (Scriptweaver, Bossbinder, Skiptrotter)."""
	var bcx = cx + lean / 4
	# Fitted jacket (asymmetric)
	for y in range(by - 19, by - 8):
		var w = 5
		_SU._pixel(img, bcx - w - 1, y, pal[0])
		_SU._pixel(img, bcx + w + 1, y, pal[0])
		for x in range(-w, w + 1):
			var c = pal[2]
			if y < by - 16:
				c = pal[3]
			elif x > 2:  # Asymmetric - right side different shade
				c = pal[1]
			elif x < -3 and y > by - 13:
				c = pal[3]  # Left side accent panel
			_SU._pixel(img, bcx + x, y, c)

	# Belt with tech buckle
	for x in range(-5, 6):
		_SU._pixel(img, bcx + x, by - 9, pal[0])
	_SU._pixel(img, bcx, by - 9, pal[3])  # Buckle glow
	_SU._pixel(img, bcx - 1, by - 9, pal[3])

	# Legs with boots
	for leg_side in [-1, 1]:
		var lx = bcx + leg_side * 3
		for y in range(by - 8, by - 3):
			_SU._pixel(img, lx - 1, y, pal[2])
			_SU._pixel(img, lx, y, pal[2])
		# Boots (heavier)
		for y in range(by - 3, by + 1):
			_SU._pixel(img, lx - 2, y, pal[1])
			_SU._pixel(img, lx - 1, y, pal[1])
			_SU._pixel(img, lx, y, pal[1])
			_SU._pixel(img, lx + 1, y, pal[1])
		_SU._pixel(img, lx - 2, by, pal[0])
		_SU._pixel(img, lx + 1, by, pal[0])


static func _draw_time_outfit(img: Image, pal: Array, cx: int, by: int, lean: int) -> void:
	"""Hourglass motifs, celestial trim (Time Mage)."""
	var bcx = cx + lean / 4
	# Semi-robed with fitted waist (hourglass shape)
	for y in range(by - 19, by + 1):
		var t = float(y - (by - 19)) / 20.0
		# Hourglass: wide at shoulders and hem, narrow at waist
		var w: int
		if t < 0.35:
			w = int(5 - t * 4)  # Narrowing from shoulder to waist
		else:
			w = int(3 + (t - 0.35) * 8)  # Widening from waist to hem
		_SU._pixel(img, bcx - w - 1, y, pal[0])
		_SU._pixel(img, bcx + w + 1, y, pal[0])
		for x in range(-w, w + 1):
			var c = pal[2]
			if y < by - 16:
				c = pal[3]
			elif y > by - 4:
				c = pal[1]
			_SU._pixel(img, bcx + x, y, c)

	# Celestial trim (star dots on hem)
	var trim_color = Color(0.9, 0.85, 0.5)
	for x in range(-6, 7, 3):
		_SU._pixel(img, bcx + x, by - 1, trim_color)

	# Bottom outline
	var bot_w = int(3 + 0.65 * 8)
	for x in range(-bot_w - 1, bot_w + 2):
		_SU._pixel(img, bcx + x, by, pal[0])


## =====================
## LAYER: SECONDARY JOB ACCENTS
## =====================

static func _draw_secondary_accents(img: Image, ctx: Dictionary, cx: int, by: int, lean: int) -> void:
	"""Apply secondary job visual influence: palette tinting, accent piece, trim color."""
	var sec_tint: Color = ctx["secondary_tint"]
	if sec_tint == Color.TRANSPARENT:
		return

	var bcx = cx + lean / 4
	var sec_pal = _SU.make_snes_palette(sec_tint)

	# 1. Palette tint: shift outfit highlights ~25% toward secondary color
	_apply_secondary_tint(img, ctx, sec_tint)

	# 2. Accent piece: small 2-4px visual element per secondary job type
	var sec_outfit = OUTFIT_MAP.get(ctx.get("secondary_job_id", ""), "armored")
	_draw_accent_piece(img, sec_pal, sec_outfit, bcx, by)

	# 3. Trim color: inner edge accents use secondary job color
	_draw_trim(img, sec_pal, bcx, by)


static func _apply_secondary_tint(img: Image, ctx: Dictionary, sec_tint: Color) -> void:
	"""Shift outfit highlight pixels ~25% toward secondary job color."""
	var outfit_pal = ctx["outfit_pal"]
	var highlight = outfit_pal[3]  # highlight color of primary outfit

	for y in range(H):
		for x in range(W):
			var px = img.get_pixel(x, y)
			if px.a < 0.5:
				continue
			# Only tint pixels matching the primary outfit highlight
			if _colors_close(px, highlight, 0.12):
				var tinted = px.lerp(sec_tint, 0.25)
				_SU._pixel(img, x, y, tinted)


static func _colors_close(a: Color, b: Color, threshold: float) -> bool:
	"""Check if two colors are close enough (ignoring alpha)."""
	return abs(a.r - b.r) < threshold and abs(a.g - b.g) < threshold and abs(a.b - b.b) < threshold


static func _draw_accent_piece(img: Image, sec_pal: Array, sec_outfit: String, cx: int, by: int) -> void:
	"""Draw a small accent element based on the secondary job's outfit type."""
	match sec_outfit:
		"armored":
			# Shoulder guard accent (right side, 3px)
			_SU._pixel(img, cx + 8, by - 17, sec_pal[2])
			_SU._pixel(img, cx + 8, by - 16, sec_pal[2])
			_SU._pixel(img, cx + 9, by - 17, sec_pal[1])
		"robed":
			# Glow rune on chest (2px)
			_SU._pixel(img, cx, by - 14, sec_pal[3])
			_SU._pixel(img, cx + 1, by - 14, sec_pal[3])
		"cloaked":
			# Belt pouch (3px)
			_SU._pixel(img, cx - 5, by - 10, sec_pal[1])
			_SU._pixel(img, cx - 5, by - 9, sec_pal[2])
			_SU._pixel(img, cx - 4, by - 9, sec_pal[1])
		"dark_robed":
			# Dark energy wisps (2px dots)
			_SU._pixel(img, cx - 7, by - 13, sec_pal[3])
			_SU._pixel(img, cx + 7, by - 11, sec_pal[3])
		"tech":
			# LED indicator on chest (bright dot)
			_SU._pixel(img, cx + 2, by - 15, sec_pal[3])
			_SU._pixel(img, cx + 2, by - 14, sec_pal[2])
		"time":
			# Hourglass pip on belt
			_SU._pixel(img, cx, by - 9, sec_pal[3])
			_SU._pixel(img, cx, by - 8, sec_pal[2])


static func _draw_trim(img: Image, sec_pal: Array, cx: int, by: int) -> void:
	"""Draw secondary job trim color along outfit edges."""
	# Collar trim (2px on each side of neck)
	_SU._pixel(img, cx - 2, by - 19, sec_pal[2])
	_SU._pixel(img, cx + 2, by - 19, sec_pal[2])
	# Belt buckle accent
	_SU._pixel(img, cx, by - 9, sec_pal[3])
	# Boot trim
	_SU._pixel(img, cx - 4, by - 1, sec_pal[1])
	_SU._pixel(img, cx + 4, by - 1, sec_pal[1])


## =====================
## LAYER: ARMOR OVERLAY
## =====================

static func _draw_armor_overlay(img: Image, ctx: Dictionary, cx: int, by: int, lean: int) -> void:
	"""Draw armor visual modifications on top of outfit based on armor category."""
	var armor_vis = ctx["armor_visual"]
	var category = armor_vis.get("category", "medium")
	var armor_color = armor_vis.get("color", Color(0.5, 0.5, 0.5))

	# No overlay for default/empty armor
	if category == "medium" and armor_color == Color(0.5, 0.5, 0.5):
		return

	var pal = _SU.make_snes_palette(armor_color)
	var bcx = cx + lean / 4

	match category:
		"heavy":
			# Plate overlay: reinforced chest, shoulder guards
			# Chest plate highlights (2 vertical strips)
			for y in range(by - 17, by - 10):
				_SU._pixel(img, bcx - 3, y, pal[3])
				_SU._pixel(img, bcx + 3, y, pal[3])
			# Shoulder reinforcement (larger pauldrons)
			for side in [-1, 1]:
				var sx = bcx + side * 7
				_SU._pixel(img, sx, by - 19, pal[3])
				_SU._pixel(img, sx + side, by - 19, pal[2])
				_SU._pixel(img, sx, by - 18, pal[2])
			# Waist guard
			for x in range(-5, 6):
				_SU._pixel(img, bcx + x, by - 8, pal[1])
		"light":
			# Minimal: edge accents and trim only
			# Collar accent
			_SU._pixel(img, bcx - 3, by - 19, pal[3])
			_SU._pixel(img, bcx + 3, by - 19, pal[3])
			# Hem trim
			for x in range(-4, 5, 2):
				_SU._pixel(img, bcx + x, by - 8, pal[2])
		"robe":
			# Robe draping: extended hem with fabric folds
			for x in range(-6, 7):
				_SU._pixel(img, bcx + x, by - 1, pal[1])
				if abs(x) % 3 == 0:
					_SU._pixel(img, bcx + x, by - 2, pal[2])
		_:
			# Medium: subtle chain texture on torso
			for y in range(by - 16, by - 10):
				if y % 2 == 0:
					for x in range(-4, 5, 2):
						_SU._pixel(img, bcx + x, y, pal[1])


## =====================
## LAYER: ACCESSORY VISUAL
## =====================

static func _draw_accessory_visual(img: Image, ctx: Dictionary, cx: int, by: int, lean: int) -> void:
	"""Draw accessory visual element (cape, boots, glow, etc.)."""
	var acc_vis = ctx["accessory_visual"]
	if acc_vis.is_empty():
		return

	var acc_type = acc_vis.get("type", "")
	var acc_color = acc_vis.get("color", Color(0.7, 0.7, 0.7))
	if acc_type == "":
		return

	var pal = _SU.make_snes_palette(acc_color)
	var bcx = cx + lean / 4

	match acc_type:
		"cape":
			# Short cape trailing behind (4-5px hanging from shoulders)
			for y in range(by - 18, by - 10):
				var cape_x = bcx + 8
				_SU._pixel(img, cape_x, y, pal[2])
				_SU._pixel(img, cape_x + 1, y, pal[1])
				if y > by - 14:
					_SU._pixel(img, cape_x + 2, y, pal[0])
		"boots":
			# Recolor boot area with accessory color
			for leg_side in [-1, 1]:
				var lx = bcx + leg_side * 3
				for y in range(by - 2, by + 1):
					_SU._pixel(img, lx - 1, y, pal[2])
					_SU._pixel(img, lx, y, pal[3])
					_SU._pixel(img, lx + 1, y, pal[1])
		"glow":
			# Small glowing dot near hand/chest area
			_SU._pixel(img, bcx + 5, by - 13, pal[3])
			_SU._pixel(img, bcx + 6, by - 13, pal[2])
			_SU._pixel(img, bcx + 5, by - 12, pal[2])
		"shield":
			# Small buckler on left arm
			var sx = bcx - 7
			var sy = by - 14
			for dy in range(-2, 3):
				for dx in range(-2, 1):
					if abs(dx) + abs(dy) <= 2:
						var c = pal[3] if dy < 0 else pal[2]
						_SU._pixel(img, sx + dx, sy + dy, c)
			# Shield edge
			_SU._pixel(img, sx - 2, sy, pal[0])
			_SU._pixel(img, sx, sy + 2, pal[0])
			_SU._pixel(img, sx, sy - 2, pal[0])
		"ring":
			# Small glint on hand position
			_SU._pixel(img, bcx + 6, by - 11, pal[3])


## =====================
## LAYER: HEADGEAR
## =====================

static func _draw_headgear(img: Image, ctx: Dictionary, cx: int, by: int, lean: int) -> void:
	var pal = ctx["outfit_pal"]
	var headgear = ctx["headgear"]
	var head_cx = cx + lean / 3
	var head_cy = by - 28
	var outline_c = pal[0]

	match headgear:
		"helmet_open":
			# Open-face helmet (fighter)
			for x in range(-5, 6):
				_SU._pixel(img, head_cx + x, head_cy - 7, pal[3])
				_SU._pixel(img, head_cx + x, head_cy - 6, pal[2])
			# Gem
			_SU._pixel(img, head_cx, head_cy - 7, Color(0.9, 0.2, 0.2))

		"full_helmet":
			# Full helmet with visor slit (Guardian)
			for y in range(head_cy - 7, head_cy + 2):
				for x in range(-5, 6):
					var c = pal[2] if y > head_cy - 5 else pal[3]
					_SU._pixel(img, head_cx + x, y, c)
			# Visor slit
			for x in range(-4, 5):
				_SU._pixel(img, head_cx + x, head_cy, outline_c)

		"hood":
			# White mage hood
			for y in range(head_cy - 7, head_cy - 2):
				var w = 6
				for x in range(-w, w + 1):
					var c = pal[3] if y < head_cy - 5 else pal[2]
					_SU._pixel(img, head_cx + x, y, c)
			# Red triangle
			_SU._pixel(img, head_cx, head_cy - 7, Color(0.8, 0.2, 0.2))
			_SU._pixel(img, head_cx - 1, head_cy - 6, Color(0.8, 0.2, 0.2))
			_SU._pixel(img, head_cx + 1, head_cy - 6, Color(0.8, 0.2, 0.2))

		"circlet":
			# Summoner circlet with gem
			for x in range(-5, 6):
				_SU._pixel(img, head_cx + x, head_cy - 5, Color(0.7, 0.6, 0.3))
			_SU._pixel(img, head_cx, head_cy - 6, Color(0.3, 0.8, 0.4))  # Green gem

		"bandana":
			# Thief bandana with tail
			for x in range(-5, 6):
				_SU._pixel(img, head_cx + x, head_cy - 5, pal[2])
			# Tail
			for i in range(4):
				_SU._pixel(img, head_cx + 6 + i, head_cy - 4 + i / 2, pal[1])

		"mask":
			# Ninja face mask
			for y in range(head_cy + 1, head_cy + 5):
				for x in range(-4, 5):
					_SU._pixel(img, head_cx + x, y, pal[1])

		"pointed_hat":
			# Black mage iconic pointed hat
			for y in range(head_cy - 14, head_cy - 3):
				var progress = float(head_cy - 3 - y) / 11.0
				var w = int(5 * (1.0 - progress * 0.8))
				for x in range(-w, w + 1):
					var c = pal[1]
					if x < -w + 1:
						c = pal[2]
					_SU._pixel(img, head_cx + x, y, c)
			# Hat brim
			for x in range(-7, 8):
				_SU._pixel(img, head_cx + x, head_cy - 3, pal[1])
				_SU._pixel(img, head_cx + x, head_cy - 2, outline_c)
			# Glowing eyes
			_SU._pixel(img, head_cx - 2, head_cy, Color(1.0, 0.9, 0.3))
			_SU._pixel(img, head_cx + 2, head_cy, Color(1.0, 0.9, 0.3))

		"skull_hood":
			# Necromancer skull-adorned hood
			for y in range(head_cy - 7, head_cy - 2):
				for x in range(-6, 7):
					_SU._pixel(img, head_cx + x, y, pal[1])
			# Skull emblem
			_SU._pixel(img, head_cx, head_cy - 6, Color(0.9, 0.9, 0.85))
			_SU._pixel(img, head_cx - 1, head_cy - 5, Color(0.2, 0.05, 0.1))
			_SU._pixel(img, head_cx + 1, head_cy - 5, Color(0.2, 0.05, 0.1))

		"goggles":
			# Scriptweaver tech goggles
			for side in [-1, 1]:
				var gx = head_cx + side * 3
				_SU._pixel(img, gx - 1, head_cy - 2, Color(0.3, 0.7, 0.6))
				_SU._pixel(img, gx, head_cy - 2, Color(0.4, 0.9, 0.8))
				_SU._pixel(img, gx + 1, head_cy - 2, Color(0.3, 0.7, 0.6))
			# Strap
			for x in range(-5, 6):
				_SU._pixel(img, head_cx + x, head_cy - 3, Color(0.35, 0.25, 0.2))

		"visor":
			# Bossbinder data visor
			for x in range(-5, 6):
				_SU._pixel(img, head_cx + x, head_cy - 1, Color(0.7, 0.2, 0.2, 0.8))
				_SU._pixel(img, head_cx + x, head_cy, Color(0.9, 0.3, 0.2, 0.6))

		"cap":
			# Skiptrotter traveler cap
			for x in range(-5, 7):
				_SU._pixel(img, head_cx + x, head_cy - 6, pal[2])
				_SU._pixel(img, head_cx + x, head_cy - 5, pal[1])
			# Bill
			for x in range(-1, 7):
				_SU._pixel(img, head_cx + x, head_cy - 4, pal[1])

		"astral_circlet":
			# Time Mage circlet with hourglass motif
			for x in range(-5, 6):
				_SU._pixel(img, head_cx + x, head_cy - 5, Color(0.5, 0.4, 0.7))
			# Hourglass emblem
			_SU._pixel(img, head_cx, head_cy - 6, Color(0.85, 0.8, 0.5))
			_SU._pixel(img, head_cx - 1, head_cy - 7, Color(0.85, 0.8, 0.5))
			_SU._pixel(img, head_cx + 1, head_cy - 7, Color(0.85, 0.8, 0.5))


## =====================
## LAYER: WEAPON
## =====================

static func _draw_weapon(img: Image, ctx: Dictionary, cx: int, by: int, lean: int, anim: String, frame_idx: int) -> void:
	var weapon_type = ctx["weapon_type"]
	var vis = ctx["weapon_visual"]
	var bcx = cx + lean / 4

	# Don't draw weapon during defeat
	if anim == "defeat" and frame_idx >= 2:
		return

	# Calculate weapon position based on animation
	# Weapon origin = hand/waist level (by-10), offset to right side (bcx+7)
	var wx = bcx + 7
	var wy = by - 10
	var angle = 0

	match anim:
		"attack":
			match frame_idx:
				0: wx = bcx + 8; wy = by - 12; angle = -20  # Wind up
				1: wx = bcx + 4; wy = by - 16; angle = 30   # Lunge forward
				2: wx = bcx - 2; wy = by - 10; angle = 80   # Full swing
				3: wx = bcx + 7; wy = by - 10; angle = 0    # Return
		"defend":
			wx = bcx - 4; wy = by - 12; angle = 90  # Shield position
		"cast":
			match frame_idx:
				0: wx = bcx + 8; wy = by - 14; angle = -10
				1: wx = bcx + 6; wy = by - 16; angle = -30  # Staff raised
				2: wx = bcx + 8; wy = by - 14; angle = -10
		"victory":
			wx = bcx + 4; wy = by - 16; angle = -45  # Raised in triumph

	match weapon_type:
		"sword":
			_draw_snes_sword(img, wx, wy, angle, vis)
		"staff":
			_draw_snes_staff(img, wx, wy, angle, vis)
		"dagger":
			_draw_snes_dagger(img, wx, wy, angle, vis)
		"axe":
			_draw_snes_axe(img, wx, wy, angle, vis)
		_:
			_draw_snes_sword(img, wx, wy, angle, vis)


static func _draw_snes_sword(img: Image, cx: int, cy: int, angle: int, vis: Dictionary) -> void:
	var metal = vis.get("metal", Color(0.7, 0.7, 0.8))
	var metal_light = vis.get("metal_light", Color(0.95, 0.95, 1.0))
	var outline_c = Color(0.1, 0.1, 0.15)
	var angle_rad = deg_to_rad(angle)
	var length = 10

	# Blade
	for i in range(length):
		var px = cx + int(cos(angle_rad) * i)
		var py = cy + int(sin(angle_rad) * i)
		_SU._pixel(img, px, py, metal_light if i < 3 else metal)
		# Width
		var wx = int(sin(angle_rad))
		var wy = int(-cos(angle_rad))
		_SU._pixel(img, px + wx, py + wy, metal)

	# Outline tip
	var tip_x = cx + int(cos(angle_rad) * length)
	var tip_y = cy + int(sin(angle_rad) * length)
	_SU._pixel(img, tip_x, tip_y, outline_c)

	# Crossguard (2px perpendicular)
	var gx = cx + int(cos(angle_rad) * 2)
	var gy = cy + int(sin(angle_rad) * 2)
	for g in range(-2, 3):
		_SU._pixel(img, gx + int(sin(angle_rad) * g), gy - int(cos(angle_rad) * g), Color(0.5, 0.4, 0.25))


static func _draw_snes_staff(img: Image, cx: int, cy: int, angle: int, vis: Dictionary) -> void:
	var wood = vis.get("wood", Color(0.5, 0.3, 0.2))
	var gem = vis.get("gem", Color(0.3, 0.8, 1.0))
	var angle_rad = deg_to_rad(angle)
	var length = 12

	# Shaft
	for i in range(length):
		var px = cx + int(cos(angle_rad) * i)
		var py = cy + int(sin(angle_rad) * i)
		_SU._pixel(img, px, py, wood)

	# Gem at top (2x2)
	var gx = cx + int(cos(angle_rad) * (length - 1))
	var gy = cy + int(sin(angle_rad) * (length - 1))
	_SU._pixel(img, gx, gy, gem)
	_SU._pixel(img, gx + 1, gy, gem)
	_SU._pixel(img, gx, gy - 1, gem)
	# Shine
	_SU._pixel(img, gx, gy - 1, Color(1.0, 1.0, 1.0))


static func _draw_snes_dagger(img: Image, cx: int, cy: int, angle: int, vis: Dictionary) -> void:
	var blade = vis.get("blade", Color(0.8, 0.8, 0.9))
	var blade_light = vis.get("blade_light", Color(1.0, 1.0, 1.0))
	var angle_rad = deg_to_rad(angle)
	var length = 6

	for i in range(length):
		var px = cx + int(cos(angle_rad) * i)
		var py = cy + int(sin(angle_rad) * i)
		_SU._pixel(img, px, py, blade_light if i < 2 else blade)

	# Crossguard
	var gx = cx + int(cos(angle_rad) * 1)
	var gy = cy + int(sin(angle_rad) * 1)
	_SU._pixel(img, gx + int(sin(angle_rad)), gy - int(cos(angle_rad)), Color(0.4, 0.3, 0.2))
	_SU._pixel(img, gx - int(sin(angle_rad)), gy + int(cos(angle_rad)), Color(0.4, 0.3, 0.2))


static func _draw_snes_axe(img: Image, cx: int, cy: int, angle: int, vis: Dictionary) -> void:
	var metal = vis.get("metal", Color(0.6, 0.6, 0.7))
	var metal_light = vis.get("metal_light", Color(0.85, 0.85, 0.95))
	var angle_rad = deg_to_rad(angle)

	# Shaft
	for i in range(8):
		var px = cx + int(cos(angle_rad) * i)
		var py = cy + int(sin(angle_rad) * i)
		_SU._pixel(img, px, py, Color(0.45, 0.28, 0.18))

	# Axe head (triangle at end)
	var hx = cx + int(cos(angle_rad) * 7)
	var hy = cy + int(sin(angle_rad) * 7)
	for dy in range(-3, 4):
		var w = 3 - abs(dy)
		for dx in range(0, w + 1):
			var perp_x = int(sin(angle_rad) * dy) + int(cos(angle_rad) * dx)
			var perp_y = int(-cos(angle_rad) * dy) + int(sin(angle_rad) * dx)
			_SU._pixel(img, hx + perp_x, hy + perp_y, metal_light if dy < 0 else metal)
