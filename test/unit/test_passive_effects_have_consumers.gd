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
## ⚠️ THE PREDICATE IS A PRESENCE PROXY, AND HERE IS EXACTLY HOW FAR IT REACHES.
## It asks "does this key's text appear in non-comment src/", which is not the same
## question as "is this key consumed". Bounded and exhausted 2026-07-29 rather than
## left as a caveat (cowir-sfx msg 3471, cowir-controller's predicate axis msg 3506):
##
##   comments                 FIXED — stripped below. Counting them hid THREE unwired
##                            passives, each passing on one comment that named its key.
##   dynamic construction     ONE exists: _get_passive_meta_effect_sum(element +
##                            "_absorb"). All 8 meta-effect call sites and every
##                            passive_mods index enumerated; it is the only non-literal
##                            argument, and it is exempted explicitly below.
##   fallback re-declaration  NOT FIXED, 4 keys affected. PassiveSystem.gd carries a
##                            hardcoded copy of passives.json, so a key it re-declares
##                            reads as "present" without anything consuming it:
##                            autobattle_advanced · hp_below_25 · show_formulas ·
##                            volatility_scaling. At least hp_below_25 IS consumed
##                            inside that same file, so "appears only there" does not
##                            settle it either way — it needs reading, not counting.
##   TRAILING inline comments only whole-line comments are skipped, so `foo()  # see
##                            preview_turns` would still count. Measured 2026-07-29: 0
##                            passive keys reach src/ only that way. DELIBERATELY not
##                            "fixed" — splitting on the first # would eat real code
##                            containing a string like "#FF0000", flipping this guard
##                            from safe under-reporting to false positives.
##   string literals          a key inside a live string (push_warning, a log line)
##                            counts as present. Measured: no passive key currently
##                            reaches src/ only that way.
##
## So the guard UNDER-reports: it can miss an unwired passive, never invent one. Every
## name it does report is a real promise on an equip button, which is the direction
## that matters for a player-facing claim.
##
## WHAT IT DOES is hold the set still, in BOTH directions:
##   a FIFTH unwired passive appears  -> red, because the list grew unnoticed
##   one of these four gets wired     -> red, forcing the entry out
## so the carve-out cannot quietly widen and cannot outlive its reason.
## (cowir-sfx's KNOWN_PENDING_CONSUMER shape — a dict that never claims liveness.)

const PASSIVES := "res://data/passives.json"

## Keys that describe the passive rather than what it DOES. Everything else is an
## effect block, DERIVED — this was a hand list of stat_mods/meta_effects/
## conditional_mods, which was complete the day it was written and would have stayed
## silently complete-looking if a fourth block type ever shipped. The set to check
## comes from the file now, so a new block is covered without anyone remembering.
## (cowir-ai's rule, msg 3473; cowir-sfx found the identical shape in a weapon list.)
const METADATA_KEYS := ["id", "name", "category", "description", "restrictions"]

## passive id -> why its effect keys have no consumer yet. Owner, not permission.
const AUTHORED_AHEAD := {
	"double_jump": "Ninja overworld traversal — CLAUDE.md 'speedrun functions, overworld shortcuts'",
	"wall_climb": "Ninja overworld traversal — same feature",
	"optional_detector": "Skiptrotter routing — CLAUDE.md 'warp to next quest/boss, bypass dungeons'",
	"debug_mode": "Scriptweaver debug console — CLAUDE.md 'edit formulas via debug console'",
	## Found 2026-07-29 once comments stopped counting as consumers. These are NOT authored-ahead:
	## nothing in CLAUDE.md plans them, and each promises a concrete mechanic on an equip button.
	## Listed so the set stays honest and the ratchet keeps working — not as permission to leave them.
	## steal_boost WAS here and is gone because it got wired the same day, which is this list working
	## as designed: the self-destructing direction went red the moment it became a lie.
	"time_sense": "Time Mage 'preview enemy actions 1 turn ahead' — preview_turns unread",
	"speedrun_timer": "Skiptrotter split tracking — track_personal_best unread",
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
				## Comment lines are STRIPPED. This is a CONSUMER check, and a key mentioned
				## only in prose is not consumed — counting comments was a label-read that
				## hid THREE unwired passives (steal_boost, time_sense, speedrun_timer),
				## each passing solely because one comment happened to name its key.
				for line in FileAccess.get_file_as_string(p).split("\n"):
					if line.strip_edges().begins_with("#"):
						continue
					out += line + "\n"
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
		for block in v.keys():
			if block in METADATA_KEYS:
				continue
			var b = v.get(block, {})
			if not (b is Dictionary):
				continue
			for key in b:
				if src.contains(str(key)):
					continue
				## The ONE constructed read in src/: _get_passive_meta_effect_sum(element
				## + "_absorb"). Enumerated all 8 meta-effect call sites and every
				## passive_mods index; this is the only non-literal argument, so it is the
				## only key shape a text search cannot see. Bounded and exhausted rather
				## than left as a stated caveat (cowir-sfx msg 3471).
				if str(key).ends_with("_absorb"):
					continue
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
	## Keep the parens. Written unparenthesised, `% c` bound to the trailing literal
	## (which has no specifier), threw "not all arguments converted", and KILLED THIS
	## TEST METHOD — assert_true never ran and the five assertions below were skipped.
	## GUT reported 2/2 passed with the whole floor dead: not [Failed], not even
	## [Risky], because the file's OTHER test still asserted. Asserts 3 -> 9 on fixing.
	##
	## MECHANISM — measured by cowir-main (8 shapes, one variable at a time) and
	## cowir-ai (in vs out of GUT), after I published a WRONG one ("argument position
	## aborts"). Don't hunt argument-position bugs on the strength of this file:
	##   for-loop VARIABLE as the % right operand, inside GUT  -> ABORTS the method
	##   every other shape tested (assignment · direct arg · concat · precedence ·
	##   while-loop · local var · function-call operand · all of it outside GUT)
	##                                                        -> logs, returns the
	##                                                           literal, CONTINUES
	##   const-foldable operands (two literals)               -> PARSE error, whole
	##                                                           file dead, no Totals
	## Nobody isolated WHY the loop-variable case differs; three lanes published three
	## mechanisms and two were wrong, so it is recorded as measured, not explained.
	## Detection is complementary: the abort still scores, so cowir-battle's
	## asserted-nothing/assert-count sees it; the parse-error variant has no tests to
	## score and only gate.sh's missing-Totals floor sees it.
	for c in CONTROLS:
		assert_true(src.contains(c), ("%s must resolve in src/ — if the controls do not " % c)
			+ "appear, this scan is not finding consumers and its verdict means nothing")
	assert_gt(_passives().size(), 40, "passives.json must parse with a real corpus")

	## The derivation replaced a hand list. Prove it still yields the three block types
	## that existed when it did — if it yields fewer, METADATA_KEYS is eating real
	## effect blocks and every "no dead keys" result below is vacuous.
	var blocks := {}
	for pid in _passives():
		var v = _passives()[pid]
		if v is Dictionary:
			for k in v:
				if not (k in METADATA_KEYS):
					blocks[k] = true
	for known in ["stat_mods", "meta_effects", "conditional_mods"]:
		assert_true(blocks.has(known), "%s must still be derived as an effect block" % known)


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
