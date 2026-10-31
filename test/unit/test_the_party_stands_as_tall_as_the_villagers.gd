extends GutTest

## struktured 2026-10-30: "our own characters are too small relative to npcs now". In a village every
## overworld_npc_sheets entry draws at 48 px while the party drew at 32, so the party stood at 2/3 of a
## villager's height and the artist's child, Kid Acrees, out-stood the Fighter. Mode 7 hid it: it divides
## each sheet by its own height, so only villages showed the gap.
##
## Asserts the RELATIONSHIP, never a pinned 48: the party's frame equals the villagers' and its figures
## stand within reach of the artist's villagers. Both sides are derived, so a later rescale of either
## population reds here instead of quietly reopening the gap.
##
## Pairs with OverworldPlayer rendering a sheet frame at its DECLARED size (it used to squeeze every frame
## to SPRITE_SIZE), so the art sets the drawn size and neither half fixes what he sees without the other.

const MANIFEST := "res://data/sprite_manifest.json"
const HEIGHT_TOLERANCE := 0.15


func _manifest() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	return parsed if parsed is Dictionary else {}


func _section(name: String) -> Dictionary:
	var s: Variant = _manifest().get(name, {})
	return s if s is Dictionary else {}


## The frame size most villager sheets use (148 of 149 when this was written; roy is the 64 px exception).
func _villager_frame() -> int:
	var counts := {}
	for id in _section("overworld_npc_sheets"):
		var fh := int((_section("overworld_npc_sheets")[id] as Dictionary).get("frame_height", 0))
		counts[fh] = int(counts.get(fh, 0)) + 1
	var best := 0
	for fh in counts:
		if best == 0 or int(counts[fh]) > int(counts[best]):
			best = int(fh)
	return best


## Width and height straight from the PNG header: the bytes that ship, not a cached import.
func _png_size(res_path: String) -> Vector2i:
	var f := FileAccess.open(res_path, FileAccess.READ)
	if f == null:
		return Vector2i.ZERO
	var head := f.get_buffer(24)
	if head.size() < 24:
		return Vector2i.ZERO
	var w := (head[16] << 24) | (head[17] << 16) | (head[18] << 8) | head[19]
	var h := (head[20] << 24) | (head[21] << 16) | (head[22] << 8) | head[23]
	return Vector2i(w, h)


## Opaque height of the first walk_down frame: how tall the figure actually stands in its cell.
func _standing_height(res_path: String, frame: int) -> int:
	var img := Image.load_from_file(ProjectSettings.globalize_path(res_path))
	if img == null or img.is_empty():
		return -1
	var top := -1
	var bottom := -1
	for y in mini(frame, img.get_height()):
		for x in mini(frame, img.get_width()):
			if img.get_pixel(x, y).a >= 0.5:
				if top < 0:
					top = y
				bottom = y
				break
	return bottom - top + 1 if top >= 0 else 0


## The artist's villagers, found by provenance tier rather than by name.
func _artist_villager_heights() -> Array:
	var out: Array = []
	var npcs := _section("overworld_npc_sheets")
	for id in npcs:
		var e: Dictionary = npcs[id]
		if not (str(e.get("tier", "")) in ["T2", "T3"]):
			continue
		var h := _standing_height(str(e.get("path", "")), int(e.get("frame_height", 0)))
		if h > 0:
			out.append(h)
	out.sort()
	return out


func test_the_corpus_is_the_whole_party() -> void:
	assert_gte(_section("overworld_player_sheets").size(), 14,
		"FLOOR: every job carries an overworld sheet; fewer means the derivation below judged a fraction")
	assert_gt(_villager_frame(), 0, "FLOOR: the villager frame must be derivable or the next arm compares to nothing")


func test_each_party_sheet_uses_the_villagers_frame() -> void:
	var want := _villager_frame()
	var wrong: Array = []
	var players := _section("overworld_player_sheets")
	for job in players:
		var e: Dictionary = players[job]
		if int(e.get("frame_width", 0)) != want or int(e.get("frame_height", 0)) != want:
			wrong.append("%s %dx%d" % [job, int(e.get("frame_width", 0)), int(e.get("frame_height", 0))])
	wrong.sort()
	assert_eq(wrong, [], "the party must use the villagers' %d px frame or it stands smaller in every village" % want)


func test_each_party_png_is_cut_at_its_declared_frame() -> void:
	var wrong: Array = []
	var players := _section("overworld_player_sheets")
	for job in players:
		var e: Dictionary = players[job]
		var fw := int(e.get("frame_width", 0))
		var size := _png_size(str(e.get("path", "")))
		if size != Vector2i(fw * 4, fw * 4):
			wrong.append("%s png %s, frame %d" % [job, str(size), fw])
	wrong.sort()
	assert_eq(wrong, [], "a 4x4 walk sheet must be four declared frames square, else the cut lands mid-figure")


func test_each_party_member_stands_as_tall_as_the_artists_villagers() -> void:
	var heights := _artist_villager_heights()
	assert_gt(heights.size(), 0, "CONTROL: the artist's villagers must be found, or there is no height to match")
	if heights.is_empty():
		return
	var median: float = float(heights[heights.size() / 2])
	var lo := median * (1.0 - HEIGHT_TOLERANCE)
	var hi := median * (1.0 + HEIGHT_TOLERANCE)
	var wrong: Array = []
	var players := _section("overworld_player_sheets")
	for job in players:
		var e: Dictionary = players[job]
		var h := _standing_height(str(e.get("path", "")), int(e.get("frame_height", 0)))
		if h < lo or h > hi:
			wrong.append("%s %d px" % [job, h])
	wrong.sort()
	assert_eq(wrong, [], "the artist's villagers stand %d px (median of %s); the party must be within %d%%" \
		% [int(median), str(heights), int(HEIGHT_TOLERANCE * 100)])


## The DRAWN size, not the sheet's: OverworldPlayer once squeezed every cut frame to SPRITE_SIZE, so 48px art drew at 32.
func test_each_party_member_is_drawn_at_the_villagers_frame() -> void:
	var want := _villager_frame()
	var judged := 0
	var wrong: Array = []
	for job in _section("overworld_player_sheets"):
		var player := OverworldPlayer.new()
		player.current_job = str(job)
		var cache: Dictionary = player._try_load_overworld_sheet()
		var tex: Variant = cache.get("0_0")
		if tex is Texture2D:
			judged += 1
			if (tex as Texture2D).get_height() != want:
				wrong.append("%s drawn %d px" % [job, (tex as Texture2D).get_height()])
		else:
			wrong.append("%s built no frame" % job)
		player.free()
	wrong.sort()
	assert_gte(judged, 14, "FLOOR: every job's sheet must load and be measured, not skipped")
	assert_eq(wrong, [], "a party frame must be DRAWN at the villagers' %d px, not shrunk after the cut" % want)
