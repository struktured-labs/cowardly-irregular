extends GutTest

## Five W1 quests shipped startable and permanently stuck: notify_talk skips type "custom",
## so a custom step advances only via notify_flag, and nothing called it for their flags.

const QUEST := "w1_sandrift_water_on_the_road"
const STEP2_FLAG := "quest_w1_sandrift_water_on_the_road_accepted"
const PREREQ := "cutscene_flag_rat_king_defeated"

## ⛔ THIS WAS A PREFIX LIST, AND ITS STATED CONDITION EXPIRED WITHOUT ANYONE NOTICING.
## It read `["w1_", "world1_", "world2_", "world3_"]`, excusing W4-W6 as "wholesale unwired (20
## stuck steps, no givers) — they join when their givers ship". **Their givers shipped.**
## `test_quest_givers_are_reachable.gd` records the day it happened, in the note on the list they
## left: *"2026-09-11 — foreman/dorrit/madame_orrery_w4 + firewall_attendant_w5 now have ids and
## left this list"* — and that same file's header warns that placing them "would ship
## startable-but-unfinishable quests — the W1 trap, on purpose."
##
## ⚠️ So three quests became acceptable-and-unfinishable (world4_the_watercolors,
## world5_termination_condition, world4_form_exception_alpha) in the seam between one guard's
## exemption expiring and this one's scope filter. Each guard was correct; neither watched the
## condition the other's note depended on, and `test_exemptions_have_not_expired` below watched
## `KNOWN_UNBUILT` only — never the scope constant that decided who was examined at all.
##
## 🔑 THE SCOPE IS NOW DERIVED: every quest, minus the ones the DATA declares withheld with
## `"wiring_pending": true`, which `QuestSystem.is_offerable` refuses to offer. A new world cannot
## fall outside it, and a withheld quest cannot stay withheld once its emitter lands —
## test_a_withheld_quest_is_fully_unemittable below is the other direction.

## flag -> why. An exemption carries its justification or it reads as coverage, and
## test_exemptions_have_not_expired below deletes it for you the moment it stops being true.
## Emptied 2026-08-01: lamplighters_logic step 2 shipped as 5 QuestExaminePoints in group mode on
## Brasston's own `f` gas-lamp tiles, so its exemption expired exactly as this guard promised.
const KNOWN_UNBUILT := {}

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
	## Matches any BaseVillage quest-point factory (_add_quest_examine_point, _add_quest_route_point)
	## by SHAPE — (qid, flag, …). Pinning one NAME left _add_quest_route_point invisible, which would
	## have kept lamplighters_logic's exemption green after its mechanic shipped.
	var point_re := RegEx.create_from_string("_add_quest_\\w*point\\(\\s*\"[^\"]+\"\\s*,\\s*\"([^\"]+)\"")
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
			var q = JSON.parse_string(FileAccess.get_file_as_string("res://data/quests/" + qf))
			## Withheld quests are not offerable, so a missing emitter cannot reach a player.
			if q is Dictionary and not bool((q as Dictionary).get("wiring_pending", false)):
				for o in q.get("objectives", []):
					if str(o.get("type", "")) != "custom":
						continue
					var rf: String = str(o.get("required_flag", ""))
					if rf == "" or KNOWN_UNBUILT.has(rf):
						continue
					checked += 1
					if not notifiable.has(rf):
						stuck.append("%s step%s -> %s" % [id, o.get("step", "?"), rf])
		qf = qd.get_next()
	qd.list_dir_end()
	return [checked, stuck, notifiable.size(), notifiable]


## An exemption that outlives its reason is a silent coverage hole — the exact shape that let a
## mode7 test sit retired since the day it was written. This deletes it for you.
func test_exemptions_have_not_expired() -> void:
	var r := _stuck_custom_objectives()
	assert_gt(r.size(), 3, "walk must return the notifiable set, else this cannot fire")
	if r.size() < 4:
		return
	var notifiable: Dictionary = r[3]
	assert_gt(notifiable.size(), 10, "notifiable set must be populated, else every exemption "
		+ "below looks still-needed and this guard inverts")
	## A member the scan's own call_re produces, verified single-line in src/ — my first
	## attempt named w1_tempo_defeated, which nothing in src/ emits, and the control fired.
	assert_true(notifiable.has("quest_world1_chapter_three_basics_only"),
		"a KNOWN-emittable flag must resolve — a count alone passes while the scan matches nothing")
	assert_false(notifiable.has("zzz_never_emitted"), "an invented flag must NOT resolve")
	var expired: Array = []
	for flag in KNOWN_UNBUILT:
		if notifiable.has(flag):
			expired.append("%s (%s)" % [flag, KNOWN_UNBUILT[flag]])
	assert_eq(expired, [], "this flag is now emittable, so its KNOWN_UNBUILT exemption is stale "
		+ "and is hiding real coverage. DELETE the entry: %s" % [expired])


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
		if not qf.ends_with(".json"):
			qf = qd.get_next()
			continue
		var id: String = qf.trim_suffix(".json")
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/quests/" + qf))
		## Same derived scope as the ratchet above. This filter was NARROWER still — w1_, world1_,
		## world2_, with no world3_ — so one file carried two different answers to "who is playable".
		if parsed is Dictionary and bool((parsed as Dictionary).get("wiring_pending", false)):
			qf = qd.get_next()
			continue
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


