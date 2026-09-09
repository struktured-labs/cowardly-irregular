extends GutTest

## Regression: the bard's entire specialty played a SWORD THUMP (2026-09-09).
##
## play_ability() resolves via `_ability_sounds.get(ability_id, "ability_physical")`, and the
## derived pass only ever handled type=magic and type=healing. Everything else fell through:
##
##   song     4  battle_hymn, lullaby, discord, inspiring_melody   — the Bard's whole kit
##   summon   7  Ifrit, Shiva, Ramuh, Bahamut, rat_swarm, royal_summon, pack_call
##   revival  1  raise (Anima Reddita) — a dead party member returns, to a melee hit
##
## No cue existed for any of them, so unlike the 2026-07-30 incident the fix needed ASSETS, not
## just a mapping. physical/support/meta stay on the thump deliberately — see the controls.

const TYPE_SFX: Dictionary = {
	"song": "ability_song",
	"summon": "ability_summon",
	"revival": "ability_revive",
}

## Types that must NOT have been swept in. support is 85 abilities whose cues are struktured's
## call and key on the ability id, not the type; physical thumping is correct.
const MUST_STILL_THUMP: Dictionary = {
	"cleave": "physical",
	"power_strike": "physical",
	"provoke": "support",
}


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func _abilities() -> Dictionary:
	var text: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
	var a: Variant = parsed.get("abilities", parsed)
	return a if a is Dictionary else {}


func test_the_three_cues_exist_and_load() -> void:
	## Without the assets the mapping resolves to a manifest miss, which is SILENCE — worse
	## than the thump it replaced.
	var sm: Node = _sm()
	assert_not_null(sm, "SoundManager autoload must exist")
	for cue in TYPE_SFX.values():
		assert_true(sm._sfx_manifest.has(cue), "%s missing from the manifest" % cue)
		if not sm._sfx_manifest.has(cue):
			continue
		var path: String = str((sm._sfx_manifest[cue] as Dictionary).get("file", ""))
		assert_true(ResourceLoader.exists("res://" + path), "%s -> res://%s does not load" % [cue, path])


func test_no_song_summon_or_revival_ability_plays_the_melee_thump() -> void:
	## THE LOAD-BEARING GUARD. Swept from abilities.json by TYPE, so a fifth bard song or an
	## eighth summon added by any lane fails here instead of shipping with a punch sound.
	var sm: Node = _sm()
	var abilities: Dictionary = _abilities()
	assert_gt(abilities.size(), 0, "control: abilities.json parsed to nothing — the sweep ran on zero abilities")

	## The invariant is NOT "everything gets the type cue" — the element still outranks the
	## type, so summon_ifrit correctly plays ability_fire. That precedence is pinned by name
	## in test_element_still_outranks_type below. What must never happen is the THUMP.
	var checked: int = 0
	var thumping: Array[String] = []
	for aid in abilities.keys():
		var entry: Variant = abilities[aid]
		if not (entry is Dictionary):
			continue
		var t: String = str(entry.get("type", ""))
		if not TYPE_SFX.has(t):
			continue
		checked += 1
		var got: String = str(sm._ability_sounds.get(str(aid), "ability_physical"))
		if got == "ability_physical":
			thumping.append("%s (%s) -> the melee thump, wanted %s" % [aid, t, TYPE_SFX[t]])

	assert_gte(checked, 12,
		"control: only %d song/summon/revival abilities were swept — the incident had 12, so the assert below is checking less than the known set" % checked)
	assert_eq(thumping.size(), 0,
		"%d ability(s) still resolve to the melee thump: %s" % [thumping.size(), thumping])


func test_the_bard_songs_specifically() -> void:
	## Named, not counted. The sweep above passes if abilities.json loses the songs entirely.
	var sm: Node = _sm()
	for aid in ["battle_hymn", "lullaby", "discord", "inspiring_melody"]:
		assert_eq(str(sm._ability_sounds.get(aid, "ability_physical")), "ability_song",
			"%s is a SONG — it must not play a sword hit" % aid)
	assert_eq(str(sm._ability_sounds.get("raise", "ability_physical")), "ability_revive",
		"raise brings a dead party member back; it must not play a sword hit")


