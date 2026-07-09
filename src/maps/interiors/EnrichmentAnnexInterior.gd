extends BaseInterior
class_name EnrichmentAnnexInterior

## Community Enrichment Annex — a repurposed storage building where six Maple Heights kids were "community-transferred".

const ANNEX_LAYOUT = [
	"WWWWWWWWWWWWWWWWWW",
	"W.UUUUUU.........W",
	"W............GGG.W",
	"W............GGG.W",
	"W................W",
	"W......TTT.......D",
	"W................D",
	"W................W",
	"WKK..............W",
	"W................W",
	"W.......N........W",
	"WWWWWWWWDDWWWWWWWW",
]

var _flicker_sprite: Sprite2D
var _flicker_frames: Array[ImageTexture] = []
var _flicker_frame: int = 0
var _flicker_timer: float = 0.0
const FLICKER_SPEED_MIN: float = 0.06
const FLICKER_SPEED_MAX: float = 0.5
var _flicker_light: PointLight2D

var _steady_lights: Array[PointLight2D] = []
var _light_time: float = 0.0


func _get_area_id() -> String:
	return "enrichment_annex"


func _get_display_name() -> String:
	return "Community Enrichment Annex"


func _get_ambient_key() -> String:
	return "ambient_office"


func _get_map_width() -> int:
	return 18


func _get_map_height() -> int:
	return 12


func _get_layout() -> Array:
	return ANNEX_LAYOUT


func _init_spawn_points() -> void:
	spawn_points["entrance"] = Vector2(8.5, 10)
	spawn_points["loading_bay"] = Vector2(16, 6)


func _get_music_track() -> String:
	return "village"


func _draw_floor_tile(image: Image) -> void:
	var vct = Color(0.66, 0.64, 0.50)
	var vct_alt = Color(0.69, 0.67, 0.53)
	var seam = Color(0.40, 0.38, 0.30)
	var fleck_light = Color(0.80, 0.78, 0.70)
	var fleck_dark = Color(0.30, 0.28, 0.24)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var seam_line = (x % 16 == 0) or (y % 16 == 0)
			var block = ((x / 16) + (y / 16)) % 2
			var fleck1 = (x * 5 + y * 11) % 29 == 0
			var fleck2 = (x * 9 + y * 3) % 37 == 0
			if seam_line:
				image.set_pixel(x, y, seam)
			elif fleck1:
				image.set_pixel(x, y, fleck_light)
			elif fleck2:
				image.set_pixel(x, y, fleck_dark)
			else:
				image.set_pixel(x, y, vct if block == 0 else vct_alt)


func _draw_wall_tile(image: Image) -> void:
	var panel = Color(0.72, 0.68, 0.56)
	var panel_dark = Color(0.60, 0.57, 0.46)
	var rib = Color(0.52, 0.50, 0.40)
	var stain = Color(0.56, 0.58, 0.46)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var ribbed = y % 8 == 0
			var bolt = (x % 16 == 4 or x % 16 == 12) and y % 8 == 4
			var wrong = (x * 7 + y * 5) % 61 == 0
			if ribbed:
				image.set_pixel(x, y, rib)
			elif bolt:
				image.set_pixel(x, y, panel_dark)
			elif wrong:
				image.set_pixel(x, y, stain)
			else:
				image.set_pixel(x, y, panel)


func _process(delta: float) -> void:
	_animate_flicker(delta)
	_breathe_steady_lights(delta)


func _setup_decorations() -> void:
	super._setup_decorations()
	_create_ambient_tint()
	_create_fluorescent_fixture(Vector2(4, 2), false)
	_create_fluorescent_fixture(Vector2(9, 2), true)
	_create_fluorescent_fixture(Vector2(14, 6), false)
	_create_cubbies()
	_create_rules_poster()
	_create_motivational_poster(Vector2(9, 0.3), "ENRICHMENT IS", "MANDATORY FUN")
	_create_motivational_poster(Vector2(12.5, 0.3), "YOU ARE WHERE YOU ARE", "SUPPOSED TO BE")
	_create_handless_clock()
	_create_coat_hooks()
	_create_locked_supply_cage()
	_create_craft_table()
	_create_stacked_folding_chairs()
	_create_loading_bay_door()
	_create_signin_clipboard_podium()
	_create_no_running_sign()
	_create_water_stain_patch()
	_create_deflated_balloon()
	_create_exit_sign()
	_create_entry_mat()
	_create_storage_boxes()
	_create_barred_window()
	_create_parent_pickup_sign()
	_create_taped_floor_line()
	_create_sealed_thermostat()


