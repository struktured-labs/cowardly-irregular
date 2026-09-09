extends GutTest

## Regression: 49 magic/healing abilities played the MELEE THUMP (2026-07-30).
##
## play_ability() resolves via `_ability_sounds.get(ability_id, "ability_physical")`.
## That map was hand-maintained (24 entries) against 288 abilities, so fire_breath,
## ice_breath, chain_lightning, magma_eruption, absolute_zero and every Necromancer
## dark spell played a punch — while their correct cue already sat in the manifest,
## unused. Nothing joined abilities.json to the map, so nothing failed.
##
## The load-bearing test here is the DERIVED one at the bottom. A list of the 49
## known ids would pin the incident; the invariant pins the property, so ability
## #50 cannot ship silent.

const ELEMENT_SFX: Dictionary = {
	"fire": "ability_fire",
	"ice": "ability_ice",
	"lightning": "ability_lightning",
	"dark": "ability_dark",
	"holy": "ability_holy",
	"poison": "ability_poison",
	"earth": "ability_earth",
	"wind": "ability_wind",
}

## Every cue the DERIVED pass can produce. A resolved cue outside this set came from the hand
## map, which legitimately outranks derivation; one inside it that is not the expected cue is a
## derivation bug.
const DERIVED_VOCAB: Array[String] = [
	"ability_fire", "ability_ice", "ability_lightning", "ability_dark", "ability_holy",
	"ability_poison", "ability_earth", "ability_wind", "ability_heal", "ability_arcane",
	"ability_song", "ability_summon", "ability_revive",
]


## Physical abilities that CARRY an element. A weapon strike should thump, so these
## are deliberately excluded from the derived pass — a negative control on the fix.
const PHYSICAL_WITH_ELEMENT: Array[String] = [
	"cursed_strike", "dark_slash", "glitch_strike", "lightning_dash",
]


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func _abilities() -> Dictionary:
	var text: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
	var a: Variant = parsed.get("abilities", parsed)
	return a if a is Dictionary else {}


func test_derivation_actually_ran() -> void:
	## PREMISE. Every assert below is vacuous if the derived pass no-op'd — which is
	## exactly what happens if _derive_ability_sounds_from_data() is ever called before
	## _load_sfx_manifest(), since its `_sfx_manifest.has(cue)` gate would reject all.
	var sm: Node = _sm()
	assert_not_null(sm, "SoundManager autoload must exist")
	assert_gt(sm._ability_sounds.size(), 24,
		"PREMISE BROKEN: _ability_sounds holds %d entries — the hand map alone is 24, so the derived pass added nothing. Check that _derive_ability_sounds_from_data() still runs AFTER _load_sfx_manifest() in _ready(); every assertion in this file is meaningless until it does." % sm._ability_sounds.size())


func test_known_thumping_spells_now_resolve_to_their_element() -> void:
	## Spot-checks from the original 49 — the ones a player meets first.
	var sm: Node = _sm()
	var expected: Dictionary = {
		"fire_breath": "ability_fire",
		"ice_breath": "ability_ice",
		"thunder_breath": "ability_lightning",
		"chain_lightning": "ability_lightning",
		"absolute_zero": "ability_ice",
		"magma_eruption": "ability_fire",
		"dark_matter": "ability_dark",
		"masterite_judgment": "ability_holy",
		"regenerate": "ability_heal",
	}
	for aid in expected.keys():
		assert_eq(str(sm._ability_sounds.get(aid, "ability_physical")), str(expected[aid]),
			"%s must play %s, not a melee thump" % [aid, expected[aid]])


func test_hand_map_still_outranks_the_derived_pass() -> void:
	## permakill_strike is element=dark but has a SIGNATURE cue. If the derived pass ever
	## overwrites the hand map, the meta-job cues silently become generic dark magic.
	var sm: Node = _sm()
	assert_eq(str(sm._ability_sounds.get("permakill_strike", "")), "ability_permakill",
		"permakill_strike must keep its signature cue — the hand map outranks derivation")
	assert_eq(str(sm._ability_sounds.get("mind_swap", "")), "ability_mind_swap",
		"mind_swap must keep its signature cue")


