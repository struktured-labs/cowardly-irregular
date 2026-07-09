extends BaseInterior
class_name MapleCommunityCenterInterior

## Maple Heights municipal lobby — beige/corkboard/fluorescent office where three W2 quests route through the front desk.

const COMMUNITY_CENTER_LAYOUT = [
	"WWWWWWWWWWWWWWWWWWWW",
	"W..................W",
	"W.P............FFF.W",
	"W..............FFF.W",
	"W.........Q........W",
	"W.....CCCCCCCCC....W",
	"W....N..........X..W",
	"W..................W",
	"W.O................W",
	"W.H.H.H............W",
	"W..H.H.H...........W",
	"W..H.H.............W",
	"W..................W",
	"WWWWWWWWWDDWWWWWWWWW",
]

var _copier_frames: Array[ImageTexture] = []
var _copier_sprite: Sprite2D
var _copier_frame: int = 0
var _copier_timer: float = 0.0
const COPIER_BLINK_SPEED: float = 0.4

var _lamp_lights: Array[PointLight2D] = []
var _light_time: float = 0.0


func _get_area_id() -> String:
	return "maple_community_center"


func _get_display_name() -> String:
	return "Community Center"


func _get_ambient_key() -> String:
	return "ambient_office"


func _get_map_width() -> int:
	return 20


func _get_map_height() -> int:
	return 14


func _get_layout() -> Array:
	return COMMUNITY_CENTER_LAYOUT


func _init_spawn_points() -> void:
	spawn_points["entrance"] = Vector2(9.5, 12)
	spawn_points["counter"] = Vector2(10, 6.3)
	# Cols 2-6 of the north wall stay bare corkboard — quest system anchors its bulletin board node here.
	spawn_points["bulletin"] = Vector2(4, 1.4)


func _get_music_track() -> String:
	return "village"


func _draw_floor_tile(image: Image) -> void:
	var tile = Color(0.80, 0.76, 0.63)
	var tile_alt = Color(0.83, 0.79, 0.66)
	var grout = Color(0.63, 0.58, 0.47)
	var scuff = Color(0.52, 0.49, 0.43)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var seam = (x % 16 == 0) or (y % 16 == 0)
			var block = ((x / 16) + (y / 16)) % 2
			var scuff_mark = (x * 7 + y * 13) % 53 == 0
			if seam:
				image.set_pixel(x, y, grout)
			elif scuff_mark:
				image.set_pixel(x, y, scuff)
			else:
				image.set_pixel(x, y, tile if block == 0 else tile_alt)


func _draw_wall_tile(image: Image) -> void:
	var cork = Color(0.68, 0.54, 0.35)
	var cork_dark = Color(0.58, 0.45, 0.28)
	var cork_light = Color(0.78, 0.64, 0.44)
	var frame = Color(0.42, 0.32, 0.19)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var panel_edge = (x % 16 == 0) or (y % 16 == 0)
			var fleck_dark = (x * 3 + y * 7) % 17 == 0
			var fleck_light = (x * 5 + y * 2) % 23 == 0
			if panel_edge:
				image.set_pixel(x, y, frame)
			elif fleck_dark:
				image.set_pixel(x, y, cork_dark)
			elif fleck_light:
				image.set_pixel(x, y, cork_light)
			else:
				image.set_pixel(x, y, cork)


func _process(delta: float) -> void:
	_animate_copier_jam(delta)
	_breathe_lamps(delta)


func _setup_decorations() -> void:
	super._setup_decorations()
	_create_ambient_tint()
	_create_front_counter()
	_create_take_a_number_dispenser()
	_create_take_a_number_sign()
	_create_now_serving_display()
	_create_employee_of_the_quarter_wall()
	_create_civic_banner()
	_create_wall_clock()
	_create_org_chart()
	_create_filing_cabinets()
	_create_jammed_copier()
	_create_venetian_blind_window(Vector2(0, 3))
	_create_venetian_blind_window(Vector2(0, 9))
	_create_potted_plastic_ficus()
	_create_water_cooler()
	_create_waiting_chairs()
	_create_magazine_table()
	_create_ceiling_fluorescents()
	_create_corkboard_flyers()
	_create_suggestion_box()
	_create_pamphlet_rack()
	_create_baseboard_heater()
	_create_you_are_here_map()
	_create_entry_mat()
	_create_trophy_case()
	_create_pen_on_chain()
	_create_recycling_calendar()


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
	tint.name = "OfficeTint"
	tint.color = Color(0.95, 0.97, 0.93)
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


