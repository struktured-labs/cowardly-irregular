extends GutTest

## UX fix 2026-07-04: the Free-Move MP restores (Cleric Pray / Mage
## Channel / Bard Riff) emitted healing_done + a battle-log line for
## EVERY recipient, even ones already at full MP — so Bard's Riff on a
## full party spawned a "+0 MP" green popup + glow + log line per member.
## on_healing_done didn't guard amount<=0 either. Now the restore skips
## zero-gain recipients (one gray "fizzles — everyone's full" line if
## none gained), and the popup no-ops on amount<=0.

const BM := preload("res://src/battle/BattleManager.gd")


func _pc(nm: String, max_mp: int, cur_mp: int) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = nm
	c.max_mp = max_mp
	c.current_mp = cur_mp
	c.is_alive = true
	return c


func _run_restore(party: Array, caster: Combatant) -> Dictionary:
	var bm = BM.new()
	add_child_autofree(bm)
	var typed: Array[Combatant] = []
	for p in party:
		typed.append(p)
	bm.player_party = typed
	var heals: Array = []
	var logs: Array = []
	bm.healing_done.connect(func(_t, a): heals.append(a))
	bm.battle_log_message.connect(func(m): logs.append(str(m)))
	bm._execute_mp_restore_ability(caster, {"mp_amount": 5, "target_type": "all_allies"})
	return {"heals": heals, "logs": logs}


func test_full_mp_party_no_popups_one_fizzle_line() -> void:
	var full_a := _pc("A", 30, 30)
	var full_b := _pc("B", 40, 40)
	var r := _run_restore([full_a, full_b], full_a)
	assert_eq(r["heals"].size(), 0,
		"no healing_done for full-MP members — that spawned the +0 MP popups")
	var fizzled := false
	for l in r["logs"]:
		if "fizzle" in l:
			fizzled = true
	assert_true(fizzled, "one fizzle line so the player knows the free move registered")


func test_partial_party_only_gains_get_feedback() -> void:
	var full := _pc("Full", 30, 30)
	var low := _pc("Low", 30, 10)
	var r := _run_restore([full, low], full)
	assert_eq(r["heals"], [5],
		"only the low-MP member emits healing_done (5) — the full one is silent")
	assert_eq(low.current_mp, 15, "low member actually restored")


func test_popup_guards_zero_amount() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleResultsDisplay.gd")
	var fn: int = src.find("func on_healing_done")
	assert_gt(fn, -1)
	var body: String = src.substr(fn, 400)
	assert_true(body.contains("if amount <= 0:"),
		"on_healing_done must no-op on <=0 — a universal guard against +0 popups from any heal source")
