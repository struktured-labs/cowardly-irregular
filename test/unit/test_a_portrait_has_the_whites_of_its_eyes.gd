extends GutTest

## 102 of 165 dialogue portraits had see-through holes inside the figure. The AI portraits were generated on a white
## backdrop and keyed on near-white, and the key took everything else that white with it: the whites of the eyes,
## teeth, the glint on a lens. In a conversation the speaker's eyes showed the dialogue panel through them. Nothing
## failed: a clear pixel inside a face is a legal pixel. Found 2026-10-12 by laying every portrait on a magenta sheet.
## tools/fill_portrait_key_holes.py fills every enclosed hole of up to MAX_HOLE px (near-white from 5 px, the rim's
## own colour for a speck). Larger holes are a whole keyed face or veil, or a real opening, and are NOT covered here:
## they need a decision per portrait: REVIEWED_LARGE (looked at, filled) and LEFT_OPEN (looked at, left) below.
## Busts cut from the artist's own sheets are his and are skipped.

const PORTRAITS := "res://assets/sprites/portraits/"
const MAX_HOLE := 160
## Second pass: holes above MAX_HOLE, zoomed one portrait at a time and found to be keyed white (eye whites just over
## the cap, teeth, a white veil, hood lining, collar or hair). Each names the largest hole that must now be gone.
const REVIEWED_LARGE := {
	"bossbinder.png": 492, "cleric_abstract.png": 5398, "cleric_digital.png": 397,
	"cleric_industrial.png": 785, "cleric_steampunk.png": 954, "cleric_suburban.png": 2056,
	"keepers/brutus.png": 200, "keepers/lenora.png": 2527, "masterite_arbiter_medieval.png": 1197,
	"ninja.png": 295, "npcs/boris.png": 328, "npcs/bram.png": 175,
	"npcs/child.png": 251, "npcs/dr_temporal.png": 246, "npcs/elder.png": 247,
	"npcs/guard.png": 196, "npcs/knight.png": 176, "npcs/nervous.png": 271,
	"npcs/pilgrim.png": 892, "npcs/pip.png": 198, "npcs/rowan.png": 426,
	"npcs/shopkeeper.png": 340, "npcs/villager_f.png": 351, "npcs/young_woman.png": 173,
	"scriptweaver.png": 337, "skiptrotter.png": 193, "speculator_abstract.png": 181,
	"summoner_suburban.png": 221, "time_mage.png": 295, "time_mage_industrial.png": 344,
	"time_mage_steampunk.png": 195, "time_mage_suburban.png": 333,
}
## Left open on purpose, each with why. A fill here is an art decision or would paint a real gap shut.
const LEFT_OPEN := {
	"mage_abstract.png": "the staff's ring and the gap between staff and robe are real openings",
	"mage_industrial.png": "the gap between staff and body is a real opening",
	"mage_suburban.png": "the staff's crystal frame is open",
	"masterite_curator_medieval.png": "the face under the hood is keyed out; white or shadow is an art call",
	"ninja.png": "the ring round the eye slit is keyed out; what colour it was is not recoverable by rule",
	"npcs/fairy.png": "the patch by her raised hand may be the gap between arm and body",
	"npcs/hooded_mage.png": "the whole face is keyed out; a white mask or a shadow is an art call",
	"npcs/mysterious.png": "the whole face is keyed out; a white mask or a shadow is an art call",
}
const ARTIST_DERIVED := ["fighter.png", "cleric.png", "mage.png", "rogue.png", "bard.png", "mordaine.png", "chancellor_mordaine.png", "calibrant.png"]


func small_hole_pixels(img: Image, cap: int = MAX_HOLE, floor: int = 1) -> int:
	## Clear pixels in regions the figure fully encloses (4-connected) whose size is within floor..cap.
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
		if enclosed and size <= cap and size >= floor:
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


func test_a_reviewed_portrait_has_its_larger_holes_filled() -> void:
	var holed: Array = []
	for key in REVIEWED_LARGE:
		assert_true(ResourceLoader.exists(PORTRAITS + key), "CONTROL: %s is a portrait" % key)
		assert_false(ARTIST_DERIVED.has(str(key).get_file()), "%s is an artist bust and must not be on this list" % key)
		var n := small_hole_pixels(_rgba(PORTRAITS + key), int(REVIEWED_LARGE[key]))
		if n > 0:
			holed.append("%s: %d px" % [key, n])
	assert_eq(holed, [], "reviewed portraits that still show the panel through a keyed patch: %s" % str(holed))


func test_a_portrait_left_open_is_named_with_its_reason() -> void:
	## Every portrait that still has a hole above MAX_HOLE is on LEFT_OPEN or REVIEWED_LARGE, and the open ones stay open.
	var unnamed: Array = []
	for path in _portraits(PORTRAITS):
		var key: String = path.trim_prefix(PORTRAITS)
		var big := small_hole_pixels(_rgba(path), 1 << 30, MAX_HOLE + 1)
		if LEFT_OPEN.has(key):
			assert_gt(big, 0, "%s has no large hole now: drop it from LEFT_OPEN" % key)
			assert_ne(str(LEFT_OPEN[key]), "", "%s says why it is left open" % key)
		elif big > 0 and int(REVIEWED_LARGE.get(key, 0)) <= MAX_HOLE:
			unnamed.append("%s: %d px" % [key, big])
	assert_eq(unnamed, [], "portraits with a large see-through patch nobody has looked at: %s" % str(unnamed))


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