# ---- Furniture ----

func _create_front_counter() -> void:
	var gx = 6
	var gy = 5
	var w = 9 * TILE_SIZE
	var h = 40
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var laminate = Color(0.58, 0.42, 0.28)
	var laminate_dark = Color(0.44, 0.32, 0.20)
	var countertop = Color(0.72, 0.70, 0.66)
	var countertop_edge = Color(0.55, 0.53, 0.50)
	for y in range(14, h):
		for x in range(w):
			img.set_pixel(x, y, laminate if (x / 8 + y / 6) % 2 == 0 else laminate_dark)
	for y in range(8, 14):
		for x in range(w):
			img.set_pixel(x, y, countertop_edge if y == 8 or y == 13 else countertop)
	var glass = Color(0.75, 0.85, 0.90, 0.35)
	for panel in range(3):
		var px = 20 + panel * 90
		for y in range(0, 8):
			for x in range(px, px + 70):
				if x < w:
					img.set_pixel(x, y, glass)
	var sprite = Sprite2D.new()
	sprite.name = "FrontCounter"
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(gx * TILE_SIZE, gy * TILE_SIZE - 8)
	decorations.add_child(sprite)


func _create_take_a_number_dispenser() -> void:
	var img = Image.create(14, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var post = Color(0.35, 0.34, 0.36)
	var post_dark = Color(0.22, 0.22, 0.24)
	var ticket = Color(0.92, 0.88, 0.60)
	for y in range(6, 20):
		img.set_pixel(6, y, post_dark)
		img.set_pixel(7, y, post)
	for y in range(0, 8):
		for x in range(1, 13):
			img.set_pixel(x, y, post if (x + y) % 5 != 0 else post_dark)
	for i in range(3):
		img.set_pixel(4 + i, 3, ticket)
	var sprite = Sprite2D.new()
	sprite.name = "NumberDispenser"
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(5 * TILE_SIZE + 10, 6 * TILE_SIZE + 8)
	decorations.add_child(sprite)


func _create_take_a_number_sign() -> void:
	var img = Image.create(30, 12, false, Image.FORMAT_RGBA8)
	var board = Color(0.90, 0.88, 0.80)
	var board_edge = Color(0.65, 0.62, 0.54)
	for y in range(12):
		for x in range(30):
			img.set_pixel(x, y, board_edge if (x == 0 or y == 0 or x == 29 or y == 11) else board)
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(5 * TILE_SIZE - 8, 6 * TILE_SIZE - 12)
	decorations.add_child(sprite)

	var label = Label.new()
	label.text = "PLEASE TAKE A NUMBER"
	label.position = Vector2(4.3 * TILE_SIZE, 5.75 * TILE_SIZE)
	label.add_theme_font_size_override("font_size", 6)
	label.add_theme_color_override("font_color", Color(0.35, 0.33, 0.28))
	decorations.add_child(label)


func _create_now_serving_display() -> void:
	var img = Image.create(40, 16, false, Image.FORMAT_RGBA8)
	var casing = Color(0.15, 0.15, 0.16)
	var led_off = Color(0.25, 0.08, 0.08)
	var led_on = Color(0.95, 0.20, 0.15)
	for y in range(16):
		for x in range(40):
			img.set_pixel(x, y, casing)
	var digit_cols = [4, 14, 24]
	var lit = [true, false, true]
	for i in range(3):
		var dx = digit_cols[i]
		var c = led_on if lit[i] else led_off
		for y in range(3, 13):
			for x in range(dx, dx + 8):
				if (x + y) % 4 != 0:
					img.set_pixel(x, y, c)
	var sprite = Sprite2D.new()
	sprite.name = "NowServingDisplay"
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(9 * TILE_SIZE, 3 * TILE_SIZE + 20)
	decorations.add_child(sprite)

	var label = Label.new()
	label.text = "NOW SERVING"
	label.position = Vector2(9.2 * TILE_SIZE, 3 * TILE_SIZE + 2)
	label.add_theme_font_size_override("font_size", 6)
	label.add_theme_color_override("font_color", Color(0.70, 0.68, 0.60))
	decorations.add_child(label)


func _create_employee_of_the_quarter_wall() -> void:
	var cols = 7
	var rows = 2
	var frame_w = 16
	var frame_h = 18
	var w = cols * frame_w
	var h = rows * frame_h
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var frame_gold = Color(0.62, 0.52, 0.24)
	var frame_gold_dark = Color(0.46, 0.38, 0.16)
	var photo_bg = Color(0.55, 0.68, 0.78)
	var skin = Color(0.82, 0.66, 0.52)
	var hair = Color(0.30, 0.24, 0.18)
	var collar = Color(0.85, 0.85, 0.88)
	for row in range(rows):
		for col in range(cols):
			var fx = col * frame_w
			var fy = row * frame_h
			for y in range(fy, fy + frame_h):
				for x in range(fx, fx + frame_w):
					var edge = x == fx or x == fx + frame_w - 1 or y == fy or y == fy + frame_h - 1
					img.set_pixel(x, y, frame_gold_dark if edge else frame_gold)
			for y in range(fy + 2, fy + frame_h - 2):
				for x in range(fx + 2, fx + frame_w - 2):
					img.set_pixel(x, y, photo_bg)
			for y in range(fy + 5, fy + 11):
				for x in range(fx + 5, fx + 11):
					img.set_pixel(x, y, skin)
			for x in range(fx + 4, fx + 12):
				img.set_pixel(x, fy + 4, hair)
			for y in range(fy + 11, fy + frame_h - 2):
				for x in range(fx + 3, fx + frame_w - 3):
					img.set_pixel(x, y, collar)
	var sprite = Sprite2D.new()
	sprite.name = "EmployeeOfTheQuarterWall"
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(9 * TILE_SIZE, 4)
	decorations.add_child(sprite)

	var label = Label.new()
	label.text = "EMPLOYEE OF THE QUARTER"
	label.position = Vector2(9 * TILE_SIZE, h + 6)
	label.add_theme_font_size_override("font_size", 7)
	label.add_theme_color_override("font_color", Color(0.45, 0.36, 0.20))
	decorations.add_child(label)


func _create_civic_banner() -> void:
	var w = TILE_SIZE * 3
	var h = 20
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var cloth = Color(0.30, 0.45, 0.62)
	var cloth_dark = Color(0.22, 0.35, 0.50)
	var gold = Color(0.80, 0.68, 0.30)
	for y in range(h):
		for x in range(w):
			img.set_pixel(x, y, cloth if y < h - 4 else cloth_dark)
	for x in range(0, w, 6):
		img.set_pixel(x, h - 2, gold)
	var sprite = Sprite2D.new()
	sprite.name = "CivicBanner"
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(13 * TILE_SIZE, 6)
	decorations.add_child(sprite)

	var label = Label.new()
	label.text = "MAPLE HEIGHTS COMMUNITY CENTER — SERVING SINCE (SMUDGED)"
	label.position = Vector2(12.4 * TILE_SIZE, 10)
	label.add_theme_font_size_override("font_size", 6)
	label.add_theme_color_override("font_color", Color(0.92, 0.90, 0.80))
	decorations.add_child(label)


func _create_wall_clock() -> void:
	var size = 20
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var rim = Color(0.25, 0.24, 0.22)
	var face = Color(0.92, 0.90, 0.84)
	var hand = Color(0.20, 0.19, 0.18)
	var center = size / 2.0
	for y in range(size):
		for x in range(size):
			var dist = Vector2(x - center, y - center).length()
			if dist <= center:
				img.set_pixel(x, y, rim if dist > center - 1.5 else face)
	_draw_line_on_image(img, Vector2(center, center), Vector2(center + 3, center + 5), hand)
	_draw_line_on_image(img, Vector2(center, center), Vector2(center - 1, center - 8), hand)
	var sprite = Sprite2D.new()
	sprite.name = "WallClockStuckAt459"
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(8 * TILE_SIZE, 10)
	decorations.add_child(sprite)


func _create_org_chart() -> void:
	var w = 30
	var h = 60
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var board = Color(0.88, 0.88, 0.84)
	var board_edge = Color(0.60, 0.60, 0.56)
	var box = Color(0.70, 0.78, 0.86)
	var box_edge = Color(0.40, 0.48, 0.56)
	var line = Color(0.35, 0.35, 0.33)
	for y in range(h):
		for x in range(w):
			img.set_pixel(x, y, board_edge if (x == 0 or y == 0 or x == w - 1 or y == h - 1) else board)
	var boxes = [Vector2(4, 4), Vector2(17, 6), Vector2(6, 22), Vector2(18, 26), Vector2(4, 42), Vector2(17, 46)]
	for b in boxes:
		for y in range(int(b.y), int(b.y) + 8):
			for x in range(int(b.x), int(b.x) + 9):
				if x < w and y < h:
					img.set_pixel(x, y, box_edge if (x == int(b.x) or y == int(b.y)) else box)
	for i in range(boxes.size() - 1):
		var a: Vector2 = boxes[i] + Vector2(4, 8)
		var b: Vector2 = boxes[i + 1] + Vector2(4, 0)
		_draw_line_on_image(img, a, b, line)
	var sprite = Sprite2D.new()
	sprite.name = "OrgChart"
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(19 * TILE_SIZE - 6, 5 * TILE_SIZE)
	decorations.add_child(sprite)

	var label = Label.new()
	label.text = "Org Chart (2019)"
	label.position = Vector2(17.6 * TILE_SIZE, 4.5 * TILE_SIZE)
	label.add_theme_font_size_override("font_size", 6)
	label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.50))
	decorations.add_child(label)


