extends GutTest

## Parity follow-on to the Defer log fix (v3.32.90). _execute_advance's
## header ("X advances with N actions!") was print-only — the sub-actions
## logged their effects, but nothing announced the Advance itself. With
## Defer now logging its defensive stance, the AP-spend half of the
## Advance/Defer pair should log its header too, so a multi-action turn
## reads as a deliberate choice, not a mystery flurry.

const BM := preload("res://src/battle/BattleManager.gd")


func test_advance_emits_a_header_log_line() -> void:
	var bm = BM.new()
	add_child_autofree(bm)
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Rusher"
	c.is_alive = true
	var logs: Array = []
	bm.battle_log_message.connect(func(m): logs.append(str(m)))
	# Two queued attacks with no target resolve harmlessly; we only assert the header.
	bm._execute_advance(c, {"actions": [{"type": "attack"}, {"type": "attack"}]})
	var found := false
	for l in logs:
		if "advances" in l and "2 actions" in l:
			found = true
	assert_true(found, "Advance must log a header announcing the multi-action turn")


func test_empty_advance_does_not_log_header() -> void:
	# An empty Advance is a guarded no-op (keeps the chain alive) — it must
	# NOT claim "0 actions" in the log.
	var bm = BM.new()
	add_child_autofree(bm)
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Rusher"
	c.is_alive = true
	var logs: Array = []
	bm.battle_log_message.connect(func(m): logs.append(str(m)))
	bm._execute_advance(c, {"actions": []})
	var has_header := false
	for l in logs:
		if "advances" in l:
			has_header = true
	assert_false(has_header, "empty Advance must not emit an 'advances — 0 actions' header")


func test_source_uses_battle_log() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var fn: int = src.find("func _execute_advance")
	var body: String = src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	assert_true(body.contains("battle_log_message.emit(\"[color=orange]⚡ %s advances"),
		"_execute_advance must emit the header to the battle log, not just print()")
