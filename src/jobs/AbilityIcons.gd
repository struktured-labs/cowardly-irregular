class_name AbilityIcons
extends RefCounted

## 16x16 grayscale ability icons, tinted per ability — the item icons' twin. Every id resolves.
## The KEY comes from the ability's own data (element, then type, then a support effect), never a hand list.

const DIR := "res://assets/sprites/ui/ability_icons/"
## Only an ability no rule matches lands here — test_every_ability_has_an_icon reds on it.
const DEFAULT_KEY := "unknown"

## Exceptions only: an id here beats every rule.
const NAMED_KEYS := {}

const ELEMENT_KEYS: Array[String] = ["fire", "ice", "lightning", "dark", "holy", "poison", "earth", "wind"]

const TYPE_KEYS := {
	"magic": "arcane",
	"healing": "cure",
	"revival": "phoenix",
	"mp_restore": "ether",
	"summon": "summon",
	"song": "song",
	"meta": "meta",
	"escape": "escape",
	"physical": "strike",
}

## Support effects that impair rather than weaken read as an ailment.
const STATUS_EFFECTS: Array[String] = [
	"stun", "blind", "sleep", "confuse", "silence", "doom", "taunt", "poison", "burn",
	"freeze", "charm", "petrify", "slow", "stop", "berserk", "paralyze",
]

## Non-elemental icons; elemental ones use ItemIcons.ELEMENT_TINTS so the two sets agree.
const KEY_TINTS := {
	"arcane": Color(0.75, 0.63, 1.0),
	"cure": Color(0.43, 0.86, 0.47),
	"phoenix": Color(1.0, 0.5, 0.18),
	"ether": Color(0.35, 0.62, 1.0),
	"summon": Color(0.67, 0.43, 0.94),
	"song": Color(0.95, 0.48, 0.68),
	"meta": Color(0.9, 0.35, 0.9),
	"escape": Color(0.86, 0.88, 0.92),
	"strike": Color(0.8, 0.82, 0.86),
	"buff": Color(1.0, 0.82, 0.31),
	"debuff": Color(0.82, 0.35, 0.43),
	"status": Color(1.0, 0.88, 0.35),
	"dispel": Color(0.43, 0.88, 0.92),
	"unknown": Color(0.63, 0.63, 0.63),
}

static var _base: Dictionary = {}
static var _tinted: Dictionary = {}
static var _animated: Dictionary = {}
static var _driver_on: bool = false
const MAXIMUS_FRAMES := 8
const MAXIMUS_FRAME_MSEC := 110


static func icon_key(ability_id: String) -> String:
	if NAMED_KEYS.has(ability_id):
		return str(NAMED_KEYS[ability_id])
	return key_for(_ability(ability_id))


## The rule on the data alone: element first, then type, then a support ability's effect.
static func key_for(data: Dictionary) -> String:
	var element := str(data.get("element", ""))
	if element in ELEMENT_KEYS:
		return element
	var type := str(data.get("type", ""))
	if TYPE_KEYS.has(type):
		return str(TYPE_KEYS[type])
	if type == "support":
		var effect := str(data.get("effect", ""))
		if effect in STATUS_EFFECTS:
			return "status"
		if effect == "dispel":
			return "dispel"
		if effect.contains("_down"):
			return "debuff"
		return "buff"
	return DEFAULT_KEY


static func tint_color(ability_id: String) -> Color:
	var element := str(_ability(ability_id).get("element", ""))
	if element in ELEMENT_KEYS and ItemIcons.ELEMENT_TINTS.has(element):
		return ItemIcons.ELEMENT_TINTS[element]
	return KEY_TINTS.get(icon_key(ability_id), KEY_TINTS[DEFAULT_KEY])


static func png_path(key: String) -> String:
	return DIR + key + ".png"


static func texture_for_key(key: String) -> Texture2D:
	## ResourceLoader, not FileAccess: an export packs the imported icon, not the png, so file_exists drew "?" for every ability.
	var use := key if key != "" and ResourceLoader.exists(png_path(key)) else DEFAULT_KEY
	if _base.has(use):
		return _base[use]
	# load() so the export packs the icon; Image.load on the png is dropped from the pck.
	var loaded: Variant = load(png_path(use))
	var tex: Texture2D = loaded if loaded is Texture2D else _placeholder()
	_base[use] = tex
	return tex


static func tinted(ability_id: String) -> Texture2D:
	if _tinted.has(ability_id):
		return _tinted[ability_id]
	var base := texture_for_key(icon_key(ability_id))
	var img := base.get_image()
	if img == null:
		_tinted[ability_id] = base
		return base
	img = img.duplicate()
	var c := tint_color(ability_id)
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			if p.a < 0.01 or (p.r < 0.08 and p.g < 0.08 and p.b < 0.08):
				continue
			img.set_pixel(x, y, Color(p.r * c.r, p.g * c.g, p.b * c.b, p.a))
	var tier := tier_of(ability_id)
	if tier >= 2:
		img = _with_echo(img, c)
	if tier >= 3:
		var frames := _maximus_frames(img, c)
		var anim := ImageTexture.create_from_image(frames[0])
		_animated[ability_id] = {"tex": anim, "frames": frames, "shown": 0}
		_start_driver()
		_tinted[ability_id] = anim
		return anim
	var tex := ImageTexture.create_from_image(img)
	_tinted[ability_id] = tex
	return tex


