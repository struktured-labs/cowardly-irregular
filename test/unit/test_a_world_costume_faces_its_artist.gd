extends GutTest

## Past world 1 the mage, the fighter and the cleric IDLED FACING THE WRONG WAY. Their world idles (the August batch)
## were drawn mirrored: staff and sword on the far side from the artist's. Battle sets flip_h ONCE per character from
## the job's declared facing, so a mirrored world sheet faces away from the enemy line, and the character turned around
## every time they acted, because the action sheets follow the artist. Strips that took their costume from those idles
## inherited the mirror. Measured over 195 world sheets: 20 clear mirrors (to -0.38) and 4 more just above the line.
## A world sheet must face the way its artist sheet faces: its silhouette, fitted to the artist's box, has to match
## the artist's frame rather than the artist's frame MIRRORED. Front-facing figures score near 0 either way.

const Loader := preload("res://src/battle/sprites/HybridSpriteLoader.gd")
const ANIMS := ["idle", "victory", "attack", "cast", "hit", "dead"]
## Mean (IoU with the artist frame - IoU with it mirrored) below this is drawn facing the other way. Matches
## tools/gen_world_job_sprites.py MIRRORED_BELOW; legitimate sheets measured no lower than -0.13 after the fix.
const MIRRORED_BELOW := -0.15
const BOX := 48


func _mask(img: Image, frame: int) -> PackedByteArray:
	## The frame's alpha >= 128 silhouette cropped to its box and fitted to BOX x BOX, 1 = inside.
	var fr := img.get_region(Rect2i(frame * 256, 0, 256, 256))
	var used := fr.get_used_rect()
	var out := PackedByteArray()
	out.resize(BOX * BOX)
	if used.size.x <= 0 or used.size.y <= 0:
		return out
	var x0 := 256
	var y0 := 256
	var x1 := -1
	var y1 := -1
	for y in range(used.position.y, used.end.y):
		for x in range(used.position.x, used.end.x):
			if fr.get_pixel(x, y).a >= 0.5:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 < 0:
		return out
	var w := x1 - x0 + 1
	var h := y1 - y0 + 1
	for by in BOX:
		for bx in BOX:
			var sx := x0 + int(float(bx) * w / BOX)
			var sy := y0 + int(float(by) * h / BOX)
			out[by * BOX + bx] = 1 if fr.get_pixel(sx, sy).a >= 0.5 else 0
	return out


func _iou(a: PackedByteArray, b: PackedByteArray, mirror_b: bool) -> float:
	var both := 0
	var either := 0
	for y in BOX:
		for x in BOX:
			var p := a[y * BOX + x]
			var q := b[y * BOX + (BOX - 1 - x if mirror_b else x)]
			both += 1 if p and q else 0
			either += 1 if p or q else 0
	return float(both) / maxf(1.0, float(either))


func _rgba(path: String) -> Image:
	var img: Image = (load(path) as Texture2D).get_image().duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


func facing_margin(world: Image, artist: Image, frames: Array) -> float:
	var total := 0.0
	for pair in frames:
		var a := _mask(world, pair[0])
		var b := _mask(artist, pair[1])
		total += _iou(a, b, false) - _iou(a, b, true)
	return total / maxf(1.0, float(frames.size()))


func _world_sheets() -> Array:
	## [job, anim, suffix] for every world battle sheet with an artist sheet beside it.
	var out: Array = []
	var root := "res://assets/sprites/jobs/"
	for job in DirAccess.get_directories_at(root):
		for anim in ANIMS:
			if not ResourceLoader.exists(root + job + "/" + anim + ".png"):
				continue
			for suffix in Loader.WORLD_SUFFIXES:
				if suffix != "" and ResourceLoader.exists("%s%s/%s_%s.png" % [root, job, anim, suffix]):
					out.append([job, anim, suffix])
	return out


func test_every_world_sheet_faces_the_way_its_artist_sheet_does() -> void:
	var sheets := _world_sheets()
	assert_gt(sheets.size(), 190, "CONTROL: the world battle sheets were found (%d)" % sheets.size())
	var bad: Array = []
	for s in sheets:
		var root := "res://assets/sprites/jobs/%s/" % s[0]
		var world := _rgba(root + "%s_%s.png" % [s[1], s[2]])
		var artist := _rgba(root + "%s.png" % s[1])
		var nw: int = world.get_width() / 256
		var na: int = artist.get_width() / 256
		var frames: Array = []
		for i in ([0] if s[1] == "idle" else [0, nw / 2, nw - 1]):
			frames.append([i, 0 if s[1] == "idle" else mini(i, na - 1)])
		var m := facing_margin(world, artist, frames)
		if m < MIRRORED_BELOW:
			bad.append("%s %s_%s: %+.2f (drawn facing the other way)" % [s[0], s[1], s[2], m])
	assert_eq(bad, [], "%d world sheet(s) face away from where their artist sheet faces: %s" % [bad.size(), str(bad.slice(0, 8))])


func test_the_measure_tells_a_figure_from_its_mirror() -> void:
	## Positive control: an asymmetric figure (a body with an arm out to one side) against itself and its mirror.
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(100, 60, 50, 140), Color.WHITE)
	img.fill_rect(Rect2i(40, 90, 60, 14), Color.WHITE)
	var mirrored := img.duplicate() as Image
	mirrored.flip_x()
	assert_gt(facing_margin(img, img, [[0, 0]]), 0.3, "a figure faces the way it faces")
	assert_lt(facing_margin(mirrored, img, [[0, 0]]), MIRRORED_BELOW, "its mirror faces the other way")
