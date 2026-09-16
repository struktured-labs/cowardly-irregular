extends GutTest

## Tick 176 closed this moment's LOG parity — _on_party_hp_changed emits "X has fallen!" to match
## _on_enemy_died's "X has been defeated!". The AUDIO parity stayed open for six months: an enemy
## death plays enemy_death on the dedicated _death_player with DEATH_THUD under it, and a party
## member dropping played nothing at all. Same moment, same handler, half the feedback.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const BATTLE_SCENE := "res://src/battle/BattleScene.gd"
const CUE := "party_ko"


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func before_each() -> void:
	var sm: Node = _sm()
	if sm:
		sm._sfx_cooldowns.clear()


func test_the_cue_is_authored_and_resolves() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	assert_true(sm._sfx_manifest.has(CUE), "%s is not in the manifest — the wire below is silent" % CUE)
	var f: String = str(sm._sfx_manifest.get(CUE, {}).get("file", ""))
	var path: String = f if f.begins_with("res://") else "res://" + f
	assert_true(ResourceLoader.exists(path), "%s names %s and it is not on disk" % [CUE, f])


func test_an_ally_falling_reaches_the_death_voice() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	sm._death_player.stream = null
	sm.play_death(CUE)
	assert_not_null(sm._death_player.stream, "the ally-KO cue did not play at all")
	assert_true(str(sm._death_player.stream.resource_path).contains(CUE),
		"the death voice is holding %s, not the ally cue" % str(sm._death_player.stream.resource_path).get_file())


func test_it_does_not_evict_the_enemy_death_cry() -> void:
	# Both route through play_death, and a party member can fall in the same frame an enemy dies.
	# They SHARE _death_player by design — this pins that the sharing is the only collision, i.e.
	# the ally cue does not land on _battle_player and cut the hit that killed them.
	var sm: Node = _sm()
	if sm == null:
		return
	sm.play_battle("attack_hit")
	var impact = sm._battle_player.stream
	assert_not_null(impact, "CONTROL: a battle cue must be sounding for this to mean anything")
	sm._sfx_cooldowns.clear()
	sm.play_death(CUE)
	assert_eq(sm._battle_player.stream, impact,
		"the ally-KO cue replaced the battle voice — it must ride its own death voice")


func test_the_moment_that_logs_the_fall_also_sounds_it() -> void:
	# Source-bound: the cue must sit in the SAME branch as the "has fallen" line, not merely
	# somewhere in the file. A cue in a neighbouring branch is a different moment.
	var code: String = GdSource.code_of(BATTLE_SCENE)
	assert_ne(code, "", "CONTROL: BattleScene code must survive the comment strip")
	var start: int = code.find("func _on_party_hp_changed(")
	assert_gt(start, -1, "CONTROL: _on_party_hp_changed is gone — this arm no longer describes the caller")
	var nxt: int = code.find("\nfunc ", start + 1)
	var body: String = code.substr(start, nxt - start) if nxt > start else code.substr(start)
	var gate: int = body.find("new_value <= 0 and old_value > 0")
	assert_gt(gate, -1, "CONTROL: the KO gate is gone — the cue may now fire on every HP tick")
	var branch: String = body.substr(gate)
	assert_true(branch.contains("play_death(\"%s\")" % CUE),
		"the ally-KO cue left the branch that announces the fall — the log and the sound are one moment")
	assert_true(branch.contains("has fallen"),
		"CONTROL: the 'has fallen' line must still be in this branch, or the pairing above is vacuous")


func test_the_cue_is_pinned_against_a_silent_re_roll() -> void:
	# It descends by construction, which is the shape the centroid test can mistake for a whoop.
	var f := FileAccess.open("res://test/fixtures/sfx_whoop_baseline.json", FileAccess.READ)
	assert_not_null(f, "CONTROL: the whoop baseline must be readable")
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	var cues: Dictionary = parsed.get("cues", parsed) if parsed is Dictionary else {}
	assert_true(cues.has(CUE), "%s is not pinned in the whoop baseline — a re-roll could ship unmeasured" % CUE)


func test_every_member_this_file_reaches_for_still_exists() -> void:
	## A direct `sm._x` on a RENAMED member raises at runtime and ABORTS the arm. An abort after
	## that arm's last assert scores PASSING — measured 2026-09-16: renaming the dedicated voice
	## this file exists to defend gave EXIT=0, Failing 0, NO Risky line, and moved only the assert
	## count. `get()` returns null for an absent name instead of raising, so the rename fails loudly
	## here and names itself before any other arm gets the chance to go quiet.
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	for member_name in ["_battle_player", "_death_player", "_sfx_cooldowns", "_sfx_manifest"]:
		## assert_true on an explicit `!= null`: assert_ne deep-compares, and three of these members
		## are Dictionaries, which it refuses with "Only Arrays and Dictionaries are supported".
		assert_true(sm.get(member_name) != null,
			"SoundManager has no %s — this file reaches for it directly, and a rename would abort its arms SILENTLY" % member_name)
