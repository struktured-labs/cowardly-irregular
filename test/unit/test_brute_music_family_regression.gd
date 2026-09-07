extends GutTest

## Goblin/brute music split (struktured 2026-08-22): "the goblin battle music is too
## barbarian sounding, could be better for like an actual barbarian/ogre".
##
## The audio was not bad, it was miscast. battle_goblin.ogg is now battle_brute.ogg and
## serves troll/cave_troll/ogre/barbarian. Goblins fall to the PROCEDURAL theme, which
## carried the identical brief - "tribal", 140 BPM A minor, generator comments reading
## "war drums, primal" and "war chant" - so re-pointing the OGG alone would have swapped
## one war-drum bed for another and he would have heard no difference. Both were changed.
##
## The routing arms are explicit ON PURPOSE. The fallback at the bottom of the match in
## _play_music_by_key is gated on `parts.size() > 1`, so one-word ids (ogre, barbarian,
## troll) never reach it. A battle_brute key alone would have been a silent no-op whose
## only symptom is "wrong music", which nobody files as a bug.

const SM_SRC: String = "res://src/audio/SoundManager.gd"
const BRUTE_KEYS: Array[String] = ["battle_brute", "battle_troll", "battle_cave_troll", "battle_ogre", "battle_barbarian"]


func _sm_source() -> String:
	var s: String = FileAccess.get_file_as_string(SM_SRC)
	assert_gt(s.length(), 10000, "SCOPE control: SoundManager.gd read back %d chars" % s.length())
	return s


func test_goblins_and_brutes_have_SEPARATE_tracks() -> void:
	## Inverted 2026-08-26. This arm used to assert battle_goblin.ogg was ABSENT, because the
	## recast moved that file to battle_brute.ogg and goblins had no track of their own. A new
	## goblin theme has since been generated, so absence is no longer the property worth
	## defending -- the old arm's own message named this case and said to invert it.
	##
	## What actually matters is that the two are DIFFERENT AUDIO. He objected to goblins
	## sounding like barbarians; identical bytes under two names would reproduce that exactly,
	## and a file-existence check cannot see it.
	assert_true(ResourceLoader.exists("res://assets/audio/music/battle_brute.ogg"),
		"battle_brute.ogg is missing - the brute family has no theme and falls to generic battle music")
	assert_true(ResourceLoader.exists("res://assets/audio/music/battle_goblin.ogg"),
		"battle_goblin.ogg is missing - goblins fall through to the world bed")

	var g: PackedByteArray = FileAccess.get_file_as_bytes("res://assets/audio/music/battle_goblin.ogg")
	var b: PackedByteArray = FileAccess.get_file_as_bytes("res://assets/audio/music/battle_brute.ogg")
	assert_gt(g.size(), 1000, "SCOPE control: goblin ogg read back %d bytes" % g.size())
	assert_gt(b.size(), 1000, "SCOPE control: brute ogg read back %d bytes" % b.size())
	assert_ne(g, b, "battle_goblin.ogg and battle_brute.ogg are BYTE-IDENTICAL - goblins are scored with the barbarian bed again, which is the complaint that started this")


const BRUTE_OGG: String = "battle_brute.ogg"

func _route_and_get_path(track: String) -> String:
	## play_music sets _music_player.stream SYNCHRONOUSLY; the crossfade only moves the
	## OUTGOING stream to _music_player_b. So the routing decision is readable immediately.
	SoundManager.play_music(track)
	var stream: AudioStream = SoundManager._music_player.stream
	if stream == null:
		return "<no stream>"
	var path: String = str(stream.resource_path)
	## An EMPTY resource_path means the stream loaded but carries no path — the signature of
	## a stale import cache, not of a routing bug. Naming it here because the old message
	## read "routed to , not the brute theme", which cost cowir-ai a diagnosis on 2026-08-22.
	return "<empty resource_path — STALE IMPORT CACHE? run: godot --headless --audio-driver Dummy --import>" if path.is_empty() else path