func _create_light_texture(radius: int = 96) -> ImageTexture:
	var size = radius * 2
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center = size / 2
	for y in range(size):
		for x in range(size):
			var dist = Vector2(x - center, y - center).length()
			var alpha = clampf(1.0 - dist / float(center), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, alpha * alpha))
	return ImageTexture.create_from_image(img)


func _create_ambient_tint() -> void:
	var tint = CanvasModulate.new()
	tint.name = "AnnexTint"
	tint.color = Color(0.90, 0.96, 0.88)
	add_child(tint)


func _draw_line_on_image(img: Image, a: Vector2, b: Vector2, c: Color) -> void:
	var steps = int(a.distance_to(b))
	for i in range(steps):
		var t = float(i) / float(max(steps, 1))
		var p = a.lerp(b, t)
		var px = int(p.x)
		var py = int(p.y)
		if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
			img.set_pixel(px, py, c)


# ---- Lighting ----

func _create_fluorescent_fixture(gp: Vector2, flicker: bool) -> void:
	var light_tex = _create_light_texture(80)
	if flicker:
		_flicker_frames.clear()
		for f in range(2):
			var img = Image.create(28, 8, false, Image.FORMAT_RGBA8)
			_draw_tube_frame(img, f)
			_flicker_frames.append(ImageTexture.create_from_image(img))
		_flicker_sprite = Sprite2D.new()
		_flicker_sprite.name = "FlickeringTube"
		_flicker_sprite.texture = _flicker_frames[0]
		_flicker_sprite.position = gp * TILE_SIZE
		decorations.add_child(_flicker_sprite)
		_flicker_light = PointLight2D.new()
		_flicker_light.position = gp * TILE_SIZE
		_flicker_light.color = Color(0.85, 0.92, 1.0)
		_flicker_light.energy = 0.45
		_flicker_light.texture = light_tex
		decorations.add_child(_flicker_light)
	else:
		var img = Image.create(28, 8, false, Image.FORMAT_RGBA8)
		_draw_tube_frame(img, 0)
		var sprite = Sprite2D.new()
		sprite.texture = ImageTexture.create_from_image(img)
		sprite.position = gp * TILE_SIZE
		decorations.add_child(sprite)
		var lamp = PointLight2D.new()
		lamp.position = gp * TILE_SIZE
		lamp.color = Color(0.85, 0.92, 1.0)
		lamp.energy = 0.32
		lamp.texture = light_tex
		decorations.add_child(lamp)
		_steady_lights.append(lamp)


func _draw_tube_frame(img: Image, frame: int) -> void:
	var casing = Color(0.75, 0.75, 0.72)
	var tube_on = Color(0.92, 0.96, 1.0)
	var tube_off = Color(0.55, 0.58, 0.60)
	for x in range(28):
		img.set_pixel(x, 0, casing)
		img.set_pixel(x, 7, casing)
	var tube = tube_on if frame == 0 else tube_off
	for y in range(2, 6):
		for x in range(2, 26):
			img.set_pixel(x, y, tube)


func _animate_flicker(delta: float) -> void:
	_flicker_timer -= delta
	if _flicker_timer <= 0.0:
		_flicker_frame = 1 - _flicker_frame
		if _flicker_sprite and _flicker_frames.size() > 1:
			_flicker_sprite.texture = _flicker_frames[_flicker_frame]
		if _flicker_light:
			_flicker_light.energy = 0.45 if _flicker_frame == 0 else 0.08
		_flicker_timer = randf_range(FLICKER_SPEED_MIN, FLICKER_SPEED_MAX)


func _breathe_steady_lights(delta: float) -> void:
	_light_time += delta
	for i in range(_steady_lights.size()):
		var light = _steady_lights[i]
		if is_instance_valid(light):
			light.energy = 0.32 + 0.03 * sin(_light_time * 1.4 + i)


# ---- Signage ----

