extends Control
class_name CharacterPortrait

## CharacterPortrait - Generates FF-style character face portraits
## Can be used in battle, menus, and anywhere character visuals are needed

const CustomizationScript = preload("res://src/character/CharacterCustomization.gd")

## Size presets
enum PortraitSize {
	SMALL,   # 32x32 - for lists, small icons
	MEDIUM,  # 48x48 - for menus, party display
	LARGE,   # 64x64 - for battle, detailed view
	XLARGE   # 96x96 - for character creation preview
}

## Portrait data
var customization = null  # CharacterCustomization
var job_id: String = "fighter"
var size_preset: PortraitSize = PortraitSize.MEDIUM

## Calculated size
var _portrait_size: Vector2 = Vector2(48, 48)


func _init(custom = null, job: String = "fighter", size: PortraitSize = PortraitSize.MEDIUM) -> void:
	customization = custom
	job_id = job
	size_preset = size
	_calculate_size()


func _ready() -> void:
	_build_portrait()


func _calculate_size() -> void:
	match size_preset:
		PortraitSize.SMALL:
			_portrait_size = Vector2(32, 32)
		PortraitSize.MEDIUM:
			_portrait_size = Vector2(48, 48)
		PortraitSize.LARGE:
			_portrait_size = Vector2(64, 64)
		PortraitSize.XLARGE:
			_portrait_size = Vector2(96, 96)
	custom_minimum_size = _portrait_size
	size = _portrait_size


func set_customization(custom, job: String = "") -> void:
	customization = custom
	if job != "":
		job_id = job
	_build_portrait()


func _build_portrait() -> void:
	# Clear existing
	for child in get_children():
		child.queue_free()

	if not customization:
		_build_placeholder()
		return

	var scale_factor = _portrait_size.x / 48.0  # Base size is 48

	# Background (job color)
	var bg = ColorRect.new()
	bg.color = _get_job_color(job_id).darkened(0.3)
	bg.size = _portrait_size
	bg.position = Vector2.ZERO
	add_child(bg)

	# Face base
	var face_w = 36 * scale_factor
	var face_h = 40 * scale_factor
	var face = ColorRect.new()
	face.color = customization.skin_tone
	face.size = Vector2(face_w, face_h)
	face.position = Vector2((_portrait_size.x - face_w) / 2, _portrait_size.y - face_h - 2 * scale_factor)
	add_child(face)

	# Hair
	var hair = _create_hair(scale_factor)
	add_child(hair)

	# Job outfit elements (collar/hat)
	var outfit = _create_job_outfit(scale_factor)
	if outfit:
		add_child(outfit)

	# Eyes
	_create_eyes(scale_factor)

	# Eyebrows
	_create_eyebrows(scale_factor)

	# Nose
	_create_nose(scale_factor)

	# Mouth
	_create_mouth(scale_factor)

	# Border
	var border = ColorRect.new()
	border.color = _get_job_color(job_id)
	border.size = Vector2(_portrait_size.x, 2 * scale_factor)
	border.position = Vector2(0, _portrait_size.y - 2 * scale_factor)
	add_child(border)


func _build_placeholder() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.2, 0.2, 0.25)
	bg.size = _portrait_size
	add_child(bg)

	var question = Label.new()
	question.text = "?"
	question.add_theme_font_size_override("font_size", int(24 * _portrait_size.x / 48.0))
	question.position = _portrait_size / 2 - Vector2(6, 12)
	add_child(question)


func _create_hair(scale: float) -> Control:
	var hair = ColorRect.new()
	hair.color = customization.hair_color

	var base_x = _portrait_size.x / 2
	var base_y = 4 * scale

	match customization.hair_style:
		CustomizationScript.HairStyle.SHORT:
			hair.size = Vector2(38 * scale, 14 * scale)
			hair.position = Vector2(base_x - 19 * scale, base_y)
		CustomizationScript.HairStyle.LONG:
			hair.size = Vector2(42 * scale, 28 * scale)
			hair.position = Vector2(base_x - 21 * scale, base_y - 2 * scale)
		CustomizationScript.HairStyle.SPIKY:
			hair.size = Vector2(44 * scale, 20 * scale)
			hair.position = Vector2(base_x - 22 * scale, base_y - 6 * scale)
		CustomizationScript.HairStyle.BRAIDED:
			hair.size = Vector2(36 * scale, 22 * scale)
			hair.position = Vector2(base_x - 18 * scale, base_y)
		CustomizationScript.HairStyle.PONYTAIL:
			hair.size = Vector2(34 * scale, 18 * scale)
			hair.position = Vector2(base_x - 17 * scale, base_y)
		CustomizationScript.HairStyle.MOHAWK:
			hair.size = Vector2(12 * scale, 24 * scale)
			hair.position = Vector2(base_x - 6 * scale, base_y - 8 * scale)

	return hair


