extends GutTest

## The final boss changed faces between her cutscene and her fight. world6_calibrant_intro asks for the portrait key
## "calibrant" and shows portraits/calibrant.png. The battle that follows asks by the MONSTER id, "the_calibrant",
## which the portrait table did not name, so the boss intro fell back to a bust cut from her battle sheet: a 128px
## sheet she shares with Chancellor Mordaine, shown at 36px and scaled up, a different and blurry woman.
## Found 2026-10-12 by rendering the boss intro box for 18 bosses and looking. Same class as
## test_portrait_identity_class_regression (one character, two keys, two faces), on the boss-intro surface.
## A monster whose id is "the_<key>" for a portrait key is that character and shows that face.

const Dialogue := preload("res://src/cutscene/CutsceneDialogue.gd")

var _art: Node = null


func before_all() -> void:
	_art = Dialogue.new()


func after_all() -> void:
	if _art:
		_art.free()


func _monster_ids() -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var monsters: Dictionary = parsed.get("monsters", parsed) if parsed is Dictionary else {}
	return monsters.keys()


func test_the_calibrant_fights_with_the_face_her_cutscene_shows() -> void:
	var cutscene_face := str(Dialogue.PORTRAIT_SPRITES.get("calibrant", ""))
	assert_true(ResourceLoader.exists(cutscene_face), "CONTROL: the cutscene key names a real portrait (%s)" % cutscene_face)
	var boss_face: Texture2D = _art.monster_art("the_calibrant")
	assert_not_null(boss_face, "the Calibrant has a face in her boss intro")
	assert_eq(boss_face.resource_path, cutscene_face, "the boss intro shows the face the cutscene before it showed")


func test_a_the_named_monster_shares_its_portrait_keys_face() -> void:
	## Derived: every monster "the_<key>" where <key> is a portrait key. The Calibrant is the one today.
	var ids := _monster_ids()
	assert_gt(ids.size(), 90, "CONTROL: the monsters were read (%d)" % ids.size())
	var pairs := 0
	var split: Array = []
	for id in ids:
		var key := str(id).trim_prefix("the_")
		if key == str(id) or not Dialogue.PORTRAIT_SPRITES.has(key):
			continue
		pairs += 1
		var face: Texture2D = _art.monster_art(str(id))
		var want := str(Dialogue.PORTRAIT_SPRITES[key])
		if face == null or face.resource_path != want:
			split.append("%s shows %s, its cutscene key '%s' shows %s" % [id, face.resource_path.get_file() if face else "nothing", key, want.get_file()])
	assert_gt(pairs, 0, "CONTROL: the Calibrant pair was reached (%d)" % pairs)
	assert_eq(split, [], "one character, two faces across cutscene and battle: %s" % str(split))
