extends GutTest

## The Cursed Armor IDLED CROUCHED: its idle frames are a squat 89px figure, every other frame stands 145-147px, so in
## battle it waited at 61% of its own size and sprang to full height on every attack and hit. A monster's idle is the
## creature the player sizes up; it must stand at roughly the height of the rest of its sheet.

## Idle median height / other animations' median height below this is a different-sized creature. Next lowest: 0.82.
const MIN_IDLE_SHARE := 0.75
const WORLD_SUFFIXES := ["_suburban", "_steampunk", "_industrial", "_digital", "_abstract", "_futuristic"]


func _sheets() -> Dictionary:
	var m = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	return m.get("monster_sheets", {})


func frame_heights(img: Image, fw: int, fh: int) -> Array:
	## Opaque height (alpha >= 0.5) of each frame along a single-row sheet; 0 for an empty frame.
	## Not get_used_rect: it counts any alpha, so one faint stray speck stretches a frame's height.
	var out: Array = []
	for i in img.get_width() / fw:
		var top := -1
		var bottom := -1
		for y in fh:
			for x in range(i * fw, (i + 1) * fw):
				if img.get_pixel(x, y).a >= 0.5:
					if top < 0:
						top = y
					bottom = y
					break
		out.append(0 if top < 0 else bottom - top + 1)
	return out


func _median(values: Array) -> float:
	var v := values.duplicate()
	v.sort()
	if v.is_empty():
		return 0.0
	var mid: int = v.size() / 2
	return float(v[mid]) if v.size() % 2 == 1 else (float(v[mid - 1]) + float(v[mid])) / 2.0


func idle_share(heights: Array, anims: Dictionary) -> float:
	var idle: Array = []
	var rest: Array = []
	for name in anims:
		var a: Dictionary = anims[name]
		for i in range(int(a.get("start", 0)), int(a.get("end", a.get("start", 0))) + 1):
			if i < heights.size() and int(heights[i]) > 0:
				(idle if name == "idle" else rest).append(heights[i])
	if idle.is_empty() or rest.is_empty():
		return 1.0
	return _median(idle) / _median(rest)


func test_every_monster_idles_at_its_own_height() -> void:
	var sheets := _sheets()
	var checked := 0
	var short: Array = []
	for id in sheets:
		var skip := false
		for s in WORLD_SUFFIXES:
			skip = skip or str(id).ends_with(s)
		if skip:
			continue
		var e: Dictionary = sheets[id]
		var path := str(e.get("path", ""))
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img == null:
			short.append("%s: sheet will not load" % id)
			continue
		img.convert(Image.FORMAT_RGBA8)
		var fh := int(e.get("frame_height", img.get_height()))
		var fw := int(e.get("frame_width", fh))
		var share := idle_share(frame_heights(img, fw, fh), e.get("animations", {}))
		checked += 1
		if share < MIN_IDLE_SHARE:
			short.append("%s: idles at %.2f of its other poses' height" % [id, share])
	assert_gt(checked, 80, "CONTROL: the base monster sheets were measured (%d)" % checked)
	assert_eq(short, [], "monsters that idle as a smaller creature than they fight as: %s" % str(short))


func test_the_measure_sees_a_crouch() -> void:
	var anims := {"idle": {"start": 0, "end": 1}, "attack": {"start": 2, "end": 3}}
	assert_lt(idle_share([89, 89, 147, 145], anims), MIN_IDLE_SHARE, "a crouched idle is a smaller creature")
	assert_gt(idle_share([140, 141, 147, 145], anims), MIN_IDLE_SHARE, "a standing idle is the same creature")
