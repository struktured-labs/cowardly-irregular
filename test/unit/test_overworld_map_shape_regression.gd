extends GutTest
## Every world's authored map must match that world's own MAP_WIDTH/MAP_HEIGHT.
##
## FOUND 2026-08-22. IndustrialOverworld's row 33 was 59 characters against MAP_WIDTH 60.
## Nothing reported it, because the generator is forgiving by design:
##   var char = row[x] if x < row.length() else "f"
##   while map_data.size() < MAP_HEIGHT: map_data.append("f".repeat(60))
## A short row silently becomes floor and a short map silently grows one. That forgiveness
## is correct at runtime -- an out-of-range read would crash the world -- but it means a
## typo in authored terrain lands as a walkable hole in a wall that no one authored and
## no one can see. The row in question was a solid wall run.
##
## THE SHAPE IS THE ASSERTION, NOT THE CONTENT. This deliberately says nothing about which
## characters a map uses or where its walls go -- re-authoring a world must stay free. It
## pins only that the authored rectangle is the rectangle the world declares, which is a
## property no legitimate map edit ever breaks.

const WORLDS := {
	"SuburbanOverworld": "res://src/exploration/SuburbanOverworld.gd",
	"SteampunkOverworld": "res://src/exploration/SteampunkOverworld.gd",
	"IndustrialOverworld": "res://src/exploration/IndustrialOverworld.gd",
	"FuturisticOverworld": "res://src/exploration/FuturisticOverworld.gd",
	"AbstractOverworld": "res://src/exploration/AbstractOverworld.gd",
}


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "cannot open %s" % path)
	return "" if f == null else f.get_as_text()


func _declared(src: String, key: String) -> int:
	var re := RegEx.new()
	re.compile("const %s: int = (\\d+)" % key)
	var m := re.search(src)
	return -1 if m == null else int(m.get_string(1))


## The rows of the map_data literal, in order
func _rows(src: String) -> Array:
	var start := src.find("map_data: Array[String] = [")
	if start < 0:
		return []
	var end := src.find("\n\t]", start)
	if end < 0:
		return []
	var re := RegEx.new()
	re.compile("\"([^\"]*)\"")
	var out: Array = []
	for m in re.search_all(src.substr(start, end - start)):
		out.append(m.get_string(1))
	return out


func test_every_world_map_is_the_rectangle_it_declares() -> void:
	var checked := 0
	for name in WORLDS:
		var src := _read(WORLDS[name])
		var w := _declared(src, "MAP_WIDTH")
		var h := _declared(src, "MAP_HEIGHT")
		assert_gt(w, 0, "%s: MAP_WIDTH not found -- the scan cannot see this world" % name)
		assert_gt(h, 0, "%s: MAP_HEIGHT not found -- the scan cannot see this world" % name)
		# A PNG-driven world (W2 since 2026-08-29) authors its rectangle in the image.
		# Same property, measured on the artifact the runtime actually loads; the ASCII
		# scrape below would otherwise pull arbitrary quoted strings out of loader code.
		var img_re := RegEx.new()
		img_re.compile("const MAP_IMAGE: String = \"(res://[^\"]+)\"")
		var img_m := img_re.search(src)
		if img_m != null:
			var tex = load(img_m.get_string(1))
			assert_not_null(tex, "%s: MAP_IMAGE %s does not load" % [name, img_m.get_string(1)])
			if tex != null:
				var isz: Vector2i = tex.get_image().get_size() if tex is Texture2D else Vector2i.ZERO
				assert_eq(isz, Vector2i(w, h), "%s: MAP_IMAGE is %s against declared %dx%d" % [name, str(isz), w, h])
			checked += 1
			continue
		var rows := _rows(src)
		assert_gt(rows.size(), 0, "%s: no map_data literal found -- the scan is looking in the wrong place" % name)
		if rows.is_empty():
			continue
		checked += 1
		assert_eq(rows.size(), h, "%s authors %d rows against MAP_HEIGHT %d; the generator pads the difference with floor" % [name, rows.size(), h])
		var ragged: Array = []
		for i in range(rows.size()):
			var row: String = rows[i]
			if row.length() != w:
				ragged.append("row %d is %d chars" % [i, row.length()])
		assert_eq(ragged, [], "%s has rows that are not MAP_WIDTH %d: %s. A short row is silently filled with 'f' (floor), so a wall gains a hole nobody authored." % [name, w, str(ragged)])
	assert_eq(checked, WORLDS.size(), "only %d of %d worlds were actually measured" % [checked, WORLDS.size()])