func _create_motivational_poster(gp: Vector2, line1: String, line2: String) -> void:
	var w = 24
	var h = 30
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var frame = Color(0.35, 0.34, 0.30)
	var poster_bg = Color(0.30, 0.42, 0.55)
	for y in range(h):
		for x in range(w):
			var edge = x == 0 or y == 0 or x == w - 1 or y == h - 1
			img.set_pixel(x, y, frame if edge else poster_bg)
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = gp * TILE_SIZE
	decorations.add_child(sprite)

	var label1 = Label.new()
	label1.text = line1
	label1.position = gp * TILE_SIZE + Vector2(-6, 10)
	label1.add_theme_font_size_override("font_size", 6)
	label1.add_theme_color_override("font_color", Color(0.95, 0.90, 0.60))
	decorations.add_child(label1)

	var label2 = Label.new()
	label2.text = line2
	label2.position = gp * TILE_SIZE + Vector2(-6, 20)
	label2.add_theme_font_size_override("font_size", 5)
	label2.add_theme_color_override("font_color", Color(0.85, 0.85, 0.82))
	decorations.add_child(label2)


func _create_rules_poster() -> void:
	var w = 22
	var h = 26
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var paper = Color(0.88, 0.86, 0.76)
	var edge = Color(0.55, 0.52, 0.42)
	for y in range(h):
		for x in range(w):
			img.set_pixel(x, y, edge if (x == 0 or y == 0 or x == w - 1 or y == h - 1) else paper)
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(6.3 * TILE_SIZE, 0.4 * TILE_SIZE)
	decorations.add_child(sprite)

	var l1 = Label.new()
	l1.text = "RULE 1: ENRICHMENT IS MANDATORY."
	l1.position = Vector2(5.9 * TILE_SIZE, 0.9 * TILE_SIZE)
	l1.add_theme_font_size_override("font_size", 5)
	l1.add_theme_color_override("font_color", Color(0.25, 0.22, 0.18))
	decorations.add_child(l1)

	var l2 = Label.new()
	l2.text = "RULE 2: SEE RULE 1."
	l2.position = Vector2(5.9 * TILE_SIZE, 1.4 * TILE_SIZE)
	l2.add_theme_font_size_override("font_size", 5)
	l2.add_theme_color_override("font_color", Color(0.25, 0.22, 0.18))
	decorations.add_child(l2)


func _create_cubbies() -> void:
	var gx = 2
	var cols = 6
	var cell_w = 16
	var cell_h = 20
	var w = cols * cell_w
	var img = Image.create(w, cell_h, false, Image.FORMAT_RGBA8)
	var wood = Color(0.58, 0.46, 0.32)
	var wood_dark = Color(0.42, 0.33, 0.22)
	var slot = Color(0.20, 0.17, 0.13)
	for y in range(cell_h):
		for x in range(w):
			img.set_pixel(x, y, wood if (x / cell_w) % 2 == 0 else wood_dark)
	for c in range(cols + 1):
		var lx = c * cell_w
		if lx < w:
			for y in range(cell_h):
				img.set_pixel(lx, y, wood_dark.darkened(0.3))
	for c in range(cols):
		var cx = c * cell_w
		for y in range(4, 14):
			for x in range(cx + 3, cx + cell_w - 3):
				img.set_pixel(x, y, slot)
	var sprite = Sprite2D.new()
	sprite.name = "Cubbies"
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(gx * TILE_SIZE, TILE_SIZE - cell_h)
	decorations.add_child(sprite)
	for c in range(cols):
		var label = Label.new()
		label.text = "PARTICIPANT %d" % (c + 1)
		label.position = Vector2((gx + c * 0.5) * TILE_SIZE, TILE_SIZE + 2)
		label.add_theme_font_size_override("font_size", 4)
		label.add_theme_color_override("font_color", Color(0.40, 0.38, 0.30))
		decorations.add_child(label)