func _create_job_outfit(scale: float) -> Control:
	var outfit = Control.new()
	var base_x = _portrait_size.x / 2
	var base_y = _portrait_size.y

	match job_id:
		"fighter":
			# Red bandana/headband
			var bandana = ColorRect.new()
			bandana.color = Color(0.7, 0.2, 0.2)
			bandana.size = Vector2(40 * scale, 4 * scale)
			bandana.position = Vector2(base_x - 20 * scale, 12 * scale)
			outfit.add_child(bandana)
		"white_mage":
			# White hood/cowl
			var hood = ColorRect.new()
			hood.color = Color(0.95, 0.95, 0.98)
			hood.size = Vector2(44 * scale, 8 * scale)
			hood.position = Vector2(base_x - 22 * scale, 2 * scale)
			outfit.add_child(hood)
		"black_mage":
			# Dark hat brim
			var hat = ColorRect.new()
			hat.color = Color(0.15, 0.15, 0.3)
			hat.size = Vector2(42 * scale, 12 * scale)
			hat.position = Vector2(base_x - 21 * scale, 0)
			outfit.add_child(hat)
			# Yellow eyes glow
			var glow_l = ColorRect.new()
			glow_l.color = Color(1.0, 0.9, 0.3)
			glow_l.size = Vector2(4 * scale, 3 * scale)
			glow_l.position = Vector2(base_x - 10 * scale, 18 * scale)
			outfit.add_child(glow_l)
			var glow_r = ColorRect.new()
			glow_r.color = Color(1.0, 0.9, 0.3)
			glow_r.size = Vector2(4 * scale, 3 * scale)
			glow_r.position = Vector2(base_x + 6 * scale, 18 * scale)
			outfit.add_child(glow_r)
		"thief":
			# Green bandana
			var bandana = ColorRect.new()
			bandana.color = Color(0.2, 0.5, 0.2)
			bandana.size = Vector2(38 * scale, 5 * scale)
			bandana.position = Vector2(base_x - 19 * scale, 10 * scale)
			outfit.add_child(bandana)

	return outfit


func _create_eyes(scale: float) -> void:
	var eye_color = Color(0.15, 0.15, 0.25)
	var base_x = _portrait_size.x / 2
	var base_y = 20 * scale

	var eye_w = 6 * scale
	var eye_h = 5 * scale

	match customization.eye_shape:
		CustomizationScript.EyeShape.NORMAL:
			eye_w = 6 * scale
			eye_h = 5 * scale
		CustomizationScript.EyeShape.NARROW:
			eye_w = 8 * scale
			eye_h = 3 * scale
		CustomizationScript.EyeShape.WIDE:
			eye_w = 7 * scale
			eye_h = 7 * scale
		CustomizationScript.EyeShape.CLOSED:
			eye_w = 8 * scale
			eye_h = 2 * scale

	# Left eye
	var eye_l = ColorRect.new()
	eye_l.color = eye_color
	eye_l.size = Vector2(eye_w, eye_h)
	eye_l.position = Vector2(base_x - 12 * scale, base_y)
	add_child(eye_l)

	# Right eye
	var eye_r = ColorRect.new()
	eye_r.color = eye_color
	eye_r.size = Vector2(eye_w, eye_h)
	eye_r.position = Vector2(base_x + 4 * scale, base_y)
	add_child(eye_r)

	# Eye highlights (for non-closed)
	if customization.eye_shape != CustomizationScript.EyeShape.CLOSED:
		var hl_l = ColorRect.new()
		hl_l.color = Color(1.0, 1.0, 1.0, 0.8)
		hl_l.size = Vector2(2 * scale, 2 * scale)
		hl_l.position = Vector2(base_x - 10 * scale, base_y + 1 * scale)
		add_child(hl_l)

		var hl_r = ColorRect.new()
		hl_r.color = Color(1.0, 1.0, 1.0, 0.8)
		hl_r.size = Vector2(2 * scale, 2 * scale)
		hl_r.position = Vector2(base_x + 6 * scale, base_y + 1 * scale)
		add_child(hl_r)


