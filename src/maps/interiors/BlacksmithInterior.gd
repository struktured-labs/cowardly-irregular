extends BaseInterior
class_name BlacksmithInterior

## BlacksmithInterior — "The Forge": a dedicated smithy scene for atmospheric village routing (distinct from ShopInterior's BLACKSMITH shop_type, which is the buy/sell UI).

const MAP_W: int = 22
const MAP_H: int = 14

const SOOT := Color(0.08, 0.07, 0.07)
const IRON_DARK := Color(0.20, 0.19, 0.22)
const IRON := Color(0.32, 0.31, 0.34)
const IRON_LIGHT := Color(0.48, 0.46, 0.50)
const STONE_WARM := Color(0.30, 0.26, 0.24)
const RUST := Color(0.55, 0.28, 0.12)
const EMBER := Color(0.90, 0.35, 0.10)
const EMBER_HOT := Color(1.0, 0.75, 0.25)
const BRASS := Color(0.62, 0.48, 0.24)
const LEATHER := Color(0.34, 0.22, 0.13)
const WOOD := Color(0.38, 0.26, 0.14)
const WOOD_DARK := Color(0.26, 0.17, 0.09)
const STRAW := Color(0.68, 0.58, 0.28)
const PARCHMENT := Color(0.78, 0.70, 0.52)
const WATER := Color(0.28, 0.42, 0.52)
const OIL := Color(0.20, 0.18, 0.10)
const COAL := Color(0.10, 0.10, 0.11)
const BLADE := Color(0.70, 0.72, 0.76)
const BLADE_BRIGHT := Color(0.90, 0.92, 0.95)

## Forge fire animation
var _forge_fire_sprite: Sprite2D
var _forge_fire_frames: Array[ImageTexture] = []
var _forge_fire_frame: int = 0
var _forge_fire_timer: float = 0.0
const FORGE_FIRE_SPEED: float = 0.15

## Forge light — dual sine flicker per the atmosphere brief
var _forge_light: PointLight2D
var _forge_light_time: float = 0.0

## Chimney smoke puffs
var _smoke_sprite: Sprite2D
var _smoke_frames: Array[ImageTexture] = []
var _smoke_frame: int = 0
var _smoke_timer: float = 0.0
const SMOKE_SPEED: float = 0.3

## Hot iron glow resting on the anvil
var _iron_glow_sprite: Sprite2D
var _iron_glow_time: float = 0.0

## Master smith hammer-strike cycle
var _smith_sprite: Sprite2D
var _smith_frames: Array[ImageTexture] = []
var _smith_frame: int = 0
var _smith_timer: float = 0.0
const SMITH_STRIKE_SPEED: float = 0.16
const SMITH_IMPACT_FRAME: int = 2

## Spark flash synced to the smith's impact frame
var _spark_sprite: Sprite2D
var _spark_frames: Array[ImageTexture] = []

## Apprentice bellows-pump cycle
var _apprentice_sprite: Sprite2D
var _apprentice_frames: Array[ImageTexture] = []
var _apprentice_frame: int = 0
var _apprentice_timer: float = 0.0
const APPRENTICE_PUMP_SPEED: float = 0.22


func _get_area_id() -> String:
	return "blacksmith_interior"


func _get_display_name() -> String:
	return "The Forge"


func _get_map_width() -> int:
	return MAP_W


func _get_map_height() -> int:
	return MAP_H


## No smithy-specific music key exists yet, so "village" is the only real fallback SoundManager recognizes.
func _get_music_track() -> String:
	return "village"


func _init_spawn_points() -> void:
	spawn_points["entrance"] = Vector2(10.5, 12)
	spawn_points["forge"] = Vector2(5, 6)


