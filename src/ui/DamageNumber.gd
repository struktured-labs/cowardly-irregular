extends Node2D
class_name DamageNumber

## Floating damage/heal number that appears near targets

var value: int = 0
var is_heal: bool = false
var is_critical: bool = false
var is_miss: bool = false
var banner_text: String = ""

var _label: PixelText = null
var _lifetime: float = 1.2
var _elapsed: float = 0.0
var _start_pos: Vector2
## The float path; the node itself sits on whole pixels so the glyphs never straddle one.
var _pos: Vector2
var _velocity: Vector2
var _flash_tween: Tween = null
var _polish_tween: Tween = null


func _ready() -> void:
	_start_pos = position
	_pos = position
	position = _pos.round()
	# Random horizontal drift
	_velocity = Vector2(randf_range(-30, 30), -60)
	_create_label()


## struktured 2026-09-07: MP gains are purple, AP grants red, HP heals stay green — "hp" | "mp" | "ap".
var kind: String = "hp"


func setup(amount: int, heal: bool = false, crit: bool = false, resource_kind: String = "hp") -> void:
	value = amount
	is_heal = heal
	is_critical = crit
	kind = resource_kind


func setup_miss() -> void:
	is_miss = true
	value = 0


## Immunity and a ward are not misses. The banner is the word that floats where MISS would.
func setup_banner(text: String) -> void:
	banner_text = text
	is_miss = false
	value = 0


func _create_label() -> void:
	# Pixel pass 2026-11-02 (struktured: "more pixel 16 bit esque"): a 5x7 PixelText at an integer scale, tiered by size and
	# Text Size, replaces the smooth Label. Fatness is the baked outline; tiers step in whole pixels.
	var px: int = BASE_PX
	var text := ""
	var color: Color

	if banner_text != "":
		text = banner_text
		color = Color(0.45, 0.9, 1.0) if banner_text == "BLOCK" else Color(0.78, 0.78, 0.82)
		_lifetime = 0.9
	elif is_miss:
		text = "MISS"
		color = Color(0.65, 0.65, 0.65)
		_lifetime = 0.9
	else:
		text = str(value)

		if value >= 50:
			px = BIG_PX

		if is_critical:
			px += 1

		# Tick 226: color-blind friendly palette swaps green→cyan (heal) and orange→yellow (crit). Both are distinguishable for deuteranopia/protanopia (red-green color blindness, ~5% of males).
		if is_heal:
			color = _heal_color()
			if kind == "mp":
				color = AccessibilityPalette.mp()
				text = "%d MP" % value
			elif kind == "ap":
				color = AccessibilityPalette.ap()
				text = "+%d AP" % value
		elif is_critical:
			color = _crit_color()
		else:
			color = Color.WHITE

	_px = pixel_scale_for(px)
	_label = PixelText.new(text, _px)
	_label.modulate = color
	add_child(_label)

	if is_critical:
		_add_crit_glow(text, color)

	_stagger_in()
	if value >= 50 or is_critical or is_heal:
		_flash_effect()
	if is_critical:
		_crit_wobble_effect()
	elif is_heal:
		_heal_bounce_effect()


const BASE_PX := 3
const BIG_PX := 4


## Text Size scales the glyph pixel, never the texture: TextScale rounds to a whole number, floor 1.
static func pixel_scale_for(px: int) -> int:
	return maxi(1, TextScale.scaled(px))


var _px: int = BASE_PX
var _glow: Array[PixelText] = []