func test_physical_abilities_with_an_element_still_thump() -> void:
	## NEGATIVE CONTROL on the fix's scope. These are weapon strikes; mapping them to
	## elemental magic would be a regression in the opposite direction.
	var sm: Node = _sm()
	var abilities: Dictionary = _abilities()
	for aid in PHYSICAL_WITH_ELEMENT:
		assert_true(abilities.has(aid),
			"control: %s must still exist in abilities.json, else this control is vacuous" % aid)
		if not abilities.has(aid):
			continue
		assert_eq(str(abilities[aid].get("type", "")), "physical",
			"control: %s must still be type=physical, else it belongs in the derived pass" % aid)
		assert_eq(str(sm._ability_sounds.get(aid, "ability_physical")), "ability_physical",
			"%s is a weapon strike — it must keep the physical thump" % aid)


func test_no_spell_is_left_playing_the_melee_thump() -> void:
	## THE LOAD-BEARING GUARD. Derived from abilities.json, so a new elemental spell
	## added by any lane fails here instead of shipping with a punch sound.
	var sm: Node = _sm()
	var abilities: Dictionary = _abilities()
	assert_gt(abilities.size(), 0,
		"control: abilities.json parsed to nothing — the sweep below ran on zero abilities")

	var checked: int = 0
	var unmapped: Array[String] = []
	for aid in abilities.keys():
		var entry: Variant = abilities[aid]
		if not (entry is Dictionary):
			continue
		var t: String = str(entry.get("type", ""))
		if t != "magic" and t != "healing":
			continue
		var cue: String = str(ELEMENT_SFX.get(str(entry.get("element", "")).to_lower(), ""))
		if cue == "":
			cue = "ability_heal" if t == "healing" else "ability_arcane"
		## This used to exempt poison/earth/wind "until a cue exists". It was TRUE when written,
		## and that is exactly how it converted "we owe four assets" into "this is fine" and never
		## expired — 36 spells thumped behind it. An exemption justified by an ABSENCE has to name
		## what ends it. The cues exist now, so the exemption is deleted rather than updated; what
		## survives is the manifest check, which is a live condition and not a standing pass.
		if cue == "" or not sm._sfx_manifest.has(cue):
			continue
		checked += 1
		var got: String = str(sm._ability_sounds.get(str(aid), "ability_physical"))
		if got == cue:
			continue
		## A cue OUTSIDE the derived vocabulary is a deliberate signature override (permakill_strike
		## -> ability_permakill) and the hand map is allowed to win. A cue INSIDE it that is not the
		## expected one is a derivation bug — which is the case the thump-only check missed: once
		## ability_arcane exists it CATCHES a deleted element mapping, so acid_splash silently
		## degrades from poison to generic magic and never resolves to ability_physical at all.
		if DERIVED_VOCAB.has(got):
			unmapped.append("%s (%s) -> %s, wanted %s" % [aid, t, got, cue])

	assert_gt(checked, 0,
		"control: zero magic/healing abilities had an available cue — the sweep is broken, so the assert below checked nothing")
	assert_eq(unmapped.size(), 0,
		"%d spell(s) resolve to the WRONG derived cue while their own cue exists in the manifest. ability_physical means a melee thump; any other wrong value means the spell degraded to a different element's sound: %s" % [unmapped.size(), unmapped])


func test_the_four_late_elements_resolve() -> void:
	## 2026-09-09: 36 spells were STILL thumping after the 2026-07-30 fix, hidden behind an
	## exemption comment in this very file that said poison/earth/wind "legitimately fall through".
	## Named, not counted — the sweep above passes if abilities.json loses these rows entirely.
	var sm: Node = _sm()
	var expected: Dictionary = {
		"acid_splash": "ability_poison", "toxic_cloud": "ability_poison",
		"root_bind": "ability_earth", "sandstorm": "ability_earth",
		"whirlwind": "ability_wind",
		## element=none — the largest bucket of the 36 and the one no element cue could reach.
		"fork_bomb": "ability_arcane", "null_reference": "ability_arcane",
		"phantom_wail": "ability_arcane", "fourth_wall_break": "ability_arcane",
	}
	for aid in expected.keys():
		assert_eq(str(sm._ability_sounds.get(aid, "ability_physical")), str(expected[aid]),
			"%s must play %s, not the melee thump" % [aid, expected[aid]])


