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
	var use := key if key != "" and FileAccess.file_exists(png_path(key)) else DEFAULT_KEY
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
	var tex := ImageTexture.create_from_image(img)
	_tinted[ability_id] = tex
	return tex


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
