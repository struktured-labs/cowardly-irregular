extends GutTest

## fester and memory_leak are type "magic", so both engines apply their status through
## _apply_ability_status / _maybe_inflict_status — which spells the AUTHORED EFFECT NAME.
##
##   fester       effect "amplify_poison"     Combatant:784 reads "festered"
##   memory_leak  effect "memory_leak_status"  Combatant:842 reads "memory_leak"
##
## So both casts wrote a key nothing reads, in BOTH engines: fester never doubled a poison tick and
## memory_leak never drained. Aliased beside freeze->stun and burn->burning, which are the same class.
##
## ⚠️ test_amplify_poison_effect_handler_regression and test_memory_leak_status_effect_handler_regression
## are GREEN on main. They drive _execute_support_ability, whose arms for these two effects are
## UNREACHABLE — no shipped ability authoring either effect is typed support/song/status.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")
const HEADLESS_PATH := "res://src/autogrind/HeadlessBattleResolver.gd"
const BM_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"

var _res


func before_each() -> void:
	_res = ResolverScript.new()
	for n in ["AutogrindSystem", "AutobattleSystem"]:
		var sys: Node = get_node_or_null("/root/" + n)
		if sys != null and "_test_disable_persistence" in sys:
			sys._test_disable_persistence = true


func _combatant(nm: String, hp: int = 200) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": nm, "max_hp": hp, "max_mp": 999,
		"attack": 10, "defense": 0, "magic": 10, "speed": 10})
	add_child_autofree(c)
	c.current_mp = c.max_mp
	c.current_hp = hp
	return c


func _certain(ability_id: String) -> Dictionary:
	## The AUTHORED ability with its roll removed — both engines gate on effect_chance (0.4 here), so
	## the authored dict would make every arm below flaky. Everything else stays as shipped.
	var js: Node = get_node_or_null("/root/JobSystem")
	if js == null or not js.has_method("get_ability"):
		return {}
	var ab: Dictionary = js.get_ability(ability_id).duplicate(true)
	if ab.is_empty():
		return {}
	ab["effect_chance"] = 1.0
	return ab


func test_fester_lands_the_key_the_poison_tick_reads() -> void:
	var ab: Dictionary = _certain("fester")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	assert_eq(str(ab.get("effect", "")), "amplify_poison", "CONTROL: fester still authors amplify_poison")
	var target := _combatant("Victim")
	_res._maybe_inflict_status(_combatant("Diseased Rat"), target, ab, "fester")
	assert_true(target.has_status("festered"),
		"the grind must land Combatant's key — nothing reads 'amplify_poison'")
	assert_false(target.has_status("amplify_poison"), "the authored effect name is the junk key")


func test_a_festered_target_takes_double_poison() -> void:
	## The consequence, as an HP delta against an unfestered control in the same tick. The key
	## landing proves the alias fired; only this proves the alias was worth firing.
	var ab: Dictionary = _certain("fester")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var plain := _combatant("Plain")
	var fest := _combatant("Festered")
	_res._maybe_inflict_status(_combatant("Diseased Rat"), fest, ab, "fester")
	plain.add_status("poison", 3)
	fest.add_status("poison", 3)
	var plain_before: int = plain.current_hp
	var fest_before: int = fest.current_hp
	plain.update_buff_durations()
	fest.update_buff_durations()
	var plain_lost: int = plain_before - plain.current_hp
	var fest_lost: int = fest_before - fest.current_hp
	gut.p("    poison tick  plain=%d  festered=%d" % [plain_lost, fest_lost])
	assert_gt(plain_lost, 0, "CONTROL: the unfestered tick must hurt, or the compare is vacuous")
	assert_eq(fest_lost, plain_lost * 2, "fester must double the poison tick")


func test_memory_leak_lands_the_key_the_drain_reads() -> void:
	var ab: Dictionary = _certain("memory_leak")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var target := _combatant("Victim")
	_res._maybe_inflict_status(_combatant("Script Error"), target, ab, "memory_leak")
	assert_true(target.has_status("memory_leak"), "the grind must land Combatant's key")
	assert_false(target.has_status("memory_leak_status"), "the authored effect name is the junk key")
	assert_eq(int(target.status_durations.get("memory_leak", -1)), int(ab.get("duration", 3)),
		"and it must carry the authored duration, not the applier's default")


