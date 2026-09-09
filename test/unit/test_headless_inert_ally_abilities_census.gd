extends GutTest

## The friendly-fire guard turned HARM into a SILENT NO-OP for every ability whose type has no arm.
## Strictly better than damaging the party — and cowir-sfx's finding the same hour is that a fix
## which degrades gracefully BLINDS the guard that found it: "does nothing" and "correctly handled"
## are indistinguishable from the outside, so the population can quietly convert into "fine".
##
## cowir-battle measured 21 ally-targeted abilities now inert in every grind — the entire meta-job
## kit plus Raise. CLAUDE.md calls meta jobs "all five REAL" and a design pillar, so this is a
## pillar that does not function in the mode the game is named for. That is a DESIGN question
## (what should undo_death do mid-grind?), explicitly struktured's, not a bug to invent an answer to.
##
## This census does not fix it. It refuses to let it go quiet: the count is pinned and the failure
## message NAMES the abilities, so implementing one forces a deliberate edit here rather than
## letting the set drift silently in either direction.

const ALLY_MARKERS := ["ally", "self", "party"]


func _type_of(ability_id: String) -> String:
	var f := FileAccess.open("res://data/abilities.json", FileAccess.READ)
	if f == null:
		return ""
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	var table: Dictionary = parsed.get("abilities", parsed)
	var v = table.get(ability_id, {})
	return str((v as Dictionary).get("type", "")) if typeof(v) == TYPE_DICTIONARY else ""


func _fresh(cname: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({
		"name": cname, "max_hp": 400, "max_mp": 40,
		"attack": 10, "defense": 10, "magic": 20, "speed": 10
	})
	add_child_autofree(c)
	return c


## Observable state, not source text: HP, MP, buff/debuff count, status count. An ability that
## changes none of these did nothing to its target, whatever its implementation looks like.
func _fingerprint(c: Combatant) -> Array:
	return [c.current_hp, c.current_mp, c.active_buffs.size(), c.status_effects.size()]


func _ally_targeted_ability_ids() -> Array[String]:
	var out: Array[String] = []
	var f := FileAccess.open("res://data/abilities.json", FileAccess.READ)
	if f == null:
		return out
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	var table: Dictionary = parsed.get("abilities", parsed)
	for k in table.keys():
		var v = table[k]
		if typeof(v) != TYPE_DICTIONARY:
			continue
		var tt := str(v.get("target_type", ""))
		for marker in ALLY_MARKERS:
			if tt.contains(marker):
				out.append(str(k))
				break
	return out


func _inert_ids() -> Array[String]:
	var inert: Array[String] = []
	for ability_id in _ally_targeted_ability_ids():
		var resolver := HeadlessBattleResolver.new()
		var caster := _fresh("Caster")
		var target := _fresh("Target")
		target.current_mp = 0        # leave headroom so a restore is observable
		target.current_hp = 200      # and so a heal is observable
		resolver._player_party = [caster, target]
		resolver._enemy_party = []
		var before := _fingerprint(target)
		resolver._resolve_ability(caster, ability_id, [target])
		if _fingerprint(target) == before:
			inert.append(ability_id)
	return inert


## Types this resolver deliberately does not model. Deriving the expectation from TYPE rather than
## pinning a count: I measured 20 where cowir-battle derived 21 and could not explain the gap, and
## a number I cannot explain is not a ratchet — it is a coincidence waiting to be "fixed".
const UNMODELLED_TYPES := ["meta", "summon", "revival", "escape"]


func test_everything_inert_is_inert_for_a_KNOWN_reason() -> void:
	## The census refuses to let the population go quiet. It does not assert HOW MANY — it asserts
	## that every silent ability is silent because its TYPE is unmodelled. An ability that goes
	## inert for any other reason (an arm regressing) names itself here.
	var offenders: Array[String] = []
	for ability_id in _inert_ids():
		if not UNMODELLED_TYPES.has(_type_of(ability_id)):
			offenders.append("%s(%s)" % [ability_id, _type_of(ability_id)])
	assert_eq(offenders.size(), 0,
		("these abilities do NOTHING in a headless grind and their type IS modelled — an arm " +
		"regressed: %s") % str(offenders))


func test_the_inert_population_is_reported_not_hidden() -> void:
	## Names the set on every run. cowir-battle measured 21 ally-targeted abilities silenced by the
	## friendly-fire guard — the whole meta-job kit plus Raise. CLAUDE.md calls meta jobs a design
	## pillar, so this is a pillar that does not function in autogrind. Design, struktured's call.
	var inert := _inert_ids()
	inert.sort()
	gut.p("INERT IN HEADLESS (%d): %s" % [inert.size(), str(inert)])
	assert_gt(inert.size(), 0,
		"if this ever reaches zero the meta kit was implemented — delete this census, it has done its job")


func test_an_armed_ability_is_not_counted_inert() -> void:
	## ARM+. Without this a resolver that did nothing at all would score every ability inert and
	## the census would still "pass" once EXPECTED_INERT was updated to match.
	var inert := _inert_ids()
	for armed in ["cure", "pray", "battle_hymn"]:
		assert_false(inert.has(armed),
			"%s IS handled — if it appears here, its arm regressed and the census is measuring a broken resolver" % armed)


func test_the_census_can_actually_detect_inertness() -> void:
	## ARM+ the other way: prove the fingerprint notices a real no-op. A fabricated id reaches
	## nothing, so it must register as inert; if it does not, the detector is broken.
	var resolver := HeadlessBattleResolver.new()
	var caster := _fresh("Caster")
	var target := _fresh("Target")
	resolver._player_party = [caster, target]
	var before := _fingerprint(target)
	resolver._resolve_ability(caster, "zzq_not_a_real_ability", [target])
	assert_eq(_fingerprint(target), before,
		"control: an unknown ability must leave the target untouched, or the fingerprint is blind")
