extends GutTest

## Every scholar in the game spoke with a tiny full-body sprite where everyone else has a face. PORTRAIT_SPRITES sent
## the "scholar" type, the fallback for the apprentice, the herbalist, Sprocket and every generic scholar, to
## npcs/scholar.png: 192x166, a whole standing figure in an older style, shrunk into the same box as the 256x256 busts
## beside it. A proper scholar bust (npcs/scholarly.png) had sat next to it since the 2026-07-31 batch, wired only to
## the "scholarly" spelling. Nothing failed: any image is a legal portrait. Found 2026-10-12 on a sheet of all 165.
## A dialogue face is a 256x256 bust. The table is read from the script itself, not from its source text.

const Dialogue := preload("res://src/cutscene/CutsceneDialogue.gd")
const BUST := Vector2i(256, 256)
## Faces that are not busts yet, each with why. Named so the gap is visible; the list may only shrink.
const NOT_A_BUST_YET := {
	"res://assets/sprites/portraits/npcs/brigadier.png": "96x96, an early low-resolution portrait with a stray white stroke; no bust of him exists",
}


func _faces() -> Dictionary:
	## path -> [the keys that show it], for every portrait the table names.
	var out := {}
	for key in Dialogue.PORTRAIT_SPRITES:
		var path := str(Dialogue.PORTRAIT_SPRITES[key])
		if not out.has(path):
			out[path] = []
		(out[path] as Array).append(str(key))
	return out


func test_every_dialogue_face_is_a_256_bust() -> void:
	var faces := _faces()
	assert_gt(faces.size(), 80, "CONTROL: the portrait table was read (%d distinct faces)" % faces.size())
	var odd: Array = []
	for path in faces:
		if not ResourceLoader.exists(path):
			continue
		var tex := load(path) as Texture2D
		var size := Vector2i(tex.get_width(), tex.get_height())
		if NOT_A_BUST_YET.has(path):
			assert_ne(size, BUST, "%s is a bust now: drop it from NOT_A_BUST_YET" % path)
		elif size != BUST:
			odd.append("%s is %dx%d, shown for %s" % [str(path).get_file(), size.x, size.y, str(faces[path])])
	assert_eq(odd, [], "dialogue faces that are not 256x256 busts: %s" % str(odd))


func test_a_scholar_speaks_with_the_scholar_bust() -> void:
	## The named case, through the table the game reads.
	var path := str(Dialogue.PORTRAIT_SPRITES.get("scholar", ""))
	assert_true(ResourceLoader.exists(path), "CONTROL: the scholar type names a real file (%s)" % path)
	var tex := load(path) as Texture2D
	assert_eq(Vector2i(tex.get_width(), tex.get_height()), BUST, "the scholar type shows a bust, not a small standing figure")
	assert_eq(path, str(Dialogue.PORTRAIT_SPRITES.get("scholarly", "")), "scholar and scholarly are one type and wear one face")


func test_the_named_exceptions_are_real_files() -> void:
	for path in NOT_A_BUST_YET:
		assert_true(_faces().has(path), "%s is listed but the table no longer names it" % path)
		assert_ne(str(NOT_A_BUST_YET[path]), "", "%s says why it is not a bust yet" % path)
