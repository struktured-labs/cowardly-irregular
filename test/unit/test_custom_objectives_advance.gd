extends GutTest

## Five W1 quests shipped startable and permanently stuck: notify_talk skips type "custom",
## so a custom step advances only via notify_flag, and nothing called it for their flags.

const QUEST := "w1_sandrift_water_on_the_road"
const STEP2_FLAG := "quest_w1_sandrift_water_on_the_road_accepted"
const PREREQ := "cutscene_flag_rat_king_defeated"

var _saved_quests: Dictionary = {}
var _saved_flags: Dictionary = {}


func before_each() -> void:
	_saved_quests = GameState.quests.duplicate(true)
	_saved_flags = GameState.story_flags.duplicate(true)


func after_each() -> void:
	GameState.quests = _saved_quests
	GameState.story_flags = _saved_flags


func _qs() -> Node:
	return get_node_or_null("/root/QuestSystem")


## Every custom objective's required_flag, joined against every flag anything can notify.
func _stuck_custom_objectives() -> Array:
	var notifiable := {}
	var call_re := RegEx.create_from_string("notify_flag\\(\\s*\"([^\"]+)\"")
	var const_re := RegEx.create_from_string("const\\s+(\\w+)\\s*(?::=|:\\s*String\\s*=|=)\\s*\"([^\"]+)\"")
	var var_call_re := RegEx.create_from_string("notify_flag\\(\\s*([A-Z_][A-Z0-9_]*)\\s*\\)")
	var point_re := RegEx.create_from_string("_add_quest_examine_point\\(\\s*\"[^\"]+\"\\s*,\\s*\"([^\"]+)\"")
	## A QuestExaminePoint built directly (dungeons have no BaseVillage helper) sets .flag
	## as a property — invisible to the factory pattern above, and W3's junction uses it.
	var direct_re := RegEx.create_from_string("\\w+\\.flag\\s*=\\s*\"([^\"]+)\"")
	## MasteriteEncounter's export. Named EXACTLY, not broadened to \\w*flag — that also
	## matches .prereq_flag (SandriftVillage: the Warden's precondition), and counting a
	## GATE as an emitter trades a false red for a false green.
	var quest_flag_re := RegEx.create_from_string("\\w+\\.quest_flag\\s*=\\s*\"([^\"]+)\"")
	var stack: Array = ["res://src"]
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		var d := DirAccess.open(dir)
		if d == null:
			continue
		d.list_dir_begin()
		var f := d.get_next()
		while f != "":
			var p: String = dir + "/" + f
			if d.current_is_dir():
				stack.append(p)
			elif f.ends_with(".gd"):
				var text := ""
				for line in FileAccess.get_file_as_string(p).split("\n"):
					if not line.strip_edges().begins_with("#"):
						text += line + "\n"
				var consts := {}
				for m in const_re.search_all(text):
					consts[m.get_string(1)] = m.get_string(2)
				for m in call_re.search_all(text):
					notifiable[m.get_string(1)] = true
				for m in var_call_re.search_all(text):
					if consts.has(m.get_string(1)):
						notifiable[consts[m.get_string(1)]] = true
				for m in point_re.search_all(text):
					notifiable[m.get_string(1)] = true
				for m in direct_re.search_all(text):
					notifiable[m.get_string(1)] = true
				for m in quest_flag_re.search_all(text):
					notifiable[m.get_string(1)] = true
			f = d.get_next()
		d.list_dir_end()
	## Both emitter dicts live in QuestSystem; TALK_TALLY_EMITTERS is KEYED by its group flag.
	var qs_src := FileAccess.get_file_as_string("res://src/quests/QuestSystem.gd")
	for m in RegEx.create_from_string("\"flag\"\\s*:\\s*\"([^\"]+)\"").search_all(qs_src):
		notifiable[m.get_string(1)] = true
	for m in RegEx.create_from_string("TALK_TALLY_EMITTERS[\\s\\S]*?\\{([\\s\\S]*?)\\n\\}").search_all(qs_src):
		for k in RegEx.create_from_string("\\n\\t\"([^\"]+)\"").search_all(m.get_string(1)):
			notifiable[k.get_string(1)] = true

	var stuck: Array = []
	var checked := 0
	var qd := DirAccess.open("res://data/quests/")
	if qd == null:
		return [-1]
	qd.list_dir_begin()
	var qf := qd.get_next()
	while qf != "":
		if qf.ends_with(".json"):
			var id := qf.trim_suffix(".json")
			if id.begins_with("w1_") or id.begins_with("world1_") or id.begins_with("world2_"):
				var q = JSON.parse_string(FileAccess.get_file_as_string("res://data/quests/" + qf))
				if q is Dictionary:
					for o in q.get("objectives", []):
						if str(o.get("type", "")) != "custom":
							continue
						var rf: String = str(o.get("required_flag", ""))
						if rf == "":
							continue
						checked += 1
						if not notifiable.has(rf):
							stuck.append("%s step%s -> %s" % [id, o.get("step", "?"), rf])
		qf = qd.get_next()
	qd.list_dir_end()
	return [checked, stuck, notifiable.size()]