func test_no_magic_spell_resolves_to_the_fallback() -> void:
	## RESOLUTION-shaped, not ELIGIBILITY-shaped. Asking "does type=magic have an arm" answered
	## "yes, 100%" while 36 rows resolved to the thump — eligibility is a property of the CODE,
	## resolution is a property of every ROW. That distinction is the whole bug.
	var sm: Node = _sm()
	var abilities: Dictionary = _abilities()
	var checked: int = 0
	var thumping: Array[String] = []
	for aid in abilities.keys():
		var entry: Variant = abilities[aid]
		if not (entry is Dictionary) or str(entry.get("type", "")) != "magic":
			continue
		checked += 1
		if str(sm._ability_sounds.get(str(aid), "ability_physical")) == "ability_physical":
			thumping.append("%s (element=%s)" % [aid, entry.get("element", "none")])
	assert_gte(checked, 80, "control: only %d magic abilities swept — the corpus moved" % checked)
	## CONTROL the resolver itself: if _ability_sounds were empty or my lookup were broken, the
	## count above would be 89 and this would fire first with a comprehensible reason.
	assert_eq(str(sm._ability_sounds.get("fire", "")), "ability_fire",
		"control: a known-good spell must reach its bespoke cue, or the sweep is measuring a dead map")
	assert_eq(thumping.size(), 0,
		"%d magic spell(s) resolve to the melee thump: %s" % [thumping.size(), thumping])


func test_every_derived_cue_target_exists_in_the_manifest() -> void:
	## A mapping to a cue that isn't in the manifest falls through to procedural or
	## silence — worse than the thump it replaced.
	var sm: Node = _sm()
	var missing: Array[String] = []
	for aid in sm._ability_sounds.keys():
		var cue: String = str(sm._ability_sounds[aid])
		if not sm._sfx_manifest.has(cue):
			missing.append("%s -> %s" % [aid, cue])
	assert_gt(sm._ability_sounds.size(), 0, "control: the map is empty")
	assert_eq(missing.size(), 0,
		"ability cue target(s) absent from the manifest: %s" % [missing])

func test_play_ability_actually_CONSULTS_the_derived_map() -> void:
	## THE CALL-SITE GAP. Every other assertion here reads sm._ability_sounds directly —
	## they prove the map is BUILT, never that play_ability READS it. Change line ~474 to
	## stop consulting the map and all of them stay green while every dragon breath
	## silently reverts to a melee thump.
	##
	## test_sfx_reverse_orphan_audit drives play_ability("fire") — but fire is in the HAND
	## map, so the DERIVED path specifically has no call-site coverage. This closes that.
	##
	## Observable is the SFX cooldown stamp: a manifest MISS provably does not stamp
	## (pinned by that file's premise assert), so a stamp means the cue resolved.
	var sm: Node = _sm()
	assert_not_null(sm, "SoundManager autoload required")
	var derived_id: String = "fire_breath"
	assert_eq(str(sm._ability_sounds.get(derived_id, "")), "ability_fire",
		"PREMISE: %s must be a DERIVED entry (not hand-mapped) or this test proves nothing about the derived path" % derived_id)
	sm._sfx_cooldowns.erase("ability_fire")
	assert_false(sm._sfx_cooldowns.has("ability_fire"),
		"control: the cue key must start unstamped or the assert below is satisfied by an earlier test")
	sm.play_ability(derived_id)
	assert_true(sm._sfx_cooldowns.has("ability_fire"),
		"play_ability('%s') did NOT resolve ability_fire — the derived map is built but play_ability is not reading it, which is the exact defect every other assertion in this file is blind to" % derived_id)