func _create_filing_cabinets() -> void:
	var gx = 15
	var gy = 2
	var w = 3 * TILE_SIZE
	var h = 2 * TILE_SIZE
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var metal = Color(0.58, 0.58, 0.60)
	var metal_dark = Color(0.42, 0.42, 0.45)
	var handle = Color(0.30, 0.30, 0.32)
	for y in range(h):
		for x in range(w):
			img.set_pixel(x, y, metal if (x + y) % 13 != 0 else metal_dark)
	for cab in range(3):
		var cx = cab * TILE_SIZE
		for dy in [0, int(h / 2.0)]:
			for x in range(cx + 2, cx + TILE_SIZE - 2):
				img.set_pixel(x, dy + 2, metal_dark)
			for x in range(cx + 6, cx + 16):
				img.set_pixel(x, dy + 8, handle)
	for y in range(int(h / 2.0) + 2, h - 2):
		for x in range(TILE_SIZE + 4, TILE_SIZE * 2 - 4):
			img.set_pixel(x, y, metal_dark.darkened(0.3))
	var sprite = Sprite2D.new()
	sprite.name = "FilingCabinets"
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(gx * TILE_SIZE, gy * TILE_SIZE)
	decorations.add_child(sprite)


func _create_jammed_copier() -> void:
	_copier_frames.clear()
	for f in range(2):
		var img = Image.create(24, 26, false, Image.FORMAT_RGBA8)
		_draw_copier_frame(img, f)
		_copier_frames.append(ImageTexture.create_from_image(img))
	_copier_sprite = Sprite2D.new()
	_copier_sprite.name = "JammedCopier"
	_copier_sprite.centered = false
	_copier_sprite.texture = _copier_frames[0]
	_copier_sprite.position = Vector2(16 * TILE_SIZE, 6 * TILE_SIZE - 4)
	decorations.add_child(_copier_sprite)