## BEHAVIOURAL. A source pin on "notify_flag( is present" stays GREEN against the shipped
## defect, so read the objective index instead of the call site.
func test_custom_objective_advances_when_its_emitter_fires() -> void:
	var qs := _qs()
	assert_not_null(qs, "QuestSystem autoload required — without it this proves nothing")
	if qs == null:
		return

	GameState.set_story_flag(PREREQ)
	qs.accept(QUEST)
	assert_eq(str(qs.get_state(QUEST)), "active", "quest must accept, else the drive below is vacuous")
	var after_accept: int = qs.get_objective_index(QUEST)
	assert_eq(after_accept, 1, "accepting completes the talk-to-giver step, landing on the custom step")

	## NEGATIVE CONTROL: setting the flag without notifying must NOT advance — this is exactly
	## the shipped state, and an assertion that cannot see it is not testing anything.
	GameState.set_story_flag(STEP2_FLAG)
	assert_eq(qs.get_objective_index(QUEST), 1, "a flag being SET must not advance the objective — "
		+ "_complete_objective sets flag_on_complete and never notifies, which is why emitted "
		+ "and advanceable are different properties")

	qs.notify_flag(STEP2_FLAG)
	assert_eq(qs.get_objective_index(QUEST), 2, "the objective must ADVANCE when its emitter fires. "
		+ "Five W1 quests shipped where nothing ever called this, so the player accepted a quest "
		+ "that could never reach step 3")


## The bounds guard IS mutation-verifiable on its negative branch, and that branch is not a
## crash — GDScript indexes arrays from the end, so a corrupted index silently picks a step.
func test_negative_objective_index_does_not_select_a_step_from_the_end() -> void:
	var point = load("res://src/exploration/QuestExaminePoint.gd").new()
	point.quest_id = QUEST
	point.flag = STEP2_FLAG
	add_child_autofree(point)

	## QUEST's objectives are [talk, custom, talk], so an index of -2 resolves to the CUSTOM
	## step. Unguarded this returns true and the point fires notify_flag for a step the player
	## is not on — stranding the quest, which is the defect the emitter exists to prevent.
	GameState.quests[QUEST] = {"state": "active", "objective_index": -2}
	assert_false(point._is_live(), "a negative objective_index must be refused, not indexed from "
		+ "the end. Save corruption is a shipped mechanic, so this state is reachable, and the "
		+ "unguarded read returns a REAL objective rather than erroring — a silent wrong answer")

	## POSITIVE CONTROL: the same point must still go live on the honest index, else the guard
	## refuses everything and the assertion above passes for the wrong reason.
	GameState.quests[QUEST] = {"state": "active", "objective_index": 1}
	assert_true(point._is_live(), "the emitter must still arm on the real current objective")