func test_every_brute_key_routes_to_the_brute_theme() -> void:
	## CONVERTED from a source pin on the match arm. Pinning the arm text asserts a
	## SPELLING: it passes if the arm exists but calls _start_monster_music with the wrong
	## argument, and reds on a harmless reformat. This asserts the OUTCOME - which OGG the
	## player is actually holding - so it covers both, and it survives the match being
	## rewritten as a dictionary lookup.
	var saved: Dictionary = SoundManager.capture_music_state()
	for key in BRUTE_KEYS:
		var path: String = _route_and_get_path(key)
		assert_true(path.ends_with(BRUTE_OGG), "%s routed to %s, not the brute theme" % [key, path])
	SoundManager.restore_music_state(saved)

func test_CONTROL_a_non_brute_key_does_not_reach_the_brute_theme() -> void:
	## Without this the arm above passes on a router that sends EVERYTHING to the brute
	## theme. battle_skeleton is used because it ships its own OGG, so the control costs
	## a cached load rather than a procedural generation.
	var saved: Dictionary = SoundManager.capture_music_state()
	var path: String = _route_and_get_path("battle_skeleton")
	SoundManager.restore_music_state(saved)
	assert_false(path.ends_with(BRUTE_OGG), "battle_skeleton reached the brute theme - the router does not discriminate")
	assert_true(path.ends_with("battle_skeleton.ogg"), "battle_skeleton routed to %s" % path)

func test_CONTROL_the_fallback_really_is_gated_on_multiword_ids() -> void:
	## The whole reason the arms above must be explicit. If this precondition ever relaxes,
	## the arms become redundant rather than load-bearing - and someone should know that
	## before deleting them as duplication.
	var src: String = _sm_source()
	assert_true(src.contains("parts.size() > 1"),
		"the family fallback is no longer gated on a multi-word id. Re-check whether the explicit brute arms are still required, rather than assuming either way.")


func _is_war_drum_flavoured(entry: Dictionary) -> bool:
	return entry.get("style", "") == "tribal" or entry.get("bass_style", "") == "drums"

func test_the_procedural_goblin_is_no_longer_a_war_chant() -> void:
	## NOT because the procedural theme is what goblins play - MEASURED 2026-08-22, it is
	## not: battle_goblin resolves to the world bed (battle_medieval) because play_music
	## consults the manifest first and returns on a hit, so the proc-gen arm is unreachable.
	## This guards the params anyway: they are what a machine WITHOUT a world bed falls to,
	## and leaving a tribal brief in the tree re-creates the character he objected to the
	## moment anything reaches it.
	##
	## MONSTER_MUSIC_PARAMS is a class-level const, so this reads the value the generator
	## uses. The previous version sliced source with a fixed 140-char window for a 106-char
	## entry: it overshot into "skeleton", so skeleton going tribal would have redded the
	## GOBLIN test, and a goblin entry grown past 140 would have truncated to a false green.
	var params: Dictionary = SoundManager.MONSTER_MUSIC_PARAMS
	assert_true(params.has("goblin"), "SCOPE: no goblin entry in MONSTER_MUSIC_PARAMS (%d entries)" % params.size())
	assert_false(_is_war_drum_flavoured(params["goblin"]),
		"the procedural goblin is war-drum flavoured again - the character he objected to, reached by the other of the two sources. style=%s bass_style=%s" % [params["goblin"].get("style"), params["goblin"].get("bass_style")])

func test_CONTROL_the_war_drum_detector_can_still_say_tribal() -> void:
	## No monster ships "tribal"/"drums" any more, so there is no live positive case.
	## Without this the arm above passes on any dictionary and proves nothing.
	assert_true(_is_war_drum_flavoured({"style": "tribal", "bass_style": "staccato"}), "the detector misses a tribal style")
	assert_true(_is_war_drum_flavoured({"style": "frantic", "bass_style": "drums"}), "the detector misses a war-drum bass")
	assert_false(_is_war_drum_flavoured({"style": "frantic", "bass_style": "staccato"}), "the detector flags the SHIPPED goblin values - it cannot distinguish anything")



## A4, C5, E4, E5, G4 — the exact pitch set of main's pentatonic goblin war chant.
const WAR_CHANT_PITCHES: Array[float] = [440.0, 523.25, 329.63, 659.25, 392.0]

func _distinct_pitches(mel: Array) -> Array:
	var seen: Dictionary = {}
	for n in mel:
		var f: float = float(n)
		if f > 0.0:
			seen[snappedf(f, 0.01)] = true
	return seen.keys()

