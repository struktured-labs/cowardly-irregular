extends GutTest

## THE CLERIC CAST PROTECT AND IT SOUNDED LIKE A SWORD HIT.
##
## `play_ability` ends in `_ability_sounds.get(id, "ability_physical")` — a sword unsheathing — and
## the derived pass that rescues spells SKIPS any ability whose `type` is not `magic` or in
## _TYPE_SFX. `support` is not in it, deliberately: that const's own comment says "physical/support/
## meta are deliberately absent — the thump is right for physical, and buff cues are keyed on the
## ability id, not the type." So support cues were always meant to be ID-KEYED, and the gap is that
## the intent was never completed. Measured: 84 support abilities fall back to the thump, of which 8
## are reachable in normal play — protect · shell · regen · esuna (Cleric), scan · shadow_step ·
## smoke_bomb (Rogue), provoke (Fighter). This commit does the Cleric's four, per the intent rather
## than by adding a generic type arm, which would fix 84 at once and contradict the comment.
##
## ⚠️ The EFFECT cue was never the problem and is not what this guards: BattleScene already plays
## `buff` for protect/shell/regen, and esuna's cure is cued from BattleManager's cleanse executor.
## The CAST was the sword.

const SfxState := preload("res://test/unit/helpers/sfx_state.gd")
const SWORD := "ability_physical"
const KIT := ["protect", "shell", "regen", "esuna",
		"scan", "shadow_step", "smoke_bomb", "provoke"]

## Still unmapped, so still thumping. A LEDGER, not an aspiration: it reds when someone maps one of
## these, which is the point — the next lane to fix a Rogue or Fighter cue must update this line, and
## a declaration that outlives its fact is worse than none.
## ⛔ THIS FILE PLAYS EIGHT CUES AND SHIPPED WITH NO TEARDOWN. A full suite is ONE process, so the
## last stream stays on the shared _ability_player, and sfx_state.gd's own measured note is that a
## leaked stream satisfies any other file's `assert_true(player.stream != null, "CONTROL: ...")`
## exactly as a real cue does — it disabled three arms in a sibling lane. My steal guard adopted this
## helper earlier the same session; I did not carry it here, which is the half of a rule you forget
## precisely because you already applied it once.
##
## ⚠️ NOT the mixer-wedge class that red .672: `_live_bed()` covers music / music_b / ambient /
## VOICE, and _ability_player is none of those, so this file cannot leave a bed that clears someone's
## stall latch. Two different pollution routes through the same autoload — naming which one this is
## so the next reader does not widen the fix.
func after_each() -> void:
	for id in KIT:
		SoundManager._sfx_cooldowns.erase("ability_" + id)
	SoundManager._sfx_suppressed_by_cooldown = false
	SfxState.release_streams()


func _manifest() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sfx_manifest.json"))
	assert_true(parsed is Dictionary, "VOID: sfx_manifest.json did not parse")
	return (parsed as Dictionary).get("sfx", {}) if parsed is Dictionary else {}


func test_premise_the_kit_is_support_typed_and_would_fall_back() -> void:
	## Without this the arms below pass for the wrong reason: if these became `healing`-typed they
	## would be rescued by the derived pass and the id map would be redundant rather than load-bearing.
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	assert_true(parsed is Dictionary, "VOID: abilities.json did not parse")
	var abilities: Dictionary = (parsed as Dictionary).get("abilities", parsed) if parsed is Dictionary else {}
	var wrong: Array[String] = []
	for id in KIT:
		var a: Dictionary = abilities.get(id, {})
		if str(a.get("type", "")) != "support":
			wrong.append("%s is type '%s'" % [id, str(a.get("type", ""))])
	assert_eq(wrong, [],
		"these are no longer support-typed, so the derived pass may now cover them and the id map below is not what is saving them: %s" % [wrong])


func test_every_kit_ability_maps_to_its_own_cue_not_the_sword() -> void:
	var missing: Array[String] = []
	for id in KIT:
		var cue: String = str(SoundManager._ability_sounds.get(id, SWORD))
		if cue != "ability_" + id:
			missing.append("%s -> %s" % [id, cue])
	assert_eq(missing, [],
		"these Cleric abilities no longer map to their own cue, so play_ability falls back to %s and the Cleric casts a sword again: %s" % [SWORD, missing])


