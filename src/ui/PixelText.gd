extends Node2D
class_name PixelText

## Retro glyphs for floating battle text (struktured 2026-11-02: "more pixel 16 bit esque ... a retro feel but
## with capabilities a retro device couldn't"). A hand-authored 5x7 face (project-owned, no third-party license),
## baked once per character into a tiny texture with a 1px dark outline and a 1px drop shadow, then drawn at
## INTEGER scale with nearest filtering so it never blurs. Readability comes from the outline, not smoothing.
## Each glyph is its own Sprite2D so callers can stagger, pop and shake them one at a time.

const ROWS := 7
const OUTLINE := Color(0.05, 0.03, 0.09, 1.0)
const SHADOW := Color(0.0, 0.0, 0.0, 0.55)
const SPACE_COLS := 3
const UNKNOWN := "?"

const GLYPHS := {
	"0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
	"1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
	"2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
	"3": ["#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###."],
	"4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
	"5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
	"6": ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
	"7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
	"8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
	"9": [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],
	"A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
	"C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
	"D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
	"E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
	"F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
	"G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".####"],
	"H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"I": [".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."],
	"J": ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
	"K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
	"L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
	"M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
	"N": ["#...#", "#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#"],
	"O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
	"Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
	"R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
	"S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
	"T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
	"U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
	"W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "#.#.#", ".#.#."],
	"X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
	"Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
	"Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
	"+": [".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."],
	"-": [".....", ".....", ".....", "#####", ".....", ".....", "....."],
	"%": ["##..#", "##..#", "...#.", "..#..", ".#...", "#..##", "#..##"],
	"!": ["#", "#", "#", "#", "#", ".", "#"],
	"?": [".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#.."],
	".": [".", ".", ".", ".", ".", ".", "#"],
	",": [".", ".", ".", ".", ".", "#", "#"],
	"'": ["#", "#", ".", ".", ".", ".", "."],
	":": [".", "#", ".", ".", ".", "#", "."],
	"—": [".....", ".....", ".....", "#####", ".....", ".....", "....."],
	"x": [".....", ".....", "#...#", ".#.#.", "..#..", ".#.#.", "#...#"],
}

static var _cache: Dictionary = {}

var text: String = ""
var pixel_scale: Vector2i = Vector2i(3, 3)
var glyph_sprites: Array[Sprite2D] = []
var _advances: Array[int] = []


func _init(t: String = "", px: int = 3) -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	text = t
	pixel_scale = Vector2i(maxi(1, px), maxi(1, px))
	_build()


static func can_draw(ch: String) -> bool:
	return ch == " " or GLYPHS.has(ch) or GLYPHS.has(ch.to_upper())


## Unknown characters draw as "?" rather than vanishing, so a missing glyph is visible on screen.
static func _rows_for(ch: String) -> Array:
	if GLYPHS.has(ch):
		return GLYPHS[ch]
	if GLYPHS.has(ch.to_upper()):
		return GLYPHS[ch.to_upper()]
	return GLYPHS[UNKNOWN]


## A white glyph with its outline and shadow baked in; tinting is the caller's modulate (the dark rim survives it).
static func glyph_texture(ch: String) -> ImageTexture:
	if _cache.has(ch):
		return _cache[ch]
	var rows: Array = _rows_for(ch)
	var w: int = str(rows[0]).length()
	var img := Image.create(w + 3, ROWS + 3, false, Image.FORMAT_RGBA8)
	var ink := {}
	for y in ROWS:
		for x in w:
			if str(rows[y])[x] == "#":
				ink[Vector2i(x + 1, y + 1)] = true
	var rim := {}
	for p in ink:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var q: Vector2i = p + Vector2i(dx, dy)
				if not ink.has(q):
					rim[q] = true
	for p in rim.keys() + ink.keys():
		var s: Vector2i = p + Vector2i(1, 1)
		if not ink.has(s) and not rim.has(s):
			img.set_pixelv(s, SHADOW)
	for p in rim:
		img.set_pixelv(p, OUTLINE)
	for p in ink:
		img.set_pixelv(p, Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	_cache[ch] = tex
	return tex


## The unscaled cell extent of a string, for laying out before (or without) building it; base_size() of a built one.
static func measure(t: String) -> Vector2i:
	var w := 0
	for i in t.length():
		w += SPACE_COLS if t[i] == " " else str(_rows_for(t[i])[0]).length() + 1
	return Vector2i(maxi(0, w - 1) + 2, ROWS + 2)


func set_text(t: String) -> void:
	text = t
	_build()


## Integer steps only: a pop or squash is a whole-pixel change, never a blur.
func set_pixel_scale(sx: int, sy: int = -1) -> void:
	pixel_scale = Vector2i(maxi(1, sx), maxi(1, sy if sy > 0 else sx))
	_layout()


func base_size() -> Vector2i:
	var w := 0
	for a in _advances:
		w += a
	return Vector2i(maxi(0, w - 1) + 2, ROWS + 2)


func _build() -> void:
	for s in glyph_sprites:
		if is_instance_valid(s):
			s.free()
	glyph_sprites.clear()
	_advances.clear()
	for i in text.length():
		var ch: String = text[i]
		if ch == " ":
			_advances.append(SPACE_COLS)
			continue
		var spr := Sprite2D.new()
		spr.centered = false
		spr.texture = glyph_texture(ch)
		spr.set_meta("char", ch)
		add_child(spr)
		glyph_sprites.append(spr)
		_advances.append(str(_rows_for(ch)[0]).length() + 1)
	_layout()


func _layout() -> void:
	var size := base_size()
	var x0: int = -int(size.x * pixel_scale.x / 2)
	var y0: int = -int(size.y * pixel_scale.y / 2)
	var cursor := 0
	var gi := 0
	for i in text.length():
		if text[i] != " ":
			var spr: Sprite2D = glyph_sprites[gi]
			spr.scale = Vector2(pixel_scale)
			spr.position = Vector2(x0 + cursor * pixel_scale.x, y0)
			gi += 1
		cursor += _advances[i]


## Where a glyph rests; a hop animation offsets from here in whole pixels.
func rest_position(spr: Sprite2D) -> Vector2:
	var gi := glyph_sprites.find(spr)
	if gi < 0:
		return spr.position
	var size := base_size()
	var cursor := 0
	var seen := 0
	for i in text.length():
		if text[i] != " ":
			if seen == gi:
				break
			seen += 1
		cursor += _advances[i]
	return Vector2(-int(size.x * pixel_scale.x / 2) + cursor * pixel_scale.x, -int(size.y * pixel_scale.y / 2))
