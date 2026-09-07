extends GutTest

## _get_counter_action matched ability SPELLING, not ability DATA (2026-07-29).
##
## The `defense_boost` counter arm selected a defensive ability with
##   "defense" in id or "guard" in id or "shield" in id
## Glacius owns `frost_armor` — type support, effect defense_up,
## stat_modifier 1.8 — which is exactly the ability that arm wants. The
## filter missed it because the word is "armor". The intent existed, the
## ability existed, and a spelling convention stood between them.
##
## WHY THIS TEST LOOKS THE WAY IT DOES: an earlier fix of mine in this
## same feature asserted that a bias dictionary CONTAINED a key, passed
## six assertions and three mutations, and was inert — because nothing
## read that key on the path the boss took. So this file asserts the
## returned ACTION, on the path the caller actually uses, built from the
## shipped ability data rather than a fixture I could make agree with me.

var _bm: Node


func before_each() -> void:
	_bm = load("res://src/battle/BattleManager.gd").new()
	add_child_autofree(_bm)


func _abilities_of(monster_id: String) -> Array:
	# Real kit, real ability dicts — the same shape _make_ai_decision passes.
	var mf: FileAccess = FileAccess.open("res://data/monsters.json", FileAccess.READ)
	var af: FileAccess = FileAccess.open("res://data/abilities.json", FileAccess.READ)
	assert_not_null(mf)
	assert_not_null(af)
	var monsters: Dictionary = JSON.parse_string(mf.get_as_text())
	var abilities: Dictionary = JSON.parse_string(af.get_as_text())
	var out: Array = []
	for aid in (monsters[monster_id] as Dictionary).get("abilities", []):
		if abilities.has(str(aid)):
			out.append(abilities[str(aid)])
	return out


func _boss() -> Combatant:
	var c: Combatant = autofree(Combatant.new())
	c.combatant_name = "Glacius"
	c.is_alive = true
	return c


## ── (0) THE PREMISE every assertion below rests on ───────────────────

func test_premise_the_caller_actually_uses_the_returned_action() -> void:
	# @cowir-sfx's inversion class (msg 3387): a true premise, asserted
	# nowhere, whose falsification makes a guard rot into NO claim rather
	# than a false one.
	#
	# Everything below proves _get_counter_action RETURNS the right action.
	# That only matters because _make_ai_decision returns it as the boss's
	# move. Change the caller to ignore or discard it and every assertion
	# in this file still passes while the fix is inert — which is exactly
	# how my own dragon-intent commit died: verified return value, unread
	# by the path the boss takes.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var call_at: int = src.find("_get_counter_action(combatant, counter_strategy")
	assert_gt(call_at, -1,
		"PREMISE BROKEN: _make_ai_decision no longer calls _get_counter_action. Every assertion below this line is vacuous — the function may be perfect and no boss will ever run it.")
	var window: String = src.substr(call_at, 260)
	assert_true(window.contains("if not counter_action.is_empty()") and window.contains("return counter_action"),
		"PREMISE BROKEN: the caller no longer RETURNS the counter action. The asserts below still pass because they call the function directly — they would be proving a value nobody reads. Re-instrument this file against whatever consumes it now; do not delete the premise to make it green.")


## ── (1) The regression: the action is actually produced ──────────────

func test_glacius_defense_boost_returns_a_real_action() -> void:
	var kit: Array = _abilities_of("ice_dragon")
	assert_gt(kit.size(), 0, "precondition: Glacius's kit must resolve")
	var action: Dictionary = _bm._get_counter_action(_boss(), "defense_boost", [], [], kit)
	assert_false(action.is_empty(),
		"defense_boost must produce an action — an empty return means the caller falls through and the intent contributes nothing")
	assert_eq(str(action.get("ability_id", "")), "frost_armor",
		"it must pick frost_armor — the one ability in the kit whose effect IS defense_up")


func test_returned_action_has_the_shape_the_caller_consumes() -> void:
	# The caller returns this dict straight out of _make_ai_decision as the
	# boss's action. A malformed dict would be worse than an empty one.
	var action: Dictionary = _bm._get_counter_action(_boss(), "defense_boost", [], [], _abilities_of("ice_dragon"))
	for key in ["type", "combatant", "ability_id", "targets", "speed"]:
		assert_true(action.has(key), "action must carry '%s' or the execute path cannot run it" % key)
	assert_eq(str(action.get("type", "")), "ability")
	assert_eq((action.get("targets", []) as Array).size(), 1,
		"a self-buff targets the caster alone")