func _draw_copier_frame(img: Image, frame: int) -> void:
	var body = Color(0.68, 0.66, 0.62)
	var body_dark = Color(0.50, 0.48, 0.45)
	var glass = Color(0.25, 0.28, 0.30)
	var paper_jam = Color(0.88, 0.86, 0.80)
	var light_on = Color(0.95, 0.15, 0.15)
	var light_off = Color(0.35, 0.10, 0.10)
	for y in range(26):
		for x in range(24):
			img.set_pixel(x, y, body if (x + y) % 9 != 0 else body_dark)
	for y in range(2, 8):
		for x in range(2, 22):
			img.set_pixel(x, y, glass)
	for y in range(6, 14):
		img.set_pixel(20, y, paper_jam)
		img.set_pixel(21, y, paper_jam)
	var blink = light_on if frame == 0 else light_off
	img.set_pixel(3, 3, blink)
	img.set_pixel(4, 3, blink)


func _animate_copier_jam(delta: float) -> void:
	_copier_timer += delta
	if _copier_timer >= COPIER_BLINK_SPEED:
		_copier_timer -= COPIER_BLINK_SPEED
		_copier_frame = (_copier_frame + 1) % _copier_frames.size()
		if _copier_sprite and _copier_frames.size() > 0:
			_copier_sprite.texture = _copier_frames[_copier_frame]