## The ability's power tier from its own data (Ignis 1, Maior 2, Maximus 3); 0 when it has none.
static func tier_of(ability_id: String) -> int:
	return int(_ability(ability_id).get("tier", 0))


## Tier 2 reads "doubled": a hot echo 2px behind the glyph plus a white glint, without growing taller.
static func _with_echo(src: Image, c: Color) -> Image:
	var out := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	var hot := c.lightened(0.35)
	for y in src.get_height():
		for x in src.get_width():
			var p := src.get_pixel(x, y)
			if p.a > 0.5 and x - 2 >= 0:
				out.set_pixel(x - 2, y, Color(hot.r, hot.g, hot.b, 0.45))
	out.blend_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), Vector2i.ZERO)
	for g in [Vector2i(14, 0), Vector2i(15, 1), Vector2i(13, 1)]:
		if out.get_pixelv(g).a < 0.5:
			out.set_pixelv(g, Color(1, 1, 1, 0.95 if g == Vector2i(14, 0) else 0.6))
	return out


## Tier 3 animates: a gold outline, a halo that breathes, and a sparkle that twinkles across two corners.
static func _maximus_frames(src: Image, c: Color) -> Array[Image]:
	var frames: Array[Image] = []
	var gold := Color(1.0, 0.84, 0.3)
	## A gold rim on an already-gold glyph (lightning) erases its edge, so those keep the dark outline.
	var rim_gold: bool = Vector3(c.r - gold.r, c.g - gold.g, c.b - gold.b).length() > 0.35
	for f in MAXIMUS_FRAMES:
		var img: Image = src.duplicate()
		var w: int = img.get_width()
		var h: int = img.get_height()
		var pulse := 0.25 + 0.55 * (0.5 + 0.5 * sin(TAU * float(f) / MAXIMUS_FRAMES))
		for y in h:
			for x in w:
				var p := src.get_pixel(x, y)
				if rim_gold and p.a > 0.5 and p.r < 0.08 and p.g < 0.08 and p.b < 0.08:
					img.set_pixel(x, y, gold.darkened(0.25 * (1.0 - pulse)))
				elif p.a < 0.1 and _touches_ink(src, x, y):
					img.set_pixel(x, y, Color(c.r, c.g, c.b, pulse))
		var star: Vector2i = Vector2i(13, 2) if f < MAXIMUS_FRAMES / 2 else Vector2i(2, 13)
		var arm: int = [0, 1, 2, 1, 0, 1, 2, 1][f % 8]
		img.set_pixelv(star, Color.WHITE)
		for d in range(1, arm + 1):
			for o in [Vector2i(d, 0), Vector2i(-d, 0), Vector2i(0, d), Vector2i(0, -d)]:
				var q: Vector2i = star + o
				if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h:
					img.set_pixelv(q, Color(1, 1, 1, 0.9 if d == 1 else 0.55))
		frames.append(img)
	return frames


static func _touches_ink(img: Image, x: int, y: int) -> bool:
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var q: Vector2i = Vector2i(x, y) + o
		if q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height() and img.get_pixelv(q).a > 0.5:
			return true
	return false


## One per-frame driver swaps every Maximus icon's pixels in place, so every row holding that texture animates.
static func _start_driver() -> void:
	if _driver_on:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	tree.process_frame.connect(_tick_animated)
	_driver_on = true


static func _tick_animated() -> void:
	var f := int(Time.get_ticks_msec() / MAXIMUS_FRAME_MSEC) % MAXIMUS_FRAMES
	for id in _animated:
		var a: Dictionary = _animated[id]
		if int(a["shown"]) != f:
			(a["tex"] as ImageTexture).update(a["frames"][f])
			a["shown"] = f


static func make_rect(ability_id: String, px: int) -> TextureRect:
	var rect := TextureRect.new()
	rect.name = "AbilityIcon"
	rect.texture = tinted(ability_id)
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(px, px)
	rect.size = Vector2(px, px)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## The name every menu shows. A raw `id.capitalize()` prints "Fire" for the spell the menus call "Ignis".
static func name_of(ability_id: String) -> String:
	var name := str(_ability(ability_id).get("name", ""))
	return name if name != "" else ability_id.capitalize()


## Icon at a grid cell's left edge, vertically centred. The cell's label is left alone: an autowrapped Label
## will not shrink below its measured width, so moving it only pushes a centred name out the right side.
static func attach_to_cell(cell: Control, ability_id: String, px: int = 16) -> TextureRect:
	var icon := make_rect(ability_id, px)
	var h: float = maxf(cell.custom_minimum_size.y, cell.size.y)
	icon.position = Vector2(4, floorf((h - px) / 2.0))
	cell.add_child(icon)
	return icon


static func apply_button(btn: Button, ability_id: String) -> void:
	if ability_id == "":
		return
	btn.icon = tinted(ability_id)
	btn.expand_icon = true
	btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	btn.add_theme_constant_override("icon_max_width", 32)


static func _placeholder() -> Texture2D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(KEY_TINTS[DEFAULT_KEY])
	return ImageTexture.create_from_image(img)


static func _ability(ability_id: String) -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return {}
	var jobs := tree.root.get_node_or_null("JobSystem")
	if jobs == null or not jobs.has_method("get_ability"):
		return {}
	var data = jobs.get_ability(ability_id)
	return data if data is Dictionary else {}
