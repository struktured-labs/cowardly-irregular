class_name MapImageLoader
extends RefCounted

## Loads an overworld map from a 1px-per-tile PNG into the same Array[String] the ASCII
## literal produces, so it is a drop-in for `map_data`.
##
## WHY AN IMAGE. The ASCII literal does not survive the scale-up: W1 is 70 rows x 100 chars,
## and a 4x map is 140 rows of exactly 200 hand-aligned characters. IndustrialOverworld
## already carries the failure that format invites -- rows of 59 AND 60, silently ragged.
## An image cannot have ragged rows. That deletes the defect class rather than guarding it.
##
## WHY THE PIXEL ENCODES THE CHARACTER, NOT THE TILE TYPE. `_char_to_tile_type` collapses
## 25 characters into ~12 visual types: "1","2","3","4" all return CAVE_ENTRANCE and
## "W","E","G","D","I" all return VILLAGE_GATE. But `_register_spawn_point` keys on the
## CHARACTER. A tile-type image would render identically and silently erase every dragon
## cave's and every village's spawn identity.
##
## WHY IT IS READ AS BYTES AND NOT load()ed. The map PNG carries `importer="keep"`. Godot's
## default PNG import sets `process/fix_alpha_border=true`, which REWRITES RGB under
## non-opaque pixels at import time -- it does not touch the source file, so a test reading
## the PNG on disk passes while the SHIPPED texture differs. A kept file is not a Resource,
## so ResourceLoader cannot see it; FileAccess + load_png_from_buffer reads the authored
## bytes. (cowir-deploy, 2026-08-15.)
##
## STRICTNESS IS THE POINT. 12 of the 25 characters appear exactly ONCE -- every landmark is
## a single pixel. An unknown colour is a hard error naming its coordinate, never a silent
## fallback to grass, because a lost landmark pixel removes a spawn point with no symptom
## until a player walks to where a cave used to be.

const PALETTE_PATH := "res://data/maps/map_palette.json"

## THE WORLD ID IS REQUIRED, AND THAT IS THE POINT. Measured 2026-08-22 across the six
## worlds' `_char_to_tile_type` arms: 48 distinct map characters, 30 used by more than one
## world, and ZERO of those 30 meaning the same thing in two of them. "c" is COAST in
## medieval, BASKETBALL_COURT in suburban, CONCRETE in steampunk, CONVEYOR_BELT in
## industrial, CIRCUIT_FLOOR in futuristic.
##
## A default world would be the dangerous convenience: decoding an image against the wrong
## world's table does not fail, it produces a PLAUSIBLE MAP MADE OF THE WRONG TILES -- every
## pixel resolves, every row is the right length, the map renders. There is no symptom to
## notice. So an unknown world decodes NOTHING and says which world it was asked for.

## world id -> { "to_char": {rgb24: char}, "to_rgb": {char: rgb24} }
static var _by_world: Dictionary = {}
## world id -> the reason it could not be built, "" once it is built
static var _errors: Dictionary = {}


static func _key(r: int, g: int, b: int) -> int:
	return (r << 16) | (g << 8) | b


static func _read_palette() -> Variant:
	if not FileAccess.file_exists(PALETTE_PATH):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(PALETTE_PATH))


## Returns "" on success, or a human-readable reason naming `world_id`. Idempotent.
static func ensure_palette(world_id: String) -> String:
	if _by_world.has(world_id):
		return ""
	if _errors.has(world_id):
		return _errors[world_id]

	var parsed = _read_palette()
	if parsed == null:
		_errors[world_id] = "palette missing or unparseable: %s" % PALETTE_PATH
		return _errors[world_id]
	if not (parsed is Dictionary) or not parsed.has("worlds"):
		_errors[world_id] = "palette has no 'worlds' section: %s" % PALETTE_PATH
		return _errors[world_id]

	var worlds: Dictionary = parsed["worlds"]
	if not worlds.has(world_id):
		# names the asked-for world AND what exists, so a typo is one line from fixed
		var known: Array = worlds.keys()
		known.sort()
		_errors[world_id] = "unknown world '%s'; palette defines %s" % [world_id, str(known)]
		return _errors[world_id]

	var section: Dictionary = worlds[world_id]
	var to_char := {}
	var to_rgb := {}
	for kind in ["terrain", "landmarks"]:
		if not section.has(kind):
			_errors[world_id] = "world '%s' has no '%s' section" % [world_id, kind]
			return _errors[world_id]
		for ch in (section[kind] as Dictionary):
			var rgb: Array = (section[kind][ch] as Dictionary).get("rgb", [])
			if rgb.size() != 3:
				_errors[world_id] = "world '%s' entry '%s' has no 3-component rgb" % [world_id, ch]
				return _errors[world_id]
			var k := _key(int(rgb[0]), int(rgb[1]), int(rgb[2]))
			# a collision WITHIN a world means two characters decode to one and the map
			# silently loses one; across worlds it is expected and harmless
			if to_char.has(k):
				_errors[world_id] = "world '%s' collision: '%s' and '%s' share rgb %s" % [
					world_id, ch, to_char[k], str(rgb)]
				return _errors[world_id]
			to_char[k] = String(ch)
			to_rgb[String(ch)] = k
	_by_world[world_id] = {"to_char": to_char, "to_rgb": to_rgb}
	return ""


