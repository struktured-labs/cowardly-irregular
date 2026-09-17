extends GutTest

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")
const GRIND := "res://src/autogrind/HeadlessBattleResolver.gd"
const LIVE := "res://src/battle/BattleManager.gd"

## Fourteen magic/physical monster abilities carry a stat-down `effect`. The grind wrote it as a
## STATUS TOKEN — `add_status("defense_down")` — which has_status reads and nothing else does, so
## armor_break, ice_breath, soul_wail and eleven others cost the caster MP and did nothing.
##
## ⛔ AND THIS IS A GAP I MEASURED AS CLOSED AND PUBLISHED AS SAFE. Earlier today I checked this exact
## path, found both engines writing the same inert token, and reported "we AGREE, no parity gap —
## the divergence only opens when live starts applying it, which my arm watches for". Live then
## started applying it, via @cowir-battle's `_apply_stat_down` in `_apply_ability_status` — and my
## arm watches the SUPPORT match, a different function. It watched the wrong door.
##
## 🔑 The lesson is not "check again later". It is that a declaration naming a FUTURE trigger has to
## name the trigger's LOCATION, and mine named a behaviour ("live starts applying it") that could
## arrive anywhere. This file pins the twin relationship instead: the two appliers must handle the
## same effect set, so live growing an arm reds here whatever function it grows it in.

var _res


func before_each() -> void:
	_res = ResolverScript.new()


func _mob(name: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": 9999, "max_mp": 9999,
		"attack": 40, "defense": 40, "magic": 40, "speed": 40})
	add_child_autofree(c)
	c.current_hp = c.max_hp
	c.current_mp = c.max_mp
	return c


## Cast until the effect_chance roll lands, then report what the target is carrying.
func _cast_until_applied(ability_id: String, tries: int = 200) -> Dictionary:
	for _i in tries:
		var caster := _mob("Caster")
		var target := _mob("Target")
		_res._player_party = [target]
		_res._enemy_party = [caster]
		caster.current_mp = caster.max_mp
		_res._resolve_ability(caster, ability_id, [target])
		if target.active_debuffs.size() > 0 or target.status_effects.size() > 0:
			return {"debuffs": target.active_debuffs.duplicate(true), "statuses": target.status_effects.duplicate()}
	return {"debuffs": [], "statuses": []}


func test_an_armor_break_actually_breaks_armor() -> void:
	## The headline: a PHYSICAL monster ability whose whole text is the debuff.
	var got: Dictionary = _cast_until_applied("armor_break")
	gut.p("    armor_break -> debuffs %s · statuses %s" % [str(got["debuffs"]), str(got["statuses"])])
	assert_false((got["statuses"] as Array).has("defense_down"),
		"armor_break wrote a STATUS TOKEN named after the debuff it failed to apply — has_status reads it and nothing else does")
	var names: Array = []
	for d in (got["debuffs"] as Array):
		names.append(str(d.get("effect", "")))
	assert_true(names.has("Armor Break"),
		"armor_break applied no defense debuff: %s" % str(names))


func test_every_authored_stat_down_on_the_damage_paths_lands_as_a_debuff() -> void:
	## THE CORPUS ARM, derived: every magic/physical ability whose effect live's _apply_stat_down
	## handles. Fourteen today, all cast by pooled monsters, so all reachable in a grind.
	var ab: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var handled := ["attack_down", "defense_down", "speed_down", "magic_defense_down", "all_stats_down"]
	var subjects: Array = []
	for aid in ab:
		var d: Dictionary = ab[aid]
		if ["magic", "physical"].has(str(d.get("type", ""))) and handled.has(str(d.get("effect", ""))):
			subjects.append(str(aid))
	assert_gt(subjects.size(), 10, "CONTROL: the damage paths must really carry stat-downs, or this arm is vacuous")
	var tokens: Array = []
	for aid in subjects:
		var got: Dictionary = _cast_until_applied(str(aid))
		for st in (got["statuses"] as Array):
			if handled.has(str(st)):
				tokens.append("%s -> status '%s'" % [str(aid), str(st)])
	gut.p("    magic/physical stat-down abilities: %d · still writing a token: %d" % [subjects.size(), tokens.size()])
	assert_eq(tokens, [],
		"a stat-down is still landing as an inert status token: %s" % str(tokens))