func test_element_still_outranks_type() -> void:
	## Three summons DECLARE an element, and the element cue is the better sound — summoning
	## Ifrit should read as fire, not as a generic summon. Pinned by name because it is a
	## deliberate precedence choice, not an accident of dictionary order: if the type ever
	## started winning, these would go quietly generic with nothing failing.
	var sm: Node = _sm()
	var expected: Dictionary = {
		"summon_ifrit": "ability_fire",
		"summon_shiva": "ability_ice",
		"summon_ramuh": "ability_lightning",
	}
	for aid in expected.keys():
		assert_eq(str(sm._ability_sounds.get(aid, "ability_physical")), str(expected[aid]),
			"%s declares an element; the element cue must outrank the generic summon cue" % aid)
	## And the elementless ones must NOT have been dragged along with them.
	for aid in ["summon_bahamut", "rat_swarm", "royal_summon", "pack_call"]:
		assert_eq(str(sm._ability_sounds.get(aid, "ability_physical")), "ability_summon",
			"%s declares no element — it must land on the generic summon cue" % aid)


func test_riff_is_a_chord_not_a_sword() -> void:
	## The Bard's Free Move IS her attack (struktured 2026-08-29: "the bard doesnt need an attack
	## option"). It is type=physical, so DERIVATION CANNOT REACH IT — only the hand map can, which
	## is why it survived the fix above and needs its own assert. Its shipped description reads "a
	## sour, clashing chord struck like a weapon"; ability_physical is a sword unsheathing, so the
	## audio contradicted the text the player is shown.
	var sm: Node = _sm()
	assert_eq(str(sm._ability_sounds.get("riff", "ability_physical")), "ability_riff",
		"riff must play its own chord, not the sword thump")
	assert_true(sm._sfx_manifest.has("ability_riff"), "ability_riff missing from the manifest")
	## The engine already groups riff with the four songs (BattleAnimator play_cast) and routes its
	## VFX to MP_RESTORE. Audio was the last channel still calling it a sword — pin that agreement.
	var abilities: Dictionary = _abilities()
	assert_eq(str((abilities.get("riff", {}) as Dictionary).get("animation", "")), "riff",
		"control: riff's animation field changed — the engine grouping this assert relies on has moved")


func test_physical_and_support_were_not_swept_in() -> void:
	## NEGATIVE CONTROL on scope. Mapping every unmapped type would have caught 185 abilities
	## including all 85 support buffs — an over-fix that changes the whole battle mix at once.
	var sm: Node = _sm()
	var abilities: Dictionary = _abilities()
	for aid in MUST_STILL_THUMP.keys():
		assert_true(abilities.has(aid), "control: %s must exist in abilities.json or this control is vacuous" % aid)
		if not abilities.has(aid):
			continue
		assert_eq(str((abilities[aid] as Dictionary).get("type", "")), str(MUST_STILL_THUMP[aid]),
			"control: %s changed type — it no longer controls what this test says it does" % aid)
		assert_eq(str(sm._ability_sounds.get(aid, "ability_physical")), "ability_physical",
			"%s is type=%s and must keep the thump" % [aid, MUST_STILL_THUMP[aid]])


func test_play_ability_actually_resolves_the_new_cue() -> void:
	## CALL SITE. Every assert above reads _ability_sounds directly — they prove the map is
	## BUILT, never that play_ability reads it for these types. A manifest miss provably does
	## not stamp the cooldown, so a stamp means the cue resolved.
	var sm: Node = _sm()
	assert_eq(str(sm._ability_sounds.get("battle_hymn", "")), "ability_song",
		"PREMISE: battle_hymn must be a derived entry or this proves nothing")
	sm._sfx_cooldowns.erase("ability_song")
	assert_false(sm._sfx_cooldowns.has("ability_song"),
		"control: the cue must start unstamped or an earlier test satisfies the assert below")
	sm.play_ability("battle_hymn")
	assert_true(sm._sfx_cooldowns.has("ability_song"),
		"play_ability('battle_hymn') did not resolve ability_song — the map is built but the call site is not reading it")
