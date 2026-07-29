extends GutTest

## A passive description is a PROMISE ON AN EQUIP BUTTON. MenuScene.gd:898 renders it
## while the player decides what to equip, so an effect nothing reads is not dormant
## data — it is a capability the player is told they now have.
##
## This class has shipped twice and been fixed twice, both by WIRING the effect:
##   Combatant.gd:371  death_resistance "75% chance to survive a killing blow"
##                     — "no code path read the meta effect, the passive was pure decoration"
##   Combatant.gd:444  "+50% healing" — "players equipped the passive seeing it and got nothing"
##
## Four more remain, measured 2026-07-29. All are REACHABLE: each sits on a job in
## jobs.json, and advanced/meta jobs unlock in JobMenu under debug mode, which defaults
## on. Control: weapon_mastery's attack_multiplier resolves in 6 src/ files.
##
## THESE ARE NOT ACCIDENTS. Every one is a feature named in CLAUDE.md — Ninja's
## "overworld shortcuts", Skiptrotter's "bypass dungeons", Scriptweaver's debug console.
## They were authored ahead of an engine that has not arrived. So this file does NOT
## demand they be fixed, and deliberately does not rewrite their prose: editing
## "Jump over gaps" down to something true would launder a planned feature into a
## smaller one, and the fix both prior instances got was a consumer, not a reword.
##
## WHAT IT DOES is hold the set still, in BOTH directions:
##   a FIFTH unwired passive appears  -> red, because the list grew unnoticed
##   one of these four gets wired     -> red, forcing the entry out
## so the carve-out cannot quietly widen and cannot outlive its reason.
## (cowir-sfx's KNOWN_PENDING_CONSUMER shape — a dict that never claims liveness.)

const PASSIVES := "res://data/passives.json"
const EFFECT_BLOCKS := ["stat_mods", "meta_effects", "conditional_mods"]

## passive id -> why its effect keys have no consumer yet. Owner, not permission.
const AUTHORED_AHEAD := {
	"double_jump": "Ninja overworld traversal — CLAUDE.md 'speedrun functions, overworld shortcuts'",
	"wall_climb": "Ninja overworld traversal — same feature",
	"optional_detector": "Skiptrotter routing — CLAUDE.md 'warp to next quest/boss, bypass dungeons'",
	"debug_mode": "Scriptweaver debug console — CLAUDE.md 'edit formulas via debug console'",
}

## Keys whose consumers we assert exist, to prove the scan itself resolves.
const CONTROLS := ["attack_multiplier", "healing_multiplier"]


func _passives() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(PASSIVES))
	return d.get("passives", d) if d is Dictionary else {}


## Every .gd under src/, flattened once — the corpus a consumer would have to live in.
func _src_text() -> String:
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
				out += FileAccess.get_file_as_string(p)
			f = d.get_next()
		d.list_dir_end()
	return out


## passive id -> its effect keys that appear nowhere in src/.
func _unwired() -> Dictionary:
	var src := _src_text()
	var out := {}
	for pid in _passives():
		var v = _passives()[pid]
		if not (v is Dictionary):
			continue
		var dead: Array = []
		for block in EFFECT_BLOCKS:
			var b = v.get(block, {})
			if not (b is Dictionary):
				continue
			for key in b:
				if not src.contains(str(key)):
					dead.append(str(key))
		if not dead.is_empty():
			out[pid] = dead
	return out


## FLOOR. An empty src/ walk makes every key look dead and the diff below meaningless;
## a failed JSON parse makes every key look live. Both directions have to be excluded.
func test_control_scan_resolves() -> void:
	var src := _src_text()
	assert_gt(src.length(), 200000, "src/ walk must load a real corpus — a short read makes "
		+ "every effect key look unwired")
	for c in CONTROLS:
		assert_true(src.contains(c), "%s must resolve in src/ — if the controls do not appear, "
			+ "this scan is not finding consumers and its verdict means nothing" % c)
	assert_gt(_passives().size(), 40, "passives.json must parse with a real corpus")


## THE RATCHET. Both directions.
func test_unwired_passive_set_is_exactly_the_authored_ahead_set() -> void:
	var found := _unwired()

	var new_ones: Array = []
	for pid in found:
		if not AUTHORED_AHEAD.has(pid):
			new_ones.append("%s: %s" % [pid, found[pid]])
	assert_eq(new_ones, [], "a passive gained an effect key that nothing in src/ reads. Its "
		+ "description is rendered on an equip button (MenuScene.gd:898), so the player is being "
		+ "promised a capability that does not exist — the same defect fixed at Combatant.gd:371 "
		+ "and :444, both times by wiring the effect. Wire it, or add it here with an owner: %s" % [new_ones])

	var now_wired: Array = []
	for pid in AUTHORED_AHEAD:
		if not found.has(pid):
			now_wired.append(pid)
	assert_eq(now_wired, [], "these are listed as authored-ahead but their effects now resolve in "
		+ "src/. Good — remove them from AUTHORED_AHEAD so the list keeps describing reality: %s" % [now_wired])
