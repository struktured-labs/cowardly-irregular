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


## Bosses fought straight after a cutscene in which they speak, where the cutscene asks for one portrait key and the
## battle asks by a differently named monster id: monster id -> [cutscene file, the portrait key it uses for them].
## Found by listing every portrait key that shares a name with a monster that has no key of its own (2026-10-12).
const FOUGHT_AFTER_THEIR_CUTSCENE := {
	"cave_rat_king": ["world1_rat_king_intro", "boss_rat_king"],
	"bard_hostile_courtier": ["world1_spotlight_bard_ch7", "courtier"],
}


func test_a_boss_keeps_the_face_from_the_cutscene_before_the_fight() -> void:
	var split: Array = []
	for id in FOUGHT_AFTER_THEIR_CUTSCENE:
		var cutscene: String = FOUGHT_AFTER_THEIR_CUTSCENE[id][0]
		var key: String = FOUGHT_AFTER_THEIR_CUTSCENE[id][1]
		var text := FileAccess.get_file_as_string("res://data/cutscenes/%s.json" % cutscene)
		assert_string_contains(text, '"portrait": "%s"' % key, "CONTROL: %s still shows the '%s' portrait" % [cutscene, key])
		assert_true(_monster_ids().has(id), "CONTROL: %s is a monster" % id)
		var want := str(Dialogue.PORTRAIT_SPRITES.get(key, ""))
		assert_true(ResourceLoader.exists(want), "CONTROL: the key '%s' names a real portrait" % key)
		var face: Texture2D = _art.monster_art(id)
		if face == null or face.resource_path != want:
			split.append("%s: cutscene shows %s, boss intro shows %s" % [id, want.get_file(), face.resource_path.get_file() if face and face.resource_path != "" else "a cut-out of its battle sheet"])
	assert_eq(split, [], "a boss changes faces between its cutscene and its fight: %s" % str(split))
