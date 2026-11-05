extends GutTest

## In W2-W6 the party's job name follows the world everywhere a player reads it, speaker tags included (cowir-story canon
## 21964). CutsceneDialogue printed the authored tag verbatim, so 738 W2+ lines labelled the party "Fighter" while every
## other screen said that world's name. The LINE TEXT stays as authored; only the tag is rendered.

const DIALOGUE := "res://src/cutscene/CutsceneDialogue.gd"

var _saved_world: int = 1
var _d: Node = null


func before_each() -> void:
	_saved_world = int(GameState.current_world)
	_d = load(DIALOGUE).new()
	add_child_autofree(_d)


func after_each() -> void:
	GameState.current_world = _saved_world


## Starter jobs whose world-2 name differs from their base name; derived, so a data change keeps the arm honest.
func _renamed_in(world: int) -> Array:
	GameState.current_world = world
	var out: Array = []
	for id in JobSystem.jobs:
		var base := str(JobSystem.get_job(id).get("name", id))
		if JobSystem.get_job_display_name(id) != base:
			out.append(id)
	return out


func test_in_world_two_a_job_tag_reads_that_worlds_name() -> void:
	var renamed := _renamed_in(2)
	assert_gt(renamed.size(), 2, "CONTROL: world 2 renames some jobs, or this arm proves nothing")
	for id in renamed:
		var base := str(JobSystem.get_job(id).get("name", id))
		var want := JobSystem.get_job_display_name(id)
		assert_eq(_d.speaker_label(base), want, "a '%s' tag reads %s in world 2" % [base, want])
		assert_eq(_d.speaker_label(id), want, "the id '%s' as a tag reads %s too" % [id, want])


func test_world_one_is_unchanged() -> void:
	GameState.current_world = 1
	for id in ["fighter", "cleric", "mage", "rogue", "bard"]:
		var base := str(JobSystem.get_job(id).get("name", id))
		assert_eq(_d.speaker_label(base), base, "W1 keeps '%s' as written" % base)


func test_everyone_else_passes_through() -> void:
	GameState.current_world = 2
	for who in ["Elder Theron", "???", "Narrator", "Goblin", ""]:
		assert_eq(_d.speaker_label(who), who, "'%s' is not a job, so its tag is as written" % who)


func test_the_box_renders_the_tag_and_keeps_the_line() -> void:
	var renamed := _renamed_in(2)
	assert_gt(renamed.size(), 0, "CONTROL: a renamed job exists")
	var base := str(JobSystem.get_job(renamed[0]).get("name", renamed[0]))
	var src := FileAccess.get_file_as_string(DIALOGUE)
	assert_true(src.contains("_speaker_label.text = speaker_label("), "the live label goes through speaker_label")
	assert_false(src.contains('_speaker_label.text = entry.get("speaker"'), "and no longer prints the tag verbatim")
	assert_ne(base, JobSystem.get_job_display_name(renamed[0]), "CONTROL: the base name differs in world 2")


## The voice blip's pitch is hashed from the speaker NAME, so it must keep reading the AUTHORED tag: otherwise the Cleric
## would blip at another pitch in W2 ("School Nurse" hashes differently), audibly and with nothing red (cowir-music 21970).
func test_the_voice_keeps_the_authored_speaker() -> void:
	var src := FileAccess.get_file_as_string(DIALOGUE)
	var show := src.find("func _show_current_line")
	assert_gt(show, -1, "CONTROL: the line renderer exists")
	var i := src.find("_load_voice_blip(", show)
	assert_gt(i, -1, "CONTROL: the line renderer calls the blip loader")
	var call_line := src.substr(i, src.find("\n", i) - i)
	assert_true(call_line.contains('entry.get("speaker"'), "the blip is pitched from the authored tag: %s" % call_line)
	assert_false(call_line.contains("speaker_label("), "never from the rendered, per-world name")
