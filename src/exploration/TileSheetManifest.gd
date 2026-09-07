class_name TileSheetManifest
extends RefCounted
## Artist/AI tile sheets per world: data/sprite_manifest.json["tile_sheets"][key] = {path, tier, tile, tiles{NAME|NAME:variant:[col,row]}, cliff{}, overlay{}, props{NAME:[col,row,w,h]}} — regions in TILE units; anything unnamed falls through to the procedural drawer.

const MANIFEST_PATH := "res://data/sprite_manifest.json"
const SECTIONS := ["tiles", "cliff", "overlay", "props"]
## Sheet key -> generator script that owns the TileType vocabulary
const GENERATOR_KEYS := {
	"medieval": "res://src/exploration/TileGenerator.gd",
	"suburban": "res://src/exploration/SuburbanTileGenerator.gd",
	"steampunk": "res://src/exploration/SteampunkTileGenerator.gd",
	"industrial": "res://src/exploration/IndustrialTileGenerator.gd",
	"futuristic": "res://src/exploration/FuturisticTileGenerator.gd",
	"abstract": "res://src/exploration/AbstractTileGenerator.gd",
}
const CLIFF_NAMES := ["face", "edge_1", "edge_2", "edge_3", "edge_4", "edge_5", "edge_6", "edge_7", "edge_8", "edge_9", "edge_10", "edge_11", "edge_12", "edge_13", "edge_14", "edge_15"]
const OVERLAY_NAMES := ["stair", "ramp", "shadow", "fringe_1", "fringe_2", "fringe_3", "fringe_4", "fringe_5", "fringe_6", "fringe_7", "fringe_8", "fringe_9", "fringe_10", "fringe_11", "fringe_12", "fringe_13", "fringe_14", "fringe_15"]

static var _sheets: Dictionary = {}
static var _images: Dictionary = {}
static var _loaded: bool = false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(MANIFEST_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if parsed is Dictionary and parsed.get("tile_sheets") is Dictionary:
		_sheets = parsed["tile_sheets"]


## Tests inject sheets + decoded images here so no run touches disk
static func set_for_test(sheets: Dictionary, images: Dictionary) -> void:
	_sheets = sheets
	_images = images
	_loaded = true


static func reset_for_test() -> void:
	_sheets = {}
	_images = {}
	_loaded = false


static func has_sheet(key: String) -> bool:
	_load()
	return key != "" and _sheets.has(key)


static func _image_for(path: String) -> Image:
	if _images.has(path):
		return _images[path]
	var img: Image = null
	if path != "" and ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex:
			img = tex.get_image()
	_images[path] = img
	return img


## The named region as a fresh Image, or null when the sheet/section/name is absent (silent) or the region is unusable (warned)
static func region(key: String, section: String, name: String, size_tiles: Vector2i = Vector2i(1, 1)) -> Image:
	if not has_sheet(key):
		return null
	var entry: Dictionary = _sheets[key]
	var sec = entry.get(section)
	if not (sec is Dictionary) or not sec.has(name):
		return null
	var coords = sec[name]
	if not (coords is Array) or coords.size() < 2:
		push_warning("[TILES] %s/%s/%s: region must be [col,row(,w,h)], got %s" % [key, section, name, str(coords)])
		return null
	var tile := int(entry.get("tile", 32))
	var w := tile * (int(coords[2]) if coords.size() >= 4 else size_tiles.x)
	var h := tile * (int(coords[3]) if coords.size() >= 4 else size_tiles.y)
	var src := _image_for(str(entry.get("path", "")))
	if src == null:
		push_warning("[TILES] %s: sheet %s is missing or not loadable — falling through to procedural" % [key, entry.get("path", "")])
		return null
	var rect := Rect2i(int(coords[0]) * tile, int(coords[1]) * tile, w, h)
	if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > src.get_width() or rect.end.y > src.get_height():
		push_warning("[TILES] %s/%s/%s: region %s lies outside the %dx%d sheet — falling through to procedural" % [key, section, name, rect, src.get_width(), src.get_height()])
		return null
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	out.blit_rect(src, rect, Vector2i.ZERO)
	return out


## Pure contract check for a tile_sheets dictionary; returns one string per problem (empty = clean)
static func validate(sheets: Dictionary, images: Dictionary = {}) -> Array:
	var problems: Array = []
	for key in sheets:
		var entry = sheets[key]
		if not (entry is Dictionary):
			problems.append("%s: entry is not an object" % key)
			continue
		if not GENERATOR_KEYS.has(key):
			problems.append("%s: unknown sheet key (expected one of %s)" % [key, GENERATOR_KEYS.keys()])
			continue
		var path := str(entry.get("path", ""))
		var img: Image = images.get(path, null)
		if img == null and path != "" and ResourceLoader.exists(path):
			var tex := load(path) as Texture2D
			img = tex.get_image() if tex else null
		if img == null:
			problems.append("%s: path '%s' does not load" % [key, path])
		var tile := int(entry.get("tile", 32))
		var gen_script = load(GENERATOR_KEYS[key])
		var tile_names: Array = gen_script.TileType.keys() if gen_script else []
		var prop_names: Array = VillageProp.Kind.keys()
		for section in SECTIONS:
			var sec = entry.get(section)
			if sec == null:
				continue
			if not (sec is Dictionary):
				problems.append("%s/%s: not an object" % [key, section])
				continue
			for name in sec:
				var base := str(name).get_slice(":", 0)
				var known := true
				match section:
					"tiles": known = base in tile_names
					"cliff": known = str(name) in CLIFF_NAMES
					"overlay": known = str(name) in OVERLAY_NAMES
					"props": known = str(name) in prop_names
				if not known:
					problems.append("%s/%s/%s: unknown name" % [key, section, name])
				var c = sec[name]
				if not (c is Array) or c.size() < 2 or (section == "props" and c.size() != 4):
					problems.append("%s/%s/%s: region must be %s" % [key, section, name, "[col,row,w,h]" if section == "props" else "[col,row]"])
					continue
				if img != null:
					var w := tile * (int(c[2]) if c.size() >= 4 else 1)
					var h := tile * (int(c[3]) if c.size() >= 4 else 1)
					if int(c[0]) * tile + w > img.get_width() or int(c[1]) * tile + h > img.get_height() or int(c[0]) < 0 or int(c[1]) < 0:
						problems.append("%s/%s/%s: region %s exceeds the %dx%d sheet" % [key, section, name, str(c), img.get_width(), img.get_height()])
	return problems
