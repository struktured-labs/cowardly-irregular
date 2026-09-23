extends GutTest

## A CHARGE ADVERTISED AS A DURATION.
##
## Several statuses are spent by the first thing that tests them: the consumer
## checks has_status(X) and calls remove_status(X) in the same breath. The
## ability that applies one carries `duration: 2`, the description repeats the
## 2, and the player plans two turns of cover they do not have.
##
##   barrier      _execute_attack / _execute_physical_ability / _execute_magic_ability
##                nullifies ONE hit outright (any magnitude, either damage kind), then breaks
##   magic_block  _execute_magic_ability — cancels ONE spell
##   invisible    ASYMMETRIC: spells miss for the full duration, but the first
##                PHYSICAL swing consumes it ("the swing reveals them")
##
## This is a different axis from test_defense_buff_label_honesty, which guards
## physical-vs-blanket wording on defense_up. That file's peer group was one
## effect; the family is every effect that mitigates. Sweeping the family is
## what found these — four descriptions, none of them defense_up.
## (cowir-sfx msg 3356/3365: "my sibling check was real; its SCOPE was the batch
## when the peer group is the family.")
##
## The consumed set is DERIVED from BattleManager, never listed here. Re-authoring
## a consumer so it ticks down instead of clearing re-derives what its abilities
## may claim.
##
## NOTE `absorb_amount: 800` on guardian_wall is dead data as measured 2026-07-29 —
## 2 mentions in src/, both inside comments (controls: duration 93, mp_cost 34,
## target_type 69). The barrier consumer nullifies the hit whatever its size. Left
## in place, not mine to remove.
##
## That is not a footnote: guardian_wall's description says the ward nullifies a hit
## "outright", which is TRUE ONLY WHILE absorb_amount IS DEAD. Wire it and the ward
## becomes a capped pool, the description becomes a lie, and this guard would not
## notice — the wording still admits single use. So the claim is asserted below
## rather than left in prose.

const ABILITIES := "res://data/abilities.json"
const BATTLE_MGR := "res://src/battle/BattleManager.gd"

## Promises persistence across turns.
const DURATION_CLAIM := "(?i)for (\\d+|one|two|three|multiple) turns?|\\ball incoming\\b"

## Admits the charge is spent once.
const SINGLE_USE := "(?i)\\bnext\\b|\\bone (hit|spell|attack)\\b|\\bonce\\b|\\bfirst\\b|\\bsingle\\b|\\boutright\\b"

## stun used to clear on the first skipped turn, so time_stop (duration 2) and
## infinite_loop (duration 3) advertised turns they did not deliver. The skip
## consumer now ticks status_durations, so those claims are true and stun is not
## in the consumed set. If it goes back to an immediate clear, the guard below
## fails on those two descriptions — do not carve it out again.


func _abilities() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(ABILITIES))
	return d.get("abilities", d) if d is Dictionary else {}


## Statuses whose check and removal sit in the same block — spent, not timed.
func _consumed_statuses() -> Dictionary:
	var lines := FileAccess.get_file_as_string(BATTLE_MGR).split("\n")
	var re := RegEx.new()
	re.compile("has_status\\(\"(\\w+)\"\\)")
	var out := {}
	for i in lines.size():
		var m := re.search(lines[i])
		if m == null:
			continue
		var s := m.get_string(1)
		var window := ""
		for j in range(i, mini(i + 8, lines.size())):
			window += lines[j] + "\n"
		if not window.contains("remove_status(\"%s\")" % s):
			continue
		# A duration tick in the same block is timed, not spent on first use.
		if window.contains("status_durations.get(\"%s\"" % s) or window.contains("status_durations[\"%s\"]" % s):
			continue
		out[s] = true
	return out


## VACUOUS-PASS CONTROL. A reworded consumer or a failed parse empties one side,
## and two empty sets agree perfectly — the guard below would go green having read
## nothing. Both floors must fire before any of it means anything.
func test_control_both_sides_are_non_empty() -> void:
	var consumed := _consumed_statuses()
	assert_gt(consumed.size(), 4, "must derive consumed-on-use statuses from BattleManager — 0 makes the guard vacuous: %s" % [consumed.keys()])
	for s in ["barrier", "magic_block", "invisible"]:
		assert_true(consumed.has(s), "%s must still be consumed-on-use — if it now ticks down, its abilities may advertise duration again" % s)
	assert_false(consumed.has("stun"), "stun ticks authored duration on each skipped turn — an immediate clear makes time_stop and infinite_loop lie")

	var ab := _abilities()
	assert_gt(ab.size(), 50, "abilities.json must parse with a real corpus")
	var appliers := 0
	for k in ab:
		if ab[k] is Dictionary and consumed.has(ab[k].get("effect", "")):
			appliers += 1
	assert_gt(appliers, 5, "must find abilities applying a consumed-on-use effect, else this file guards nothing")


