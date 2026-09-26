class_name ItemIcons
extends RefCounted

## 16x16 grayscale icons, tinted per item. Black outline stays black. Every id resolves.

const DIR := "res://assets/sprites/ui/item_icons/"
const DEFAULT_KEY := "pouch"

const NAMED_KEYS := {
	"potion": "potion",
	"hi_potion": "potion",
	"mega_potion": "potion",
	"x_potion": "potion",
	"ether": "ether",
	"hi_ether": "ether",
	"mega_ether": "ether",
	"elixir": "elixir",
	"megalixir": "elixir",
	"tent": "tent",
	"power_drink": "tonic",
	"speed_tonic": "tonic",
	"defense_tonic": "tonic",
	"magic_tonic": "tonic",
	"waterskin": "tonic",
	"smoke_bomb": "smoke",
	"repel": "repel",
	"antidote": "antidote",
	"remedy": "antidote",
	"echo_herbs": "herb",
	"eye_drops": "antidote",
	"gold_needle": "antidote",
	"phoenix_down": "phoenix",
	"bomb_fragment": "bomb",
	"arctic_wind": "gem",
	"lightning_bolt": "bolt",
	"holy_water": "tonic",
}

const NAMED_TINTS := {
	"potion": Color(0.92, 0.22, 0.24),
	"hi_potion": Color(1.0, 0.55, 0.15),
	"mega_potion": Color(1.0, 0.82, 0.2),
	"x_potion": Color(0.75, 0.12, 0.18),
	"elixir": Color(0.95, 0.88, 0.45),
	"megalixir": Color(1.0, 0.95, 0.7),
	"ether": Color(0.35, 0.62, 1.0),
	"hi_ether": Color(0.25, 0.4, 0.95),
	"mega_ether": Color(0.2, 0.28, 0.85),
	"tent": Color(0.85, 0.55, 0.3),
	"power_drink": Color(0.95, 0.3, 0.25),
	"speed_tonic": Color(0.4, 0.9, 0.45),
	"defense_tonic": Color(0.45, 0.6, 0.95),
	"magic_tonic": Color(0.7, 0.4, 0.95),
	"smoke_bomb": Color(0.75, 0.78, 0.82),
	"repel": Color(0.55, 0.85, 0.4),
	"antidote": Color(0.35, 0.82, 0.35),
	"remedy": Color(0.95, 0.8, 0.3),
	"echo_herbs": Color(0.4, 0.75, 0.35),
	"eye_drops": Color(0.45, 0.75, 0.95),
	"gold_needle": Color(0.95, 0.82, 0.35),
	"phoenix_down": Color(1.0, 0.5, 0.18),
	"bomb_fragment": Color(0.9, 0.35, 0.2),
	"arctic_wind": Color(0.55, 0.85, 1.0),
	"lightning_bolt": Color(1.0, 0.9, 0.35),
	"holy_water": Color(1.0, 0.92, 0.55),
}

## First matching snake-segment wins. "bow" matches wooden_bow, not rainbow.
const KEYWORDS := [
	["feather", "phoenix"],
	["repel", "repel"],
	["potion", "potion"],
	["ether", "ether"],
	["elixir", "elixir"],
	["tonic", "tonic"],
	["drink", "tonic"],
	["herb", "herb"],
	["antidote", "antidote"],
	["smoke", "smoke"],
	["bomb", "bomb"],
	["bolt", "bolt"],
	["scroll", "scroll"],
	["scythe", "scythe"],
	["dagger", "dagger"],
	["sword", "sword"],
	["staff", "staff"],
	["bow", "bow"],
	["axe", "axe"],
	["shield", "shield"],
	["helmet", "helmet"],
	["helm", "helmet"],
	["robe", "robe"],
	["garb", "robe"],
	["armor", "armor"],
	["mail", "armor"],
	["vest", "armor"],
	["shard", "gem"],
	["crystal", "gem"],
	["prism", "gem"],
	["core", "gem"],
	["gem", "gem"],
	["gear", "gear"],
	["cog", "gear"],
	["scrap", "gear"],
	["circuit", "gear"],
	["wrench", "gear"],
	["valve", "gear"],
	["spring", "gear"],
	["pipe", "gear"],
	["plate", "gear"],
	["scale", "trophy"],
	["fang", "trophy"],
	["horn", "trophy"],
	["hide", "trophy"],
	["wing", "trophy"],
	["tail", "trophy"],
	["bone", "trophy"],
	["shell", "trophy"],
	["key", "key"],
	["token", "key"],
	["trophy", "key"],
	["badge", "key"],
]

