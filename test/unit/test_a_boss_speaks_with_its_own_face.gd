extends GutTest

## A boss's own intro lines were FACELESS (the portrait frame hidden) — the safe answer after a skeleton
## was once drawn with the hero's face. But every one of the 47 monsters with intro dialogue has a battle
## sheet, and CutsceneDialogue already cuts a bust from a monster sheet (it does so for 396 cutscene lines).
## Now a line whose speaker IS the boss shows that bust; a line spoken by a party member shows their
## portrait and look (the Sneering Courtier duel has the Bard speak, and she spoke in the boss's colours);
## anyone else — a villager — stays faceless. A drawn fallback face is never used for a boss.
## Derived from monsters.json, so a new boss is covered the day it gets intro lines.

const DialogueScript := preload("res://src/ui/BattleDialogue.gd")
const CutsceneDialogueScript := preload("res://src/cutscene/CutsceneDialogue.gd")

var _art: Node = null


func before_all() -> void:
	_art = CutsceneDialogueScript.new()


func after_all() -> void:
	if _art:
		_art.free()


func _monsters() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	return parsed.get("monsters", parsed) if parsed is Dictionary else {}


func _intro_bosses() -> Array:
	var out: Array = []
	var mons := _monsters()
	var ids: Array = mons.keys()
	ids.sort()
	for id in ids:
		var m = mons[id]
		var d = m.get("dialogue", {}) if m is Dictionary else {}
		if d is Dictionary and d.get("intro", []) is Array and not (d.get("intro", []) as Array).is_empty():
			out.append(str(id))
	return out


## Two resolvers cut two AtlasTextures from one sheet; the same face is the same sheet and region.
## `a` as the box draws it: a painted file is shown resampled to the 72px rect, so that is the face to compare.
func _same_face(a: Texture2D, b: Texture2D) -> bool:
	if a is AtlasTexture and b is AtlasTexture:
		return (a as AtlasTexture).atlas == (b as AtlasTexture).atlas and (a as AtlasTexture).region == (b as AtlasTexture).region
	var cell := Vector2(DialogueScript.PORTRAIT_SIZE - 8, DialogueScript.PORTRAIT_SIZE - 8)
	return a == b or a == HybridSpriteLoader.fitted_portrait(b, cell)


## The five starters' faces. A boss id starting "bard_" once resolved to the Bard through the mood rung.
func _job_faces() -> Array:
	var out: Array = []
	for j in ["fighter", "cleric", "mage", "rogue", "bard"]:
		out.append(_art.portrait_art(j))
	return out


func _pc(job_id: String) -> Combatant:
	var pc := Combatant.new()
	pc.combatant_name = job_id.capitalize()
	pc.is_alive = true
	pc.max_hp = 40
	pc.current_hp = 40
	pc.job = JobSystem.get_job(job_id)
	add_child_autofree(pc)
	return pc


func _box(party: Array) -> Node:
	var box = DialogueScript.new()
	add_child_autofree(box)
	box.set_party(party)
	return box


func test_every_intro_boss_line_wears_that_boss_s_bust() -> void:
	var bosses := _intro_bosses()
	assert_gt(bosses.size(), 40, "CONTROL: the intro bosses were read")
	var mons := _monsters()
	var bad: Array = []
	var judged := 0
	for id in bosses:
		var name := str(mons[id].get("name", id))
		var box = _box([_pc("fighter")])
		box.show_boss_intro(name, mons[id]["dialogue"]["intro"], id)
		for e in box._dialogue_queue:
			if not box._speaks_as_boss(str(e.get("speaker", "")), name):
				continue
			judged += 1
			# What the dialogue would DRAW for this line, judged against the monster's own bust.
			var shown: Texture2D = box._boss_art_for(str(e.get("boss_art", "")))
			if str(e.get("boss_art", "")) != id:
				bad.append("%s: '%s' has no boss art" % [id, e.get("speaker", "")])
			elif shown == null:
				bad.append("%s: no bust resolves from its sheet" % id)
			elif shown in _job_faces():
				bad.append("%s: wears a party member's portrait" % id)
			elif not _same_face(shown, _art.monster_art(id)):
				bad.append("%s: not its own bust" % id)
		box.queue_free()
	assert_gt(judged, 100, "CONTROL: boss-spoken lines were judged (%d)" % judged)
	assert_eq(bad, [], "boss lines without the boss's own face: %s" % str(bad.slice(0, 8)))


func test_the_first_boss_line_shows_the_bust() -> void:
	var id: String = _intro_bosses()[0]
	var mons := _monsters()
	var name := str(mons[id].get("name", id))
	var boss_line := "%s: You will not pass." % name
	var box = _box([_pc("fighter")])
	box.show_boss_intro(name, [boss_line], id)
	assert_true(box._portrait_frame.visible, "%s's line must show a face" % name)
	assert_true(_same_face(box._portrait_image.texture, _art.monster_art(id)), "the face is the bust cut from its own sheet")


func test_a_duel_boss_named_after_a_job_does_not_wear_that_job() -> void:
	var box = _box([_pc("fighter")])
	box.show_boss_intro("The Sneering Courtier", ["Courtier: My hall is not a market."], "bard_hostile_courtier")
	assert_true(box._portrait_frame.visible, "the Courtier's line shows a face")
	assert_false(_same_face(box._portrait_image.texture, _art.portrait_art("bard")), "the Courtier wore the Bard's portrait")
	assert_true(_same_face(box._portrait_image.texture, _art.monster_art("bard_hostile_courtier")), "the Courtier wears its own bust")


func test_a_bystander_stays_faceless() -> void:
	var box = _box([_pc("cleric")])
	box.show_boss_intro("The Grinding Wound", ["Villager: Please, save him!"], "cleric_survive_target")
	var e: Dictionary = box._dialogue_queue[0]
	assert_eq(str(e.get("art", "")), "", "a villager must not borrow the boss's face")
	assert_false(box._portrait_frame.visible, "a bystander's line stays faceless")


func test_a_party_member_named_in_a_line_speaks_as_themselves() -> void:
	var box = _box([_pc("bard")])
	box.show_boss_intro("The Sneering Courtier", ["Bard: I have heard better from a door hinge."], "bard_hostile_courtier")
	var e: Dictionary = box._dialogue_queue[0]
	assert_eq(str(e.get("art", "")), "bard", "the Bard's line wears the Bard's face")
	assert_ne(str(e.get("theme", "")), "enemy", "and not the boss's colours")
	assert_true(box._portrait_frame.visible)
	assert_true(_same_face(box._portrait_image.texture, _art.portrait_art("bard")), "the Bard wears the Bard's face")


func test_no_boss_art_falls_back_to_a_drawn_face() -> void:
	assert_null(_art.portrait_art("no_such_monster_or_job"), "portrait_art answers null rather than drawing a generic face")
	assert_not_null(_art.portrait_texture("no_such_monster_or_job"), "CONTROL: the cutscene path still draws one")


func test_the_battle_scene_names_the_boss_at_every_intro_call() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var calls := 0
	var named := 0
	for line in src.split("\n"):
		var t := line.strip_edges()
		if t.begins_with("#") or not t.contains("show_boss_intro("):
			continue
		calls += 1
		if t.contains("_boss_monster_id()"):
			named += 1
	assert_gt(calls, 1, "CONTROL: both intro call sites were found")
	assert_eq(named, calls, "every boss-intro call must pass the boss's monster id, or its lines stay faceless")