func test_each_kit_cue_is_authored_and_on_disk() -> void:
	var sfx := _manifest()
	var bad: Array[String] = []
	for id in KIT:
		var key: String = "ability_" + id
		if not sfx.has(key):
			bad.append("%s unregistered" % key)
			continue
		var f: String = str((sfx[key] as Dictionary).get("file", ""))
		var res: String = f if f.begins_with("res://") else "res://" + f
		if not FileAccess.file_exists(res):
			bad.append("%s -> %s not on disk" % [key, f])
	assert_eq(bad, [], "the kit's cues are registered but unreachable: %s" % [bad])


func test_the_cue_that_actually_plays_is_the_authored_one() -> void:
	## ⛔ THE ARM THAT MATTERS. The three above prove the MAPPING and the FILE; none proves playback.
	## A key whose file will not load falls through to the procedural path and the player hears the
	## old sound while every assertion above stays green — which is exactly how an asset committed
	## without its .import artifact behaves (measured on status_static: stream length 0.00s).
	## The stream's LENGTH is the discriminator, because the sword is 0.48s and none of these are.
	var sfx := _manifest()
	var sword_len: float = float((sfx.get(SWORD, {}) as Dictionary).get("duration_seconds", 0.48))
	var wrong: Array[String] = []
	for id in KIT:
		SoundManager._sfx_cooldowns.erase("ability_" + id)
		SoundManager.play_ability(id)
		var p: AudioStreamPlayer = SoundManager._ability_player
		if p == null or p.stream == null:
			wrong.append("%s left no stream on the ability player" % id)
			continue
		var want: float = float((sfx.get("ability_" + id, {}) as Dictionary).get("duration_seconds", -1.0))
		var got: float = p.stream.get_length()
		if absf(got - want) > 0.06:
			wrong.append("%s played %.2fs, authored %.2fs%s" % [id, got, want,
				"  <- that is the SWORD" if absf(got - sword_len) < 0.06 else ""])
		SoundManager._sfx_cooldowns.erase("ability_" + id)
	assert_eq(wrong, [],
		"these abilities do not play their own authored cue: %s" % [wrong])


func test_every_support_ability_a_PLAYER_can_cast_has_a_cue_of_its_own() -> void:
	## ⛔ THIS WAS A HAND-LIST OF STILL-THUMPING IDS AND I EMPTIED IT IN THE SAME COMMIT THAT FIXED
	## THE LAST FOUR — which made the arm iterate nothing and pass trivially, while its comment
	## claimed it "still reds if someone re-adds a reachable ability". A control that cannot fail,
	## written by me, two minutes old, and caught only by asking what its mutation would be.
	##
	## Derived instead, so it cannot go vacuous: REACHABLE = support-typed AND owned by a starter
	## job. Every member must carry an id-keyed cue, because the derived pass skips `support` and
	## play_ability's default is ability_physical, a sword. A new reachable support ability reds this
	## the day it lands; the 65 monster-only and 11 debug-gated ones are out of scope by the same
	## derivation rather than by a list someone has to remember to update.
	const STARTERS := ["fighter", "cleric", "mage", "rogue", "bard"]
	var ap: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var jp: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/jobs.json"))
	assert_true(ap is Dictionary and jp is Dictionary, "VOID: abilities.json or jobs.json did not parse")
	if not (ap is Dictionary and jp is Dictionary):
		return
	var abilities: Dictionary = (ap as Dictionary).get("abilities", ap)
	var jobs: Dictionary = (jp as Dictionary).get("jobs", jp)

	var owned_by_starter: Dictionary = {}
	for jid in jobs.keys():
		if not (str(jid) in STARTERS):
			continue
		var blob: String = JSON.stringify(jobs[jid])
		for aid in abilities.keys():
			if blob.contains("\"%s\"" % str(aid)):
				owned_by_starter[str(aid)] = true

	var reachable: Array[String] = []
	for aid in abilities.keys():
		var a: Variant = abilities[aid]
		if a is Dictionary and str((a as Dictionary).get("type", "")) == "support" and owned_by_starter.has(str(aid)):
			reachable.append(str(aid))
	reachable.sort()
	assert_gt(reachable.size(), 4,
		"CONTROL: derived only %d reachable support abilities — the derivation broke and this arm is vacuous, which is exactly what the hand-list it replaced became" % reachable.size())

	var thumping: Array[String] = []
	for aid in reachable:
		if not SoundManager._ability_sounds.has(aid):
			thumping.append(aid)
	assert_eq(thumping, [],
		"these support abilities are castable by a starter job and have no id-keyed cue, so play_ability falls back to ability_physical and they cast a SWORD: %s" % [thumping])