func _create_venetian_blind_window(anchor: Vector2) -> void:
	var w = 26
	var h = 34
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var frame = Color(0.55, 0.52, 0.46)
	var glass = Color(0.62, 0.72, 0.78)
	var slat_light = Color(0.80, 0.78, 0.70)
	var slat_shadow = Color(0.48, 0.46, 0.42)
	for y in range(h):
		for x in range(w):
			var edge = x < 2 or x >= w - 2 or y < 2 or y >= h - 2
			img.set_pixel(x, y, frame if edge else glass)
	for y in range(4, h - 4, 3):
		var shade = slat_light if (y / 3) % 2 == 0 else slat_shadow
		for x in range(3, w - 3):
			img.set_pixel(x, y, shade)
	var sprite = Sprite2D.new()
	sprite.name = "VenetianWindow_%d" % int(anchor.y)
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = anchor * TILE_SIZE + Vector2(4, 2)
	decorations.add_child(sprite)


func _create_potted_plastic_ficus() -> void:
	var img = Image.create(16, 26, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var pot = Color(0.42, 0.30, 0.20)
	var pot_dark = Color(0.30, 0.20, 0.13)
	var leaf = Color(0.24, 0.42, 0.22)
	var leaf_light = Color(0.32, 0.52, 0.28)
	for y in range(18, 26):
		for x in range(3, 13):
			img.set_pixel(x, y, pot_dark if x < 5 or x > 10 else pot)
	var tips = [Vector2(8, 2), Vector2(3, 6), Vector2(13, 6), Vector2(5, 10), Vector2(11, 10)]
	for tip in tips:
		_draw_line_on_image(img, Vector2(8, 17), tip, leaf)
		if tip.x >= 0 and tip.x < 16 and tip.y >= 0 and tip.y < 26:
			img.set_pixel(int(tip.x), int(tip.y), leaf_light)
	var sprite = Sprite2D.new()
	sprite.name = "PlasticFicus"
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(2 * TILE_SIZE, 2 * TILE_SIZE - 2)
	decorations.add_child(sprite)


func _create_water_cooler() -> void:
	var img = Image.create(14, 30, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var body = Color(0.75, 0.78, 0.80)
	var base = Color(0.55, 0.58, 0.60)
	var jug = Color(0.55, 0.75, 0.85, 0.65)
	var jug_cap = Color(0.30, 0.55, 0.75)
	for y in range(2, 12):
		for x in range(2, 12):
			var dist = Vector2(x - 7, y - 6).length()
			if dist < 5.5:
				img.set_pixel(x, y, jug)
	for x in range(5, 9):
		img.set_pixel(x, 1, jug_cap)
	for y in range(12, 26):
		for x in range(3, 11):
			img.set_pixel(x, y, body)
	for y in range(26, 30):
		for x in range(1, 13):
			img.set_pixel(x, y, base)
	for x in range(4, 7):
		img.set_pixel(x, 20, Color(0.35, 0.34, 0.32))
	var sprite = Sprite2D.new()
	sprite.name = "WaterCooler"
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(2 * TILE_SIZE, 8 * TILE_SIZE - 4)
	decorations.add_child(sprite)


func _create_waiting_chairs() -> void:
	var chair_tiles = [
		Vector2(2, 9), Vector2(4, 9), Vector2(6, 9),
		Vector2(3, 10), Vector2(5, 10), Vector2(7, 10),
		Vector2(3, 11), Vector2(5, 11),
	]
	for gp in chair_tiles:
		_create_plastic_chair(gp)


func _create_plastic_chair(gp: Vector2) -> void:
	var img = Image.create(18, 18, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var plastic = Color(0.65, 0.30, 0.24)
	var plastic_dark = Color(0.48, 0.20, 0.16)
	var leg = Color(0.35, 0.34, 0.32)
	for y in range(2, 10):
		for x in range(2, 16):
			img.set_pixel(x, y, plastic if y < 8 else plastic_dark)
	for x in [3, 14]:
		for y in range(10, 17):
			img.set_pixel(x, y, leg)
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = gp * TILE_SIZE
	decorations.add_child(sprite)


func _create_magazine_table() -> void:
	var img = Image.create(18, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var wood = Color(0.50, 0.38, 0.26)
	var mag_colors = [Color(0.65, 0.30, 0.30), Color(0.35, 0.50, 0.60), Color(0.70, 0.60, 0.25)]
	for y in range(8, 12):
		for x in range(1, 17):
			img.set_pixel(x, y, wood)
	for leg_x in [2, 14]:
		for y in range(12, 16):
			img.set_pixel(leg_x, y, wood.darkened(0.3))
	for i in range(3):
		for x in range(3, 15):
			img.set_pixel(x, 7 - i * 2, mag_colors[i])
	var sprite = Sprite2D.new()
	sprite.name = "MagazineTable"
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(8 * TILE_SIZE, 9 * TILE_SIZE + 6)
	decorations.add_child(sprite)


func _create_ceiling_fluorescents() -> void:
	var light_tex = _create_light_texture(90)
	for gp in [Vector2(6, 2), Vector2(12, 2), Vector2(9, 8)]:
		var lamp = PointLight2D.new()
		lamp.position = gp * TILE_SIZE
		lamp.color = Color(0.88, 0.92, 1.0)
		lamp.energy = 0.30
		lamp.texture = light_tex
		decorations.add_child(lamp)
		_lamp_lights.append(lamp)


func _breathe_lamps(delta: float) -> void:
	_light_time += delta
	for i in range(_lamp_lights.size()):
		var light = _lamp_lights[i]
		if is_instance_valid(light):
			light.energy = 0.30 + 0.04 * sin(_light_time * 1.6 + i * 1.1)


func _create_flyer(anchor: Vector2, paper: Color) -> void:
	var img = Image.create(20, 26, false, Image.FORMAT_RGBA8)
	for y in range(26):
		for x in range(20):
			img.set_pixel(x, y, paper)
	var ink = paper.darkened(0.55)
	for x in range(3, 17):
		if x % 2 == 0:
			img.set_pixel(x, 4, ink)
	for line in range(3):
		for x in range(3, 17):
			if (x + line) % 3 != 0:
				img.set_pixel(x, 8 + line * 3, ink)
	for i in range(6):
		img.set_pixel(2 + i * 3, 24, ink)
	var pin = Color(0.70, 0.15, 0.15)
	img.set_pixel(10, 1, pin)
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.rotation = 0.05
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = anchor * TILE_SIZE
	decorations.add_child(sprite)


func _create_corkboard_flyers() -> void:
	# East of col 6 only — cols 2-6 are the reserved bare-corkboard bulletin band.
	_create_flyer(Vector2(16.3, 1.2), Color(0.85, 0.80, 0.55))
	_create_flyer(Vector2(17.5, 9.3), Color(0.82, 0.70, 0.75))


func _create_suggestion_box() -> void:
	var img = Image.create(16, 14, false, Image.FORMAT_RGBA8)
	var wood = Color(0.40, 0.30, 0.20)
	var wood_dark = Color(0.28, 0.20, 0.13)
	var slot = Color(0.10, 0.09, 0.08)
	for y in range(14):
		for x in range(16):
			img.set_pixel(x, y, wood if (x + y) % 7 != 0 else wood_dark)
	for x in range(4, 12):
		img.set_pixel(x, 2, slot)
	var sprite = Sprite2D.new()
	sprite.name = "SuggestionBox"
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(17 * TILE_SIZE, 11 * TILE_SIZE)
	decorations.add_child(sprite)

	var label = Label.new()
	label.text = "Suggestions (Est. Unopened)"
	label.position = Vector2(15.4 * TILE_SIZE, 11.9 * TILE_SIZE)
	label.add_theme_font_size_override("font_size", 6)
	label.add_theme_color_override("font_color", Color(0.50, 0.44, 0.36))
	decorations.add_child(label)


func _create_pamphlet_rack() -> void:
	var img = Image.create(16, 22, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var wire = Color(0.30, 0.30, 0.32)
	var pamphlets = [Color(0.75, 0.55, 0.30), Color(0.55, 0.70, 0.45), Color(0.70, 0.45, 0.55)]
	for y in range(2, 20):
		img.set_pixel(8, y, wire)
	for i in range(3):
		var py = 3 + i * 6
		for x in range(2, 15):
			img.set_pixel(x, py, pamphlets[i])
		img.set_pixel(2, py - 1, wire)
		img.set_pixel(14, py - 1, wire)
	var sprite = Sprite2D.new()
	sprite.name = "PamphletRack"
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(16 * TILE_SIZE, 11 * TILE_SIZE)
	decorations.add_child(sprite)


func _create_baseboard_heater() -> void:
	var w = TILE_SIZE * 4
	var h = 8
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var metal = Color(0.70, 0.70, 0.68)
	var metal_dark = Color(0.52, 0.52, 0.50)
	for y in range(h):
		for x in range(w):
			img.set_pixel(x, y, metal if x % 4 != 0 else metal_dark)
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(12 * TILE_SIZE, 12 * TILE_SIZE + 24)
	decorations.add_child(sprite)


func _create_you_are_here_map() -> void:
	var img = Image.create(20, 20, false, Image.FORMAT_RGBA8)
	var paper = Color(0.86, 0.84, 0.74)
	var ink = Color(0.30, 0.28, 0.24)
	var dot = Color(0.75, 0.15, 0.15)
	for y in range(20):
		for x in range(20):
			img.set_pixel(x, y, paper)
	for x in range(2, 18):
		img.set_pixel(x, 2, ink)
		img.set_pixel(x, 17, ink)
	for y in range(2, 18):
		img.set_pixel(2, y, ink)
		img.set_pixel(17, y, ink)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			img.set_pixel(10 + dx, 10 + dy, dot)
	var sprite = Sprite2D.new()
	sprite.name = "YouAreHereMap"
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(2 * TILE_SIZE, 12 * TILE_SIZE + 4)
	decorations.add_child(sprite)


func _create_entry_mat() -> void:
	var w = TILE_SIZE * 2
	var h = 14
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var mat = Color(0.34, 0.30, 0.24)
	var mat_dark = Color(0.24, 0.21, 0.17)
	var trim = Color(0.55, 0.50, 0.40)
	for y in range(h):
		for x in range(w):
			var edge = x < 2 or x >= w - 2 or y < 2 or y >= h - 2
			img.set_pixel(x, y, trim if edge else (mat_dark if (x + y) % 6 == 0 else mat))
	var sprite = Sprite2D.new()
	sprite.centered = false
	sprite.z_index = -1
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(8.5 * TILE_SIZE, 12 * TILE_SIZE + 4)
	decorations.add_child(sprite)


func _create_trophy_case() -> void:
	var w = 26
	var h = 24
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var case_frame = Color(0.40, 0.32, 0.20)
	var glass = Color(0.65, 0.75, 0.80, 0.35)
	var trophy = Color(0.75, 0.62, 0.25)
	for y in range(h):
		for x in range(w):
			var edge = x < 2 or x >= w - 2 or y < 2 or y >= h - 2
			img.set_pixel(x, y, case_frame if edge else glass)
	for i in range(3):
		var tx = 5 + i * 7
		for y in range(14, 20):
			img.set_pixel(tx, y, trophy)
		img.set_pixel(tx, 13, trophy)
	var sprite = Sprite2D.new()
	sprite.name = "TrophyCase"
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(1 * TILE_SIZE + 2, 10 * TILE_SIZE)
	decorations.add_child(sprite)

	var label = Label.new()
	label.text = "Participation, 1994-Present"
	label.position = Vector2(0.5 * TILE_SIZE, 10.7 * TILE_SIZE)
	label.add_theme_font_size_override("font_size", 5)
	label.add_theme_color_override("font_color", Color(0.55, 0.48, 0.30))
	decorations.add_child(label)


func _create_pen_on_chain() -> void:
	var img = Image.create(10, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var chain = Color(0.55, 0.54, 0.50)
	var pen = Color(0.15, 0.35, 0.65)
	_draw_line_on_image(img, Vector2(2, 0), Vector2(6, 8), chain)
	for y in range(8, 13):
		img.set_pixel(6, y, pen)
		img.set_pixel(7, y, pen)
	var sprite = Sprite2D.new()
	sprite.name = "PenOnChain"
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(9 * TILE_SIZE + 4, 5 * TILE_SIZE + 2)
	decorations.add_child(sprite)


func _create_recycling_calendar() -> void:
	var w = 20
	var h = 24
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var paper = Color(0.88, 0.90, 0.84)
	var grid = Color(0.55, 0.58, 0.52)
	for y in range(h):
		for x in range(w):
			img.set_pixel(x, y, paper)
	for gy in range(4, h - 2, 4):
		for x in range(2, w - 2):
			img.set_pixel(x, gy, grid)
	for gx in range(2, w - 2, 4):
		for y in range(2, h - 2):
			img.set_pixel(gx, y, grid)
	var sprite = Sprite2D.new()
	sprite.name = "RecyclingCalendar"
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(19 * TILE_SIZE - 4, 9 * TILE_SIZE)
	decorations.add_child(sprite)

	var label = Label.new()
	label.text = "Recycling: Every Other Thursday*"
	label.position = Vector2(17.2 * TILE_SIZE, 8.3 * TILE_SIZE)
	label.add_theme_font_size_override("font_size", 5)
	label.add_theme_color_override("font_color", Color(0.40, 0.42, 0.36))
	decorations.add_child(label)


# ---- NPCs ----

func _setup_npcs() -> void:
	super._setup_npcs()
	_place_quest_fixtures()
	var OverworldNPCScript = load("res://src/exploration/OverworldNPC.gd")
	if not OverworldNPCScript:
		return
	_create_front_desk_clerk(OverworldNPCScript)
	_create_waiting_man(OverworldNPCScript)
	_create_waiting_woman(OverworldNPCScript)
	_create_sleeping_kid(OverworldNPCScript)


# Quest wiring: bulletin-board giver at the reserved corkboard + front-desk multiplexer.
func _place_quest_fixtures() -> void:
	var BoardScript = load("res://src/exploration/BulletinBoard.gd")
	if BoardScript:
		var board = BoardScript.new()
		board.position = spawn_points.get("bulletin", Vector2(4, 1.4)) * TILE_SIZE
		npcs.add_child(board)
	var DeskScript = load("res://src/exploration/CivicFrontDesk.gd")
	if DeskScript:
		var desk = DeskScript.new()
		desk.position = spawn_points.get("counter", Vector2(10, 6.3)) * TILE_SIZE + Vector2(0, TILE_SIZE)
		npcs.add_child(desk)


func _create_front_desk_clerk(NPCScript) -> void:
	# npc_id is quest-critical — QuestSystem keys W2 turn-ins on "front_desk_clerk_w2" exactly.
	var clerk = NPCScript.new()
	clerk.npc_name = "Front Desk Clerk"
	clerk.npc_type = "shopkeeper"
	clerk.npc_id = "front_desk_clerk_w2"
	clerk.facing_direction = 0
	clerk.position = Vector2(10 * TILE_SIZE, 4 * TILE_SIZE)
	clerk.dialogue_lines = [
		"Take a number. The numbers are decorative, but take one.",
		"Someone will be with you. That someone is technically me. I am also someone else's someone. It works out.",
		"The forms are behind you, in front of you, and also, somehow, still at the printer.",
		"I've worked this counter for six years. I don't recommend it. I also don't recommend not working it. There isn't a version of this where I recommend something.",
	]
	npcs.add_child(clerk)


func _create_waiting_man(NPCScript) -> void:
	var gerald = NPCScript.new()
	gerald.npc_name = "Gerald"
	gerald.npc_type = "villager"
	gerald.facing_direction = 0
	gerald.position = Vector2(2 * TILE_SIZE, 9 * TILE_SIZE)
	gerald.dialogue_lines = [
		"I've been sitting here since Tuesday. This chair and I have an understanding now.",
		"They called a number ending in the digit I have. Coincidence. I didn't get up.",
		"This is genuinely one of the better chairs in the building. I've done a lot of research.",
	]
	npcs.add_child(gerald)


func _create_waiting_woman(NPCScript) -> void:
	var denise = NPCScript.new()
	denise.npc_name = "Denise"
	denise.npc_type = "villager"
	denise.facing_direction = 0
	denise.position = Vector2(5 * TILE_SIZE, 10 * TILE_SIZE)
	denise.dialogue_lines = [
		"Section 4C wants my signature. Section 9 also wants my signature, in a font it insists is different from the one I used in 4C.",
		"This is my third copy. The first two are somewhere in this building being wrong in new ways.",
		"*doesn't look up* If you're here for a form, bring a pencil. Not a pen. Trust me.",
	]
	npcs.add_child(denise)


func _create_sleeping_kid(NPCScript) -> void:
	var kid = NPCScript.new()
	kid.npc_name = "Kid, Asleep"
	kid.npc_type = "child"
	kid.facing_direction = 2
	kid.position = Vector2(4 * TILE_SIZE, 11 * TILE_SIZE)
	kid.dialogue_lines = [
		"*snoring*",
		"*mumbles* ...five more minutes, Mom...",
		"*does not wake up*",
	]
	npcs.add_child(kid)


# ---- Transitions ----

func _setup_transitions() -> void:
	super._setup_transitions()
	var AreaTransitionScript = load("res://src/exploration/AreaTransition.gd")
	if not AreaTransitionScript:
		return
	var exit = AreaTransitionScript.new()
	exit.name = "Exit"
	exit.target_map = "maple_heights_village"
	exit.target_spawn = "community_center_exit"
	exit.require_interaction = false
	exit.position = Vector2(9.5 * TILE_SIZE, 13.5 * TILE_SIZE)
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
