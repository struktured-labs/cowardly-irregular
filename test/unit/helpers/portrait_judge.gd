extends RefCounted

## Judges what a TextureRect DRAWS of a portrait: the scale its texture's pixels reach the screen at, and how close those
## pixels are to an exact AREA AVERAGE of the source — a reference no resampler in the game produces. A nearest drop
## scores 1.0x of its own error by definition; Lanczos measured 0.09-0.23x on all 88 authored files.

## The shown face's error against the area average, as a fraction of a nearest drop's error on the same art.
const MAX_ERROR_VS_DROP := 0.5
## Below this a drop is invisible and so is any fix: the least-detailed authored file measured 0.0104.
const MIN_DROP_ERROR := 0.005


## A copy of `tex`'s pixels as RGBA8 — a copy, because the headless renderer hands back the texture's own Image.
static func pixels(tex: Texture2D) -> Image:
	var img: Image = tex.get_image().duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


## Screen pixels per texture pixel, from the stretch mode and the rect's own scale.
static func drawn_scale(rect: TextureRect) -> float:
	var t := rect.texture
	var k := 1.0
	match rect.stretch_mode:
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED, TextureRect.STRETCH_KEEP_ASPECT, TextureRect.STRETCH_SCALE:
			k = minf(rect.size.x / t.get_width(), rect.size.y / t.get_height())
		TextureRect.STRETCH_KEEP_ASPECT_COVERED:
			k = maxf(rect.size.x / t.get_width(), rect.size.y / t.get_height())
	return k * rect.scale.x


static func area_average(src: Image, w: int, h: int) -> PackedFloat32Array:
	## Exact area average of premultiplied RGB at w x h: each output pixel is the mean of the source it covers.
	var sw := src.get_width()
	var sh := src.get_height()
	var d := src.get_data()
	var sx := float(sw) / w
	var sy := float(sh) / h
	var rows := PackedFloat32Array()
	rows.resize(w * sh * 3)
	for y in sh:
		for x in w:
			var a0 := x * sx
			var a1 := a0 + sx
			var acc := Vector3.ZERO
			var i := int(floor(a0))
			while i < sw and float(i) < a1:
				var o := (y * sw + i) * 4
				var k := (minf(a1, i + 1.0) - maxf(a0, float(i))) * d[o + 3] / 255.0 / 255.0
				acc += Vector3(d[o], d[o + 1], d[o + 2]) * k
				i += 1
			for c in 3:
				rows[(y * w + x) * 3 + c] = acc[c] / sx
	var out := PackedFloat32Array()
	out.resize(w * h * 3)
	for x in w:
		for y in h:
			var b0 := y * sy
			var b1 := b0 + sy
			var acc := Vector3.ZERO
			var j := int(floor(b0))
			while j < sh and float(j) < b1:
				var k := minf(b1, j + 1.0) - maxf(b0, float(j))
				acc += Vector3(rows[(j * w + x) * 3], rows[(j * w + x) * 3 + 1], rows[(j * w + x) * 3 + 2]) * k
				j += 1
			for c in 3:
				out[(y * w + x) * 3 + c] = acc[c] / sy
	return out


static func error(img: Image, ref: PackedFloat32Array) -> float:
	var d := img.get_data()
	var n := img.get_width() * img.get_height()
	var t := 0.0
	for p in n:
		var al := d[p * 4 + 3] / 255.0
		for c in 3:
			t += absf(d[p * 4 + c] / 255.0 * al - ref[p * 3 + c])
	return t / float(n * 3)


## "" when `rect` draws `source` (pixels captured BEFORE the surface was built) resampled 1:1 and close to its area
## average; otherwise why not.
static func judge(label: String, rect: TextureRect, source: Image) -> String:
	if rect == null or rect.texture == null:
		return "%s: no face shown" % label
	var scale := drawn_scale(rect)
	if absf(scale - 1.0) > 0.001:
		return "%s: %dx%d art drawn at %.3fx" % [label, rect.texture.get_width(), rect.texture.get_height(), scale]
	var drawn := pixels(rect.texture)
	var ref := area_average(source, drawn.get_width(), drawn.get_height())
	var dropped := source.duplicate() as Image
	dropped.resize(drawn.get_width(), drawn.get_height(), Image.INTERPOLATE_NEAREST)
	var drop_err := error(dropped, ref)
	if drop_err < MIN_DROP_ERROR:
		return "%s: CONTROL: a pixel drop of this art is only %.4f off, so nothing here can be judged" % [label, drop_err]
	var err := error(drawn, ref)
	if err > drop_err * MAX_ERROR_VS_DROP:
		return "%s: %.4f off the area average, a pixel drop is %.4f" % [label, err, drop_err]
	return ""
