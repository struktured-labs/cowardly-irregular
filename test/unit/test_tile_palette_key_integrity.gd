extends GutTest

## A tile's draw function may only read colours its own palette declares.
##
## `PALETTES` is keyed BY TILE TYPE — each tile gets its own ~9-key palette, and
## `_draw_tile` hands a draw function only that tile's dictionary. Reading a key
## the tile doesn't declare is not a fallback and not a warning: in GDScript an
## invalid Dictionary key access ABORTS the function on the spot.
##
## Found 2026-08-06 in IndustrialTileGenerator._draw_guard_post, whose very first
## statement was `img.fill(palette["concrete"])` against a palette declaring
## `light` and no `concrete`. The function aborted before drawing a single pixel,
## so GUARD_POST — an impassable tile — rendered completely blank. The industrial
## overworld had invisible walls, and the tell was a lone SCRIPT ERROR in a log
## nobody reads while every test in the suite stayed green.
##
## That is the silent-failure class this project cares most about, in its purest
## form: no crash, no failing assertion, a tile count that looks healthy
## (`{9: 6}` — six guard posts placed), and a blank square on screen.
##
## The check is DERIVED both ways. `PALETTES` and `TileType` are read off the
## script's constant map at runtime, not parsed, so no assumption about their
## literal shape can make this pass blind — an earlier hand-rolled parse of the
## same data reported "63 keys missing" from a palette it had failed to find at
## all, and only the accompanying control showed the corpus was empty rather
## than the code broken.

const GEN_DIR := "res://src/exploration"


func _generator_paths() -> Array:
	var out: Array = []
	var dir := DirAccess.open(GEN_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if not (f.ends_with(".gd") and f.contains("TileGenerator")):
			continue
		var script = load(GEN_DIR + "/" + f)
		if script == null:
			continue
		var consts: Dictionary = script.get_script_constant_map()
		if consts.has("PALETTES") and consts.has("TileType"):
			out.append(GEN_DIR + "/" + f)
	out.sort()
	return out


## The `_draw_tile` dispatch body only — arms elsewhere in the file are not
## dispatch and would attribute a function to the wrong tile.
func _dispatch_body(src: String) -> String:
	var start := src.find("func _draw_tile(")
	if start < 0:
		return ""
	var nxt := src.find("\nfunc ", start + 1)
	return src.substr(start, (nxt - start) if nxt > 0 else -1)


func _fn_body(src: String, fn: String) -> String:
	var start := src.find("func %s(" % fn)
	if start < 0:
		return ""
	var nxt := src.find("\nfunc ", start + 1)
	return src.substr(start, (nxt - start) if nxt > 0 else -1)


func test_every_draw_function_only_reads_keys_its_tile_declares() -> void:
	var paths := _generator_paths()
	assert_gt(paths.size(), 0, "found tile generators declaring PALETTES + TileType — zero would pass this file for free")

	var arm_re := RegEx.create_from_string("TileType\\.([A-Z_]+):\\s+(_draw_\\w+)\\(")
	var read_re := RegEx.create_from_string("palette\\[\\s*\"([a-z_]+)\"\\s*\\]")

	var total_arms := 0
	var total_reads := 0
	var offenders: Array = []
	var thin: Array = []

	for path in paths:
		var script = load(path)
		var consts: Dictionary = script.get_script_constant_map()
		var palettes: Dictionary = consts["PALETTES"]
		var tile_type: Dictionary = consts["TileType"]
		var src: String = FileAccess.get_file_as_string(path)
		var arms := arm_re.search_all(_dispatch_body(src))
		# A generator whose dispatch stops parsing would contribute zero arms and
		# vanish from the sweep silently; name it instead.
		if arms.size() == 0:
			thin.append("%s: parsed ZERO dispatch arms" % path.get_file())
			continue

		for m in arms:
			var tname := m.get_string(1)
			var fn := m.get_string(2)
			total_arms += 1
			if not tile_type.has(tname):
				offenders.append("%s: dispatch names TileType.%s which the enum does not declare" % [path.get_file(), tname])
				continue
			var idx = tile_type[tname]
			if not palettes.has(idx):
				offenders.append("%s: TileType.%s (%s) has no PALETTES entry — every colour read by %s aborts" % [path.get_file(), tname, str(idx), fn])
				continue
			var declared: Dictionary = palettes[idx]
			for r in read_re.search_all(_fn_body(src, fn)):
				total_reads += 1
				var key := r.get_string(1)
				if not declared.has(key):
					offenders.append("%s: %s reads palette[\"%s\"] but TileType.%s declares only %s — the read ABORTS the function and the tile draws blank" % [
						path.get_file(), fn, key, tname, str(declared.keys())])

	assert_true(thin.is_empty(),
		"%d generator(s) contributed no dispatch arms, so their tiles were never checked:\n  %s" % [thin.size(), "\n  ".join(thin)])
	assert_gt(total_arms, 0, "parsed dispatch arms across the generators")
	assert_gt(total_reads, 0,
		"parsed %d arms but ZERO palette reads — the read pattern stopped matching and this sweep is now blind" % total_arms)
	assert_true(offenders.is_empty(),
		"%d palette read(s) name a key their tile does not declare:\n  %s" % [offenders.size(), "\n  ".join(offenders)])


## The control: prove a missing key WOULD be seen. Without it, "no offenders"
## is equally consistent with a palette that answers every key.
func test_a_key_no_palette_declares_is_detectable() -> void:
	var paths := _generator_paths()
	assert_gt(paths.size(), 0, "have generators to inspect")
	var checked := 0
	for path in paths:
		var palettes: Dictionary = load(path).get_script_constant_map()["PALETTES"]
		assert_gt(palettes.size(), 0, "%s declares at least one tile palette" % path.get_file())
		for idx in palettes:
			var declared: Dictionary = palettes[idx]
			assert_false(declared.has("zzz_not_a_real_colour"),
				"%s tile %s must not answer a fabricated key — if palettes answered anything, the sweep above could never fail" % [path.get_file(), str(idx)])
			assert_gt(declared.size(), 0, "%s tile %s declares colours" % [path.get_file(), str(idx)])
			checked += 1
	assert_gt(checked, 0, "inspected at least one palette — zero makes this control vacuous")