## W = soot-stone wall, . = floor; F/B/A/Q/R/T/S/O/I/H mark decoration zones only (see _setup_decorations, positions are hardcoded there, not parsed from this array).
func _get_layout() -> Array:
	return [
		"W".repeat(MAP_W),
		"W" + ".".repeat(2) + "FFFF" + "." + "QQ" + "." + "RRRRRRR" + "." + "HH" + "W",
		"W" + ".".repeat(2) + "FFFF" + "." + "QQ" + "." + "RRRRRRR" + "." + "HH" + "W",
		"W" + "BB" + "FFFF" + "." + "QQ" + ".".repeat(9) + "HH" + "W",
		"W" + "BB" + "FFFF" + "." + "QQ" + ".".repeat(8) + "TTT" + "W",
		"W" + ".".repeat(17) + "TTT" + "W",
		"W" + "H" + ".".repeat(2) + "AA" + ".".repeat(12) + "TTT" + "W",
		"W" + "H" + ".".repeat(2) + "AA" + ".".repeat(12) + "TTT" + "W",
		"W" + ".".repeat(20) + "W",
		"W" + "SS" + ".".repeat(14) + "IIII" + "W",
		"W" + "SS" + ".".repeat(14) + "IIII" + "W",
		"W" + ".".repeat(16) + "IIII" + "W",
		"W" + ".".repeat(6) + "OO" + ".".repeat(12) + "W",
		"W".repeat(10) + "DD" + "W".repeat(10),
	]


func _draw_floor_tile(image: Image) -> void:
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var seam := (x % 8 == 0) or (y % 8 == 0)
			var soot_patch := (x * 7 + y * 5) % 23 == 0
			var ember_crack := (x * 3 + y * 11) % 61 == 0
			if ember_crack:
				image.set_pixel(x, y, RUST.darkened(0.1))
			elif seam:
				image.set_pixel(x, y, SOOT)
			elif soot_patch:
				image.set_pixel(x, y, IRON_DARK)
			else:
				image.set_pixel(x, y, IRON)


func _draw_wall_tile(image: Image) -> void:
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var row := y / 10
			var offset := 10 if row % 2 == 0 else 0
			var mortar_h := y % 10 == 0
			var mortar_v := (x + offset) % 20 == 0
			var soot_streak := (x * 5 + y) % 29 == 0
			if mortar_h or mortar_v:
				image.set_pixel(x, y, SOOT)
			elif soot_streak:
				image.set_pixel(x, y, IRON_DARK)
			else:
				image.set_pixel(x, y, IRON_DARK if (x + y) % 13 == 0 else STONE_WARM)


func _process(delta: float) -> void:
	_animate_forge_fire(delta)
	_flicker_forge_light(delta)
	_animate_smoke(delta)
	_pulse_iron_glow(delta)
	_animate_smith(delta)
	_animate_apprentice(delta)


func _animate_forge_fire(delta: float) -> void:
	_forge_fire_timer += delta
	if _forge_fire_timer < FORGE_FIRE_SPEED:
		return
	_forge_fire_timer -= FORGE_FIRE_SPEED
	_forge_fire_frame = (_forge_fire_frame + 1) % _forge_fire_frames.size()
	if _forge_fire_sprite and _forge_fire_frames.size() > 0:
		_forge_fire_sprite.texture = _forge_fire_frames[_forge_fire_frame]


## Dual sine wave keeps forge glow energy in the 0.7-1.2 range from the atmosphere brief.
func _flicker_forge_light(delta: float) -> void:
	_forge_light_time += delta
	if _forge_light:
		_forge_light.energy = 0.95 + 0.18 * sin(_forge_light_time * 7.3) + 0.07 * sin(_forge_light_time * 13.1)


func _animate_smoke(delta: float) -> void:
	_smoke_timer += delta
	if _smoke_timer < SMOKE_SPEED:
		return
	_smoke_timer -= SMOKE_SPEED
	_smoke_frame = (_smoke_frame + 1) % _smoke_frames.size()
	if _smoke_sprite and _smoke_frames.size() > 0:
		_smoke_sprite.texture = _smoke_frames[_smoke_frame]


func _pulse_iron_glow(delta: float) -> void:
	_iron_glow_time += delta
	if _iron_glow_sprite:
		_iron_glow_sprite.modulate.a = 0.55 + 0.35 * sin(_iron_glow_time * 4.0)


func _animate_smith(delta: float) -> void:
	_smith_timer += delta
	if _smith_timer < SMITH_STRIKE_SPEED:
		return
	_smith_timer -= SMITH_STRIKE_SPEED
	_smith_frame = (_smith_frame + 1) % _smith_frames.size()
	if _smith_sprite and _smith_frames.size() > 0:
		_smith_sprite.texture = _smith_frames[_smith_frame]
	if _spark_sprite and _spark_frames.size() > 1:
		_spark_sprite.texture = _spark_frames[1] if _smith_frame == SMITH_IMPACT_FRAME else _spark_frames[0]


