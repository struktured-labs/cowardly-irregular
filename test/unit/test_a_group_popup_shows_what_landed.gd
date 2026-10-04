extends GutTest

## Every group attack and formation special emitted damage_dealt with the amount it COMPUTED, then called
## take_damage, which applies defense (and wards, and the dial) and returns what actually landed. So the
## popup over the enemy read higher than the HP bar moved, on every All-Out, Combo, Limit Break and all
## six formations. The popup is the number a player reads; it now carries take_damage's return.

const MENU := preload("res://src/battle/BattleCommandMenu.gd")

var _saved: Dictionary = {}
var _popups: Dictionary = {}


func before_each() -> void:
	_saved = {"pp": BattleManager.player_party.duplicate(), "ep": BattleManager.enemy_party.duplicate()}
	_popups = {}
	BattleManager.damage_dealt.connect(_on_damage)
	seed(20261004)


func after_each() -> void:
	if BattleManager.damage_dealt.is_connected(_on_damage):
		BattleManager.damage_dealt.disconnect(_on_damage)
	randomize()
	BattleManager.player_party.assign(_saved["pp"].filter(func(x): return is_instance_valid(x)))
	BattleManager.enemy_party.assign(_saved["ep"].filter(func(x): return is_instance_valid(x)))


func _on_damage(target, amount, _crit = false, _el = "", _mod = 1.0) -> void:
	_popups[target] = int(_popups.get(target, 0)) + int(amount)


func _c(n: String, def_v: int) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": n, "max_hp": 10000000, "max_mp": 999, "attack": 120, "defense": def_v, "magic": 120, "speed": 10})
	c.magic_defense = def_v
	add_child_autofree(c)
	c.current_ap = 4
	return c


func _check(label: String, run: Callable) -> Array[String]:
	var party: Array[Combatant] = []
	for i in 4:
		party.append(_c("PC%d" % i, 30))
	var foe := _c("Wall", 300)
	BattleManager.player_party.assign(party)
	BattleManager.enemy_party.assign([foe] as Array[Combatant])
	var before := {}
	for c in party + [foe]:
		before[c] = c.current_hp
	_popups = {}
	run.call(party, foe)
	var bad: Array[String] = []
	for c in before:
		var lost: int = int(before[c]) - c.current_hp
		var shown: int = int(_popups.get(c, 0))
		if lost > 0 and shown != lost:
			bad.append("%s: %s's popups read %d, its HP fell %d" % [label, c.combatant_name, shown, lost])
	return bad


func test_every_group_popup_carries_what_landed() -> void:
	var bad: Array[String] = []
	var any_damage := false
	for gt in ["all_out_attack", "limit_break"]:
		bad.append_array(_check(gt, func(p, f): BattleManager._execute_physical_group(p, [f] as Array[Combatant], gt, 0)))
	bad.append_array(_check("combo_magic", func(p, f): BattleManager._execute_combo_magic(p, [f] as Array[Combatant], 0)))
	for form in MENU.FORMATIONS:
		var fid := str(form["id"])
		bad.append_array(_check(fid, func(p, f): BattleManager._execute_formation_special(p, [f] as Array[Combatant], fid)))
	assert_eq(bad, [] as Array[String], "a damage popup must read what take_damage removed: %s" % str(bad))


func test_defense_is_high_enough_to_matter() -> void:
	## CONTROL: with 0 defense the computed and landed amounts coincide and the arm above proves nothing.
	var foe := _c("Wall", 300)
	assert_lt(foe.damage_preview(500, false), 500, "300 DEF must mitigate a 500 hit")


func test_a_self_damage_recoil_popup_shows_what_landed() -> void:
	## stack_overflow's damage_to_self_pct recoil had the same shape: the popup and the log printed the
	## pre-defense recoil while take_damage removed less.
	var caster := _c("Hacker", 0)
	caster.magic_defense = 400
	var foe := _c("Dummy", 0)
	BattleManager.player_party.assign([caster] as Array[Combatant])
	BattleManager.enemy_party.assign([foe] as Array[Combatant])
	var before := caster.current_hp
	_popups = {}
	BattleManager._execute_magic_ability(caster, JobSystem.get_ability("stack_overflow"), [foe])
	var lost := before - caster.current_hp
	assert_gt(lost, 0, "CONTROL: the overflow must recoil onto the caster")
	assert_eq(int(_popups.get(caster, 0)), lost, "the recoil popup must read the HP the caster lost")


func test_the_group_log_line_agrees_with_the_popup() -> void:
	## .575 fixed the popups; the "hits X for N" / "blasts X for N" log lines kept the pre-defense number,
	## so the popup and the log disagreed about the same hit.
	var lines: Array[String] = []
	var cb := func(m): lines.append(str(m))
	BattleManager.battle_log_message.connect(cb)
	var bad: Array[String] = []
	bad.append_array(_check("all_out_attack", func(p, f): BattleManager._execute_physical_group(p, [f] as Array[Combatant], "all_out_attack", 0)))
	var all_out_popup: int = int(_popups.values()[0]) if _popups.size() > 0 else -1
	bad.append_array(_check("combo_magic", func(p, f): BattleManager._execute_combo_magic(p, [f] as Array[Combatant], 0)))
	var combo_popup: int = int(_popups.values()[0]) if _popups.size() > 0 else -1
	BattleManager.battle_log_message.disconnect(cb)
	var joined := "\n".join(lines)
	assert_string_contains(joined, "Wall for %d!" % all_out_popup, "the All-Out log line must read the popup's %d" % all_out_popup)
	assert_string_contains(joined, "Wall for %d!" % combo_popup, "the Combo log line must read the popup's %d" % combo_popup)
