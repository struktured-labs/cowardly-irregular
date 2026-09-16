extends GutTest

## THE SAFETY PROPERTY THIS FILE EXISTS FOR LIVED ONLY IN A COMMENT.
##
## HeadlessBattleResolver's support arm ends with an else-branch whose comment reads: "Live owns a
## ~40-arm effect table; headless deliberately does NOT mirror it. An effect we do not model is a
## NO-OP, never damage." That rule is not decoration — the same file records why it exists: the `_:`
## default arm USED to take unmodelled types, so "an all_allies ability arrived holding the PARTY and
## this attacked them". The no-op rule is the repair for an ability that healed nobody and hurt the
## party instead.
##
## Nothing pinned it. 52 shipped support/song/status abilities author an effect the resolver neither
## names nor stat-maps — taunt, barrier, scan, shadow_step, steal, brave_actions and 46 more — and
## every one of them relies on that else-branch staying harmless. A future arm added to the support
## path, or a category re-pointed into a damage arm, would send a self- or ally-targeted ability into
## `take_damage` and no existing test would notice.
##
## ⚠️ Written after @cowir-music's observation that a deliberate decision recorded only in prose
## invites the opposite action: their `alias_note` records the mechanism that makes four apparently
## redundant manifest keys load-bearing, and a census calling it UNREAD is what tempts a cleanup.
## This is the same shape in code — a comment saying "never damage" is exactly what a later change
## does not read.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const SRC := "res://src/autogrind/HeadlessBattleResolver.gd"

var _res


func before_each() -> void:
	_res = ResolverScript.new()


func _combatant(name: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": 9999, "max_mp": 9999,
		"attack": 30, "defense": 10, "magic": 30, "speed": 10})
	add_child_autofree(c)
	c.current_hp = c.max_hp
	c.current_mp = c.max_mp
	return c


## Every shipped support/song/status ability whose effect the resolver neither names nor stat-maps.
## DERIVED from the source, not listed: a hand list would miss the 53rd.
func _unmodelled_support_abilities() -> Array:
	var code: String = GdSource.code_of(SRC)
	var arm_start: int = code.find('"support", "song", "status":')
	var arm: String = code.substr(arm_start, code.find("\n\t\t_:", arm_start) - arm_start)
	var named: Dictionary = {}
	var re := RegEx.new()
	re.compile('effect == "([a-z_]+)"')
	for m in re.search_all(arm):
		named[m.get_string(1)] = true
	var map_at: int = code.find("func _effect_to_stat")
	var mapped_src: String = code.substr(map_at, 1400) if map_at > 0 else ""
	var re2 := RegEx.new()
	re2.compile('"([a-z_]+)":')
	for m in re2.search_all(mapped_src):
		named[m.get_string(1)] = true

	var abilities: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var out: Array = []
	for aid in abilities.keys():
		var a: Dictionary = abilities[aid]
		if not (str(a.get("type", "")) in ["support", "song", "status"]):
			continue
		var eff: String = str(a.get("effect", ""))
		if eff != "" and not named.has(eff):
			out.append(aid)
	return out


func test_no_unmodelled_support_effect_damages_its_target() -> void:
	## The property, over the whole real corpus rather than one example. Self- and ally-targeted
	## abilities are the dangerous case: the defect this rule repaired sent an all_allies ability into
	## the damage path and attacked the party with it.
	var unmodelled: Array = _unmodelled_support_abilities()
	assert_gt(unmodelled.size(), 20,
		"CONTROL: the corpus must still hold many unmodelled support effects (%d) — if this collapses the derivation is broken, not the game" % unmodelled.size())
	var harmed: Array = []
	for aid in unmodelled:
		var caster := _combatant("Caster")
		var ally := _combatant("Ally")
		_res._player_party = [caster, ally]
		_res._enemy_party = []
		var c0: int = caster.current_hp
		var a0: int = ally.current_hp
		_res._resolve_ability(caster, aid, [ally])
		if ally.current_hp < a0 or caster.current_hp < c0:
			harmed.append("%s (ally -%d, caster -%d)" % [aid, a0 - ally.current_hp, c0 - caster.current_hp])
	gut.p("    checked %d unmodelled support effects" % unmodelled.size())
	assert_eq(harmed, [],
		"an ability the resolver does not model DAMAGED its target — the else-branch is meant to be a no-op, and this is the defect that once attacked the party with an all_allies ability: %s" % str(harmed))


func test_a_modelled_effect_still_does_its_job() -> void:
	## Anti-vacuity from the other side: if the support arm stopped working entirely, every ability
	## would be harmless and the arm above would pass on a dead engine.
	var caster := _combatant("Caster")
	var ally := _combatant("Ally")
	_res._player_party = [caster, ally]
	_res._enemy_party = []
	var before: float = ally.get_buffed_stat("defense", ally.defense)
	_res._resolve_ability(caster, "protect", [ally])
	assert_gt(ally.get_buffed_stat("defense", ally.defense), before,
		"CONTROL: a MODELLED support effect must still land, or 'nothing was damaged' proves only that nothing happened")


func test_the_no_op_branch_is_still_the_one_that_catches_them() -> void:
	## Structural. The behavioural arm passes if unmodelled effects are caught anywhere harmless; this
	## pins that the else-branch exists and still routes to add_status rather than to a damage call —
	## the specific shape the comment promises.
	var code: String = GdSource.code_of(SRC)
	assert_gt(code.length(), 5000, "CONTROL: the resolver was actually read")
	var arm_start: int = code.find('"support", "song", "status":')
	assert_gt(arm_start, 0, "CONTROL: the support arm must be locatable")
	var arm: String = code.substr(arm_start, code.find("\n\t\t_:", arm_start) - arm_start)
	assert_true(arm.contains("target.add_status(effect, duration)"),
		"the support arm's fall-through no longer routes an unmodelled effect to add_status")
	for damaging in ["take_damage", "_resolve_attack_with_power", "_drain_to"]:
		assert_false(arm.contains(damaging),
			"the support arm now calls %s — an ability we do not model must never reach a damage path" % damaging)