func _create_handless_clock() -> void:
	var size = 18
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var rim = Color(0.30, 0.29, 0.26)
	var face = Color(0.88, 0.86, 0.78)
	var center = size / 2.0
	for y in range(size):
		for x in range(size):
			var dist = Vector2(x - center, y - center).length()
			if dist <= center:
				img.set_pixel(x, y, rim if dist > center - 1.5 else face)
	var sprite = Sprite2D.new()
	sprite.name = "HandlessClock"
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(11 * TILE_SIZE, 8)
	decorations.add_child(sprite)

	var label = Label.new()
	label.text = "TIME ENRICHMENT IN PROGRESS"
	label.position = Vector2(9.8 * TILE_SIZE, 22)
	label.add_theme_font_size_override("font_size", 5)
	label.add_theme_color_override("font_color", Color(0.55, 0.52, 0.42))
	decorations.add_child(label)


func _create_coat_hooks() -> void:
	var w = TILE_SIZE * 2
	var h = 6
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rail = Color(0.42, 0.40, 0.36)
	var hook = Color(0.30, 0.28, 0.25)
	for x in range(w):
		img.set_pixel(x, 1, rail)
	for hx in range(4, w, 10):
		img.set_pixel(hx, 2, hook)
		img.set_pixel(hx, 3, hook)
		img.set_pixel(hx, 4, hook)
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(10 * TILE_SIZE, TILE_SIZE * 4)
	decorations.add_child(sprite)


func _create_no_running_sign() -> void:
	var img = Image.create(20, 10, false, Image.FORMAT_RGBA8)
	var board = Color(0.85, 0.82, 0.30)
	var board_edge = Color(0.55, 0.52, 0.15)
	for y in range(10):
		for x in range(20):
			img.set_pixel(x, y, board_edge if (x == 0 or y == 0 or x == 19 or y == 9) else board)
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(4 * TILE_SIZE, 9 * TILE_SIZE - 4)
	decorations.add_child(sprite)

	var label = Label.new()
	label.text = "NO RUNNING"
	label.position = Vector2(3.5 * TILE_SIZE, 8.85 * TILE_SIZE)
	label.add_theme_font_size_override("font_size", 5)
	label.add_theme_color_override("font_color", Color(0.30, 0.28, 0.10))
	decorations.add_child(label)


# ---- Furniture ----

func _create_locked_supply_cage() -> void:
	var gx = 13
	var gy = 2
	var w = 3 * TILE_SIZE
	var h = 2 * TILE_SIZE
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var wire = Color(0.40, 0.40, 0.42)
	var post = Color(0.30, 0.30, 0.32)
	for y in range(0, h, 6):
		for x in range(w):
			img.set_pixel(x, y, wire)
	for x in range(0, w, 6):
		for y in range(h):
			img.set_pixel(x, y, wire)
	for px in [0, w - 2]:
		for y in range(h):
			img.set_pixel(px, y, post)
			img.set_pixel(px + 1, y, post)
	var lock = Color(0.70, 0.60, 0.25)
	for y in range(int(h / 2.0) - 3, int(h / 2.0) + 3):
		for x in range(int(w / 2.0) - 3, int(w / 2.0) + 3):
			img.set_pixel(x, y, lock)
	var sprite = Sprite2D.new()
	sprite.name = "LockedSupplyCage"
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(gx * TILE_SIZE, gy * TILE_SIZE)
	decorations.add_child(sprite)

	var label = Label.new()
	label.text = "SUPPLY CAGE — LOCKED"
	label.position = Vector2((gx - 0.5) * TILE_SIZE, (gy - 0.4) * TILE_SIZE)
	label.add_theme_font_size_override("font_size", 6)
	label.add_theme_color_override("font_color", Color(0.55, 0.50, 0.30))
	decorations.add_child(label)


func _create_craft_table() -> void:
	var gx = 7
	var gy = 5
	var w = 3 * TILE_SIZE
	var h = 30
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var wood = Color(0.55, 0.42, 0.28)
	var wood_dark = Color(0.42, 0.32, 0.20)
	for y in range(10, 30):
		for x in range(w):
			img.set_pixel(x, y, wood if (x + y) % 11 != 0 else wood_dark)
	var paper = Color(0.92, 0.90, 0.82)
	for i in range(3):
		var px = 6 + i * 28
		for y in range(0, 10):
			for x in range(px, px + 20):
				if x < w:
					img.set_pixel(x, y, paper)
	var sprite = Sprite2D.new()
	sprite.name = "CraftTable"
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(gx * TILE_SIZE, gy * TILE_SIZE - 4)
	decorations.add_child(sprite)
	for i in range(3):
		_create_identical_house_drawing(Vector2(gx * TILE_SIZE + 10 + i * 28, gy * TILE_SIZE - 2))


