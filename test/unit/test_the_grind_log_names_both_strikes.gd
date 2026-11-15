extends GutTest

## The grind log shows a multi-strike attack's parts, "for 31 (18 + 13)", as live shows each number; one strike shows none.
## The balance harness parses that line, so its attack regex must accept both forms or it silently drops every Rogue attack.

const RESOLVER := preload("res://src/autogrind/HeadlessBattleResolver.gd")
const HARNESS := "res://tools/balance_harness.gd"
const SUFFIX := "^(.+) attacks (.+) for (\\d+) \\((\\d+(?: \\+ \\d+)+)\\)$"

var _res = null


func before_each() -> void:
	_res = RESOLVER.new()


func after_each() -> void:
	if _res != null:
		_res.free()
	_res = null


func _job(job_id: String) -> Dictionary:
	var js = Engine.get_main_loop().root.get_node_or_null("JobSystem")
	var j = js.get_job(job_id) if js else {}
	return j if j is Dictionary else {}


func _make(name_str: String, job_id: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name_str, "max_hp": 999999, "max_mp": 50,
		"attack": 60, "defense": 0, "magic": 10, "speed": 100})
	add_child_autofree(c)
	c.current_hp = c.max_hp
	if job_id != "":
		c.job = _job(job_id)
	return c


## Attack lines from n attacks by attacker on a dummy, through the resolver's own action executor.
func _attack_lines(attacker: Combatant, n: int) -> Array:
	var dummy := _make("Dummy", "")
	_res._player_party = [attacker]
	_res._enemy_party = [dummy]
	_res._battle_log.clear()
	for i in n:
		_res._execute_action({"type": "attack", "combatant": attacker, "target": dummy})
	var out: Array = []
	for line in _res._battle_log:
		if " attacks " in line:
			out.append(line)
	return out


func _harness_attack_rx() -> RegEx:
	var src := FileAccess.get_file_as_string(HARNESS)
	var m := RegEx.create_from_string('\\["attack", "((?:[^"\\\\]|\\\\.)*)"\\]').search(src)
	if m == null:
		return null
	return RegEx.create_from_string(m.get_string(1).replace("\\\\", "\\"))


func test_floor_the_resolver_carries_the_strike_parts() -> void:
	assert_true(_res.has_method("_strike_parts_text"), "FLOOR: HeadlessBattleResolver._strike_parts_text is gone")
	assert_true("_last_strike_parts" in _res, "FLOOR: HeadlessBattleResolver._last_strike_parts is gone")


func test_a_rogue_attack_line_names_both_strikes_and_they_sum_to_the_total() -> void:
	var rogue := _make("Rogue", "rogue")
	assert_eq(rogue.basic_attack_strikes().size(), 2, "CONTROL: the Rogue's attack is two strikes")
	var lines := _attack_lines(rogue, 40)
	assert_eq(lines.size(), 40, "every attack logs one line")
	var rx := RegEx.create_from_string(SUFFIX)
	var suffixed := 0
	for line in lines:
		var m := rx.search(line)
		if m == null:
			continue
		suffixed += 1
		var sum := 0
		for part in m.get_string(4).split(" + "):
			sum += int(part)
		assert_eq(sum, int(m.get_string(3)), "the parts must sum to the total: %s" % line)
	assert_eq(suffixed, lines.size(), "every Rogue attack line must name its strikes (%d of %d did): %s" % [suffixed, lines.size(), str(lines.slice(0, 3))])


func test_control_a_one_strike_attack_line_has_no_parts() -> void:
	var fighter := _make("Fighter", "fighter")
	assert_eq(fighter.basic_attack_strikes().size(), 1, "CONTROL: the Fighter swings once")
	var lines := _attack_lines(fighter, 20)
	assert_eq(lines.size(), 20, "every attack logs one line")
	for line in lines:
		assert_false(line.ends_with(")"), "a one-strike attack must not carry a parts suffix: %s" % line)


func test_the_balance_harness_parses_both_forms() -> void:
	var rx := _harness_attack_rx()
	assert_not_null(rx, "VOID: no [\"attack\", ...] regex found in %s" % HARNESS)
	if rx == null:
		return
	var rogue_lines := _attack_lines(_make("Rogue", "rogue"), 10)
	var fighter_lines := _attack_lines(_make("Fighter", "fighter"), 10)
	assert_eq(rogue_lines.size() + fighter_lines.size(), 20, "CONTROL: both attackers logged")
	for line in rogue_lines + fighter_lines:
		var m := rx.search(line)
		assert_not_null(m, "the harness's attack regex must parse: %s" % line)
		if m == null:
			continue
		var total := int(line.get_slice(" for ", 1).get_slice(" ", 0))
		assert_eq(int(m.get_string(3)), total, "the harness must read the TOTAL, not a part: %s" % line)
