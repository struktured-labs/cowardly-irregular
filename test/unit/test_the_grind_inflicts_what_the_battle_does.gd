extends GutTest

## ⛔ IN THE GRIND, NO DAMAGING ABILITY EVER INFLICTED ITS STATUS. HeadlessBattleResolver's `magic` and
## `physical` arms dealt the damage and dropped the effect entirely, while BattleManager rolls
## `effect_chance` — a key 68 abilities author, from 0.2 to 1.0. It failed in BOTH directions: the
## Bard's Riff never blinded, `plague_bite` never poisoned at its authored 1.0, and no enemy ever
## stunned, poisoned or blinded the party. CLAUDE.md puts hours of play in the grind.
##
## Found by censusing ability keys against each engine separately — the gap
## test_ability_effect_keys_reach_the_engine_regression names in its third limit and hands to this lane:
## a key the live engine reads scores CONSUMED there even when the grind ignores it.
##
## Measured on the real resolver, 400 casts each, before → after:
##   riff (0.7)           0/400 → 284/400      ice_prison (0.8)   0/400 → 320/400
##   poison_touch (1.0)   0/400 → 400/400      shield_bash (0.3)  0/400 → 107/400
##   fire (no chance)     0/400 →   0/400  — the opt-in default, preserved
##   corrupting_touch     0/400 → 400/400 from the random_debuff pool

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")
## Enough casts that a 0.3 and a 0.7 cannot be confused, with a band far wider than the binomial
## spread (±0.15 is over 6 sigma at n=400). Seeded, so the arms are deterministic rather than flaky.
const CASTS := 400
const BAND := 0.15
var _saved_persist: bool


func before_each() -> void:
	_saved_persist = AutobattleSystem._test_disable_persistence
	AutobattleSystem._test_disable_persistence = true
	seed(20260916)


func after_each() -> void:
	## ⛔ RESTORE GLOBAL RANDOMNESS. `seed()` in before_each sets the PROCESS-WIDE rng, and GUT runs
	## every file in one process — so without this, every test that runs AFTER this file inherits a
	## deterministic stream. Measured: a probe drawing one randi() reported three different values
	## when run alone and THE SAME VALUE three times when run after this file.
	## The leak is order-dependent, which is the worst shape: a later probabilistic arm becomes
	## deterministic, and whether it draws a lucky number depends on which files preceded it.
	randomize()
	AutobattleSystem._test_disable_persistence = _saved_persist


func _combatant(name: String) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = name
	c.max_hp = 99999
	c.current_hp = 99999
	c.attack = 80
	c.magic = 80
	c.defense = 10
	c.is_alive = true
	return c


## How often the ability's status lands over CASTS attempts, and which statuses were seen.
func _landed(ability: Dictionary, ability_id: String = "probe") -> Dictionary:
	var resolver = ResolverScript.new()
	var caster := _combatant("Mira")
	var hits: int = 0
	var seen := {}
	for i in CASTS:
		var victim := _combatant("Goblin")
		resolver._maybe_inflict_status(caster, victim, ability, ability_id)
		if victim.status_effects.size() > 0:
			hits += 1
			for st in victim.status_effects:
				seen[str(st)] = true
		victim.free()
	return {"rate": float(hits) / float(CASTS), "seen": seen.keys()}


func test_the_authored_chance_is_the_rate_the_grind_rolls() -> void:
	var offenders: Array = []
	for ability_id in ["riff", "poison_touch", "ice_prison", "shield_bash"]:
		var ability: Dictionary = JobSystem.get_ability(ability_id)
		assert_false(ability.is_empty(), "CONTROL: %s is a real shipped ability" % ability_id)
		var authored: float = float(ability.get("effect_chance", 0.0))
		assert_gt(authored, 0.0, "CONTROL: %s authors a chance for this arm to be about" % ability_id)
		var rate: float = float(_landed(ability, ability_id)["rate"])
		if absf(rate - authored) > BAND:
			offenders.append("%s authored %.2f, landed %.2f" % [ability_id, authored, rate])
	assert_eq(offenders.size(), 0, "the grind rolls a different chance than the ability authors: " + str(offenders))


