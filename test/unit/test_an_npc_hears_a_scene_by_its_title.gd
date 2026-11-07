extends GutTest

## GameLoop logs a finished story cutscene as "Cutscene complete: <file id>", and every NPC prompt's recent-events block
## printed that summary, so a townsperson could be told "world1_mordaine_intro" and say it back. The block now shows the
## scene's authored title ("Witnessed ..."), or drops the line when none resolves; old saves' logged ids are read the same way.

const DP := preload("res://src/llm/DialoguePrompts.gd")
const SCENE := "world1_mordaine_intro"


func _logged(cid: String) -> Dictionary:
	return {"type": EventLog.TYPE_STORY_FLAG, "summary": "Cutscene complete: %s" % cid, "data": {"cutscene_id": cid, "flag": "x"}}


func _prompt(events: Array) -> String:
	return DP.build_npc_opening("Theron", "an elder", "Harmonia", events)


func test_a_finished_scene_reaches_the_npc_by_its_title() -> void:
	var title: String = DP.cutscene_title(SCENE)
	assert_ne(title, "", "CONTROL: the scene has an authored title to show")
	assert_false(title.contains("_"), "CONTROL: that title is not itself an id")
	var p: String = _prompt([_logged(SCENE)])
	assert_string_contains(p, "Witnessed \"%s\"" % title, "the NPC hears the scene as the player saw it")
	assert_false(p.contains(SCENE), "THE DEFECT: the NPC was handed the scene's file id")


func test_every_story_scene_has_a_title_to_show() -> void:
	var dir := DirAccess.open("res://data/cutscenes")
	assert_not_null(dir, "CONTROL: the cutscene folder opens")
	if dir == null:
		return
	var seen: int = 0
	var missing: PackedStringArray = PackedStringArray()
	for f in dir.get_files():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/cutscenes/" + f)) if f.ends_with(".json") else null
		if not (parsed is Dictionary and (parsed as Dictionary).has("steps")):
			continue  # not a scene (npc_showcase_personas.json lives here too)
		seen += 1
		if DP.cutscene_title(f.get_basename()) == "":
			missing.append(f.get_basename())
	assert_gt(seen, 100, "CONTROL: the cutscene corpus is real (%d files)" % seen)
	assert_eq(missing.size(), 0, "these scenes have no title, so an NPC would hear nothing of them: %s" % ", ".join(missing))


func test_an_unknown_scene_says_nothing_and_other_events_are_untouched() -> void:
	var p: String = _prompt([_logged("no_such_scene_xyz"), {"type": "battle", "summary": "The Rat King fell"},
		{"type": EventLog.TYPE_STORY_FLAG, "summary": "Calibrant glimpsed", "data": {"flag": "calibrant_seen"}}])
	assert_false(p.contains("no_such_scene_xyz"), "an unresolvable id is dropped, never shown")
	assert_string_contains(p, "The Rat King fell", "an ordinary event keeps its summary")
	assert_string_contains(p, "Calibrant glimpsed", "a story flag that names no cutscene keeps its summary")
