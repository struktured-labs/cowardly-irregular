extends GutTest

## Esuna is in the DEFAULT cleric autobattle script (AutobattleSystem, three sites) and in two
## preset templates. In a LIVE battle it clears ten ailments (BattleManager's "cleanse" arm). In a
## GRIND the resolver had no arm for it, so it fell through to the generic unmodelled-effect
## fallback — `target.add_status(effect, duration)` — and the cleric spent 10 MP to give the ally
## a junk status literally named "cleanse" while the blind it was cast to cure stayed on.
##
## Same shape as the Ninja's vanish/shadow_step (.330): a spell the shipped scripts cast every
## fight, applied by the grind and read by nobody. One rung worse, because the fallback does not
## merely no-op — it writes a status name no consumer anywhere recognises.

const ResolverScript := preload("res://src/autogrind/HeadlessBattleResolver.gd")
## BattleManager's list, duplicated deliberately: if live grows an ailment and headless does not,
## the divergence should red HERE rather than be quietly inherited from a shared constant.
const LIVE_AILMENTS := ["poison", "blind", "sleep", "stun", "burning", "curse", "confuse", "fear", "charm", "doom"]

var _resolver: HeadlessBattleResolver

func before_each() -> void:
	_resolver = ResolverScript.new()

func _cleric() -> Combatant:
	var c := Combatant.new()
	c.combatant_name = "Cleric"
	c.max_hp = 100
	c.current_hp = 100
	c.max_mp = 60
	c.current_mp = 60
	return c

func _ally() -> Combatant:
	var a := Combatant.new()
	a.combatant_name = "Ally"
	a.max_hp = 100
	a.current_hp = 40
	return a

func _cast_esuna(caster: Combatant, target: Combatant) -> void:
	_resolver.call("_resolve_ability", caster, "esuna", [target])

func test_esuna_clears_the_blind_it_was_cast_for() -> void:
	var caster := _cleric()
	var target := _ally()
	target.add_status("blind", 3)
	assert_true(target.has_status("blind"), "CONTROL: the ally is blinded before the cast")
	_cast_esuna(caster, target)
	assert_false(target.has_status("blind"),
		"the grind's Esuna left the blind on — 10 MP for nothing, every fight")

func test_esuna_does_not_invent_a_status_called_cleanse() -> void:
	## The specific fallthrough. "cleanse" is an EFFECT name, never a status; no consumer in the
	## repo reads it, so it accumulated on the ally as silent garbage.
	var target := _ally()
	_cast_esuna(_cleric(), target)
	assert_false(target.has_status("cleanse"),
		"the unmodelled-effect fallback wrote the effect name as a status")

func test_it_clears_every_ailment_the_live_battle_clears() -> void:
	## Parity by enumeration. A partial list is the same defect wearing a smaller blast radius.
	var target := _ally()
	for ailment in LIVE_AILMENTS:
		target.add_status(ailment, 3)
	var applied: Array = []
	for ailment in LIVE_AILMENTS:
		if target.has_status(ailment):
			applied.append(ailment)
	assert_eq(applied.size(), LIVE_AILMENTS.size(),
		"CONTROL: every ailment applied before the cast (%s)" % str(applied))
	_cast_esuna(_cleric(), target)
	var left: Array = []
	for ailment in LIVE_AILMENTS:
		if target.has_status(ailment):
			left.append(ailment)
	assert_eq(left.size(), 0, "the grind's Esuna left ailments the live one clears: " + str(left))

func test_it_lifts_a_death_sentence_like_the_live_arm() -> void:
	## doom_counter is a separate field from the status, and live zeroes it. Missed here, a
	## grind-doomed character dies through a successful cleanse.
	var target := _ally()
	target.doom_counter = 3
	_cast_esuna(_cleric(), target)
	assert_eq(target.doom_counter, 0, "a cleansed ally is still counting down to death")

func test_it_leaves_buffs_alone() -> void:
	## CONTROL against over-clearing: cleanse takes NEGATIVE statuses. Stripping a protect the
	## party just paid for would be a worse bug than the one this file fixes.
	var target := _ally()
	target.add_status("regen", 3)
	target.add_status("blind", 3)
	_cast_esuna(_cleric(), target)
	assert_true(target.has_status("regen"), "cleanse stripped a BUFF — it must only take ailments")
	assert_false(target.has_status("blind"), "CONTROL: and it still took the ailment")

func test_the_grind_can_actually_inflict_what_esuna_cures() -> void:
	## Anti-vacuity, and the reason this is player-facing rather than theoretical: the fix is only
	## worth shipping if a grind produces these ailments in the first place. The resolver's own
	## round tick names four of them as things it expires off combatants.
	var src: String = FileAccess.get_file_as_string("res://src/autogrind/HeadlessBattleResolver.gd")
	assert_gt(src.length(), 1000, "CONTROL: the resolver reads")
	var inflicted: Array = []
	for ailment in LIVE_AILMENTS:
		if src.contains('remove_status("%s")' % ailment):
			inflicted.append(ailment)
	assert_gt(inflicted.size(), 2,
		"the grind expires fewer ailments than expected — re-check that Esuna has work to do: %s" % str(inflicted))