func test_a_damaging_ability_that_authors_no_chance_still_inflicts_nothing() -> void:
	## The live default is 0.0 on purpose — a damaging ability opts IN to a status by authoring a chance.
	## ⚠️ `death_sentence` is the fixture because it authors an EFFECT (doom) and no chance: my first
	## version used `fire`, which authors no effect at all and returns early, so it could not see the
	## default and stayed green when I flipped that default to 1.0. Three shipped damaging abilities
	## carry an effect with no chance, and all three are inert in the live engine too, by this rule.
	var sentence: Dictionary = JobSystem.get_ability("death_sentence")
	assert_eq(str(sentence.get("effect", "")), "doom", "CONTROL: death_sentence authors an effect")
	assert_false(sentence.has("effect_chance"), "CONTROL: and no chance, which is what the default decides")
	assert_eq(float(_landed(sentence, "death_sentence")["rate"]), 0.0,
		"so it inflicts nothing, %d casts running — the same as live" % CASTS)
	var fire: Dictionary = JobSystem.get_ability("fire")
	assert_eq(float(_landed(fire, "fire")["rate"]), 0.0, "and an ability with no effect at all inflicts nothing either")


func test_random_debuff_is_the_one_that_defaults_to_certain() -> void:
	## Mirrors the live special case: two abilities present the debuff as their headline and omit the
	## key, so `random_debuff` alone defaults to 1.0 and draws from the pool.
	var corrupting: Dictionary = JobSystem.get_ability("corrupting_touch")
	assert_eq(str(corrupting.get("effect", "")), "random_debuff", "CONTROL: corrupting_touch authors the random debuff")
	assert_false(corrupting.has("effect_chance"), "CONTROL: and authors no chance, which is why the default matters")
	var result: Dictionary = _landed(corrupting, "corrupting_touch")
	assert_eq(float(result["rate"]), 1.0, "it lands every time")
	assert_gt((result["seen"] as Array).size(), 1, "and draws varied debuffs from the pool, not one fixed status (%s)" % str(result["seen"]))
	for status in result["seen"]:
		assert_true(ResolverScript._RANDOM_DEBUFF_POOL.has(str(status)) or str(status) == "burning",
			"every drawn debuff comes from the pool (%s)" % str(status))


func test_the_two_aliases_land_the_status_that_actually_ticks() -> void:
	## freeze -> stun and burn -> burning, applied where live applies them. The DoT ticks only
	## "burning", so an ability inflicting "burn" in the grind would have been inert decoration.
	var frozen: Dictionary = _landed({"effect": "freeze", "effect_chance": 1.0, "duration": 3}, "frost_bite")
	assert_eq(frozen["seen"], ["stun"], "freeze is applied as stun")
	var burned: Dictionary = _landed({"effect": "burn", "effect_chance": 1.0, "duration": 3}, "ember")
	assert_eq(burned["seen"], ["burning"], "and burn as burning, which is the one that ticks")


func test_a_dead_target_is_not_afflicted() -> void:
	var resolver = ResolverScript.new()
	var caster := _combatant("Mira")
	var corpse := _combatant("Goblin")
	corpse.is_alive = false
	resolver._maybe_inflict_status(caster, corpse, {"effect": "poison", "effect_chance": 1.0}, "poison_touch")
	assert_eq(corpse.status_effects.size(), 0, "a certain status is still not applied to the dead")


func test_both_damage_arms_call_it() -> void:
	## The arms above prove the roll; this proves the grind's damage paths use it — which is the actual
	## defect, since the roll existed nowhere and the damage arms simply moved on.
	var code: String = GdSourceHelper.code_of("res://src/autogrind/HeadlessBattleResolver.gd")
	for arm in ['"magic":', '"physical":']:
		var at: int = code.find(arm)
		assert_gt(at, -1, "CONTROL: the %s arm survives stripping" % arm)
		var next_arm: int = code.find("\n\t\t\"", at + 1)
		var body: String = code.substr(at, (next_arm - at) if next_arm > at else 600)
		assert_true(body.contains("_maybe_inflict_status(caster, target, ability, ability_id)"),
			"the %s arm must roll the status after its damage lands" % arm)


const GdSourceHelper = preload("res://test/unit/helpers/gd_source.gd")