func test_the_goblin_melody_IS_chromatic_not_pentatonic() -> void:
	## CONVERTED from a source pin. Two earlier drafts of this arm were hollow: one pinned
	## comment text, one pinned note names against a slice whose end anchor I guessed —
	## and on a wrong guess the extraction silently widened to the whole file, 53x over.
	## Calling the generator removes the mechanism instead of guarding it: no anchor to
	## miss, no corpus to widen, and it asserts the data the synthesizer actually plays.
	var mel: Array = SoundManager._get_monster_melody("goblin")
	assert_gt(mel.size(), 100, "SCOPE control: the goblin melody came back %d notes" % mel.size())

	var outside: Array = []
	for p in _distinct_pitches(mel):
		if not WAR_CHANT_PITCHES.has(p):
			outside.append(p)
	assert_gt(outside.size(), 0, "every pitch in the goblin melody belongs to the pentatonic war-chant set {A4,C5,E4,E5,G4} — the tribal theme is back in the data, whatever the comments say")

func test_CONTROL_the_pentatonic_detector_can_still_say_pentatonic() -> void:
	## Without this, the arm above passes on ANY melody and proves nothing about goblin.
	var fake: Array = [440.0, 523.25, 0, 329.63, 659.25, 392.0, 0, 440.0]
	var outside: Array = []
	for p in _distinct_pitches(fake):
		if not WAR_CHANT_PITCHES.has(p):
			outside.append(p)
	assert_eq(outside.size(), 0, "the detector flags a genuinely pentatonic line as chromatic — it cannot distinguish anything")


func test_goblins_never_get_the_barbarian_theme() -> void:
	## His actual requirement. The brute theme is the track he called too barbarian for
	## goblins, so the thing that must stay true - whatever the router does internally - is
	## that a goblin encounter does not reach it. Until the new goblin track lands this
	## resolves to the world bed, which is inoffensive; what would be a regression is
	## battle_goblin finding its way back to battle_brute.ogg.
	var saved: Dictionary = SoundManager.capture_music_state()
	var path: String = _route_and_get_path("battle_goblin")
	SoundManager.restore_music_state(saved)
	assert_false(path.ends_with(BRUTE_OGG), "battle_goblin routed to the brute theme - goblins are barbarian-scored again, which is the complaint that started this")

## The prompt file is a SECOND source and the generator reads only it.
const REJECTED_GOBLIN_WORDS: Array[String] = ["tribal", "war drum", "primitive chanting", "chanting"]

func test_the_goblin_PROMPT_is_not_the_brief_he_rejected() -> void:
	## He asked for the goblin theme to be replaced because it was too barbarian. The recast
	## moved the audio and updated the manifest -- and left tools/music_prompts.json still
	## saying "tribal, war drums, primitive chanting". That file is what the generator reads,
	## so regenerating would have handed back exactly the track he rejected, under a new name.
	## Found 2026-08-30 while generating the replacement; cowir-sfx hit the identical shape
	## with ability_heal's "birdsong" prompt the same day.
	var raw: String = FileAccess.get_file_as_string("res://tools/music_prompts.json")
	assert_gt(raw.length(), 1000, "SCOPE control: music_prompts.json read back %d chars" % raw.length())
	var parsed = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "music_prompts.json did not parse")
	var shared: Dictionary = (parsed as Dictionary).get("shared_tracks", {})
	assert_true(shared.has("battle_goblin"), "SCOPE control: no battle_goblin prompt entry")
	assert_true(shared.has("battle_brute"), "battle_brute has no prompt entry - regenerating it would invent a character")

	var goblin: String = (str(shared["battle_goblin"].get("style", "")) + " " + str(shared["battle_goblin"].get("prompt", ""))).to_lower()
	for word in REJECTED_GOBLIN_WORDS:
		assert_false(goblin.contains(word),
			"the goblin PROMPT contains %s - that is the barbarian brief he rejected, and the generator reads this file, not the manifest" % word)

	## The same vocabulary is CORRECT for the brute family: that bed is literally the old track.
	var brute: String = (str(shared["battle_brute"].get("style", "")) + " " + str(shared["battle_brute"].get("prompt", ""))).to_lower()
	assert_true(brute.contains("tribal") or brute.contains("war drum"),
		"the brute prompt lost its tribal character - regenerating it would drift off the bed it describes")
