extends GutTest

## ⛔ CORRECTING MY OWN CLAIM FROM AN HOUR AGO, and the corrected version is worse.
##
## Last hour I proved _bias_by_intent's scope note false for Mordaine and wrote that
## "the conclusion holds for the four DRAGONS". The sentence it rests on is true —
## they author none of the three attack_weight-armed intents — and the conclusion I
## drew was reached without measuring, because I checked the key my change was about
## and not the other key in the same table. The day's own class: label broader than
## predicate.
##
## The dragons' six intents DO reach a live mechanical path. _COUNTER_INTENT_TAGS is
## exactly the six they author, and _resolve_counter_strategy returns the intent id
## ITSELF for those — so the counter branch fires with no AutogrindSystem learning
## and no adaptation_level, at 0.3 x counter_action_chance(2.0) = 0.60.
##
## 🔴 AND THE MEASUREMENT CONTRADICTED THAT TOO — but it was THREE of six, not five,
## and the two I got wrong were wrong because of MY FIXTURE, not the game. Corrected
## 2026-09-18 after re-measuring against a real W1 party:
##
##                      fire_r  ice_r  light_r  focus_healer  defense_boost  rotate
##     fire_dragon      0.000   0.000  0.000    0.615         0.000          0.590
##     ice_dragon       0.000   0.000  0.000    0.620         0.640          0.565
##     mordaine         0.000   0.000  0.000    0.593         0.000          0.585
##
## ⛔ `focus_healer` FILTERS THE ENEMY LIST FOR A CLERIC, and this file's victim was
## a lone `{"id": "fighter"}`. So its 0.000 measured my party, not the intent — and
## the W1 party ALWAYS carries a Cleric. It works on every boss tested.
## ⛔ `defense_boost` FILTERS THE BOSS'S OWN KIT for effect `defense_up`. I measured
## Pyrroth only; Glacius owns `frost_armor` (effect: defense_up) and counters at
## 0.640. It is boss-dependent, not inert.
##
## 🔑 TWO INDEPENDENT NARROWNESSES — one party, one boss — each producing a zero that
## read as a property of the game. The arm below asserted both as KNOWN_INERT and
## passed, because the fixture that produced the claim was also the fixture that
## tested it.
##
## rotate_aggro at exactly 0.60 is the control that makes the zeroes mean something:
## the branch, the bias read and the arithmetic are live, so the other five are a
## content gap and not a dead mechanism. The three resist arms filter for an ability
## whose id contains "resist" or "shield", and NO BOSS IN THE GAME OWNS ONE.
##
## So the LLM picks from six strategic postures and THREE do nothing: the boss
## announces it is guarding against fire, then behaves exactly as with no intent.
##
## ⛔ THE REMAINING THREE ARE NOT FIXED HERE. Giving dragons resist abilities, or
## widening the filter to reach inferno_rage / storm_gathering, changes how the boss
## fights play. Struktured's call, not a bugfix. Pinned with the population named.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")
const ROLLS := 400

const COUNTER_TAGS := ["fire_resist", "ice_resist", "lightning_resist",
	"focus_healer", "defense_boost", "rotate_aggro"]

## INVERTED PIN: when a boss gains a resist/shield ability or the filter widens,
## these stop being zero and this reds naming the one that woke up — delete its entry
## then, do not re-baseline the number.
## ⚠️ `focus_healer` and `defense_boost` were in this list until 2026-09-18 and BOTH
## WORK. They are live behaviour now pinned POSITIVELY below; an inverted pin over a
## working feature is the one that reds on a correct change and passes on a breakage.
const KNOWN_INERT := ["fire_resist", "ice_resist", "lightning_resist"]

var _bm = null


func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)


func _monsters() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	assert_not_null(parsed, "CONTROL: monsters.json parses")
	return (parsed as Dictionary).get("monsters", parsed)


func _from_data(mid: String) -> Combatant:
	var v: Dictionary = _monsters()[mid]
	var st: Dictionary = v.get("stats", {})
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = mid
	c.max_hp = int(st.get("max_hp", 100)); c.current_hp = c.max_hp
	c.max_mp = int(st.get("max_mp", 9999)); c.current_mp = c.max_mp
	c.attack = int(st.get("attack", 10)); c.defense = int(st.get("defense", 10))
	c.magic = int(st.get("magic", 10)); c.magic_defense = int(st.get("magic_defense", 10))
	c.speed = int(st.get("speed", 10))
	c.set_meta("monster_type", mid)
	c.job = {"id": mid, "abilities": (v.get("abilities", []) as Array).duplicate()}
	return c


func _member(job_id: String) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = job_id
	c.max_hp = 5000; c.current_hp = 5000
	c.job = {"id": job_id, "abilities": []}
	return c


