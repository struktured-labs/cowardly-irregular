extends GutTest

## Every speaker without a dedicated blip typed with a MENU BLIP instead of a voice.
##
## CutsceneDialogue builds the path as VOICE_BLIP_DIR + "voice_blip_" + key + ".ogg", and
## VOICE_BLIP_FALLBACK was already prefixed — "voice_blip_default" — so the fallback resolved to
## voice_blip_voice_blip_default.ogg, which has never existed. The real file is
## voice_blip_default.ogg. `_load_voice_blip` then leaves _voice_blip_stream null and
## `_play_voice_blip()` falls through to SoundManager.play_ui("menu_move"), per typed character.
##
## MEASURED 2026-09-12, assets on disk: bard · cleric · fighter · mage · rogue · default.
## VOICE_BLIP_ALIASES routes narrator, elder→theron, scholar, and shopkeeper/villager/merchant/
## guard→generic_npc. NONE of those four targets has an asset, so all of them hit the broken
## fallback. Every narrator line in every cutscene, and every ordinary NPC, typed as a menu blip.
##
## Second cost, on the SFX side: a menu blip on _ui_player is the same channel the 24 cutscene
## cues >=1.0s use (cave_whispers 3.00s, boss_defeat_stinger 2.48s), so the typing also cut them.

const DIR := "res://assets/audio/sfx/"


func _fallback() -> String:
	return CutsceneDialogue.VOICE_BLIP_FALLBACK


func test_the_fallback_key_resolves_to_a_file_that_exists() -> void:
	## THE regression. The path is built by the same expression the source uses.
	var path: String = DIR + "voice_blip_" + _fallback() + ".ogg"
	assert_true(FileAccess.file_exists(path),
		"the fallback blip resolves to %s, which does not exist — every speaker without a dedicated blip gets null and types with play_ui(\"menu_move\"). The asset is voice_blip_default.ogg, so the key must be \"default\", not \"voice_blip_default\"" % path)


func test_the_shipped_default_asset_is_reachable_by_the_fallback() -> void:
	## The other direction: the asset exists and was reachable by NO key. A shipped file nothing
	## can load is an orphan that the manifest hides, because the manifest key looks consumed.
	assert_true(FileAccess.file_exists(DIR + "voice_blip_default.ogg"),
		"CONTROL: the default blip asset must exist, or this test defends nothing")
	assert_eq(_fallback(), "default",
		"VOICE_BLIP_FALLBACK is the KEY, and the loader prefixes it — a value carrying its own \"voice_blip_\" prefix double-prefixes the path")


func test_every_alias_target_either_has_an_asset_or_reaches_the_fallback() -> void:
	## DERIVED over the real alias table, not a hand list: a new alias pointing at a missing
	## family is fine ONLY while the fallback works. This is what made the defect invisible —
	## four of seven aliases target families with no asset and that was survivable by design.
	var aliases: Dictionary = CutsceneDialogue.VOICE_BLIP_ALIASES
	assert_gt(aliases.size(), 0, "CONTROL: the alias table must be non-empty or this loop is vacuous")
	var fallback_path: String = DIR + "voice_blip_" + _fallback() + ".ogg"
	var stranded: Array[String] = []
	for k in aliases:
		var target: String = str(aliases[k])
		if FileAccess.file_exists(DIR + "voice_blip_" + target + ".ogg"):
			continue
		if not FileAccess.file_exists(fallback_path):
			stranded.append("%s -> %s" % [k, target])
	assert_eq(stranded, [],
		"aliases whose family has no asset AND whose fallback does not resolve (%d): %s — these speakers type with a menu blip" % [stranded.size(), stranded])


func test_the_loader_prefixes_exactly_once() -> void:
	## Pins the invariant rather than the string: whatever the fallback is, prefixing it once must
	## land on a real file, and prefixing it twice must not be what the code does.
	var once: String = DIR + "voice_blip_" + _fallback() + ".ogg"
	var twice: String = DIR + "voice_blip_voice_blip_" + _fallback() + ".ogg"
	assert_true(FileAccess.file_exists(once), "one prefix must resolve: %s" % once)
	assert_false(FileAccess.file_exists(twice),
		"CONTROL: the double-prefixed path must NOT exist — if someone adds it, the bug is papered over rather than fixed")