func _animate_apprentice(delta: float) -> void:
	_apprentice_timer += delta
	if _apprentice_timer < APPRENTICE_PUMP_SPEED:
		return
	_apprentice_timer -= APPRENTICE_PUMP_SPEED
	_apprentice_frame = (_apprentice_frame + 1) % _apprentice_frames.size()
	if _apprentice_sprite and _apprentice_frames.size() > 0:
		_apprentice_sprite.texture = _apprentice_frames[_apprentice_frame]


# ---------------------------------------------------------------------------
# Decorations
# ---------------------------------------------------------------------------

func _setup_decorations() -> void:
	super._setup_decorations()
	_setup_forge()
	_create_anvil()
	_create_quenching_corner()
	_create_weapon_rack()
	_create_tempering_station()
	_create_sword_dummy()
	_create_order_board()
	_create_storage_barrels()
	_create_hanging_weapons()
	_create_ambient_lighting()


func _setup_forge() -> void:
	var center := Vector2(5, 3) * TILE_SIZE
	_forge_fire_sprite = Sprite2D.new()
	_forge_fire_sprite.z_index = 4
	_forge_fire_sprite.position = center
	add_child(_forge_fire_sprite)
	_forge_fire_frames.clear()
	for f in range(3):
		var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
		_draw_forge_frame(img, f)
		_forge_fire_frames.append(ImageTexture.create_from_image(img))
	if _forge_fire_frames.size() > 0:
		_forge_fire_sprite.texture = _forge_fire_frames[0]

	_forge_light = PointLight2D.new()
	_forge_light.position = Vector2(5, 3.6) * TILE_SIZE
	_forge_light.color = Color(1.0, 0.55, 0.18)
	_forge_light.energy = 1.0
	_forge_light.texture = _create_light_texture(220)
	add_child(_forge_light)

	_smoke_sprite = Sprite2D.new()
	_smoke_sprite.z_index = 9
	_smoke_sprite.position = Vector2(5, 1.1) * TILE_SIZE
	add_child(_smoke_sprite)
	_smoke_frames.clear()
	for f in range(3):
		var simg := Image.create(40, 80, false, Image.FORMAT_RGBA8)
		_draw_smoke_frame(simg, f)
		_smoke_frames.append(ImageTexture.create_from_image(simg))
	if _smoke_frames.size() > 0:
		_smoke_sprite.texture = _smoke_frames[0]

	_create_iron_glow(Vector2(5, 6.8) * TILE_SIZE)


## Redraws the full stone body + opening + embers + flames each frame (only 3 frames, cheap) rather than layering a separate overlay, avoiding alignment drift.
func _draw_forge_frame(img: Image, frame: int) -> void:
	img.fill(Color.TRANSPARENT)
	var w := img.get_width()
	var h := img.get_height()
	for y in range(h):
		for x in range(w):
			var block_r := y / 12
			var block_c := x / 14
			var mortar := (y % 12 < 2) or (x % 14 < 2)
			var c := SOOT if mortar else (IRON_LIGHT if (block_r + block_c) % 4 == 0 else IRON)
			img.set_pixel(x, y, c)
	for y in range(0, 20):
		var inset := int((20 - y) * 1.4)
		for x in range(0, inset):
			img.set_pixel(x, y, Color.TRANSPARENT)
			img.set_pixel(w - 1 - x, y, Color.TRANSPARENT)
	var ox := w / 2 - 26
	var oy := h - 64
	var ow := 52
	var oh := 56
	for y in range(oy, oy + oh):
		for x in range(ox, ox + ow):
			img.set_pixel(x, y, Color(0.05, 0.04, 0.04))
	for y in range(oy + oh - 20, oy + oh - 2):
		for x in range(ox + 4, ox + ow - 4):
			var heat := (x * 2 + y * 3 + frame * 5) % 9
			if heat < 2:
				img.set_pixel(x, y, EMBER_HOT)
			elif heat < 5:
				img.set_pixel(x, y, EMBER)
			elif heat < 7:
				img.set_pixel(x, y, RUST)
			else:
				img.set_pixel(x, y, Color(0.15, 0.10, 0.08))
	for fl in range(5):
		var fx := ox + 6 + fl * 10 + ((frame * 3 + fl) % 3) - 1
		var flame_h := 26 + ((frame + fl * 2) % 3) * 8
		for y in range(oy + oh - 22 - flame_h, oy + oh - 18):
			if fx < 0 or fx >= w:
				continue
			var t := float(oy + oh - 18 - y) / float(flame_h + 4)
			var c2 := EMBER_HOT if t > 0.7 else (EMBER if t > 0.35 else RUST)
			_safe_px(img, fx, y, c2)
			_safe_px(img, fx + 1, y, c2)
	for s in range(10):
		var seed := s * 17 + frame * 7
		var sx := ox + (seed % ow)
		var sy := oy + oh - 24 - ((seed * 3 + frame * 11) % 60)
		_safe_px(img, sx, sy, EMBER_HOT if s % 3 == 0 else EMBER)


