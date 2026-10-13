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

const SWORD := "ability_physical"
const KIT := ["protect", "shell", "regen", "esuna"]

## Still unmapped, so still thumping. A LEDGER, not an aspiration: it reds when someone maps one of
## these, which is the point — the next lane to fix a Rogue or Fighter cue must update this line, and
## a declaration that outlives its fact is worse than none.
const STILL_THUMPING := ["scan", "shadow_step", "smoke_bomb", "provoke"]


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


func test_the_rest_of_the_reachable_gap_is_still_named() -> void:
	## The ledger. These four are reachable in normal play and still cast a sword; naming them is how
	## the gap stays visible instead of being rediscovered. If one gains a cue this arm reds — move it
	## out of STILL_THUMPING and into KIT in the same commit.
	var wired: Array[String] = []
	for id in STILL_THUMPING:
		if SoundManager._ability_sounds.has(id):
			wired.append("%s -> %s" % [id, str(SoundManager._ability_sounds[id])])
	assert_eq(wired, [],
		"these now have a cue, which is good — move them from STILL_THUMPING into KIT so this ledger keeps matching the tree: %s" % [wired])