## The W1 party, which ALWAYS carries a Cleric. This was one lone fighter, and
## `focus_healer` filters the enemy list for `cleric`/`healer` — so the fixture
## decided the result and the arm that checked it used the same fixture.
func _party() -> Array:
	return [_member("fighter"), _member("cleric"), _member("mage"),
		_member("rogue"), _member("bard")]


## Fraction of turns that took the COUNTER branch, driving the real entry point.
## The branch's only externally visible mark is its log line; the action it returns
## is an ordinary ability dict, indistinguishable from a normal choice.
func _counter_rate(mid: String, intent_id: String, party: Array = []) -> float:
	var boss := _from_data(mid)
	if intent_id != "":
		boss.set_meta("llm_intent", intent_id)
	# Suppress the phase-transition re-pick, or this measures an intent nobody asked
	# for. _maybe_advance_boss_phase fires when new_phase > boss_dialogue_phase, and
	# that meta starts at 0 — so the FIRST roll always transitions 0 -> 1, calls
	# BossDialogue.pick_intent, and OVERWRITES llm_intent with a randomly chosen
	# scripted intent. When that lands on a counter tag the remaining rolls counter
	# at 0.3 x 2.0 = 0.6, which is why this file failed about 1 run in 6 with a
	# measured 0.58 while claiming to measure "aggress". Diagnosed by printing the
	# meta AFTER the rolls: the call requested aggress and ended holding
	# rotate_aggro. Pinning the phase high means no transition, so the intent under
	# test is the intent that rolls.
	boss.set_meta("boss_dialogue_phase", 99)
	var foes: Array = party if not party.is_empty() else _party()
	# Array box, not an int: GDScript lambdas capture primitives BY VALUE, so
	# `counters += 1` in the closure increments a copy and the caller reads 0
	# forever — a false ALARM, the direction that gets published.
	var counters: Array = [0]
	var seen_any: int = 0
	_bm.battle_log_message.connect(
		func(msg: String) -> void:
			if msg.find("anticipates your strategy") != -1:
				counters[0] += 1
	)
	for _i in ROLLS:
		boss.current_hp = boss.max_hp
		boss.current_mp = boss.max_mp
		## NO existence floor here DELIBERATELY: renaming _make_ai_decision makes this file
		## EC=1 · Failing 1 — rung 2, always visible. Measured 2026-09-16.
		var action: Dictionary = _bm._make_ai_decision(boss, [boss], foes)
		if not action.is_empty():
			seen_any += 1
	assert_gt(seen_any, 0, "CONTROL: %s must produce actions at all, or nothing was driven" % mid)
	# The rate above is only ABOUT intent_id if intent_id survived the rolls. Without
	# this the file reported a confident number for an intent it was no longer
	# driving, and failed as a flake rather than saying so.
	if intent_id != "":
		assert_eq(str(boss.get_meta("llm_intent", "")), intent_id,
			("the boss's intent changed mid-measurement (%s -> %s), so this rate is not about %s. " +
			"A phase transition re-picks it; see the boss_dialogue_phase pin above.")
			% [intent_id, str(boss.get_meta("llm_intent", "")), intent_id])
	return float(counters[0]) / float(ROLLS)


func test_rotate_aggro_proves_the_counter_branch_is_live() -> void:
	var idle: float = _counter_rate("fire_dragon", "")
	var rotating: float = _counter_rate("fire_dragon", "rotate_aggro")
	gut.p("  fire_dragon counter rate — idle %.3f · rotate_aggro %.3f" % [idle, rotating])
	assert_lt(idle, 0.05,
		"CONTROL: no intent and no learned strategy must leave the counter branch off")
	assert_gt(rotating, 0.4,
		"rotate_aggro must fire at ~0.60 (0.3 x counter_action_chance 2.0) — without this the zeroes below could just mean the branch never runs")


func test_an_unknown_intent_does_not_force_a_counter() -> void:
	assert_lt(_counter_rate("fire_dragon", "hokum_pokum"), 0.05,
		"an intent outside _COUNTER_INTENT_TAGS must not force the counter path — the LLM must not make a boss counter by naming garbage")


func test_focus_healer_is_about_the_PARTY_not_the_boss() -> void:
	## THE ARM THAT WAS MISSING, and it is a discriminator rather than a threshold:
	## the SAME boss, the SAME intent, two parties. `focus_healer` filters the enemy
	## list for a cleric, so a party without one cannot make it fire — which is what
	## this file measured for eight days and reported as "the intent does nothing".
	var with_cleric: float = _counter_rate("fire_dragon", "focus_healer", _party())
	var no_cleric: float = _counter_rate("fire_dragon", "focus_healer",
		[_member("fighter"), _member("rogue")])
	gut.p("  focus_healer — with a cleric %.3f · without %.3f" % [with_cleric, no_cleric])
	assert_gt(with_cleric, 0.4,
		"focus_healer must counter at ~0.60 against a party holding a Cleric; got %.3f" % with_cleric)
	assert_lt(no_cleric, 0.05,
		"focus_healer must find nothing when no Cleric is present (%.3f) — if this rises, the arm stopped filtering and the discriminator above is measuring nothing" % no_cleric)


