extends GutTest
## `is_miniboss` without `is_boss` is a SILENT misclassification, and the stakes are not local to the
## writer: five is_boss consumers have no is_miniboss fallback, so a miniboss flagged only as a
## miniboss takes no boss dialogue, no danger-HP line, and no ELITE grade on the victory screen.
## `test_a_miniboss_is_a_miniboss_whichever_door_it_came_through_regression` pins that for ONE door
## (spawn_miniboss, the .654 fix). This pins the INVARIANT across every door, derived from the
## spawner's own source, so a new path cannot reintroduce the defect the other guard closed.
##
## Why derived and not a line-number list: that guard's header names BattleScene:795/:3441/:5603 and
## VictoryOverlay:161/:186, which today are :810/:3517/:5699 and :231/:256. Every pointer drifted,
## the identity did not. A guard that re-measures cannot go stale the way a guard that cites does.
const SPAWNER_PATH := "res://src/battle/BattleEnemySpawner.gd"
const CONSUMER_PATHS := ["res://src/battle/BattleScene.gd", "res://src/battle/VictoryOverlay.gd"]


## Top-level `func` bodies, keyed by name. Comment-stripped so a commented-out write cannot satisfy
## the invariant, and line-preserving so a body's bounds are the file's own.
static func _functions(path: String) -> Dictionary:
	var src := GdSource.strip_comments(FileAccess.get_file_as_string(path))
	var out := {}
	var name := ""
	var buf := PackedStringArray()
	for line in src.split("\n"):
		if line.begins_with("func ") or line.begins_with("static func "):
			if name != "":
				out[name] = "\n".join(buf)
			var head := line.substr(line.find("func ") + 5)
			name = head.substr(0, maxi(head.find("("), 0))
			buf = PackedStringArray()
		if name != "":
			buf.append(line)
	if name != "":
		out[name] = "\n".join(buf)
	return out


func _spawn_functions() -> Dictionary:
	var all := _functions(SPAWNER_PATH)
	var out := {}
	for n in all:
		if str(n).begins_with("spawn"):
			out[n] = all[n]
	return out


## FLOOR: the derivation must find the doors, or every arm below judges an empty dict.
func test_floor_the_derivation_finds_the_spawn_doors() -> void:
	var fns := _spawn_functions()
	assert_gt(fns.size(), 2, "the spawner must expose more than two spawn* functions, or the parse broke")
	for required in ["spawn_enemies", "spawn_miniboss", "spawn_encounter_enemies"]:
		assert_true(fns.has(required), "%s must be found by the derivation" % required)
	assert_true(FileAccess.file_exists(SPAWNER_PATH), "the spawner source must be readable")


## THE INVARIANT: any door that flags a miniboss flags it boss-like too. Derived, so a NEW door is
## covered the day it is written rather than the day someone remembers to add it here.
func test_no_door_flags_a_miniboss_without_flagging_it_boss() -> void:
	var fns := _spawn_functions()
	var writers := 0
	for n in fns:
		var body: String = fns[n]
		var mini := body.contains('set_meta("is_miniboss"')
		var boss := body.contains('set_meta("is_boss"')
		if not mini:
			continue
		writers += 1
		assert_true(boss,
			"%s sets is_miniboss and NOT is_boss -- the five is_boss consumers with no miniboss fallback would treat this enemy as an ordinary encounter" % n)
	assert_gt(writers, 0, "FLOOR: at least one door must flag a miniboss, or this arm judges nothing")


## And the converse, so the pair cannot be split from the other side: a door that flags a monster
## boss-like for a MINIBOSS roster must keep the miniboss meta the music and the banner read.
func test_the_miniboss_meta_is_not_replaced_by_the_boss_one() -> void:
	var fns := _spawn_functions()
	assert_true(fns.has("spawn_miniboss"), "FLOOR: the miniboss door must exist")
	var body: String = fns["spawn_miniboss"]
	assert_true(body.contains('set_meta("is_miniboss"'),
		"spawn_miniboss must keep is_miniboss -- it drives music selection and the MINIBOSS banner, so the boss flag is an addition, never a substitution")
	assert_true(body.contains('set_meta("is_boss"'), "and must still flag it boss-like")


## THE EXEMPTION, and it is load-bearing in the opposite direction: the dispatcher flags neither,
## because its own roster contains no boss. An arm asserting "every door flags both" would read that
## as a defect and license flagging ordinary monsters as bosses -- a balance change wearing a
## consistency fix. This arm is what makes the exemption checkable instead of remembered.
func test_the_dispatcher_is_exempt_because_its_roster_holds_no_boss() -> void:
	var fns := _spawn_functions()
	assert_true(fns.has("spawn_enemies"), "FLOOR: the dispatcher must exist")
	var body: String = fns["spawn_enemies"]
	assert_false(body.contains('set_meta("is_boss"'),
		"the dispatcher must not flag its random roster boss-like")
	var raw := FileAccess.get_file_as_string("res://data/monsters.json")
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "FLOOR: monsters.json must parse")
	if not (parsed is Dictionary):
		return
	var monsters: Dictionary = (parsed as Dictionary).get("monsters", parsed)
	var checked := 0
	for entry in BattleEnemySpawner.MONSTER_TYPES:
		var mid: String = str(entry.get("id", ""))
		var m: Dictionary = monsters.get(mid, {})
		checked += 1
		assert_false(bool(m.get("boss", false)) or bool(m.get("miniboss", false)),
			"%s is in the dispatcher's random roster AND flagged boss/miniboss -- the exemption above is then wrong and that roster needs the flags" % mid)
	assert_gt(checked, 0, "FLOOR: the dispatcher's roster must be non-empty")


## THE PREMISE that makes the invariant worth guarding, measured rather than quoted: at least one
## is_boss consumer decides boss-ness with no is_miniboss fallback in its own frame. If this ever
## reaches zero the invariant is moot and this file can go -- which is a finding, not a failure.
func test_a_consumer_really_does_decide_boss_ness_without_a_miniboss_fallback() -> void:
	var lonely := PackedStringArray()
	for path in CONSUMER_PATHS:
		var fns := _functions(path)
		for n in fns:
			var body: String = fns[n]
			if not body.contains('has_meta("is_boss")'):
				continue
			if body.contains("is_miniboss"):
				continue
			lonely.append("%s.%s" % [path.get_file(), n])
	assert_gt(lonely.size(), 0,
		"no consumer reads is_boss without a miniboss fallback -- the invariant this file defends has no stakes left, so re-derive it rather than keeping a guard that cannot matter")
	gut.p("fallback-less is_boss consumers: %s" % ", ".join(lonely))