## ── (2) The premise, from shipped data — not a fixture I control ─────

func test_frost_armor_really_declares_defense_up() -> void:
	# If a rebalance retypes frost_armor, the fix above stops applying and
	# this says so, instead of the counter arm silently going quiet again.
	var af: FileAccess = FileAccess.open("res://data/abilities.json", FileAccess.READ)
	var abilities: Dictionary = JSON.parse_string(af.get_as_text())
	var fa: Dictionary = abilities.get("frost_armor", {})
	assert_false(fa.is_empty(), "frost_armor must exist")
	assert_eq(str(fa.get("effect", "")), "defense_up",
		"the fix keys on effect — if this changes, the selection changes with it")


func test_id_substring_alone_would_not_have_found_it() -> void:
	# Pins WHY the bug existed. If someone later renames frost_armor to
	# frost_guard, the old filter would start working and this assertion
	# becomes false — at which point the regression is genuinely gone and
	# this test should be revisited, not silenced.
	var fid: String = "frost_armor"
	assert_false(fid.contains("defense") or fid.contains("guard") or fid.contains("shield"),
		"frost_armor matches none of the id substrings — that is the whole defect")


## ── (2b) The PROPERTY, not the one coordinate ────────────────────────

func test_any_defense_up_ability_is_found_whatever_its_id_says() -> void:
	# @cowir-ai's fixture-coincidence class (msg 3390): the mutant is
	# wrong, the guard runs correctly, and the single sample happens not
	# to expose it. My other assertions all use frost_armor, so a filter
	# hardcoded to `id == "frost_armor"` would satisfy the headline test
	# while restoring the exact defect — matching a SPELLING again.
	#
	# The property is "selected by effect, regardless of id". So: ids that
	# deliberately contain none of the substrings, and one that actively
	# looks like something else.
	for fake_id in ["zzz_unhelpful", "frost_armor", "warm_hug", "attack_stance_of_serenity"]:
		var synthetic: Dictionary = {"id": fake_id, "type": "support", "effect": "defense_up"}
		var action: Dictionary = _bm._get_counter_action(_boss(), "defense_boost", [], [], [synthetic])
		assert_eq(str(action.get("ability_id", "")), fake_id,
			"an ability whose EFFECT is defense_up must be selected whatever its id reads as — id '%s' was skipped, which means the filter is matching spelling again" % fake_id)


func test_effect_absent_means_not_selected_whatever_the_type() -> void:
	# The other half of the property: `type: support` alone must not
	# qualify. Without this, widening the filter to "any support ability"
	# passes every assertion above, and Pyrroth "defends" with attack_up.
	for eff in ["attack_up", "haste", ""]:
		var synthetic: Dictionary = {"id": "zzz_unhelpful", "type": "support", "effect": eff}
		var action: Dictionary = _bm._get_counter_action(_boss(), "defense_boost", [], [], [synthetic])
		assert_true(action.is_empty(),
			"effect '%s' is not a defensive buff — selecting it would make a boss 'defend' by buffing its own offence" % eff)


## ── (3) Controls: the fix widens, it does not replace ────────────────

func test_substring_matched_abilities_still_work() -> void:
	# iron_guard has no `effect: defense_up`; it was found by substring
	# before and must still be found now.
	var af: FileAccess = FileAccess.open("res://data/abilities.json", FileAccess.READ)
	var abilities: Dictionary = JSON.parse_string(af.get_as_text())
	if not abilities.has("iron_guard"):
		pending("iron_guard absent")
		return
	var action: Dictionary = _bm._get_counter_action(_boss(), "defense_boost", [], [], [abilities["iron_guard"]])
	assert_eq(str(action.get("ability_id", "")), "iron_guard",
		"the substring path must survive — this fix widens the filter, it does not replace it")


func test_offensive_kits_still_produce_nothing() -> void:
	# Pyrroth's inferno_rage is attack_up, not defense_up. A filter that
	# grabbed any `support` ability would wrongly make Pyrroth "defend"
	# with an attack buff — the over-correction this fix must not make.
	var action: Dictionary = _bm._get_counter_action(_boss(), "defense_boost", [], [], _abilities_of("fire_dragon"))
	assert_true(action.is_empty(),
		"Pyrroth owns no defensive ability in any representation — defense_boost must still find nothing rather than grab attack_up")