func test_defense_boost_fires_exactly_for_the_bosses_that_can_express_it() -> void:
	## DERIVED both sides: which W1 bosses own an ability whose effect is `defense_up`
	## is read from the data, not listed here. I first measured this on Pyrroth alone
	## and recorded 0.000 as a property of the intent; Glacius owns `frost_armor` and
	## counters at 0.64. One boss is not the population.
	var mons: Dictionary = _monsters()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var abilities: Dictionary = (parsed as Dictionary).get("abilities", parsed)
	var can: Array[String] = []
	var cannot: Array[String] = []
	for bid in ["fire_dragon", "ice_dragon", "chancellor_mordaine"]:
		var owns: bool = false
		for aid in (mons.get(bid, {}) as Dictionary).get("abilities", []):
			var eff: String = str((abilities.get(str(aid), {}) as Dictionary).get("effect", ""))
			if eff == "defense_up" or str(aid).find("defense") != -1 \
					or str(aid).find("guard") != -1 or str(aid).find("shield") != -1:
				owns = true
				break
		if owns:
			can.append(bid)
		else:
			cannot.append(bid)
	assert_gt(can.size(), 0,
		"CONTROL: no boss owns a defence ability, so this arm proves nothing — the derivation broke or the data changed")
	assert_gt(cannot.size(), 0,
		"CONTROL: every boss owns one, so the negative half below is vacuous")
	for bid in can:
		var r: float = _counter_rate(bid, "defense_boost", _party())
		assert_gt(r, 0.4, "%s owns a defence ability so defense_boost must fire; got %.3f" % [bid, r])
	for bid in cannot:
		var r2: float = _counter_rate(bid, "defense_boost", _party())
		assert_lt(r2, 0.05, "%s owns no defence ability so defense_boost cannot build an action; got %.3f" % [bid, r2])


func test_three_of_six_counter_intents_do_nothing_for_a_dragon() -> void:
	## INVERTED. Each SHOULD eventually counter; today none of these can, because
	## _get_counter_action's arm finds no ability it can use.
	for tag in KNOWN_INERT:
		var rate: float = _counter_rate("fire_dragon", tag)
		assert_lt(rate, 0.05,
			"'%s' now produces counters (%.3f). That is an IMPROVEMENT, not a regression — remove it from KNOWN_INERT." % [tag, rate])


func test_no_boss_owns_the_ability_the_resist_arms_look_for() -> void:
	## Why the three resist arms are inert, as a property of the data rather than
	## of one boss. This is what would have to change for them to work.
	var mons: Dictionary = _monsters()
	var checked: int = 0
	for bid in ["fire_dragon", "ice_dragon", "lightning_dragon", "shadow_dragon", "chancellor_mordaine"]:
		var kit: Array = (mons.get(bid, {}) as Dictionary).get("abilities", [])
		assert_gt(kit.size(), 0, "CONTROL: %s must have a kit, or this proves nothing" % bid)
		checked += 1
		for aid in kit:
			var a: String = str(aid)
			assert_false(a.find("resist") != -1 or a.find("shield") != -1,
				"%s owns '%s' — the resist counter arms filter on exactly that substring, so its resist intents just became live. Re-measure." % [bid, a])
	assert_eq(checked, 5, "CONTROL: all five W1 bosses must have been examined")


func test_every_counter_tag_is_one_a_dragon_actually_authors() -> void:
	## The join that makes any of this reachable at all.
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/boss_dialogue.json"))
	assert_not_null(parsed, "CONTROL: boss_dialogue.json parses")
	var root: Dictionary = (parsed as Dictionary).get("bosses", parsed)
	for dragon in ["pyrroth", "glacius", "voltharion", "umbraxis"]:
		var specs: Array = (root.get(dragon, {}) as Dictionary).get("scripted_intents", [])
		assert_gt(specs.size(), 0, "CONTROL: %s's intents must parse by the 'id' key" % dragon)
		var armed: int = 0
		for spec in specs:
			if spec is Dictionary and COUNTER_TAGS.has(str((spec as Dictionary).get("id", ""))):
				armed += 1
		assert_gt(armed, 0,
			"%s must author at least one counter-forcing intent, or its intent layer really would be dialogue-only" % dragon)


func test_mordaines_armed_intent_does_not_also_force_counters() -> void:
	## Keeps the two bias paths separable — 'aggress' carries attack_weight and no
	## counter_action_chance, so it moves the spell rate and must leave counters alone.
	assert_lt(_counter_rate("chancellor_mordaine", "aggress"), 0.05,
		"'aggress' is an attack_weight intent, not a counter intent — if both keys moved together the two findings would not be independent")