func test_the_authored_magnitude_is_what_lands() -> void:
	## oxidize authors 0.6 and spectral_touch 0.85 — so a hardcoded modifier reds here even though
	## both "apply a defense debuff". Same lesson as the support-arm magnitude bug this lane fixed
	## earlier: reading the key is not the same as honouring it.
	var ab: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	for aid in ["oxidize", "spectral_touch"]:
		var authored: float = float((ab[aid] as Dictionary).get("stat_modifier", 1.0))
		var got: Dictionary = _cast_until_applied(aid)
		var found: float = -1.0
		for d in (got["debuffs"] as Array):
			if str(d.get("effect", "")) == "Armor Break":
				found = float(d.get("modifier", -1.0))
		gut.p("    %s authored %.2f landed %.2f" % [aid, authored, found])
		assert_almost_eq(found, authored, 0.001,
			"%s landed at %.2f, authored %.2f — the magnitude is not being read off the ability" % [aid, found, authored])


func test_the_two_engines_handle_the_same_effect_set() -> void:
	## ⛔ THE TWIN ARM, and the repair for the declaration that failed. My previous guard watched the
	## SUPPORT match for live growing an arm; live grew it in _apply_ability_status instead and the
	## guard was blind. This one compares the two APPLIERS' effect sets directly, so it reds wherever
	## live adds one — the relationship is pinned, not a named location.
	var live: String = GdSource.code_of(LIVE)
	var grind: String = GdSource.code_of(GRIND)
	var live_at: int = live.find("func _apply_stat_down(")
	assert_gt(live_at, 0, "CONTROL: live must still own a stat-down applier — if it was renamed, this twin needs re-anchoring")
	var live_body: String = live.substr(live_at, live.find("\nfunc ", live_at + 1) - live_at)
	var grind_at: int = grind.find("func _apply_stat_down(")
	assert_gt(grind_at, 0, "CONTROL: the grind's applier must exist")
	var grind_body: String = grind.substr(grind_at, grind.find("\nfunc ", grind_at + 1) - grind_at)
	var missing: Array = []
	for eff in ["attack_down", "defense_down", "speed_down", "magic_defense_down", "all_stats_down"]:
		if live_body.contains('"%s":' % eff) and not grind_body.contains('"%s":' % eff):
			missing.append(eff)
	## magic_down is absent from BOTH by agreement — if live adds it, this reds and says so.
	if live_body.contains('"magic_down":') and not grind_body.contains('"magic_down":'):
		missing.append("magic_down (live grew an arm for it — the declaration in both files is now stale)")
	gut.p("    effects live handles that the grind does not: %s" % str(missing))
	assert_eq(missing, [],
		"live's stat-down applier handles an effect the grind's twin does not: %s" % str(missing))


func test_the_debuff_names_match_so_refresh_behaves_the_same() -> void:
	## add_debuff keys on the NAME and refreshes in place. A different spelling would STACK in the
	## grind where live refreshes — two engines, same ability, diverging after the second cast.
	var live: String = GdSource.code_of(LIVE)
	var grind: String = GdSource.code_of(GRIND)
	for nm in ["Armor Break", "Soul Sap", "Weaken", "Slow", "Despair (ATK)"]:
		assert_true(live.contains('"%s"' % nm), "CONTROL: live must still use the name '%s'" % nm)
		assert_true(grind.contains('"%s"' % nm),
			"the grind uses a different debuff name than live for the same effect — add_debuff keys on the name, so one engine would stack where the other refreshes: '%s'" % nm)