## PREMISE BEHIND guardian_wall's WORDING (re-pinned 2026-09-11). absorb_amount became a LIVE
## budget for damage_absorb (cowir-battle, lane/absorb-amount-is-a-budget) — but barrier is a
## different effect: its handlers remove the status and nullify the WHOLE hit, so guardian_wall's
## "outright" stays true and its absorb_amount: 800 is vestigial documentation. The day someone wires
## the budget into barrier, the description becomes a lie; this pins both halves so that shows up.
func _enclosing_function(src: String, idx: int) -> String:
	var start: int = src.rfind("\nfunc ", idx)
	var stop: int = src.find("\nfunc ", idx + 1)
	if stop == -1:
		stop = src.length()
	return src.substr(start, stop - start)


func test_premise_barrier_nullifies_whole_hits_and_only_damage_absorb_reads_the_budget() -> void:
	var src: String = FileAccess.get_file_as_string(BATTLE_MGR)
	var sites: int = 0
	var from: int = 0
	while true:
		var idx: int = src.find("has_status(\"barrier\")", from)
		if idx == -1:
			break
		sites += 1
		var fn: String = _enclosing_function(src, idx)
		assert_true(fn.contains("remove_status(\"barrier\")"), "CONTROL: the function around a barrier check must be the one that spends the ward, else this scanned the wrong code")
		assert_false(fn.contains("absorb_amount"), "barrier's handler now consults absorb_amount — guardian_wall's ward is capped, so its \"outright\" wording is wrong. Fix the description and this test together.")
		from = idx + 1
	assert_gt(sites, 0, "CONTROL: at least one barrier site must exist, else the absence above is vacuous")
	var absorb_idx: int = src.find("\"damage_absorb\":")
	assert_gt(absorb_idx, -1, "the damage_absorb effect arm must exist")
	assert_true(_enclosing_function(src, absorb_idx).contains("absorb_amount"), "damage_absorb must read absorb_amount — it is the budget that keeps fill_the_void from being unkillable")
	var f := FileAccess.open(ABILITIES, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var desc: String = str(data["guardian_wall"].get("description", ""))
	var single := RegEx.new()
	single.compile(SINGLE_USE)
	assert_true(single.search(desc) != null, "guardian_wall's ward is consumed on use and its text must admit it: %s" % desc)


## THE GUARD. Claim persistence only if you also admit the charge.
func test_consumed_effects_do_not_advertise_duration_alone() -> void:
	var consumed := _consumed_statuses()
	var dur := RegEx.new()
	assert_eq(dur.compile(DURATION_CLAIM), OK, "pattern must compile")
	var single := RegEx.new()
	assert_eq(single.compile(SINGLE_USE), OK, "pattern must compile")

	var liars: Array = []
	for k in _abilities():
		var v = _abilities()[k]
		if not (v is Dictionary):
			continue
		var e: String = str(v.get("effect", ""))
		if not consumed.has(e):
			continue
		var d: String = str(v.get("description", ""))
		if dur.search(d) != null and single.search(d) == null:
			liars.append("%s [%s, duration:%s]: \"%s\"" % [k, e, v.get("duration", "?"), d])

	assert_eq(liars, [], "these effects are spent by the first hit/spell that tests them, but the "
		+ "description sells turns of cover. AbilitiesMenu renders this verbatim and the player "
		+ "budgets MP against it. Say what one charge buys: %s" % [liars])


## These two descriptions are the reason the guard must see stun. They claim turns
## and do not admit single use, so an immediate clear would land them in the liar list.
func test_stun_duration_claims_are_what_the_guard_watches() -> void:
	var dur := RegEx.new()
	assert_eq(dur.compile(DURATION_CLAIM), OK)
	var single := RegEx.new()
	assert_eq(single.compile(SINGLE_USE), OK)
	var ab := _abilities()
	for id in ["time_stop", "infinite_loop"]:
		var v: Dictionary = ab[id]
		var d: String = str(v.get("description", ""))
		assert_eq(str(v.get("effect", "")), "stun", "%s must still apply stun" % id)
		assert_true(dur.search(d) != null, "%s must still advertise a multi-turn stun: %s" % [id, d])
		assert_null(single.search(d), "%s must not also admit single use, or a one-shot clear would pass the guard: %s" % [id, d])
	assert_false(_consumed_statuses().has("stun"), "stun ticks its duration, so those claims are true and the guard stays green")
