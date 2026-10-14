extends GutTest

## A derived roamer went STALE when its battle idle moved. tools/derive_overworld_roamer_sheets.py cuts each overworld
## sheet from the battle idle frames and never revisits it, so when the Cursed Armor's idle moved off a crouch the field
## still showed the crouch, and when 16 legacy monsters' idles moved off a slash arc the field still showed the arc.
## Re-derive the idle here (same autocrop + bottom-centred fit) and require the roamer's opaque pixels to overlap it.
## The hand-drawn walk grids (wolf, bat, snake, ghost...) are a different pose by design and are not listed.

## Roamers whose sheet is derived from their battle idle; re-derive with --refresh <id> when the idle changes.
const DERIVED_FROM_BATTLE_IDLE := [
	"cursed_armor", "specter", "forgotten_variable", "null_entity", "the_absence", "empty_set", "crystal_golem",
	"glitch_entity", "memory_leak", "optimization_itself", "pipe_phantom", "rogue_process", "corrupted_sprite",
	"masterite_arbiter_futuristic", "masterite_tempo_futuristic", "masterite_warden_futuristic",
	"masterite_warden_abstract",
]
const CELL := 32
## Opaque-mask overlap of the roamer's first frame with a fresh derivation. Fresh 0.94-0.99, stale 0.01-0.50.
const MIN_OVERLAP := 0.8


func _load(path: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img != null:
		img.convert(Image.FORMAT_RGBA8)
	return img


func derive(cell: Image) -> Image:
	## The tool's shrink(): crop to alpha > 10/255, fit the long side to CELL - 2, paste bottom-centred.
	var x0 := cell.get_width()
	var y0 := cell.get_height()
	var x1 := -1
	var y1 := -1
	for y in cell.get_height():
		for x in cell.get_width():
			if cell.get_pixel(x, y).a * 255.0 > 10.0:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	var tile := Image.create(CELL, CELL, false, Image.FORMAT_RGBA8)
	if x1 < 0:
		return tile
	var crop := cell.get_region(Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1))
	var s := float(CELL - 2) / float(maxi(crop.get_width(), crop.get_height()))
	crop.resize(maxi(1, roundi(crop.get_width() * s)), maxi(1, roundi(crop.get_height() * s)), Image.INTERPOLATE_BILINEAR)
	tile.blend_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), Vector2i((CELL - crop.get_width()) / 2, CELL - 1 - crop.get_height()))
	return tile


func overlap(a: Image, b: Image) -> float:
	## Intersection over union of the two CELL x CELL opaque (alpha >= 0.5) masks.
	var both := 0
	var either := 0
	for y in CELL:
		for x in CELL:
			var pa := a.get_pixel(x, y).a >= 0.5
			var pb := b.get_pixel(x, y).a >= 0.5
			both += int(pa and pb)
			either += int(pa or pb)
	return float(both) / float(either) if either > 0 else 0.0


func test_a_derived_roamer_is_cut_from_its_current_battle_idle() -> void:
	var battle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json")).get("monster_sheets", {})
	var stale: Array = []
	for id in DERIVED_FROM_BATTLE_IDLE:
		var be: Dictionary = battle.get(id, {})
		var bimg := _load(str(be.get("path", "")))
		var fimg := _load("res://assets/sprites/monsters/overworld/%s.png" % id)
		assert_not_null(bimg, "%s: battle sheet loads" % id)
		assert_not_null(fimg, "%s: overworld sheet loads" % id)
		if bimg == null or fimg == null:
			continue
		var fh := int(be.get("frame_height", 256))
		var fw := int(be.get("frame_width", fh))
		var start := int(be.get("animations", {}).get("idle", {}).get("start", 0))
		var fresh := derive(bimg.get_region(Rect2i(start * fw, 0, fw, fh)))
		var score := overlap(fresh, fimg.get_region(Rect2i(0, 0, CELL, CELL)))
		if score < MIN_OVERLAP:
			stale.append("%s overlaps its battle idle by %.2f" % [id, score])
	assert_eq(stale, [], "roamers that no longer show the creature their battle idle shows (re-derive with --refresh): %s" % str(stale))


func test_the_overlap_tells_a_figure_from_a_different_one() -> void:
	var a := Image.create(CELL, CELL, false, Image.FORMAT_RGBA8)
	a.fill_rect(Rect2i(10, 4, 12, 27), Color.WHITE)
	var b := Image.create(CELL, CELL, false, Image.FORMAT_RGBA8)
	b.fill_rect(Rect2i(2, 20, 28, 11), Color.WHITE)
	assert_almost_eq(overlap(a, a), 1.0, 0.001, "a figure overlaps itself fully")
	assert_lt(overlap(a, b), MIN_OVERLAP, "a standing figure and a low wide one are different")