func test_a_leaking_target_loses_hp_each_turn() -> void:
	var ab: Dictionary = _certain("memory_leak")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var target := _combatant("Victim")
	_res._maybe_inflict_status(_combatant("Script Error"), target, ab, "memory_leak")
	var before: int = target.current_hp
	target.update_buff_durations()
	var lost: int = before - target.current_hp
	gut.p("    leak tick = %d of %d max" % [lost, target.max_hp])
	assert_gt(lost, 0, "the drain must tick — with the junk key it never did")


func test_live_lands_the_same_two_keys() -> void:
	## The defect was never grind-only: live's magic route reaches the same applier. Driven rather
	## than pinned by source, so the two engines are compared on behaviour.
	var bm: Node = get_node_or_null("/root/BattleManager")
	if bm == null or not bm.has_method("_apply_ability_status"):
		pass_test("BattleManager autoload unavailable")
		return
	for pair in [["fester", "festered"], ["memory_leak", "memory_leak"]]:
		var ab: Dictionary = _certain(pair[0])
		if ab.is_empty():
			pass_test("JobSystem autoload unavailable")
			return
		var target := _combatant("Victim " + pair[0])
		bm._apply_ability_status(_combatant("Caster"), target, ab)
		assert_true(target.has_status(pair[1]),
			"live must land '%s' for %s — the grind alone being right is a new divergence" % [pair[1], pair[0]])
		assert_false(target.has_status(str(ab.get("effect", ""))),
			"live must not leave the authored effect name behind for " + pair[0])


func _aliases(path: String) -> Dictionary:
	## Derive the alias table from a file: `if status_to_add == "X":` then `status_to_add = "Y"`.
	var out: Dictionary = {}
	var guard := RegEx.new()
	guard.compile("if\\s+status_to_add\\s*==\\s*\"([a-z_]+)\"\\s*:")
	var assign := RegEx.new()
	assign.compile("^\\s*status_to_add\\s*=\\s*\"([a-z_]+)\"")
	var pending: String = ""
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var l: String = str(line)
		if l.strip_edges().begins_with("#"):
			continue
		var g := guard.search(l)
		if g != null:
			pending = g.get_string(1)
			continue
		if pending != "":
			var a := assign.search(l)
			if a != null:
				out[pending] = a.get_string(1)
			pending = ""
	return out


func test_the_two_engines_alias_the_same_set() -> void:
	## The twin-drift class this lane keeps hitting: an alias added to one engine and not the other
	## is invisible to any key census, because both engines "handle" the effect.
	var live: Dictionary = _aliases(BM_PATH)
	var grind: Dictionary = _aliases(HEADLESS_PATH)
	assert_gt(live.size(), 2, "CONTROL: the scan must find live's alias table, or it measures its regex")
	var live_keys: Array = live.keys()
	live_keys.sort()
	var grind_keys: Array = grind.keys()
	grind_keys.sort()
	gut.p("    live=%s" % str(live_keys))
	gut.p("    grind=%s" % str(grind_keys))
	assert_eq(grind_keys, live_keys, "the two engines must alias the same effects")
	for k in live_keys:
		assert_eq(str(grind.get(k, "")), str(live[k]), "both engines must alias %s to the same key" % k)


func test_every_alias_target_is_a_key_something_reads() -> void:
	## An alias whose TARGET nothing reads is the original defect wearing a fix. Measured against the
	## two files that consume status keys, not against the aliasing files' own lines.
	var live: Dictionary = _aliases(BM_PATH)
	assert_gt(live.size(), 2, "CONTROL: aliases must have been found")
	var combatant_src: String = FileAccess.get_file_as_string(COMBATANT_PATH)
	var bm_src: String = FileAccess.get_file_as_string(BM_PATH)
	var unread: Array[String] = []
	for effect in live:
		var key: String = str(live[effect])
		var quoted: String = "\"%s\"" % key
		var in_combatant: bool = combatant_src.contains(quoted)
		var in_live_elsewhere: bool = bm_src.count(quoted) > 1
		if not in_combatant and not in_live_elsewhere:
			unread.append("%s -> %s" % [effect, key])
	for u in unread:
		gut.p("    UNREAD TARGET: " + u)
	assert_eq(unread.size(), 0, "an alias target no engine reads: " + ", ".join(unread))


func test_the_alias_scan_can_actually_say_missing() -> void:
	## Without this, both scans above are green whenever the regex finds nothing.
	var live: Dictionary = _aliases(BM_PATH)
	assert_true(live.has("amplify_poison"), "the scan must see the alias this file added")
	assert_eq(str(live.get("amplify_poison", "")), "festered", "and read its target, not its name")
	assert_false(live.has("a_key_no_engine_aliases"), "CONTROL: membership reds on an absent alias")
