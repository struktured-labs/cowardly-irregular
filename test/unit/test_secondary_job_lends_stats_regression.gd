extends GutTest

## struktured 2026-09-06: "2ndary job does nothing apparently".
##
## The ABILITY half was fixed that day — knows_ability and get_known_abilities
## lend the secondary job's base kit. The STAT half was not. assign_secondary_job's
## own docstring promised a "minor stat boost", and recalculate_stats() — the single
## authority that rebuilds every derived stat — never read secondary_job at all.
## A secondary job was worth a sprite tint and a menu line.
##
## These arms are BEHAVIOURAL: they build real Combatants and run the real
## recalculate_stats(), so they go red if the pipeline stops lending rather than
## if someone reformats the source. Every expected value is a typed literal
## derived from the fixture, never from the code under test.

const FRACTION: float = Combatant.SECONDARY_JOB_STAT_FRACTION

## Deliberately lopsided so each arm reads a stat the OTHER job is bad at:
## the fighter's magic is low and the mage's magic is high, so a fighter/mage
## moving on `magic` cannot be explained by the primary alone.
const FIGHTER := {
	"id": "fighter",
	"stat_modifiers": {
		"max_hp": 1000, "max_mp": 30, "attack": 150,
		"defense": 140, "magic": 50, "magic_defense": 70, "speed": 8,
	},
}
const MAGE := {
	"id": "mage",
	"stat_modifiers": {
		"max_hp": 900, "max_mp": 80, "attack": 50,
		"defense": 80, "magic": 200, "magic_defense": 40, "speed": 9,
	},
}


func _pc(secondary: Variant = null, level: int = 1) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Test"
	c.job = FIGHTER.duplicate(true)
	c.job_level = level
	if secondary != null:
		c.secondary_job = (secondary as Dictionary).duplicate(true)
		c.secondary_job_id = str((secondary as Dictionary)["id"])
	c.recalculate_stats()
	return c


## The knob is load-bearing for every other arm in this file: at 0.0 the feature
## is inert and each "lends" assertion below would compare a value to itself and
## pass. Fail here rather than let the rest go quietly vacuous.
func test_the_lend_fraction_is_actually_enabled() -> void:
	assert_gt(FRACTION, 0.0,
		"SECONDARY_JOB_STAT_FRACTION is %s — at 0.0 a secondary job lends nothing and every other arm in this file passes vacuously" % FRACTION)
	assert_lt(FRACTION, 1.0,
		"SECONDARY_JOB_STAT_FRACTION is %s — at or above 1.0 a secondary is worth as much as a primary, which is not a 'minor' boost" % FRACTION)


func test_secondary_job_lends_a_fraction_of_its_magic() -> void:
	var solo := _pc()
	var dual := _pc(MAGE)
	# CONTROL: the primary alone must NOT already contain the mage's magic —
	# otherwise "dual is higher" would be true for reasons unrelated to lending.
	assert_eq(solo.magic, 50,
		"fixture drift: a level-1 fighter with no secondary should read the fighter's own magic 50, got %d" % solo.magic)
	var expected: int = 50 + roundi(200.0 * FRACTION)
	assert_eq(dual.magic, expected,
		"fighter/mage magic should be the fighter's 50 plus %s of the mage's 200 (= %d), got %d" % [FRACTION, expected, dual.magic])
	assert_gt(dual.magic, solo.magic,
		"the secondary job lent nothing — fighter/mage magic %d is not above fighter-only %d" % [dual.magic, solo.magic])


func test_every_moddable_stat_is_lent_not_just_the_named_ones() -> void:
	## The equipment block one screen below this code carries the comment
	## "a hand-listed six silently omits whatever it does not name" — this arm
	## is why the lend is driven off MODDABLE_STATS instead.
	var solo := _pc()
	var dual := _pc(MAGE)
	var moved: Array[String] = []
	for stat in Combatant.MODDABLE_STATS:
		# roundi mirrors the pipeline: truncation here would let speed (9 -> 0)
		# be skipped by `continue` and the canary below would never notice that
		# the smallest stats are silently excluded from lending.
		var lent: int = roundi(float(MAGE["stat_modifiers"].get(stat, 0)) * FRACTION)
		if lent == 0:
			continue
		var got: int = int(dual.get(stat)) - int(solo.get(stat))
		assert_eq(got, lent,
			"%s should gain %d from the secondary, gained %d" % [stat, lent, got])
		moved.append(stat)
	# Output-side canary, typed literal: names the members checked, not a count
	# derived from the loop. If the fixture or MODDABLE_STATS ever shrinks to
	# nothing, the loop above asserts zero times and this arm is the only thing
	# that notices.
	assert_eq(moved.size(), 7,
		"expected all 7 moddable stats to move; moved %s" % str(moved))


func test_lent_aptitude_scales_with_job_level_like_the_primary() -> void:
	## Placed before the level multiplier, so a level-11 fighter/mage gets
	## 1.4x the lent magic, not a flat bonus that dilutes as you level.
	var l1 := _pc(MAGE, 1)
	var l11 := _pc(MAGE, 11)
	var mult: float = 1.0 + (11 - 1) * 0.04
	assert_eq(l11.magic, int(float(l1.magic) * mult),
		"lent aptitude should scale with job_level (x%s): level 1 read %d, level 11 read %d" % [mult, l1.magic, l11.magic])


func test_dropping_the_secondary_gives_the_stats_back() -> void:
	var c := _pc(MAGE)
	var with_secondary: int = c.magic
	c.secondary_job = null
	c.secondary_job_id = ""
	c.recalculate_stats()
	assert_eq(c.magic, 50,
		"clearing the secondary should return magic to the fighter's own 50, got %d" % c.magic)
	assert_lt(c.magic, with_secondary,
		"clearing the secondary changed nothing — still %d" % c.magic)


func test_no_secondary_is_exactly_the_old_behaviour() -> void:
	## The zero-risk path: a character with no secondary must read identically
	## to pre-fix, so this change cannot move a single-job party.
	var c := _pc()
	assert_eq(c.magic, 50, "magic")
	assert_eq(c.attack, 150, "attack")
	assert_eq(c.max_hp, 1000, "max_hp")
	assert_eq(c.speed, 8, "speed")
