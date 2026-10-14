extends GutTest

## The Cursed Armor ROAMED CROUCHED: its overworld sheet was derived (tools/derive_overworld_roamer_sheets.py) from its
## battle idle while that idle pointed at a crouch, so after the battle idle was fixed to stand, the field still showed a
## squat 17px figure for a monster that stands 29px tall in the fight it starts. A derived roamer must keep the shape of
## the battle idle it was cut from; the hand-drawn walk grids (wolf, bat, snake...) are a different pose by design.

## Roamers whose sheet is derived from their battle idle, so the two must agree in shape.
const DERIVED_FROM_BATTLE_IDLE := ["cursed_armor"]
## Height/width of the roamer over that of its battle idle; past this either way it is a different pose.
const MAX_SHAPE_DRIFT := 1.3


func _manifest() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))


func _load(path: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img != null:
		img.convert(Image.FORMAT_RGBA8)
	return img


func shape(img: Image, rect: Rect2i) -> float:
	## Height over width of the opaque (alpha >= 0.5) pixels inside rect; 0 when the rect is empty.
	var x0 := rect.end.x
	var y0 := rect.end.y
	var x1 := -1
	var y1 := -1
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if img.get_pixel(x, y).a >= 0.5:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 < 0:
		return 0.0
	return float(y1 - y0 + 1) / float(x1 - x0 + 1)


func _mean_shape(img: Image, rects: Array) -> float:
	var sum := 0.0
	var n := 0
	for r in rects:
		var s := shape(img, r)
		if s > 0.0:
			sum += s
			n += 1
	return sum / n if n > 0 else 0.0


func drift(a: float, b: float) -> float:
	if a <= 0.0 or b <= 0.0:
		return INF
	return maxf(a, b) / minf(a, b)


func test_a_derived_roamer_keeps_its_battle_idles_shape() -> void:
	var m := _manifest()
	var battle: Dictionary = m.get("monster_sheets", {})
	var field: Dictionary = m.get("overworld_monster_sheets", {})
	for id in DERIVED_FROM_BATTLE_IDLE:
		var be: Dictionary = battle.get(id, {})
		var bimg := _load(str(be.get("path", "")))
		var fimg := _load("res://assets/sprites/monsters/overworld/%s.png" % id)
		assert_not_null(bimg, "%s: battle sheet loads" % id)
		assert_not_null(fimg, "%s: overworld sheet loads" % id)
		if bimg == null or fimg == null:
			continue
		var bfh := int(be.get("frame_height", bimg.get_height()))
		var bfw := int(be.get("frame_width", bfh))
		var idle: Dictionary = be.get("animations", {}).get("idle", {"start": 0, "end": 0})
		var brects: Array = []
		for i in range(int(idle.get("start", 0)), int(idle.get("end", 0)) + 1):
			brects.append(Rect2i(i * bfw, 0, bfw, bfh))
		var fe: Dictionary = field.get(id, {})
		var ffw := int(fe.get("frame_width", 32))
		var ffh := int(fe.get("frame_height", 32))
		var frects: Array = []
		for c in fimg.get_width() / ffw:
			frects.append(Rect2i(c * ffw, 0, ffw, ffh))
		var b := _mean_shape(bimg, brects)
		var f := _mean_shape(fimg, frects)
		assert_lt(drift(b, f), MAX_SHAPE_DRIFT,
			"%s roams as a different pose than it idles in battle: field h/w %.2f vs battle idle h/w %.2f" % [id, f, b])


func test_the_measure_sees_a_crouch() -> void:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(0, 0, 2, 6), Color.WHITE)
	img.fill_rect(Rect2i(4, 5, 4, 2), Color.WHITE)
	var standing := shape(img, Rect2i(0, 0, 4, 8))
	var crouched := shape(img, Rect2i(4, 0, 4, 8))
	assert_almost_eq(standing, 3.0, 0.001, "a 2x6 figure is three times taller than wide")
	assert_gt(drift(standing, crouched), MAX_SHAPE_DRIFT, "a crouch is a different pose from a stand")
	assert_lt(drift(standing, standing * 1.1), MAX_SHAPE_DRIFT, "a 10% wobble is the same pose")