const TINT_WORDS := [
	["fire", Color(1.0, 0.42, 0.18)],
	["flame", Color(1.0, 0.42, 0.18)],
	["ember", Color(1.0, 0.45, 0.2)],
	["ice", Color(0.45, 0.82, 1.0)],
	["frost", Color(0.55, 0.88, 1.0)],
	["arctic", Color(0.45, 0.82, 1.0)],
	["lightning", Color(1.0, 0.92, 0.35)],
	["thunder", Color(1.0, 0.92, 0.35)],
	["storm", Color(0.7, 0.75, 1.0)],
	["shadow", Color(0.62, 0.4, 0.85)],
	["void", Color(0.55, 0.3, 0.75)],
	["dark", Color(0.5, 0.35, 0.7)],
	["holy", Color(1.0, 0.92, 0.55)],
	["poison", Color(0.45, 0.85, 0.3)],
	["plague", Color(0.4, 0.7, 0.25)],
	["gold", Color(1.0, 0.82, 0.28)],
	["mythril", Color(0.7, 0.9, 0.95)],
	["bone", Color(0.9, 0.86, 0.75)],
	["iron", Color(0.75, 0.78, 0.82)],
	["bronze", Color(0.8, 0.55, 0.3)],
	["copper", Color(0.85, 0.5, 0.28)],
	["brass", Color(0.9, 0.75, 0.35)],
	["coal", Color(0.45, 0.45, 0.5)],
	["rust", Color(0.75, 0.4, 0.22)],
	["wood", Color(0.65, 0.45, 0.25)],
	["oak", Color(0.55, 0.38, 0.2)],
]

const ELEMENT_TINTS := {
	"fire": Color(1.0, 0.42, 0.2),
	"ice": Color(0.5, 0.85, 1.0),
	"lightning": Color(1.0, 0.9, 0.35),
	"dark": Color(0.55, 0.35, 0.75),
	"holy": Color(1.0, 0.95, 0.65),
	"poison": Color(0.45, 0.8, 0.3),
	"earth": Color(0.7, 0.5, 0.28),
	"wind": Color(0.6, 0.95, 0.75),
}

const PALETTE: Array[Color] = [
	Color(0.92, 0.32, 0.28),
	Color(0.35, 0.65, 1.0),
	Color(0.4, 0.82, 0.4),
	Color(1.0, 0.78, 0.28),
	Color(0.72, 0.42, 0.95),
	Color(1.0, 0.55, 0.22),
	Color(0.9, 0.9, 0.95),
	Color(0.95, 0.48, 0.68),
]

static var _base: Dictionary = {}
static var _tinted: Dictionary = {}


static func icon_key(item_id: String) -> String:
	if item_id == "":
		return DEFAULT_KEY
	if NAMED_KEYS.has(item_id):
		return str(NAMED_KEYS[item_id])
	var explicit := _explicit_key(item_id)
	if explicit != "":
		return explicit
	var equipped := _equipment_key(item_id)
	if equipped != "":
		return equipped
	if _is_ability(item_id):
		return "scroll"
	var from_effects := _effect_key(_item(item_id))
	if from_effects != "":
		return from_effects
	var from_words := _keyword_key(item_id)
	if from_words != "":
		return from_words
	var item := _item(item_id)
	if not item.is_empty() and item.has("category"):
		match int(item["category"]):
			0:
				return "potion"
			1:
				return "tonic"
			2:
				return "antidote"
			3:
				return "bomb"
			4:
				return "key"
			_:
				return "key"
	return DEFAULT_KEY


static func tint_color(item_id: String) -> Color:
	if NAMED_TINTS.has(item_id):
		return NAMED_TINTS[item_id]
	var visual := _visual_tint(item_id)
	if visual.a > 0.0:
		return visual
	var element := _element_tint(item_id)
	if element.a > 0.0:
		return element
	for pair in TINT_WORDS:
		if _segment_has(item_id, str(pair[0])):
			return pair[1]
	return PALETTE[posmod(item_id.hash(), PALETTE.size())]


static func texture_for_key(key: String) -> Texture2D:
	var use := key if _png_exists(key) else DEFAULT_KEY
	if _base.has(use):
		return _base[use]
	# load() so the export packs the icon; Image.load on the png is dropped from the pck.
	var loaded: Variant = load(png_path(use))
	var tex: Texture2D = loaded if loaded is Texture2D else _placeholder()
	_base[use] = tex
	return tex


static func tinted(item_id: String) -> Texture2D:
	if _tinted.has(item_id):
		return _tinted[item_id]
	var base := texture_for_key(icon_key(item_id))
	var img := base.get_image()
	if img == null:
		_tinted[item_id] = base
		return base
	img = img.duplicate()
	var c := tint_color(item_id)
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			if p.a < 0.01:
				continue
			if p.r < 0.08 and p.g < 0.08 and p.b < 0.08:
				continue
			img.set_pixel(x, y, Color(p.r * c.r, p.g * c.g, p.b * c.b, p.a))
	var tex := ImageTexture.create_from_image(img)
	_tinted[item_id] = tex
	return tex


static func make_rect(item_id: String, px: int) -> TextureRect:
	var rect := TextureRect.new()
	rect.name = "ItemIcon"
	rect.texture = tinted(item_id)
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(px, px)
	rect.size = Vector2(px, px)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


static func apply_button(btn: Button, item_id: String) -> void:
	if item_id == "":
		return
	btn.icon = tinted(item_id)
	btn.expand_icon = true
	btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	btn.add_theme_constant_override("icon_max_width", 32)