## ⛔ THE OTHER DIRECTION OF THE DERIVED SCOPE, and without it the scope key rots exactly as
## the prefix list did. A `wiring_pending` quest is withheld from the player; the moment its
## emitters exist, the key is hiding finished content and must come off. The ratchet above cannot
## see that — a withheld quest is simply not examined — so this is where the expiry lives.
##
## ⚠️ IT USES THE **STRICT** (shape-aware) SET ON PURPOSE, not the permissive corpus. A false
## "stale" ships an unfinishable quest to a player; a false "not stale" withholds finished content
## a little longer. The two counts are printed side by side so a divergence is visible rather than
## silently resolved in one direction.
func test_a_withheld_quest_is_fully_unemittable() -> void:
	var r := _stuck_custom_objectives()
	assert_gt(r.size(), 3, "walk must return the notifiable set, else this cannot fire")
	if r.size() < 4:
		return
	var notifiable: Dictionary = r[3]
	assert_gt(notifiable.size(), 10, "notifiable set must be populated, else every withheld quest "
		+ "looks correctly withheld and this arm inverts")
	var corpus := _src_corpus()
	assert_gt(corpus.length(), 200000, "src walk must load a real corpus, else the broad count below lies")

	var withheld := 0
	var flags := 0
	var mentioned := 0
	var stale: Array = []
	var qd := DirAccess.open("res://data/quests/")
	assert_not_null(qd, "quest dir must be readable")
	if qd == null:
		return
	qd.list_dir_begin()
	var qf := qd.get_next()
	while qf != "":
		if qf.ends_with(".json"):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/quests/" + qf))
			if parsed is Dictionary and bool((parsed as Dictionary).get("wiring_pending", false)):
				withheld += 1
				var customs := 0
				var emittable := 0
				for o in (parsed as Dictionary).get("objectives", []):
					if str(o.get("type", "")) != "custom":
						continue
					var rf: String = str(o.get("required_flag", ""))
					if rf == "":
						continue
					customs += 1
					flags += 1
					if corpus.contains(rf):
						mentioned += 1
					if notifiable.has(rf):
						emittable += 1
				if customs > 0 and emittable == customs:
					stale.append(qf.trim_suffix(".json"))
		qf = qd.get_next()
	qd.list_dir_end()

	assert_gt(withheld, 0, "VOID: no quest carries wiring_pending, so this arm examined nobody")
	gut.p("  %d withheld quests · %d custom flags · %d emittable (strict) · %d mentioned (broad)" % [
		withheld, flags, stale.size(), mentioned])
	assert_eq(stale, [], "every custom flag of these quests can now be notified — drop "
		+ "\"wiring_pending\" so the content ships, and restore the real prereq_flag if the "
		+ "_wiring_notes spec names one: %s" % [stale])


## Comment-stripped .gd corpus — a flag named only in prose is not a wiring.
##
## ⛔ PackedStringArray + join, NOT `out += line`. src/ is 286 files / 186,771 lines / 7.3 MB and
## GDScript's String `+=` reallocates the whole accumulated buffer per append, so the naive form
## copies ~3.6 MB on average 186,771 times to build one string. Sibling of the same defect in
## test_passive_effects_have_consumers, which measured >6.5 MINUTES of CPU per run and 4s after
## this change; this file was the second-slowest in the suite for the same reason. The per-file
## `text` accumulator above is deliberately left alone — it is scoped INSIDE the file loop, so it
## is bounded by one file rather than by the corpus.
func _src_corpus() -> String:
	var parts: PackedStringArray = PackedStringArray()
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
						parts.append(line)
			f = d.get_next()
		d.list_dir_end()
	return ("\n".join(parts) + "\n") if not parts.is_empty() else ""
