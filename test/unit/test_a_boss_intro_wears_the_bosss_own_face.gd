extends GutTest

## Post-demo list (cowir-main 22449): the four dragons and the Lost Cartographer spoke their whole intros under the
## hooded "mysterious" face while their battle sheets sat on disk, one cave away from the fight that shows them.
## CutsceneDialogue already crops a bust from a monster's battle sheet; the intros just never asked for it.
## Corpus is DERIVED: every dungeon script that names both a boss_id and a boss_cutscene_id.

const DUNGEONS := "res://src/maps/dungeons/"
const DIALOGUE := "res://src/cutscene/CutsceneDialogue.gd"

var _dialogue: Node = null


func _d() -> Node:
	if _dialogue == null:
		_dialogue = load(DIALOGUE).new()
		autofree(_dialogue)
	return _dialogue


## {boss_id: cutscene_id}, read from each dungeon's source.
func _bosses() -> Dictionary:
	var out := {}
	var boss_re := RegEx.create_from_string('(?m)^\\s*boss_id = "([^"]+)"')
	var cut_re := RegEx.create_from_string('(?m)^\\s*boss_cutscene_id = "([^"]+)"')
	for f in DirAccess.get_files_at(DUNGEONS):
		if not f.ends_with(".gd"):
			continue
		var src := FileAccess.get_file_as_string(DUNGEONS + f)
		var b := boss_re.search(src)
		var c := cut_re.search(src)
		if b != null and c != null:
			out[b.get_string(1)] = c.get_string(1)
	return out


func _lines(cutscene_id: String) -> Array:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/cutscenes/%s.json" % cutscene_id))
	var out: Array = []
	if data is Dictionary:
		for step in data.get("steps", []):
			if step is Dictionary and str(step.get("type", "")) == "dialogue":
				for line in step.get("lines", []):
					if line is Dictionary and str(line.get("portrait", "")) != "":
						out.append(line)
	return out


func test_the_corpus_was_read() -> void:
	var bosses := _bosses()
	assert_gt(bosses.size(), 9, "floor: the dungeon scripts were read (%s)" % str(bosses.keys()))
	assert_true(bosses.has("fire_dragon"), "CONTROL: Pyrroth's cave is in the corpus")
	for b in bosses:
		assert_gt(_lines(bosses[b]).size(), 0, "%s's intro %s has dialogue" % [b, bosses[b]])


func test_no_boss_with_art_hides_under_the_hood() -> void:
	var bosses := _bosses()
	var hooded: Array = []
	for b in bosses:
		if _d().monster_art(b) == null:
			continue
		for line in _lines(bosses[b]):
			if str(line["portrait"]) == "mysterious":
				hooded.append("%s: %s" % [bosses[b], line.get("speaker", "?")])
	assert_eq(hooded, [], "a boss whose battle sheet exists speaks under its own face, not the hood")


## The key names the monster, and the resolver must actually reach its sheet: a job or mood rung answering first
## (fire_dragon -> "fire") would show a stranger's face with the right-looking key.
func test_a_boss_keyed_line_shows_its_battle_sheet() -> void:
	var bosses := _bosses()
	var seen := 0
	for b in bosses:
		var art: Texture2D = _d().monster_art(b)
		for line in _lines(bosses[b]):
			if str(line["portrait"]) != b:
				continue
			seen += 1
			var tex: Texture2D = _d().portrait_texture(b)
			assert_not_null(art, "%s has battle art to show" % b)
			assert_true(tex != null and not (tex is ImageTexture), "%s's line is art, not a drawn face" % b)
			if tex is AtlasTexture and art is AtlasTexture:
				assert_eq((tex as AtlasTexture).region, (art as AtlasTexture).region, "%s: the bust is the monster's own crop" % b)
				assert_eq((tex as AtlasTexture).atlas, (art as AtlasTexture).atlas, "%s: from its own sheet" % b)
			break
	assert_gt(seen, 4, "floor: the four dragons and the cartographer each name themselves (%d bosses)" % seen)