## Each digit lands on its own beat and drops in from above with a whole-pixel overshoot.
func _stagger_in() -> void:
	var i := 0
	for spr in _label.glyph_sprites:
		spr.visible = false
		var t := create_tween()
		t.tween_interval(i * STAGGER_S)
		t.tween_callback(func() -> void: spr.visible = true)
		t.tween_method(func(k: float) -> void: _place_glyph(spr, k), -HOP_PX, 0.0, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		i += 1


const STAGGER_S := 0.035
const HOP_PX := 3.0


func _place_glyph(spr: Sprite2D, k: float) -> void:
	if is_instance_valid(spr) and is_instance_valid(_label):
		spr.position = _label.rest_position(spr) + Vector2(0, roundf(k) * _label.pixel_scale.y)


## Beyond retro: an additive halo of the same glyphs, offset a pixel each way, that pulses out.
func _add_crit_glow(text: String, color: Color) -> void:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var g := PixelText.new(text, _px)
		g.material = mat
		g.use_parent_material = false
		g.modulate = Color(color.r, color.g, color.b, 0.55)
		g.position = Vector2(d * _px)
		g.z_index = -1
		add_child(g)
		_glow.append(g)
	var t := create_tween()
	t.tween_interval(0.08)
	for g in _glow:
		t.parallel().tween_property(g, "modulate:a", 0.0, 0.5)


# Tick 226/228: heal popup color via shared AccessibilityPalette util.
func _heal_color() -> Color:
	return AccessibilityPalette.heal()


# Tick 226/228: crit popup color via shared AccessibilityPalette util.
func _crit_color() -> Color:
	return AccessibilityPalette.crit()


func _flash_effect() -> void:
	"""Pop: one whole pixel bigger, a squash, then back to rest"""
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_callback(func() -> void: _set_px(_px + 1, _px + 1))
	_flash_tween.tween_interval(0.07)
	_flash_tween.tween_callback(func() -> void: _set_px(_px + 1, maxi(1, _px - 1)))
	_flash_tween.tween_interval(0.05)
	_flash_tween.tween_callback(func() -> void: _set_px(_px, _px))


func _set_px(sx: int, sy: int) -> void:
	if is_instance_valid(_label):
		_label.set_pixel_scale(sx, sy)
	for g in _glow:
		if is_instance_valid(g):
			g.set_pixel_scale(sx, sy)


func _crit_wobble_effect() -> void:
	"""Crit: a whole-pixel shake + a colour flash that settles on the crit colour"""
	if _polish_tween and _polish_tween.is_valid():
		_polish_tween.kill()
	_polish_tween = create_tween()
	for step in 8:
		var off := Vector2(randi_range(-1, 1), randi_range(-1, 1)) * _px
		_polish_tween.tween_callback(func() -> void: _shake_to(off))
		_polish_tween.tween_interval(0.03)
	_polish_tween.tween_callback(func() -> void: _shake_to(Vector2.ZERO))
	# Tick 226: crit cycle returns to crit color (ORANGE default, yellow in color-blind mode) for consistency with the initial setup color.
	_polish_tween.parallel().tween_property(_label, "modulate", Color(1.0, 1.0, 0.7), 0.08)
	_polish_tween.tween_property(_label, "modulate", _crit_color(), 0.15)


func _shake_to(off: Vector2) -> void:
	if is_instance_valid(_label):
		_label.position = off


func _heal_bounce_effect() -> void:
	"""Heal numbers rise straight up, floatier than damage"""
	_velocity = Vector2(randf_range(-15.0, 15.0), -90.0)


func _exit_tree() -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = null
	if _polish_tween and _polish_tween.is_valid():
		_polish_tween.kill()
	_polish_tween = null


func _process(delta: float) -> void:
	_elapsed += delta

	# Float upward with deceleration
	# Heals use lighter gravity for a floatier bounce feel
	var gravity = 45.0 if is_heal else 80.0
	_velocity.y += gravity * delta
	_pos += _velocity * delta
	position = _pos.round()

	# Fade out near end
	var fade_start = _lifetime * 0.6
	if _elapsed > fade_start:
		var fade_progress = (_elapsed - fade_start) / (_lifetime - fade_start)
		modulate.a = 1.0 - fade_progress

	# Remove when done
	if _elapsed >= _lifetime:
		queue_free()
