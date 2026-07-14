extends GutTest

## Parity follow-on to the MP-restore fix (2026-07-04): _execute_healing_
## ability logged "recovers 0 HP" + emitted healing_done for targets
## already at full HP — so Cure on a healthy ally produced a "+0" popup
## (now guarded in on_healing_done) and a noise log line. Now zero-heal
## targets are skipped, with one gray fizzle line if none needed healing.

const BM := preload("res://src/battle/BattleManager.gd")


func _pc(nm: String, max_hp: int, cur_hp: int) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = nm
	c.max_hp = max_hp
	c.current_hp = cur_hp
	c.magic = 0  # keep the heal-amount math simple (no magic scaling)
	c.is_alive = true
	return c


func _heal(targets: Array, caster: Combatant) -> Dictionary:
	var bm = BM.new()
	add_child_autofree(bm)
	var heals: Array = []
	var logs: Array = []
	bm.healing_done.connect(func(_t, a): heals.append(a))
	bm.battle_log_message.connect(func(m): logs.append(str(m)))
	bm._execute_healing_ability(caster, {"heal_amount": 20}, targets)
	return {"heals": heals, "logs": logs}


func test_full_hp_target_no_healing_done_and_fizzles() -> void:
	var full := _pc("Full", 100, 100)
	var r := _heal([full], full)
	assert_eq(r["heals"].size(), 0, "no healing_done for a full-HP target")
	var fizzled := false
	for l in r["logs"]:
		if "fizzle" in l:
			fizzled = true
	assert_true(fizzled, "a heal that helps no one must say so, not log 'recovers 0 HP'")


func test_wounded_target_still_heals() -> void:
	var hurt := _pc("Hurt", 100, 50)
	var r := _heal([hurt], hurt)
	assert_eq(r["heals"].size(), 1, "a wounded target emits exactly one healing_done")
	assert_gt(r["heals"][0], 0, "the emitted amount is the real HP gained")
	assert_gt(hurt.current_hp, 50, "target actually recovered HP")