func _draw_smoke_frame(img: Image, frame: int) -> void:
	img.fill(Color.TRANSPARENT)
	var w := img.get_width()
	var h := img.get_height()
	var puff := Color(0.65, 0.62, 0.60, 0.55)
	var puff_dark := Color(0.45, 0.42, 0.40, 0.45)
	for p in range(3):
		var drift := frame * 5 + p * 3
		var cx := w / 2 + int(sin(float(drift) * 0.4) * 6) + p * 2
		var cy := h - 6 - p * 20 - frame * 4
		var r := 6 + p * 2
		for y in range(cy - r, cy + r):
			for x in range(cx - r, cx + r):
				if x < 0 or x >= w or y < 0 or y >= h:
					continue
				var d := Vector2(x - cx, y - cy).length()
				if d < r:
					img.set_pixel(x, y, puff if d < r * 0.6 else puff_dark)


func _create_iron_glow(pos: Vector2) -> void:
	var img := Image.create(24, 16, false, Image.FORMAT_RGBA8)
	var cx := 12
	var cy := 8
	for y in range(16):
		for x in range(24):
			var d := Vector2(x - cx, y - cy).length()
			var a := clampf(1.0 - d / 10.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 0.5, 0.15, a * 0.85))
	_iron_glow_sprite = Sprite2D.new()
	_iron_glow_sprite.texture = ImageTexture.create_from_image(img)
	_iron_glow_sprite.position = pos
	_iron_glow_sprite.z_index = 6
	add_child(_iron_glow_sprite)


func _create_anvil() -> void:
	var base := Vector2(4, 6) * TILE_SIZE
	_rect(WOOD_DARK, Vector2(64, 8), base + Vector2(0, 44))
	_rect(IRON_DARK, Vector2(56, 14), base + Vector2(4, 30))
	_rect(IRON, Vector2(48, 16), base + Vector2(8, 14))
	_rect(IRON_LIGHT, Vector2(40, 6), base + Vector2(12, 10))
	_rect(Color(0.42, 0.28, 0.15), Vector2(3, 16), base + Vector2(58, 30))
	_rect(IRON, Vector2(10, 8), base + Vector2(56, 26))
	_rect(IRON_LIGHT, Vector2(2, 20), base + Vector2(2, 26))
	_rect(IRON_LIGHT, Vector2(2, 20), base + Vector2(6, 26))


func _create_quenching_corner() -> void:
	var base := Vector2(8, 1) * TILE_SIZE
	_create_barrel(base + Vector2(16, 20), WATER, true)
	_create_barrel(base + Vector2(16, 66), OIL, true)
	_rect(IRON, Vector2(3, 26), base + Vector2(50, 6))
	_rect(IRON, Vector2(3, 26), base + Vector2(55, 6))
	_rect(IRON_LIGHT, Vector2(10, 3), base + Vector2(48, 30))


