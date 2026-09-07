extends GutTest

## Dead-end protection (2026-07-02): one_chicken_problem and
## untested_edge dead-ended at step-2 custom objectives whose flag
## EMITTERS don't exist yet (chicken 7-catch puzzle, Mage light-spell
## interact — both next-session builds). Their offers are temp-gated
## behind intentionally-unset flags so the morning playtest can't
## accept an uncompletable quest.
##
## RATCHET: this test FAILS THE MOMENT an emitter appears in src/ —
## forcing whoever builds it to also restore the quest's real
## prereq_flag (spec preserved in each quest's _wiring_notes).

const GATED := {
	"world1_one_chicken_problem": {
		"gate": "quest_wiring_chicken_catch_ready",
		"custom_flag": "quest_world1_one_chicken_problem_all_chickens",
	},
	"world1_untested_edge": {
		"gate": "quest_wiring_light_spell_ready",
		"custom_flag": "quest_world1_untested_edge_inscription_read",
	},
}


func _src_writes_flag(flag: String) -> bool:
	# Any src/ file naming the custom flag = an emitter exists.
	var dirs := ["res://src"]
	while not dirs.is_empty():
		var dir_path: String = dirs.pop_back()
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		d.list_dir_begin()
		var f := d.get_next()
		while f != "":
			var full := dir_path + "/" + f
			if d.current_is_dir():
				dirs.append(full)
			elif f.ends_with(".gd"):
				if FileAccess.get_file_as_string(full).contains(flag):
					return true
			f = d.get_next()
	return false


func test_gated_quests_stay_unofferable_while_emitterless() -> void:
	for qid in GATED:
		var q: Dictionary = QuestSystem.get_quest(qid)
		assert_false(q.is_empty(), "%s must load" % qid)
		var gate: String = str(GATED[qid]["gate"])
		var has_emitter: bool = _src_writes_flag(str(GATED[qid]["custom_flag"]))
		if has_emitter:
			assert_ne(str(q.get("prereq_flag", "")), gate,
				"%s: its emitter now EXISTS — remove the temp gate and restore the real prereq_flag (spec in _wiring_notes)" % qid)
		else:
			assert_eq(str(q.get("prereq_flag", "")), gate,
				"%s: no emitter in src/ — the temp gate must stay or the quest dead-ends at step 2" % qid)
