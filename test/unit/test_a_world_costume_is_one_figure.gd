extends GutTest

## The bard's world-5 costume shipped SHREDDED: bard/idle_digital.png was generated on a painted backdrop, and the
## white key (R,G,B >= 240) plus cleanup tore through her outline — 54% of the figure sat outside its main body, in 6
## pieces, see-through where the backdrop had been. Nothing loads it differently, so nothing failed: it imported,
## resolved, and drew a ragged ghost every digital battle. The first world-victory batch had 8 of 25 rolls on painted
## backdrops; the generator now asks for real alpha and refuses them, and this guards what actually ships.
## A world costume is ONE figure: its largest connected body holds most of its pixels. Legitimately detached parts
## (the summoner's floating rune, the time mage's watch, the cleric's wisps) measured at most 21% across all 71 world
## idles; the shredded bard was 54%.

const Loader := preload("res://src/battle/sprites/HybridSpriteLoader.gd")
## The largest 8-connected body must hold at least this share of a frame's opaque pixels.
const MIN_MAIN_BODY := 0.6
const SCAN := 128


func _main_body_share(tex: Texture2D, frame: int, frame_w: int) -> float:
	var img: Image = tex.get_image().duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var fr := img.get_region(Rect2i(frame * frame_w, 0, frame_w, img.get_height()))
	fr.resize(SCAN, SCAN, Image.INTERPOLATE_NEAREST)
	var d := fr.get_data()
	var seen := PackedByteArray()
	seen.resize(SCAN * SCAN)
	var total := 0
	var biggest := 0
	for start in SCAN * SCAN:
		if seen[start] or d[start * 4 + 3] < 128:
			continue
		var stack: Array[int] = [start]
		seen[start] = 1
		var n := 0
		while not stack.is_empty():
			var p: int = stack.pop_back()
			n += 1
			var x := p % SCAN
			var y := p / SCAN
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var nx: int = x + dx
					var ny: int = y + dy
					if nx < 0 or ny < 0 or nx >= SCAN or ny >= SCAN:
						continue
					var q := ny * SCAN + nx
					if not seen[q] and d[q * 4 + 3] >= 128:
						seen[q] = 1
						stack.append(q)
		total += n
		biggest = maxi(biggest, n)
	return float(biggest) / maxf(1.0, float(total))


## Every <anim>_<suffix>.png a job folder holds for a world the runtime can ask for.
func _world_sheets() -> Array:
	var out: Array = []
	var root := "res://assets/sprites/jobs/"
	for job in DirAccess.get_directories_at(root):
		for f in DirAccess.get_files_at(root + job):
			if not f.ends_with(".png"):
				continue
			for suffix in Loader.WORLD_SUFFIXES:
				if suffix != "" and f.ends_with("_%s.png" % suffix):
					out.append(root + job + "/" + f)
	out.sort()
	return out


func test_every_world_costume_is_one_figure() -> void:
	var sheets := _world_sheets()
	assert_gt(sheets.size(), 90, "CONTROL: the world costume sheets were found (%d)" % sheets.size())
	var bad: Array = []
	var judged := 0
	for path in sheets:
		if not ResourceLoader.exists(path):
			continue
		var tex := load(path) as Texture2D
		# Battle sheets are square-framed strips; overworld_ sheets are 32px walk grids, a different shape entirely
		var fw := 0 if path.get_file().begins_with("overworld_") else tex.get_height()
		if fw <= 0:
			continue
		judged += 1
		var frames: int = tex.get_width() / fw
		for i in ([0, frames - 1] if frames > 1 else [0]):
			var share := _main_body_share(tex, i, fw)
			if share < MIN_MAIN_BODY:
				bad.append("%s frame %d: main body holds %.0f%% of the figure" % [path.trim_prefix("res://assets/sprites/jobs/"), i, share * 100.0])
	assert_gt(judged, 90, "CONTROL: the world battle sheets were judged (%d)" % judged)
	assert_eq(bad, [], "world costumes that are shreds, not a figure: %s" % str(bad))


func test_the_measure_tells_a_figure_from_shreds() -> void:
	## Positive control on synthetic frames: one solid body passes, the same pixels in six pieces does not.
	var whole := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	whole.fill_rect(Rect2i(100, 60, 56, 130), Color.WHITE)
	var shreds := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for k in 6:
		shreds.fill_rect(Rect2i(40 + k * 32, 60 + (k % 2) * 40, 12, 80), Color.WHITE)
	assert_gt(_main_body_share(ImageTexture.create_from_image(whole), 0, 256), 0.99, "a solid body is one figure")
	assert_lt(_main_body_share(ImageTexture.create_from_image(shreds), 0, 256), MIN_MAIN_BODY, "six pieces are shreds")