func _create_eyebrows(scale: float) -> void:
	var brow_color = customization.hair_color.darkened(0.3)
	var base_x = _portrait_size.x / 2
	var base_y = 16 * scale

	var brow_w = 8 * scale
	var brow_h = 2 * scale

	match customization.eyebrow_style:
		CustomizationScript.EyebrowStyle.NORMAL:
			brow_w = 8 * scale
			brow_h = 2 * scale
		CustomizationScript.EyebrowStyle.THICK:
			brow_w = 9 * scale
			brow_h = 3 * scale
		CustomizationScript.EyebrowStyle.THIN:
			brow_w = 8 * scale
			brow_h = 1 * scale
		CustomizationScript.EyebrowStyle.ARCHED:
			brow_w = 8 * scale
			brow_h = 2 * scale
			base_y -= 1 * scale

	var brow_l = ColorRect.new()
	brow_l.color = brow_color
	brow_l.size = Vector2(brow_w, brow_h)
	brow_l.position = Vector2(base_x - 13 * scale, base_y)
	add_child(brow_l)

	var brow_r = ColorRect.new()
	brow_r.color = brow_color
	brow_r.size = Vector2(brow_w, brow_h)
	brow_r.position = Vector2(base_x + 4 * scale, base_y)
	add_child(brow_r)


func _create_nose(scale: float) -> void:
	var nose_color = customization.skin_tone.darkened(0.12)
	var base_x = _portrait_size.x / 2
	var base_y = 28 * scale

	var nose_w = 4 * scale
	var nose_h = 6 * scale

	match customization.nose_shape:
		CustomizationScript.NoseShape.NORMAL:
			nose_w = 4 * scale
			nose_h = 6 * scale
		CustomizationScript.NoseShape.SMALL:
			nose_w = 3 * scale
			nose_h = 4 * scale
		CustomizationScript.NoseShape.POINTED:
			nose_w = 3 * scale
			nose_h = 8 * scale
		CustomizationScript.NoseShape.BROAD:
			nose_w = 6 * scale
			nose_h = 5 * scale

	var nose = ColorRect.new()
	nose.color = nose_color
	nose.size = Vector2(nose_w, nose_h)
	nose.position = Vector2(base_x - nose_w / 2, base_y)
	add_child(nose)


func _create_mouth(scale: float) -> void:
	var base_x = _portrait_size.x / 2
	var base_y = 36 * scale

	var mouth_w = 8 * scale
	var mouth_h = 3 * scale
	var mouth_color = Color(0.6, 0.3, 0.3)

	match customization.mouth_style:
		CustomizationScript.MouthStyle.NEUTRAL:
			mouth_w = 8 * scale
			mouth_h = 2 * scale
			mouth_color = Color(0.55, 0.3, 0.3)
		CustomizationScript.MouthStyle.SMILE:
			mouth_w = 12 * scale
			mouth_h = 4 * scale
			mouth_color = Color(0.65, 0.35, 0.35)
		CustomizationScript.MouthStyle.FROWN:
			mouth_w = 10 * scale
			mouth_h = 3 * scale
			mouth_color = Color(0.5, 0.25, 0.25)
		CustomizationScript.MouthStyle.SMIRK:
			mouth_w = 8 * scale
			mouth_h = 3 * scale
			mouth_color = Color(0.6, 0.32, 0.32)

	var mouth = ColorRect.new()
	mouth.color = mouth_color
	mouth.size = Vector2(mouth_w, mouth_h)
	mouth.position = Vector2(base_x - mouth_w / 2, base_y)
	add_child(mouth)


func _get_job_color(job: String) -> Color:
	match job:
		"fighter": return Color(0.7, 0.3, 0.3)
		"white_mage": return Color(0.9, 0.9, 0.95)
		"black_mage": return Color(0.3, 0.3, 0.6)
		"thief": return Color(0.3, 0.6, 0.3)
		"red_mage": return Color(0.7, 0.3, 0.5)
		"monk": return Color(0.6, 0.4, 0.2)
		_: return Color(0.4, 0.4, 0.5)


## Static helper to create a portrait quickly
static func create(custom, job: String = "fighter", size: PortraitSize = PortraitSize.MEDIUM) -> Control:
	var script = load("res://src/ui/CharacterPortrait.gd")
	var portrait = script.new(custom, job, size)
	return portrait
