extends GutTest

## struktured 2026-11-01 (via cowir-main 21340/21341), on Harmonia's fountain: "the water animation can be even more dynamic
## looking ... looks like just lighting right now". A brightness cycle changes every frame and moves nothing; this guard
## asks for water that TRAVELS: down the streams, from one frame to the next.

const VillageFountainScript := preload("res://src/exploration/VillageFountain.gd")


func _entry() -> Dictionary:
	return VillageProp.prop_art_entry("fountain", "medieval")


func _frames() -> Array:
	var e := _entry()
	var img: Image = (load(str(e["path"])) as Texture2D).get_image()
	var n: int = int(e.get("frames", 1))
	var w: int = img.get_width() / n
	var out: Array = []
	for i in range(n):
		out.append(img.get_region(Rect2i(i * w, 0, w, img.get_height())))
	return out


func _lum(img: Image, x: int, y: int) -> float:
	var c := img.get_pixel(x, y)
	return (c.r + c.g + c.b) * c.a


## The column whose pixels change most across the loop: a stream, wherever the art draws one.
func _busiest_column(frames: Array) -> int:
	var best := -1
	var best_v := 0.0
	var f0: Image = frames[0]
	for x in range(f0.get_width()):
		var v := 0.0
		for i in range(1, frames.size()):
			for y in range(f0.get_height()):
				v += absf(_lum(frames[i], x, y) - _lum(frames[i - 1], x, y))
		if v > best_v:
			best_v = v
			best = x
	return best


## The rows of column x that change at all across the loop: the moving water, without the static stone around it.
func _moving_rows(frames: Array, x: int) -> Vector2i:
	var lo := -1
	var hi := -1
	var f0: Image = frames[0]
	for y in range(f0.get_height()):
		var v := 0.0
		for i in range(1, frames.size()):
			v += absf(_lum(frames[i], x, y) - _lum(frames[i - 1], x, y))
		if v > 0.01:
			lo = y if lo < 0 else lo
			hi = y + 1
	return Vector2i(maxi(lo, 3), mini(hi, f0.get_height() - 3))


## The vertical shift d in [-3, 3] that best maps frame a's column profile onto frame b's (b[y] ~ a[y - d]), over rows r.
func _shift(a: Image, b: Image, x: int, r: Vector2i) -> int:
	var best_d := 0
	var best_err := INF
	for d in range(-3, 4):
		var err := 0.0
		for y in range(r.x, r.y):
			err += absf(_lum(b, x, y) - _lum(a, x, y - d))
		if err < best_err - 0.001:
			best_err = err
			best_d = d
	return best_d


func test_the_fountain_has_enough_frames_to_move() -> void:
	var e := _entry()
	assert_false(e.is_empty(), "CONTROL: the medieval fountain is drawn")
	assert_gte(int(e.get("frames", 1)), 8, "a fountain whose water travels needs more than a 4-frame flicker")
	assert_gt(float(e.get("fps", 0.0)), 4.0, "the frames play faster than the old 4 fps flicker")


func test_the_water_travels_down_the_streams() -> void:
	var frames := _frames()
	var x := _busiest_column(frames)
	assert_gt(x, -1, "CONTROL: some column of the fountain changes across the loop")
	var rows := _moving_rows(frames, x)
	assert_gt(rows.y - rows.x, 4, "CONTROL: column %d moves over more than a few rows" % x)
	var down := 0
	var still := 0
	for i in range(frames.size()):
		var d := _shift(frames[i], frames[(i + 1) % frames.size()], x, rows)
		if d > 0:
			down += 1
		elif d == 0:
			still += 1
	assert_gt(down, frames.size() / 2, "column %d: only %d of %d frame steps move the water DOWN (%d stand still: a brightness cycle)" % [x, down, frames.size(), still])


func test_the_fountain_plays_at_its_declared_rate() -> void:
	var f = VillageFountainScript.new()
	f.art_world = "medieval"
	add_child_autofree(f)
	await get_tree().process_frame
	assert_eq(f._sprite_frames.size(), int(_entry().get("frames", 1)), "the fountain did not load every drawn frame")
	assert_almost_eq(f._frame_time, 1.0 / float(_entry().get("fps", 4.0)), 0.001, "the fountain ignores its drawn frame rate")
