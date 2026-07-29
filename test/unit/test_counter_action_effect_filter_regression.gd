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
