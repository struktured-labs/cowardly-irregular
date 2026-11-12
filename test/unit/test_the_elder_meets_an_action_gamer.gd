extends GutTest

## Easter egg (struktured, 2026-11-11): beat the Cave Rat King before ever speaking to Elder Theron, and the Elder is
## found rehearsing the briefing nobody heard. These arms hold the scene's TEXT and data; its gate, its completion
## flags and the party's control are cowir-cutscenes' wiring and are judged by that tip's own guard.

const SCENE := "res://data/cutscenes/world1_briefing_skipped.json"
const BRIEFING := "res://data/cutscenes/world1_chapter1.json"
const HIS_LINE := "Clearly you're an action gamer."
const FLAG := "rat_king_fell_before_the_briefing"
const TOKEN := "unread_briefing"
const STARTERS := ["fighter", "cleric", "mage", "rogue", "bard"]


func _json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## Every dialogue line in `steps`, branch cases included, as [speaker, text, portrait].
func _lines(steps: Array) -> Array:
	var out := []
	for step in steps:
		if not step is Dictionary:
			continue
		for line in step.get("lines", []):
			out.append([str(line.get("speaker", "")), str(line.get("text", "")), str(line.get("portrait", ""))])
		var cases = step.get("cases", {})
		if cases is Dictionary:
			for key in cases:
				out.append_array(_lines(cases[key]))
	return out


func _steps_of(kind: String) -> Array:
	var out := []
	for step in _json(SCENE).get("steps", []):
		if step is Dictionary and str(step.get("type", "")) == kind:
			out.append(step)
	return out


func test_the_scene_turns_on_his_line() -> void:
	var said := []
	for line in _lines(_json(SCENE).get("steps", [])):
		if line[1] == HIS_LINE:
			said.append(line)
	assert_eq(said.size(), 1, "struktured's line is said exactly once, word for word")
	if said.size() == 1:
		assert_eq(said[0][0], "Elder Theron", "it is the Elder's line")
		assert_eq(said[0][2], "theron", "said with the Elder's own face")


func test_the_elder_is_rehearsing_the_real_briefing() -> void:
	# The joke is that this is the briefing the player skipped: the rehearsal quotes its real opening lines.
	var opening := []
	for line in _lines(_json(BRIEFING).get("steps", [])):
		if line[0] == "Elder Theron" and opening.size() < 2:
			opening.append(line[1])
	assert_eq(opening.size(), 2, "CONTROL: the briefing still opens with two lines from the Elder")
	var rehearsal := ""
	for line in _lines(_json(SCENE).get("steps", [])):
		if line[0] == "Elder Theron":
			rehearsal += line[1] + " "
	assert_true(rehearsal.contains(opening[0]), "the rehearsal quotes the briefing's first line: '%s'" % opening[0])
	assert_true(rehearsal.contains(opening[1].substr(0, 22)), "and the start of its second: '%s'" % opening[1].substr(0, 22))


func test_whoever_leads_gets_the_reply() -> void:
	var branches := _steps_of("branch")
	assert_eq(branches.size(), 1, "CONTROL: one lead-job branch")
	if branches.size() != 1:
		return
	assert_eq(str(branches[0].get("condition", "")), "lead_job", "it branches on who leads the party")
	var cases: Dictionary = branches[0].get("cases", {})
	assert_true(cases.has("default"), "a lead the scene never heard of still gets a reply")
	for job in STARTERS:
		var lines := _lines(cases.get(job, []))
		assert_eq(lines.size(), 1, "the %s lead gets exactly one reply" % job)
		if lines.size() == 1:
			assert_eq(lines[0][2], job, "and it is the %s who says it" % job)


func test_the_game_noticed() -> void:
	var grants := _steps_of("grant_item")
	assert_eq(grants.size(), 1, "one token for the action player")
	if grants.size() == 1:
		assert_eq(str(grants[0].get("item", "")), TOKEN, "it is the briefing nobody heard")
	var item: Dictionary = _json("res://data/items.json").get(TOKEN, {})
	assert_eq(int(item.get("category", -1)), 4, "the token is a key item in items.json, so it can be kept and read")
	var flags := []
	for step in _steps_of("set_flag"):
		flags.append(str(step.get("flag", "")))
	assert_eq(flags.count(FLAG), 1, "the scene sets %s once: the one fact the Elder's later talk and the trials read" % FLAG)