static func png_path(key: String) -> String:
	return DIR + key + ".png"


static func _png_exists(key: String) -> bool:
	return key != "" and FileAccess.file_exists(png_path(key))


static func _placeholder() -> Texture2D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.85, 0.75, 0.4, 1))
	for x in 16:
		img.set_pixel(x, 0, Color.BLACK)
		img.set_pixel(x, 15, Color.BLACK)
	for y in 16:
		img.set_pixel(0, y, Color.BLACK)
		img.set_pixel(15, y, Color.BLACK)
	return ImageTexture.create_from_image(img)


static func _autoload(node_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(node_name)


static func _item(item_id: String) -> Dictionary:
	var items := _autoload("ItemSystem")
	if items == null or not items.has_method("get_item"):
		return {}
	var data = items.get_item(item_id)
	if data is Dictionary:
		return data
	return {}


static func _ability(item_id: String) -> Dictionary:
	var jobs := _autoload("JobSystem")
	if jobs == null or not jobs.has_method("get_ability"):
		return {}
	var data = jobs.get_ability(item_id)
	if data is Dictionary:
		return data
	return {}


static func _is_ability(item_id: String) -> bool:
	return not _ability(item_id).is_empty()


static func _equip_dict(item_id: String) -> Dictionary:
	var eq := _autoload("EquipmentSystem")
	if eq == null:
		return {}
	for pool_name in ["weapons", "armors", "accessories"]:
		var pool = eq.get(pool_name)
		if pool is Dictionary and (pool as Dictionary).has(item_id):
			var entry = (pool as Dictionary)[item_id]
			if entry is Dictionary:
				return entry
	return {}


static func _equipment_key(item_id: String) -> String:
	var eq := _autoload("EquipmentSystem")
	if eq == null:
		return ""
	var weapons = eq.get("weapons")
	if weapons is Dictionary and (weapons as Dictionary).has(item_id):
		var wtype := str(((weapons as Dictionary)[item_id] as Dictionary).get("weapon_type", "sword"))
		if wtype == "piano_scythe":
			return "scythe"
		if _png_exists(wtype):
			return wtype
		return "sword"
	var armors = eq.get("armors")
	if armors is Dictionary and (armors as Dictionary).has(item_id):
		return _armor_shape(item_id)
	var acc = eq.get("accessories")
	if acc is Dictionary and (acc as Dictionary).has(item_id):
		return "accessory"
	return ""


static func _armor_shape(item_id: String) -> String:
	if _segment_has(item_id, "robe") or _segment_has(item_id, "garb"):
		return "robe"
	if _segment_has(item_id, "helm") or _segment_has(item_id, "helmet"):
		return "helmet"
	if _segment_has(item_id, "shield"):
		return "shield"
	return "armor"


static func _explicit_key(item_id: String) -> String:
	for data in [_item(item_id), _equip_dict(item_id), _ability(item_id)]:
		var key := str(data.get("icon", ""))
		if key != "" and _png_exists(key):
			return key
	return ""


static func _effect_key(data: Dictionary) -> String:
	var effects: Variant = data.get("effects", {})
	if not (effects is Dictionary):
		return ""
	var fx: Dictionary = effects
	if bool(fx.get("revive", false)):
		return "phoenix"
	if fx.has("repel_steps"):
		return "repel"
	var heals_hp := fx.has("heal_hp") or fx.has("heal_hp_percent")
	var heals_mp := fx.has("heal_mp") or fx.has("heal_mp_percent")
	if heals_hp and heals_mp:
		return "elixir"
	if heals_mp:
		return "ether"
	if heals_hp:
		return "potion"
	if fx.has("cure_status") or bool(fx.get("cure_all_status", false)):
		return "antidote"
	if fx.has("add_buff"):
		return "tonic"
	if fx.has("damage"):
		return "bomb"
	return ""


static func _keyword_key(item_id: String) -> String:
	for pair in KEYWORDS:
		if _segment_has(item_id, str(pair[0])):
			return str(pair[1])
	return ""


static func _element_tint(item_id: String) -> Color:
	var data := _ability(item_id)
	var element := str(data.get("element", ""))
	if ELEMENT_TINTS.has(element):
		return ELEMENT_TINTS[element]
	return Color.TRANSPARENT


static func _visual_tint(item_id: String) -> Color:
	var vis: Variant = _equip_dict(item_id).get("visual", {})
	if not (vis is Dictionary):
		return Color.TRANSPARENT
	for key in ["blade_color", "gem_color", "wood_color"]:
		var raw = (vis as Dictionary).get(key, null)
		if raw is Array and (raw as Array).size() >= 3:
			var c := Color(float(raw[0]), float(raw[1]), float(raw[2]))
			if maxf(c.r, maxf(c.g, c.b)) < 0.45:
				c = c.lerp(Color.WHITE, 0.45)
			c.a = 1.0
			return c
	return Color.TRANSPARENT


static func _segment_has(item_id: String, word: String) -> bool:
	for part in item_id.split("_"):
		if part == word or part.begins_with(word):
			return true
	return false