static func palette_chars(world_id: String) -> Array:
	if ensure_palette(world_id) != "":
		return []
	var out: Array = (_by_world[world_id]["to_rgb"] as Dictionary).keys()
	out.sort()
	return out


## The rgb triple `ch` decodes from in `world_id`, or [] if that world does not define it.
static func palette_rgb(world_id: String, ch: String) -> Array:
	if ensure_palette(world_id) != "":
		return []
	var to_rgb: Dictionary = _by_world[world_id]["to_rgb"]
	if not to_rgb.has(ch):
		return []
	var k: int = to_rgb[ch]
	return [(k >> 16) & 0xFF, (k >> 8) & 0xFF, k & 0xFF]


## The spawn-bearing characters for `world_id`, read from that world's own `landmarks`
## section rather than hand-listed. A hand-list of "which chars are landmarks" drifts the
## moment one is added, and it drifted within minutes of first being written: "C" and "H"
## each appear TWICE in W1, so an eyeballed singleton list was wrong on its first run.
static func landmark_chars(world_id: String) -> Array:
	var parsed = _read_palette()
	if not (parsed is Dictionary) or not parsed.has("worlds"):
		return []
	var worlds: Dictionary = parsed["worlds"]
	if not worlds.has(world_id):
		return []
	var section: Dictionary = worlds[world_id]
	if not section.has("landmarks"):
		return []
	var out: Array = (section["landmarks"] as Dictionary).keys()
	out.sort()
	return out


## Loads `png_path` into rows of characters. On any failure returns an empty array and
## pushes an error naming the cause -- callers must treat empty as fatal, not as an
## empty map.
static func load_rows(png_path: String, world_id: String) -> Array:
	var err := ensure_palette(world_id)
	if err != "":
		push_error("[MAP] %s (loading %s)" % [err, png_path])
		return []
	if not FileAccess.file_exists(png_path):
		push_error("[MAP] no map image at %s" % png_path)
		return []

	var bytes := FileAccess.get_file_as_bytes(png_path)
	if bytes.is_empty():
		push_error("[MAP] %s read as zero bytes" % png_path)
		return []
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		push_error("[MAP] %s is not decodable as PNG" % png_path)
		return []

	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		push_error("[MAP] %s decoded to %dx%d" % [png_path, w, h])
		return []

	var to_char: Dictionary = _by_world[world_id]["to_char"]
	var rows: Array = []
	var unknown: Array = []
	for y in range(h):
		var line := ""
		for x in range(w):
			var c := img.get_pixel(x, y)
			var k := _key(c.r8, c.g8, c.b8)
			if to_char.has(k):
				line += to_char[k]
			else:
				line += "?"
				if unknown.size() < 12:
					unknown.append("(%d,%d) rgb(%d,%d,%d)" % [x, y, c.r8, c.g8, c.b8])
		rows.append(line)

	if not unknown.is_empty():
		# NOT a silent fallback: a landmark is a single pixel, and decoding an unrecognised
		# colour to grass would delete a spawn point with no symptom.
		push_error(("[MAP] %s has %s unrecognised colour(s); first: %s. " +
			"Add them to world '%s' in the palette or repaint them -- they are NOT defaulted.") % [
				png_path, world_id, "12+" if unknown.size() >= 12 else str(unknown.size()), ", ".join(unknown)])
		return []

	return rows