## RATCHET. Every playable custom objective must have something able to notify its flag.
func test_no_playable_custom_objective_is_unreachable() -> void:
	var result := _stuck_custom_objectives()
	assert_ne(result[0], -1, "quest dir must be readable, else this guard is vacuous")
	if result[0] == -1:
		return
	var checked: int = result[0]
	var stuck: Array = result[1]
	var notifiable: int = result[2]

	assert_gt(checked, 15, "must examine real custom objectives — a small corpus reports the same "
		+ "clean zero as a complete one")
	assert_gt(notifiable, 15, "must resolve real notify paths, else every objective looks stuck")
	assert_eq(stuck, [], "this custom objective can never advance: notify_talk skips type 'custom', "
		+ "so only notify_flag moves it, and nothing in src/ can fire this flag. The player can "
		+ "accept the quest and never finish it. Add an emitter (QuestExaminePoint, an interactable, "
		+ "or a DIALOGUE_EMITTERS entry): %s" % [stuck])


## COMPANION to the shape-aware ratchet, and deliberately NOT a replacement.
## That one asks "is this a real emitter" and goes blind to any mechanism it doesn't
## model — measured: it cannot see cowir-overworld's `<var>.quest_flag = "..."`.
## This one asks only "is this step definitely dark", from the flag literal, so a new
## mechanism cannot blindside it. Over-permissive by design: a literal in a dead branch
## counts. Broadening the OTHER scan instead was measured and rejected — `\w+\.\w*flag`
## also matches `.prereq_flag`, a GATE, which would trade a false red for a false green.
func test_no_playable_custom_flag_is_absent_from_src_entirely() -> void:
	var corpus := _src_corpus()

	assert_gt(corpus.length(), 200000, "src walk must load a real corpus, else every flag "
		+ "below looks dark and this inverts")
	assert_true(corpus.contains("quest_w1_sandrift_water_on_the_road_accepted"),
		"a KNOWN-wired flag must appear — a length check alone passes while the walk returns junk")
	assert_false(corpus.contains("zzz_flag_that_is_never_wired"),
		"an invented flag must NOT appear, else this matches everything")

	var checked := 0
	var dark: Array = []
	var qd := DirAccess.open("res://data/quests/")
	assert_not_null(qd, "quest dir must be readable")
	if qd == null:
		return
	qd.list_dir_begin()
	var qf := qd.get_next()
	while qf != "":
		var id: String = qf.trim_suffix(".json")
		if not qf.ends_with(".json") or not (id.begins_with("w1_") or id.begins_with("world1_") or id.begins_with("world2_")):
			qf = qd.get_next()
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/quests/" + qf))
		for o in (parsed.get("objectives", []) if parsed is Dictionary else []):
			if str(o.get("type", "")) != "custom":
				continue
			var rf: String = str(o.get("required_flag", ""))
			if rf == "":
				continue
			checked += 1
			if not corpus.contains(rf):
				dark.append("%s step%s -> %s" % [id, o.get("step", "?"), rf])
		qf = qd.get_next()
	qd.list_dir_end()

	assert_gt(checked, 15, "must examine real custom objectives, else vacuous")
	assert_eq(dark, [], "this step's required_flag appears NOWHERE in src/, by any mechanism at "
		+ "all — so nothing can possibly advance it and the quest is unfinishable. Unlike the "
		+ "shape-aware check above, this cannot be fooled by an emitter style nobody taught it: %s" % [dark])


## Comment-stripped .gd corpus — a flag named only in prose is not a wiring.
func _src_corpus() -> String:
	var out := ""
	var stack: Array = ["res://src"]
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		var d := DirAccess.open(dir)
		if d == null:
			continue
		d.list_dir_begin()
		var f := d.get_next()
		while f != "":
			var p: String = dir + "/" + f
			if d.current_is_dir():
				stack.append(p)
			elif f.ends_with(".gd"):
				for line in FileAccess.get_file_as_string(p).split("\n"):
					if not line.strip_edges().begins_with("#"):
						out += line + "\n"
			f = d.get_next()
		d.list_dir_end()
	return out
