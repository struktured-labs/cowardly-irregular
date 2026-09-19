extends GutTest

## _ability_sounds is keyed by ABILITY ID. A key matching no ability is silent BY CONSTRUCTION —
## no error, no warning, and the cue it names stays authored and unreachable forever.
## Measured 2026-09-16: "constant_modification" matched nothing since 2026-07-11, so
## ability_constant_modification.ogg could never play and modify_constant — the Scriptweaver's
## signature act, "turns a bounded game-constant dial" — fell through to ability_physical, a sword
## unsheathing. The orphan audit cannot see this: the CUE key is referenced in src/, so it is not
## an orphan; it is the ABILITY key that names nothing, and nothing was checking that side.


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func _abilities() -> Dictionary:
	var f := FileAccess.open("res://data/abilities.json", FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return {}
	var inner = parsed.get("abilities", parsed)
	return inner if inner is Dictionary else {}


func test_no_authored_cue_is_reachable_only_by_a_dead_key() -> void:
	## NOT "every key names a real ability" — four keys do not (curaga · holy · dark · drain) and
	## all four are harmless: the derivation reaches their cues from 25, 1, 25 and 7 live ability
	## ids respectively, so nothing is stranded. Measured at runtime on the FINAL map, because a
	## source read of the hand map alone says the opposite and I believed it for a minute.
	## The DEFECT is a cue no live ability can reach — which is what ability_constant_modification
	## was for fourteen months. Guard the property, not the shape.
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	var ab: Dictionary = _abilities()
	assert_gt(ab.size(), 0, "VOID, not clean: abilities.json read back 0 entries")
	assert_true(sm.get("_ability_sounds") != null, "SoundManager has no _ability_sounds — a rename would abort this arm silently")
	var live_per_cue: Dictionary = {}
	for key in sm._ability_sounds.keys():
		var cue: String = str(sm._ability_sounds[key])
		if not live_per_cue.has(cue):
			live_per_cue[cue] = 0
		if ab.has(str(key)):
			live_per_cue[cue] += 1
	assert_gt(live_per_cue.size(), 0, "VOID, not clean: the ability-sound map is empty")
	var stranded: Array = []
	for cue in live_per_cue.keys():
		if int(live_per_cue[cue]) == 0:
			stranded.append(str(cue))
	assert_eq(stranded.size(), 0,
		"these cues are named ONLY by keys that match no ability, so nothing can ever play them: %s" % str(stranded))


func test_the_scriptweavers_dial_does_not_sound_like_a_sword() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	assert_true(sm._ability_sounds.has("modify_constant"),
		"modify_constant is unmapped — it falls through to ability_physical, which is a sword unsheathing")
	assert_eq(str(sm._ability_sounds.get("modify_constant", "")), "ability_constant_modification",
		"modify_constant must reach the cue authored for it")


func test_it_actually_resolves_at_runtime() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	sm._sfx_cooldowns.clear()
	sm._ability_player.stream = null
	sm.play_ability("modify_constant")
	assert_not_null(sm._ability_player.stream, "the Scriptweaver's dial resolved no stream at all")
	assert_true(str(sm._ability_player.stream.resource_path).contains("constant_modification"),
		"play_ability('modify_constant') loaded %s" % str(sm._ability_player.stream.resource_path).get_file())


func test_the_meta_cue_note_has_not_gone_stale() -> void:
	## SoundManager:409 carries a PROSE note — "4 of 24 meta-typed abilities are mapped; the other 20
	## fall through to ability_physical" — pending struktured's call on authoring cues. Prose dies
	## quietly: cowir-sprites had a declaration falsified by their own commit and nothing redded.
	## This is the retirement trigger, and it is DIRECTIONAL rather than a pinned count: it does not
	## assert "20", which a correct mapping would red. It asserts that the note still describes
	## something real, and fires only when the last unmapped meta ability gains a cue — i.e. exactly
	## when the note should be deleted. A declaration that can only be removed, never silently kept.
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	var ab: Dictionary = _abilities()
	assert_gt(ab.size(), 0, "VOID, not clean: abilities.json read back 0 entries")
	assert_true(sm.get("_ability_sounds") != null, "SoundManager has no _ability_sounds")
	var metas: Array = []
	var unmapped: Array = []
	for k in ab.keys():
		var v = ab[k]
		if v is Dictionary and str(v.get("type", "")) == "meta":
			metas.append(str(k))
			if not sm._ability_sounds.has(str(k)):
				unmapped.append(str(k))
	assert_gt(metas.size(), 0, "VOID, not clean: no meta-typed abilities found, so this arm checked nothing")
	## Printed, not asserted: the note at SoundManager:409 deliberately carries NO count, so this is
	## where the current figure lives. Do not copy it back up there.
	print("[meta-cue] %d of %d meta-typed abilities are mapped; %d fall through to ability_physical" % [metas.size() - unmapped.size(), metas.size(), unmapped.size()])
	assert_gt(unmapped.size(), 0,
		"every meta-typed ability now has a cue — SoundManager's _TYPE_SFX note (\"physical/support/meta are deliberately absent\") describes nothing and must be DELETED")
