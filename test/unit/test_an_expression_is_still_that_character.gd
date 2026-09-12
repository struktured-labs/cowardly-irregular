extends GutTest

## THE BARD'S FIRST LINE OF THE GAME HAD A GENERATED FACE.
##
## 2026-09-12. Seven dialogue lines across five scenes name a party member with a mood —
## `bard_happy`, `cleric_sad`, `fighter_determined`, `rogue_surprised`, `bard_surprised`.
## None of those ids is a `PORTRAIT_SPRITES` key and none is a job folder, so both
## resolution rungs missed and `_create_portrait` fell through to PROCEDURAL generation:
## a synthesised face where the character's own portrait belongs.
##
## Where it lands is the reason this is worth a branch rather than a note:
##   world1_prologue    Bard  "What a tale this shall be!"     the opening cutscene
##   world6_ending      Bard  "…room for the ones who…"        the closing cutscene
##   world1_warden_defeat  Fighter · Cleric · Bard             three in one scene
##   world1_rat_king_defeat · world4_chapter4
##
## ⚠️ WHAT THIS DOES NOT CLAIM. It asserts the RESOLUTION reaches the character's texture,
## not that a player sees a particular face — no dialogue box is built here. `system`,
## `narrator` and `goblin` also miss both rungs and are deliberately left alone: they have
## no base id in the map, and a narrator having no face is a decision, not a defect.

const DIALOGUE := preload("res://src/cutscene/CutsceneDialogue.gd")
const SCENES := "res://data/cutscenes"

## Ids measured in the corpus on 2026-09-12, by NAME rather than by count — a floor
## passes while members quietly leave it.
const EXPRESSION_IDS: Array[String] = [
	"bard_happy", "cleric_sad", "fighter_determined", "rogue_surprised", "bard_surprised",
]

## Deliberately unresolved: no base id exists for these, so they keep the procedural face.
const FACELESS_IDS: Array[String] = ["system", "narrator"]

var _cache: Dictionary = {}


## Every portrait id the authored scenes actually name, walked recursively — portraits
## live inside `lines`, not on the step. A top-level `step["portrait"]` scan reports ZERO
## across all 197 files, which reads exactly like "no scene names a portrait".
func _used_portrait_ids() -> Dictionary:
	if _cache.has("used"):
		return _cache["used"]
	var out: Dictionary = {}
	var dir := DirAccess.open(SCENES)
	assert_true(dir != null, "the cutscene corpus must be readable")
	if dir == null:
		return out
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if name.ends_with(".json"):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SCENES + "/" + name))
			_collect(parsed, name, out)
		name = dir.get_next()
	dir.list_dir_end()
	_cache["used"] = out
	return out


func _collect(node: Variant, fname: String, out: Dictionary) -> void:
	if node is Dictionary:
		var d: Dictionary = node
		var p: Variant = d.get("portrait", null)
		if p is String and str(p) != "":
			if not out.has(str(p)):
				out[str(p)] = []
			(out[str(p)] as Array).append(fname)
		for k in d.keys():
			_collect(d[k], fname, out)
	elif node is Array:
		for v in (node as Array):
			_collect(v, fname, out)


## PREMISE. The corpus still names these ids, and the walk still finds portraits at all.
func test_premise_the_expression_ids_are_still_authored() -> void:
	assert_gte(EXPRESSION_IDS.size(), 5,
		"EXPRESSION_IDS holds %d, fewer than the 5 measured — the loop below is going vacuous" % EXPRESSION_IDS.size())
	var used := _used_portrait_ids()
	assert_gt(used.size(), 30,
		"only %d portrait ids found in the corpus; the recursive walk is not reaching `lines` and every arm below passes on nothing" % used.size())
	var absent: Array[String] = []
	for id in EXPRESSION_IDS:
		if not used.has(id):
			absent.append(id)
	assert_eq(absent.size(), 0,
		"a scene stopped naming an expression id: %s — if the data moved, this file is about ids that no longer exist" % ", ".join(absent))


## CONTROL, both directions, on the rungs themselves.
func test_the_resolver_answers_both_ways() -> void:
	var d = DIALOGUE.new()
	assert_true(d.PORTRAIT_SPRITES.has("bard"),
		"CONTROL: the base id must be in the map, or the fallback below has nothing to find")
	assert_false(d.PORTRAIT_SPRITES.has("bard_happy"),
		"CONTROL: if the expression id is now mapped directly, the fallback is redundant — delete it and this file together")
	d.free()


## THE BUG. Each expression id must resolve to the SAME texture as its character.
func test_an_expression_resolves_to_the_characters_own_portrait() -> void:
	var d = DIALOGUE.new()
	var wrong: Array[String] = []
	for id in EXPRESSION_IDS:
		var base: String = id.get_slice("_", 0)
		var got: Texture2D = d._create_portrait(id)
		var want: Texture2D = d._create_portrait(base)
		if got == null or want == null or got != want:
			wrong.append("%s -> %s" % [id, base])
	assert_eq(wrong.size(), 0,
		"an expression id did not resolve to its character's portrait: %s — the speaker gets a procedurally generated face in their own scene" % ", ".join(wrong))
	d.free()


## The faceless ids keep their procedural face — the fallback must not invent a character
## for `system` or `narrator`, which have no base id at all.
func test_the_faceless_ids_are_left_alone() -> void:
	var d = DIALOGUE.new()
	for id in FACELESS_IDS:
		assert_false(d.PORTRAIT_SPRITES.has(id.get_slice("_", 0)),
			"%s now has a base portrait; it would stop being faceless and that is a content decision, not this fix" % id)
	d.free()
