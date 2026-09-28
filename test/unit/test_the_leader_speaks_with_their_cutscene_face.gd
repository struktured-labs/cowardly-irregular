extends GutTest

## The party leader's boss-intro line (the authored "Hero:") showed a PROCEDURAL drawing — the hero/healer/
## rogue/mage sketches in BattleDialogue — or, for a Bard or an advanced job, no face at all. The same
## character in a cutscene shows portrait ART: CutsceneDialogue resolves assets/sprites/portraits/<job>.png
## (with the world variant), then a bust cut from the job's idle sheet. The 2026-03-23 swap that replaced
## procedural faces with portraits never reached battle dialogue, and its customised-portrait path matched
## only the legacy names hero/mira/zack/vex, which no party member carries.
## Now the leader's line asks CutsceneDialogue for the face, so a character looks the same in both.
## (cowir-story's 2026-09-28 pointer: "CutsceneDialogue already has Bard art that BattleDialogue doesn't use.")

const DialogueScript := preload("res://src/ui/BattleDialogue.gd")
const CutsceneDialogueScript := preload("res://src/cutscene/CutsceneDialogue.gd")
const STARTERS := ["fighter", "cleric", "mage", "rogue", "bard"]

var _art: Node = null


func before_all() -> void:
	_art = CutsceneDialogueScript.new()


func after_all() -> void:
	if _art:
		_art.free()


func _pc(job_id: String) -> Combatant:
	var pc := Combatant.new()
	pc.combatant_name = job_id.capitalize()
	pc.is_alive = true
	pc.max_hp = 40
	pc.current_hp = 40
	pc.job = JobSystem.get_job(job_id)
	add_child_autofree(pc)
	return pc


func _shown(job_id: String) -> Node:
	var box = DialogueScript.new()
	add_child_autofree(box)
	box.set_party([_pc(job_id)])
	box.show_boss_intro("Test Boss", ["Hero: We are not leaving."])
	return box


func test_each_starter_leader_wears_the_face_their_cutscenes_use() -> void:
	for job in STARTERS:
		var want: Texture2D = _art.portrait_texture(job)
		assert_not_null(want, "CONTROL: cutscenes have art for the %s" % job)
		var box = _shown(job)
		assert_true(box._portrait_frame.visible, "%s: the leader's line must show a face" % job)
		assert_true(box._portrait_image.visible, "%s: the art is on the portrait image" % job)
		assert_eq(box._portrait_image.texture, want, "%s: battle and cutscene must show the same face" % job)


func test_an_advanced_job_leader_gets_the_bust_cutscenes_cut_for_it() -> void:
	var want: Texture2D = _art.portrait_texture("guardian")
	assert_not_null(want, "CONTROL: cutscenes cut a bust for the Guardian from its sheet")
	var box = _shown("guardian")
	assert_true(box._portrait_frame.visible, "an advanced-job leader must not be faceless")
	assert_eq(box._portrait_image.texture, want)


func test_the_art_is_drawn_at_the_frame_size() -> void:
	var box = _shown("bard")
	await get_tree().process_frame
	assert_eq(box._portrait_image.size, Vector2(DialogueScript.PORTRAIT_SIZE - 8, DialogueScript.PORTRAIT_SIZE - 8),
		"a 256px portrait must be scaled into the frame, not grow it")


func test_boss_and_narrator_lines_keep_their_look() -> void:
	var box = DialogueScript.new()
	add_child_autofree(box)
	box.set_party([_pc("bard")])
	box.show_boss_intro("Skeleton Knight", ["Skeleton Knight: None pass."])
	assert_false(box._portrait_frame.visible, "a boss's own line stays faceless")
	var rat = DialogueScript.new()
	add_child_autofree(rat)
	rat.set_party([_pc("bard")])
	rat.show_boss_intro("Cave Rat King", ["Rat King: Squeak."])
	assert_true(rat._portrait_frame.visible, "CONTROL: the Rat King keeps his drawn face")
	assert_ne(rat._portrait_image.texture, _art.portrait_texture("bard"), "the Rat King must not wear the leader's art")
