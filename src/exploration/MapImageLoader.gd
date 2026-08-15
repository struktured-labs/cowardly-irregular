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

## rgb24 -> character. Built once from the palette JSON that the exporter also reads;
## the mapping is deliberately not duplicated in GDScript.
static var _rgb_to_char: Dictionary = {}
static var _char_to_rgb: Dictionary = {}
static var _palette_error: String = ""


static func _key(r: int, g: int, b: int) -> int:
	return (r << 16) | (g << 8) | b


## Returns "" on success, or a human-readable reason. Idempotent.
static func ensure_palette() -> String:
	if not _rgb_to_char.is_empty():
		return ""
	if _palette_error != "":
		return _palette_error
	if not FileAccess.file_exists(PALETTE_PATH):
		_palette_error = "palette missing: %s" % PALETTE_PATH
		return _palette_error
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PALETTE_PATH))
	if not (parsed is Dictionary):
		_palette_error = "palette is not a JSON object: %s" % PALETTE_PATH
		return _palette_error
	for section in ["terrain", "landmarks"]:
		if not parsed.has(section):
			_palette_error = "palette has no '%s' section" % section
			return _palette_error
		for ch in (parsed[section] as Dictionary):
			var rgb: Array = (parsed[section][ch] as Dictionary).get("rgb", [])
			if rgb.size() != 3:
				_palette_error = "palette entry '%s' has no 3-component rgb" % ch
				return _palette_error
			var k := _key(int(rgb[0]), int(rgb[1]), int(rgb[2]))
			# a collision means two characters decode to one, and the map silently loses one
			if _rgb_to_char.has(k):
				_palette_error = "palette collision: '%s' and '%s' share rgb %s" % [ch, _rgb_to_char[k], str(rgb)]
				_rgb_to_char.clear()
				return _palette_error
			_rgb_to_char[k] = String(ch)
			_char_to_rgb[String(ch)] = k
	return ""


static func palette_chars() -> Array:
	ensure_palette()
	var out: Array = _char_to_rgb.keys()
	out.sort()
	return out


## The spawn-bearing characters, read from the palette's own `landmarks` section rather than
## hand-listed. A hand-list of "which chars are landmarks" drifts the moment one is added,
## and it drifted within minutes of first being written: "C" and "H" each appear TWICE in W1,
## so an eyeballed singleton list was wrong on its first run.
static func landmark_chars() -> Array:
	if not FileAccess.file_exists(PALETTE_PATH):
		return []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PALETTE_PATH))
	if not (parsed is Dictionary) or not parsed.has("landmarks"):
		return []
	var out: Array = (parsed["landmarks"] as Dictionary).keys()
	out.sort()
	return out


## Loads `png_path` into rows of characters. On any failure returns an empty array and
## pushes an error naming the cause -- callers must treat empty as fatal, not as an
## empty map.
static func load_rows(png_path: String) -> Array:
	var err := ensure_palette()
	if err != "":
		push_error("[MAP] %s" % err)
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

	var rows: Array = []
	var unknown: Array = []
	for y in range(h):
		var line := ""
		for x in range(w):
			var c := img.get_pixel(x, y)
			var k := _key(c.r8, c.g8, c.b8)
			if _rgb_to_char.has(k):
				line += _rgb_to_char[k]
			else:
				line += "?"
				if unknown.size() < 12:
					unknown.append("(%d,%d) rgb(%d,%d,%d)" % [x, y, c.r8, c.g8, c.b8])
		rows.append(line)

	if not unknown.is_empty():
		# NOT a silent fallback: a landmark is a single pixel, and decoding an unrecognised
		# colour to grass would delete a spawn point with no symptom.
		push_error(("[MAP] %s has %s unrecognised colour(s); first: %s. " +
			"Add them to the palette or repaint them -- they are NOT defaulted.") % [
				png_path, "12+" if unknown.size() >= 12 else str(unknown.size()), ", ".join(unknown)])
		return []

	return rows
