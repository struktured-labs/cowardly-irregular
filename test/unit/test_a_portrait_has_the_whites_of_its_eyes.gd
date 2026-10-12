extends GutTest

## 102 of 165 dialogue portraits had see-through holes inside the figure. The AI portraits were generated on a white
## backdrop and keyed on near-white, and the key took everything else that white with it: the whites of the eyes,
## teeth, the glint on a lens. In a conversation the speaker's eyes showed the dialogue panel through them. Nothing
## failed: a clear pixel inside a face is a legal pixel. Found 2026-10-12 by laying every portrait on a magenta sheet.
## tools/fill_portrait_key_holes.py fills every enclosed hole of up to MAX_HOLE px (near-white from 5 px, the rim's
## own colour for a speck). Larger holes are a whole keyed face or veil, or a real opening, and are NOT covered here:
## they need a decision per portrait. Busts cut from the artist's own sheets are his and are skipped.

const PORTRAITS := "res://assets/sprites/portraits/"
const MAX_HOLE := 160
const ARTIST_DERIVED := ["fighter.png", "cleric.png", "mage.png", "rogue.png", "bard.png", "mordaine.png", "chancellor_mordaine.png", "calibrant.png"]


func small_hole_pixels(img: Image) -> int:
	## Clear pixels in regions the figure fully encloses (4-connected) that are no larger than MAX_HOLE.
	var w := img.get_width()
	var h := img.get_height()
	var d := img.get_data()
	var seen := PackedByteArray()
	seen.resize(w * h)
	var total := 0
	for start in w * h:
		if seen[start] or d[start * 4 + 3] >= 128:
			continue
		seen[start] = 1
		var stack := PackedInt32Array([start])
		var size := 0
		var enclosed := true
		while not stack.is_empty():
			var p := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			size += 1
			var x := p % w
			var y := p / w
			if x == 0 or y == 0 or x == w - 1 or y == h - 1:
				enclosed = false
			for q in [p - 1 if x > 0 else -1, p + 1 if x < w - 1 else -1, p - w if y > 0 else -1, p + w if y < h - 1 else -1]:
				if q >= 0 and not seen[q] and d[q * 4 + 3] < 128:
					seen[q] = 1
					stack.append(q)
		if enclosed and size <= MAX_HOLE:
			total += size
	return total


func _portraits(dir: String) -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".png") and not ARTIST_DERIVED.has(f):
			out.append(dir + f)
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_portraits(dir + sub + "/"))
	return out


func _rgba(path: String) -> Image:
	var img: Image = (load(path) as Texture2D).get_image().duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


func test_no_portrait_has_a_keyed_hole_in_its_face() -> void:
	var paths := _portraits(PORTRAITS)
	assert_gt(paths.size(), 140, "CONTROL: the portraits were found (%d)" % paths.size())
	var holed: Array = []
	for path in paths:
		var n := small_hole_pixels(_rgba(path))
		if n > 0:
			holed.append("%s: %d px" % [path.trim_prefix(PORTRAITS), n])
	assert_eq(holed, [], "%d portrait(s) with see-through eyes or teeth (tools/fill_portrait_key_holes.py): %s" % [holed.size(), str(holed.slice(0, 8))])


func test_the_measure_tells_a_keyed_eye_from_the_backdrop() -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(8, 8, 48, 48), Color8(200, 150, 120))
	assert_eq(small_hole_pixels(img), 0, "a whole face has no hole, and the clear backdrop is not one")
	img.fill_rect(Rect2i(16, 20, 8, 4), Color(0, 0, 0, 0))
	assert_eq(small_hole_pixels(img), 32, "an eye-sized clear patch inside the face is a hole")
	img.fill_rect(Rect2i(28, 30, 20, 20), Color(0, 0, 0, 0))
	assert_eq(small_hole_pixels(img), 32, "a 400 px opening is beyond this measure and not counted")
	var notch := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	notch.fill(Color8(200, 150, 120))
	notch.fill_rect(Rect2i(0, 30, 3, 2), Color(0, 0, 0, 0))
	assert_eq(small_hole_pixels(notch), 0, "a notch open to the image edge is not enclosed")