func _create_identical_house_drawing(pos: Vector2) -> void:
	var img = Image.create(16, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var wall = Color(0.85, 0.55, 0.35)
	var roof = Color(0.65, 0.20, 0.18)
	var door = Color(0.35, 0.22, 0.14)
	for y in range(4, 9):
		for x in range(2, 14):
			img.set_pixel(x, y, wall)
	for x in range(1, 15):
		var peak = 8 - abs(x - 8)
		if peak >= 0:
			img.set_pixel(x, 4 - int(peak / 3.0), roof)
	for y in range(6, 9):
		img.set_pixel(7, y, door)
		img.set_pixel(8, y, door)
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = pos
	decorations.add_child(sprite)


func _create_stacked_folding_chairs() -> void:
	var img = Image.create(16, 28, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var metal = Color(0.55, 0.55, 0.58)
	var metal_dark = Color(0.38, 0.38, 0.42)
	for i in range(6):
		var y = 24 - i * 4
		for x in range(1, 15):
			img.set_pixel(x, y, metal if i % 2 == 0 else metal_dark)
		img.set_pixel(1, y + 1, metal_dark)
		img.set_pixel(14, y + 1, metal_dark)
	var sprite = Sprite2D.new()
	sprite.name = "StackedFoldingChairs"
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(1 * TILE_SIZE + 2, 8 * TILE_SIZE - 12)
	decorations.add_child(sprite)


func _create_loading_bay_door() -> void:
	# East-wall roll-up door, visually paired with the LoadingBayExit AreaTransition (show_gate_visual off there).
	var w = TILE_SIZE
	var h = 2 * TILE_SIZE
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var metal = Color(0.62, 0.60, 0.56)
	var metal_dark = Color(0.46, 0.44, 0.40)
	for y in range(h):
		for x in range(w):
			img.set_pixel(x, y, metal if (y / 4) % 2 == 0 else metal_dark)
	for x in [2, w - 3]:
		for y in range(h):
			img.set_pixel(x, y, metal_dark)
	var sprite = Sprite2D.new()
	sprite.name = "LoadingBayDoor"
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(17 * TILE_SIZE, 5 * TILE_SIZE)
	decorations.add_child(sprite)

	var label = Label.new()
	label.text = "LOADING"
	label.position = Vector2(15.6 * TILE_SIZE, 5.8 * TILE_SIZE)
	label.rotation = -1.5708
	label.add_theme_font_size_override("font_size", 6)
	label.add_theme_color_override("font_color", Color(0.35, 0.33, 0.30))
	decorations.add_child(label)


func _create_signin_clipboard_podium() -> void:
	var img = Image.create(14, 22, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var post = Color(0.40, 0.38, 0.34)
	var board = Color(0.30, 0.28, 0.24)
	var clip = Color(0.65, 0.62, 0.55)
	var paper = Color(0.90, 0.88, 0.80)
	for y in range(8, 22):
		img.set_pixel(6, y, post)
		img.set_pixel(7, y, post)
	for y in range(0, 10):
		for x in range(1, 13):
			img.set_pixel(x, y, paper if y > 1 else board)
	for x in range(4, 10):
		img.set_pixel(x, 1, clip)
	var sprite = Sprite2D.new()
	sprite.name = "SignInPodium"
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(8 * TILE_SIZE, 10 * TILE_SIZE - 2)
	decorations.add_child(sprite)


func _create_water_stain_patch() -> void:
	var size = 16
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var stain = Color(0.50, 0.52, 0.40, 0.55)
	var stain_dark = Color(0.38, 0.40, 0.30, 0.65)
	var center = size / 2.0
	for y in range(size):
		for x in range(size):
			var dist = Vector2(x - center, y - center).length()
			if dist < 7:
				img.set_pixel(x, y, stain if dist < 5 else stain_dark)
	var sprite = Sprite2D.new()
	sprite.name = "WaterStain"
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(14 * TILE_SIZE, 8 * TILE_SIZE)
	decorations.add_child(sprite)


func _create_deflated_balloon() -> void:
	var img = Image.create(10, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var rubber = Color(0.65, 0.30, 0.55)
	var string_c = Color(0.70, 0.68, 0.62)
	for y in range(2, 8):
		for x in range(1, 9):
			var dist = Vector2(x - 5, y - 5).length()
			if dist < 3.5:
				img.set_pixel(x, y, rubber)
	_draw_line_on_image(img, Vector2(5, 8), Vector2(3, 13), string_c)
	var sprite = Sprite2D.new()
	sprite.name = "DeflatedBalloon"
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(15 * TILE_SIZE, 9 * TILE_SIZE)
	decorations.add_child(sprite)


func _create_exit_sign() -> void:
	var img = Image.create(20, 10, false, Image.FORMAT_RGBA8)
	var casing = Color(0.20, 0.20, 0.20)
	var glow = Color(0.85, 0.15, 0.12)
	for y in range(10):
		for x in range(20):
			img.set_pixel(x, y, casing)
	for y in range(2, 8):
		for x in range(2, 18):
			img.set_pixel(x, y, glow)
	var sprite = Sprite2D.new()
	sprite.name = "ExitSign"
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(8 * TILE_SIZE, 8)
	decorations.add_child(sprite)

	var light = PointLight2D.new()
	light.position = Vector2(8.5 * TILE_SIZE, 12)
	light.color = Color(1.0, 0.3, 0.25)
	light.energy = 0.25
	light.texture = _create_light_texture(30)
	decorations.add_child(light)


func _create_entry_mat() -> void:
	var w = TILE_SIZE * 2
	var h = 12
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var mat = Color(0.28, 0.27, 0.24)
	var mat_dark = Color(0.20, 0.19, 0.17)
	for y in range(h):
		for x in range(w):
			img.set_pixel(x, y, mat if (x + y) % 7 != 0 else mat_dark)
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.z_index = -1
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(7.5 * TILE_SIZE, 10 * TILE_SIZE + 6)
	decorations.add_child(sprite)


func _create_storage_boxes() -> void:
	var img = Image.create(20, 22, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var box = Color(0.62, 0.50, 0.32)
	var box_dark = Color(0.48, 0.38, 0.24)
	var label_c = Color(0.85, 0.82, 0.70)
	for i in range(2):
		var by = 10 - i * 10
		for y in range(by, by + 9):
			for x in range(1, 19):
				img.set_pixel(x, y, box if (x + y) % 9 != 0 else box_dark)
		for x in range(4, 16):
			img.set_pixel(x, by + 2, label_c)
	var sprite = Sprite2D.new()
	sprite.name = "StorageBoxes"
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(15 * TILE_SIZE, 8 * TILE_SIZE)
	decorations.add_child(sprite)


func _create_barred_window() -> void:
	var w = 20
	var h = 20
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var frame = Color(0.45, 0.43, 0.38)
	var glass = Color(0.55, 0.62, 0.60)
	var bar = Color(0.25, 0.24, 0.22)
	for y in range(h):
		for x in range(w):
			var edge = x < 2 or x >= w - 2 or y < 2 or y >= h - 2
			img.set_pixel(x, y, frame if edge else glass)
	for x in range(4, w - 4, 4):
		for y in range(2, h - 2):
			img.set_pixel(x, y, bar)
	var sprite = Sprite2D.new()
	sprite.name = "BarredWindow"
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(1 * TILE_SIZE + 2, 4 * TILE_SIZE)
	decorations.add_child(sprite)


func _create_parent_pickup_sign() -> void:
	var img = Image.create(18, 10, false, Image.FORMAT_RGBA8)
	var board = Color(0.85, 0.83, 0.72)
	var board_edge = Color(0.55, 0.53, 0.44)
	for y in range(10):
		for x in range(18):
			img.set_pixel(x, y, board_edge if (x == 0 or y == 0 or x == 17 or y == 9) else board)
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(12 * TILE_SIZE, 9 * TILE_SIZE - 4)
	decorations.add_child(sprite)

	var label = Label.new()
	label.text = "PARENT PICKUP LINE STARTS HERE"
	label.position = Vector2(10.7 * TILE_SIZE, 8.8 * TILE_SIZE)
	label.add_theme_font_size_override("font_size", 4)
	label.add_theme_color_override("font_color", Color(0.30, 0.28, 0.20))
	decorations.add_child(label)


func _create_taped_floor_line() -> void:
	# The queue line the pickup sign promises — painted, then abandoned less than halfway across.
	var w = TILE_SIZE * 2
	var h = 4
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var tape = Color(0.85, 0.75, 0.20)
	for x in range(0, int(w * 0.4)):
		img.set_pixel(x, 1, tape)
		img.set_pixel(x, 2, tape)
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.z_index = -1
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(11 * TILE_SIZE, 9 * TILE_SIZE + 10)
	decorations.add_child(sprite)


func _create_sealed_thermostat() -> void:
	var img = Image.create(12, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var case_c = Color(0.80, 0.78, 0.72)
	var cover = Color(0.55, 0.60, 0.62, 0.55)
	var dial = Color(0.30, 0.28, 0.26)
	for y in range(2, 12):
		for x in range(1, 11):
			img.set_pixel(x, y, case_c)
	for y in range(3, 11):
		for x in range(2, 10):
			img.set_pixel(x, y, cover)
	img.set_pixel(6, 7, dial)
	var sprite = Sprite2D.new()
	sprite.name = "SealedThermostat"
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(6 * TILE_SIZE, 8 * TILE_SIZE)
	decorations.add_child(sprite)


# ---- NPCs ----

func _setup_npcs() -> void:
	super._setup_npcs()
	var OverworldNPCScript = load("res://src/exploration/OverworldNPC.gd")
	if not OverworldNPCScript:
		return
	_create_kid_casper(OverworldNPCScript)
	_create_kid_priya(OverworldNPCScript)
	_create_kid_dev(OverworldNPCScript)
	_create_kid_ashley(OverworldNPCScript)
	_create_kid_kenji(OverworldNPCScript)
	_create_kid_sam(OverworldNPCScript)
	_create_compliance_officer(OverworldNPCScript)
	_place_liberation_zone()


# Quest wiring: the multi-path confrontation zone beside the officer
# (relocated step 3) — also emits annex_found on entry + sends kids home post-rescue.
func _place_liberation_zone() -> void:
	var LibScript = load("res://src/exploration/AnnexLiberation.gd")
	if LibScript:
		var lib = LibScript.new()
		lib.position = Vector2(8 * TILE_SIZE, 9 * TILE_SIZE) + Vector2(TILE_SIZE, TILE_SIZE)
		npcs.add_child(lib)


func _create_kid_casper(NPCScript) -> void:
	# npc_id/npc_name are quest-critical — QuestSystem's wrong_blue giver keys on id "annex_kid_1" + name "Casper".
	var casper = NPCScript.new()
	casper.npc_name = "Casper"
	casper.npc_type = "child"
	casper.npc_id = "annex_kid_1"
	casper.facing_direction = 0
	casper.position = Vector2(8 * TILE_SIZE, 6 * TILE_SIZE)
	casper.dialogue_lines = [
		"They said this is enrichment. I've been enriched for eleven days.",
		"The craft table only has one house you're allowed to draw. I checked.",
		"I'm not scared. I'm just keeping track of things. Somebody should.",
	]
	npcs.add_child(casper)


func _create_kid_priya(NPCScript) -> void:
	var priya = NPCScript.new()
	priya.npc_name = "Priya"
	priya.npc_type = "child"
	priya.npc_id = "annex_kid_2"
	priya.facing_direction = 1
	priya.position = Vector2(10 * TILE_SIZE, 7 * TILE_SIZE)
	priya.dialogue_lines = [
		"Four hundred and six. I've counted twice.",
	]
	npcs.add_child(priya)


func _create_kid_dev(NPCScript) -> void:
	var dev = NPCScript.new()
	dev.npc_name = "Dev"
	dev.npc_type = "child"
	dev.npc_id = "annex_kid_3"
	dev.facing_direction = 0
	dev.position = Vector2(9 * TILE_SIZE, 6 * TILE_SIZE)
	dev.dialogue_lines = [
		"Everyone draws the same house. Nobody told us to. We just all know it.",
	]
	npcs.add_child(dev)


func _create_kid_ashley(NPCScript) -> void:
	var ashley = NPCScript.new()
	ashley.npc_name = "Ashley"
	ashley.npc_type = "child"
	ashley.npc_id = "annex_kid_4"
	ashley.facing_direction = 1
	ashley.position = Vector2(3 * TILE_SIZE, 2 * TILE_SIZE)
	ashley.dialogue_lines = [
		"My cubby says PARTICIPANT 4. I had a name before this. I still do. I just don't say it here.",
	]
	npcs.add_child(ashley)


func _create_kid_kenji(NPCScript) -> void:
	var kenji = NPCScript.new()
	kenji.npc_name = "Kenji"
	kenji.npc_type = "child"
	kenji.npc_id = "annex_kid_5"
	kenji.facing_direction = 3
	kenji.position = Vector2(2 * TILE_SIZE, 8 * TILE_SIZE)
	kenji.dialogue_lines = [
		"If I stack the chairs neatly enough, sometimes they let me stack them again tomorrow.",
	]
	npcs.add_child(kenji)


func _create_kid_sam(NPCScript) -> void:
	var sam = NPCScript.new()
	sam.npc_name = "Sam"
	sam.npc_type = "child"
	sam.npc_id = "annex_kid_6"
	sam.facing_direction = 2
	sam.position = Vector2(13 * TILE_SIZE, 4 * TILE_SIZE)
	sam.dialogue_lines = [
		"The cage has the good crayons. The ones out here are all beige. I don't think that's an accident.",
	]
	npcs.add_child(sam)


func _create_compliance_officer(NPCScript) -> void:
	# npc_id is quest-critical — QuestSystem keys the freeing-the-kids branch on "annex_compliance_officer".
	var officer = NPCScript.new()
	officer.npc_name = "Compliance Officer"
	officer.npc_type = "guard"
	officer.npc_id = "annex_compliance_officer"
	officer.facing_direction = 0
	officer.position = Vector2(8 * TILE_SIZE, 9 * TILE_SIZE)
	officer.dialogue_lines = [
		"Visitation is by Form 12-C appointment. You do not have a Form 12-C.",
		"The children are not missing. They are enrolled. There is a difference, and it is on file.",
		"This facility exceeds every standard we wrote for it ourselves.",
		"I'm going to need you to stand behind the yellow line. There is no yellow line yet. Wait there anyway.",
	]
	npcs.add_child(officer)


# ---- Transitions ----

func _setup_transitions() -> void:
	super._setup_transitions()
	var AreaTransitionScript = load("res://src/exploration/AreaTransition.gd")
	if not AreaTransitionScript:
		return

	var front = AreaTransitionScript.new()
	front.name = "FrontExit"
	front.target_map = "maple_heights_village"
	front.target_spawn = "annex_exit"
	front.require_interaction = false
	front.position = Vector2(8.5 * TILE_SIZE, 11.5 * TILE_SIZE)
	var front_collision = CollisionShape2D.new()
	var front_shape = RectangleShape2D.new()
	front_shape.size = Vector2(TILE_SIZE * 2, TILE_SIZE)
	front_collision.shape = front_shape
	front.add_child(front_collision)
	front.collision_layer = 4
	front.collision_mask = 2
	front.monitoring = true
	front.transition_triggered.connect(_on_exit_triggered)
	transitions.add_child(front)

	# Same target/spawn as the front door — Rogue-lead approach the quest_wiring_notes call out.
	var bay = AreaTransitionScript.new()
	bay.name = "LoadingBayExit"
	bay.target_map = "maple_heights_village"
	bay.target_spawn = "annex_exit"
	bay.require_interaction = false
	bay.show_gate_visual = false
	bay.indicator_text = "Loading Bay"
	bay.position = Vector2(17.5 * TILE_SIZE, 6 * TILE_SIZE)
	var bay_collision = CollisionShape2D.new()
	var bay_shape = RectangleShape2D.new()
	bay_shape.size = Vector2(TILE_SIZE, TILE_SIZE * 2)
	bay_collision.shape = bay_shape
	bay.add_child(bay_collision)
	bay.collision_layer = 4
	bay.collision_mask = 2
	bay.monitoring = true
	bay.transition_triggered.connect(_on_exit_triggered)
	transitions.add_child(bay)