## Shared wooden-stave barrel silhouette with iron hoops, used for the quenching tubs and the coal store.
func _create_barrel(pos: Vector2, content: Color, filled: bool) -> void:
	var img := Image.create(28, 40, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for y in range(4, 38):
		var bulge := 12 if y > 14 and y < 28 else 9
		for x in range(14 - bulge, 14 + bulge):
			_safe_px(img, x, y, WOOD if (x / 3) % 2 == 0 else WOOD_DARK)
	for hy in [8, 20, 32]:
		for x in range(2, 26):
			_safe_px(img, x, hy, IRON)
	if filled:
		for y in range(5, 9):
			for x in range(5, 23):
				_safe_px(img, x, y, content)
	var node := Sprite2D.new()
	node.texture = ImageTexture.create_from_image(img)
	node.position = pos
	node.z_index = 2
	decorations.add_child(node)


func _create_weapon_rack() -> void:
	var base := Vector2(11, 1) * TILE_SIZE
	var stages := [Color(0.55, 0.30, 0.14), Color(0.45, 0.32, 0.20), Color(0.55, 0.56, 0.58), Color(0.65, 0.67, 0.70), BLADE_BRIGHT]
	for i in range(5):
		var x := base.x + 12 + i * 40
		_rect(WOOD_DARK, Vector2(6, 34), Vector2(x - 3, base.y + 10))
		_rect(stages[i], Vector2(6, 40), Vector2(x - 3, base.y + 6))
		_rect(LEATHER, Vector2(10, 8), Vector2(x - 5, base.y + 40))


func _create_tempering_station() -> void:
	var base := Vector2(18, 4) * TILE_SIZE
	_rect(WOOD_DARK, Vector2(90, 20), base + Vector2(2, 2))
	_rect(WOOD, Vector2(90, 4), base + Vector2(2, 2))
	_rect(IRON, Vector2(3, 14), base + Vector2(10, 6))
	_rect(IRON, Vector2(3, 12), base + Vector2(18, 8))
	_rect(BRASS, Vector2(3, 10), base + Vector2(26, 10))
	_rect(IRON_DARK, Vector2(30, 10), base + Vector2(30, 40))
	_rect(IRON_LIGHT, Vector2(26, 6), base + Vector2(32, 36))
	for i in range(14):
		var cx := base.x + 4 + (i * 7) % 80
		var cy := base.y + 78 + (i * 5) % 34
		_rect(COAL, Vector2(8, 6), Vector2(cx, cy))


func _create_sword_dummy() -> void:
	var base := Vector2(1, 9) * TILE_SIZE
	_rect(WOOD_DARK, Vector2(6, 40), base + Vector2(26, 20))
	_rect(STRAW, Vector2(30, 8), base + Vector2(10, 14))
	_rect(STRAW, Vector2(8, 30), base + Vector2(24, 8))
	_rect(BLADE, Vector2(3, 22), base + Vector2(14, 2))
	_rect(BLADE, Vector2(3, 20), base + Vector2(40, 4))
	_rect(BLADE, Vector2(3, 18), base + Vector2(28, -2))


func _create_order_board() -> void:
	var base := Vector2(7, 11.3) * TILE_SIZE
	_rect(WOOD_DARK, Vector2(60, 40), base)
	_rect(WOOD, Vector2(56, 36), base + Vector2(2, 2))
	var notices := [Vector2(6, 5), Vector2(24, 8), Vector2(10, 20)]
	for n in notices:
		_rect(PARCHMENT, Vector2(20, 14), base + n)
		_rect(WOOD_DARK, Vector2(14, 2), base + n + Vector2(3, 4))
		_rect(WOOD_DARK, Vector2(14, 2), base + n + Vector2(3, 9))


func _create_storage_barrels() -> void:
	var base := Vector2(17, 9) * TILE_SIZE
	_rect(WOOD_DARK, Vector2(30, 26), base + Vector2(2, 4))
	for i in range(3):
		_rect(IRON_LIGHT, Vector2(24, 5), base + Vector2(5, 8 + i * 7))
	_create_barrel(base + Vector2(52, 40), COAL, false)
	for i in range(5):
		_rect(COAL, Vector2(6, 5), base + Vector2(42 + (i % 3) * 8, 24 + (i / 3) * 6))
	for i in range(5):
		_rect(WOOD, Vector2(30, 6), base + Vector2(90, 4 + i * 7))


func _create_hanging_weapons() -> void:
	var east := Vector2(19, 1) * TILE_SIZE
	_hang_weapon(east + Vector2(6, 4), "sword")
	_hang_weapon(east + Vector2(6, 34), "axe")
	_hang_weapon(east + Vector2(6, 64), "spear")
	var west := Vector2(1, 6) * TILE_SIZE
	_hang_weapon(west + Vector2(6, 4), "sword")
	_hang_weapon(west + Vector2(6, 34), "axe")


func _hang_weapon(pos: Vector2, kind: String) -> void:
	_rect(IRON_DARK, Vector2(6, 4), pos)
	match kind:
		"sword":
			_rect(BLADE, Vector2(3, 24), pos + Vector2(1, 4))
			_rect(BRASS, Vector2(9, 3), pos + Vector2(-3, 26))
		"axe":
			_rect(WOOD_DARK, Vector2(3, 24), pos + Vector2(1, 4))
			_rect(IRON_LIGHT, Vector2(12, 10), pos + Vector2(-4, 20))
		"spear":
			_rect(WOOD_DARK, Vector2(3, 30), pos + Vector2(1, 4))
			_rect(BLADE_BRIGHT, Vector2(7, 8), pos + Vector2(-2, 0))


func _create_ambient_lighting() -> void:
	var tex := _create_light_texture(70)
	for corner in [Vector2(2, 11), Vector2(19, 2), Vector2(2, 2)]:
		var l := PointLight2D.new()
		l.position = corner * TILE_SIZE
		l.color = Color(0.55, 0.42, 0.35)
		l.energy = 0.15
		l.texture = tex
		add_child(l)


# ---------------------------------------------------------------------------
# NPCs
# ---------------------------------------------------------------------------

func _setup_npcs() -> void:
	super._setup_npcs()
	_setup_smith()
	_setup_apprentice()
	_setup_knight()
	_setup_delivery_boy()


func _setup_smith() -> void:
	var pos := Vector2(5, 8) * TILE_SIZE
	var smith := _create_npc("Borin Ashhand", "blacksmith", pos, [
		"Borin: *doesn't look up* Mind the sparks. The forge doesn't care whose boots you're wearing.",
		"Borin: Forty years at this anvil. My father's forty before that. We forge in the old ways here.",
		"Borin: Steel remembers how it's beaten. Rush the fold and it remembers that too — brittle, in the end.",
		"Borin: Want something sharp? Come back when the moon's up. Cold steel needs patience.",
		"Borin: *wipes soot from his brow* The roads are getting louder. More coin for me. More worry for everyone else.",
	])
	if smith and smith.sprite:
		smith.sprite.visible = false
	_smith_sprite = Sprite2D.new()
	_smith_sprite.z_index = 6
	_smith_sprite.position = pos
	add_child(_smith_sprite)
	_smith_frames.clear()
	for f in range(4):
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		_draw_smith_frame(img, f)
		_smith_frames.append(ImageTexture.create_from_image(img))
	if _smith_frames.size() > 0:
		_smith_sprite.texture = _smith_frames[0]

	_spark_sprite = Sprite2D.new()
	_spark_sprite.z_index = 8
	_spark_sprite.position = Vector2(5, 6.9) * TILE_SIZE
	add_child(_spark_sprite)
	_spark_frames.clear()
	for f in range(2):
		var simg := Image.create(20, 20, false, Image.FORMAT_RGBA8)
		_draw_spark_frame(simg, f)
		_spark_frames.append(ImageTexture.create_from_image(simg))
	if _spark_frames.size() > 0:
		_spark_sprite.texture = _spark_frames[0]


## 4-frame hammer-strike cycle: raised-back, mid-swing, impact, rebound. Impact angle lines up with SMITH_IMPACT_FRAME so the spark flash fires on contact.
func _draw_smith_frame(img: Image, frame: int) -> void:
	img.fill(Color.TRANSPARENT)
	var w := img.get_width()
	var h := img.get_height()
	var skin := Color(0.75, 0.55, 0.42)
	var apron := LEATHER
	for y in range(h - 18, h):
		for x in range(w / 2 - 10, w / 2 - 2):
			_safe_px(img, x, y, WOOD_DARK)
		for x in range(w / 2 + 2, w / 2 + 10):
			_safe_px(img, x, y, WOOD_DARK)
	for y in range(h - 40, h - 16):
		for x in range(w / 2 - 12, w / 2 + 12):
			_safe_px(img, x, y, apron if (x + y) % 5 != 0 else WOOD_DARK)
	for y in range(h - 50, h - 40):
		for x in range(w / 2 - 6, w / 2 + 6):
			_safe_px(img, x, y, skin)
	var angles := [-100.0, -40.0, 20.0, -20.0]
	var ang := deg_to_rad(angles[frame % 4])
	var shoulder := Vector2(w / 2.0 + 8, h - 38)
	var arm_len := 18.0
	var elbow := shoulder + Vector2(cos(ang), sin(ang)) * arm_len
	for t in range(int(arm_len)):
		var p := shoulder.lerp(elbow, float(t) / arm_len)
		_safe_px(img, int(p.x), int(p.y), skin)
		_safe_px(img, int(p.x) + 1, int(p.y), skin)
	var hx := int(elbow.x)
	var hy := int(elbow.y)
	for dy in range(-4, 5):
		for dx in range(-6, 7):
			_safe_px(img, hx + dx, hy + dy, Color(0.40, 0.39, 0.42))
	for dy in range(-2, 8):
		_safe_px(img, hx, hy + dy, Color(0.42, 0.28, 0.15))


func _setup_apprentice() -> void:
	var pos := Vector2(2, 4.6) * TILE_SIZE
	var apprentice := _create_npc("Feen", "villager", pos, [
		"Feen: *pumping the bellows* Keep... talking... can't stop... arm's on fire...",
		"Feen: Borin says a good bellows-hand can hear the fire breathe. I just hear my own shoulder.",
		"Feen: Three years apprenticed. Two more before he lets me touch the good steel.",
		"Feen: Ask him about the old ways sometime. He loves that. Buys me a minute's rest.",
		"Feen: Honestly? I'd trade this bellows for autobattle scripting. Someone else's arm can hurt instead.",
	])
	if apprentice and apprentice.sprite:
		apprentice.sprite.visible = false
	_apprentice_sprite = Sprite2D.new()
	_apprentice_sprite.z_index = 6
	_apprentice_sprite.position = pos
	add_child(_apprentice_sprite)
	_apprentice_frames.clear()
	for f in range(3):
		var img := Image.create(48, 56, false, Image.FORMAT_RGBA8)
		_draw_apprentice_frame(img, f)
		_apprentice_frames.append(ImageTexture.create_from_image(img))
	if _apprentice_frames.size() > 0:
		_apprentice_sprite.texture = _apprentice_frames[0]


## 3-frame bellow-pump: accordion folds compress/expand as the handle rises and falls.
func _draw_apprentice_frame(img: Image, frame: int) -> void:
	img.fill(Color.TRANSPARENT)
	var h := img.get_height()
	var skin := Color(0.78, 0.60, 0.46)
	var tunic := Color(0.42, 0.34, 0.20)
	var compress := sin(frame * PI * 2.0 / 3.0) * 0.5 + 0.5
	var fold_h := int(lerp(14.0, 7.0, compress))
	var by := h - 26
	for fold in range(4):
		var fx := 2 + fold * 7
		for y in range(by, by + fold_h):
			for x in range(fx, fx + 5):
				_safe_px(img, x, y, LEATHER if fold % 2 == 0 else LEATHER.lightened(0.12))
	for y in range(by + 2, by + fold_h - 2):
		for x in range(0, 3):
			_safe_px(img, x, y, IRON_LIGHT)
	var handle_pos := Vector2(30, by - lerp(12.0, 2.0, compress))
	for dx in range(-14, 4):
		_safe_px(img, int(handle_pos.x) + dx, int(handle_pos.y), WOOD)
	var body_x := 32
	for y in range(h - 40, h - 10):
		for x in range(body_x, body_x + 10):
			_safe_px(img, x, y, tunic)
	for y in range(h - 50, h - 40):
		for x in range(body_x + 1, body_x + 9):
			_safe_px(img, x, y, skin)
	var shoulder := Vector2(body_x + 2, h - 38)
	for t in range(16):
		var p := shoulder.lerp(handle_pos, float(t) / 16.0)
		_safe_px(img, int(p.x), int(p.y), skin)


func _draw_spark_frame(img: Image, frame: int) -> void:
	img.fill(Color.TRANSPARENT)
	if frame == 0:
		return
	var cx := img.get_width() / 2
	var cy := img.get_height() / 2
	for i in range(8):
		var ang := float(i) * PI / 4.0
		var length := 6 + (i % 3) * 2
		for t in range(length):
			var x := cx + int(cos(ang) * t)
			var y := cy + int(sin(ang) * t)
			_safe_px(img, x, y, EMBER_HOT if t < length / 2 else EMBER)
	_safe_px(img, cx, cy, Color(1, 1, 0.8))


func _setup_knight() -> void:
	var pos := Vector2(14, 3) * TILE_SIZE
	var knight := _create_npc("Sir Dallow", "soldier", pos, [
		"Sir Dallow: *turning a blade over in the light* Good balance. Honest steel.",
		"Sir Dallow: I've had three swords notch clean through on the road east this month.",
		"Sir Dallow: Whatever's coming out of that cave, it isn't rats anymore.",
		"Sir Dallow: The smith's prices went up. Can't blame him — demand's demand.",
		"Sir Dallow: If you're heading out there yourself, buy the good steel. Don't be a hero about it.",
	])
	if knight:
		knight.facing_direction = 1


func _setup_delivery_boy() -> void:
	var pos := Vector2(16, 8) * TILE_SIZE
	var boy := _create_npc("Tomm", "child", pos, [
		"Tomm: *hauling a sack* Coal delivery! Careful, this might be the last load for a while.",
		"Tomm: The cart road's gone bad. Da says he's seen eyes in the tree line twice this week.",
		"Tomm: Master Borin pays double for coal that actually arrives on time. Guess why.",
		"Tomm: You're an adventurer, right? Could you maybe... walk the north road sometime? Just to check?",
	])
	if boy:
		boy.facing_direction = 3
	_create_coal_cart(Vector2(17, 8) * TILE_SIZE)


func _create_coal_cart(pos: Vector2) -> void:
	_rect(WOOD_DARK, Vector2(28, 4), pos + Vector2(0, 20))
	_rect(WOOD, Vector2(24, 16), pos + Vector2(2, 4))
	for i in range(8):
		_rect(COAL, Vector2(5, 5), pos + Vector2(4 + (i * 5) % 18, 6 + (i * 3) % 10))
	_rect(IRON_DARK, Vector2(6, 6), pos + Vector2(2, 24))
	_rect(IRON_DARK, Vector2(6, 6), pos + Vector2(18, 24))


# ---------------------------------------------------------------------------
# Transitions
# ---------------------------------------------------------------------------

func _setup_transitions() -> void:
	super._setup_transitions()
	var AreaTransitionScript = load("res://src/exploration/AreaTransition.gd")
	if not AreaTransitionScript:
		return
	var exit = AreaTransitionScript.new()
	exit.name = "Exit"
	exit.target_map = "village_return"
	exit.target_spawn = "blacksmith_exit"
	exit.require_interaction = false
	exit.position = Vector2(10.5 * TILE_SIZE, 13.5 * TILE_SIZE)
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(TILE_SIZE * 2, TILE_SIZE)
	collision.shape = shape
	exit.add_child(collision)
	exit.collision_layer = 4
	exit.collision_mask = 2
	exit.monitoring = true
	exit.transition_triggered.connect(_on_exit_triggered)
	transitions.add_child(exit)


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

func _rect(color: Color, size: Vector2, pos: Vector2) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.size = size
	r.position = pos
	decorations.add_child(r)
	return r


func _safe_px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
		img.set_pixel(x, y, c)


func _create_light_texture(radius: int = 128) -> ImageTexture:
	var size := radius * 2
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := size / 2
	for y in range(size):
		for x in range(size):
			var dist := Vector2(x - center, y - center).length()
			var alpha := clampf(1.0 - dist / float(center), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, alpha * alpha))
	return ImageTexture.create_from_image(img)


func _create_npc(npc_name: String, npc_type: String, pos: Vector2, dialogue: Array) -> Node:
	var OverworldNPCScript = load("res://src/exploration/OverworldNPC.gd")
	if not OverworldNPCScript:
		return null
	var npc = OverworldNPCScript.new()
	npc.npc_name = npc_name
	npc.npc_type = npc_type
	npc.dialogue_lines = dialogue
	npc.position = pos
	npcs.add_child(npc)
	return npc
