extends GutTest

const SfxState := preload("res://test/unit/helpers/sfx_state.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")

const BATTLE_SCENE := "res://src/battle/BattleScene.gd"
const WEATHER_SYSTEM := "res://src/exploration/WeatherSystem.gd"
const THUNDER := "weather_thunder_distant"

## The SAME event is rendered twice, once per surface, from the same `storm` condition:
##   WeatherSystem._trigger_lightning   flash + tween  ->  plays weather_thunder_distant
##   BattleScene._process_weather_layer flash + tween + _storm_bolt  ->  NOTHING
## Measured 2026-09-18: zero SoundManager references in the battle function. So a storm thunders
## while you walk and goes silent the moment a fight starts, on the surface that draws the BIGGER
## version of it — battle adds a drawn bolt the overworld does not have.
##
## And the cue is 4.00s, which is why it also needed its own voice. The overworld call site chose
## play_battle deliberately (play_ambient would replace the storm BED, and the asset is mixed 18 dB
## down so the -6 battle channel lands it 3.8 dB over the rain) — correct about the LEVEL, and
## _battle_player is where every attack hit lands. Eighth instance of the shared-player class.


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func _c(sm: Node, n: String) -> float:
	return float(sm.get_script().get_script_constant_map()[n])


## The body of one function, from its header to the next one.
func _func_body(path: String, header: String) -> String:
	var code: String = GdSource.code_of(path)
	var start: int = code.find(header)
	if start < 0:
		return ""
	var nxt: int = code.find("\nfunc ", start + 1)
	return code.substr(start, nxt - start) if nxt > start else code.substr(start)


func before_each() -> void:
	var sm: Node = _sm()
	if sm:
		sm._sfx_cooldowns.clear()
		sm.reset_hit_chain()


func after_each() -> void:
	SfxState.release_streams()


func test_both_surfaces_that_draw_the_bolt_also_sound_it() -> void:
	## A RELATIONSHIP between the two renderers of one event, not a literal in either — so moving
	## the cue or renaming it is what this has to survive.
	##
	## ⚠️ "TWO SURFACES" IS TWO CODE PATHS, NOT TWO PLACES IN THE GAME, and the distinction runs the
	## generous way. Measured 2026-09-18: `_trigger_lightning` lives once in WeatherSystem and is
	## hosted SIX times — OverworldScene plus the suburban/steampunk/industrial/futuristic
	## overworlds, and BaseVillage — so the fix reaches village storms too, which the commit did
	## not say. BattleScene._process_weather_layer is the only renderer outside that function.
	##
	## ⛔ AND WHAT THIS ARM DOES NOT DO, said rather than implied: the pair is HAND-NAMED. A THIRD
	## renderer would not red here. I checked for one (`_storm_bolt` has two callers, the other
	## being the ability storm this borrows its builder from) and found none — but "none today"
	## is the claim, not "none possible". Deriving the set would need a signature for "renders a
	## weather strike" that does not exist in the code, so a floor would be fiction.
	var overworld: String = _func_body(WEATHER_SYSTEM, "func _trigger_lightning(")
	var battle: String = _func_body(BATTLE_SCENE, "func _process_weather_layer(")
	assert_ne(overworld, "", "CONTROL: WeatherSystem._trigger_lightning is gone — this file's premise is stale")
	assert_ne(battle, "", "CONTROL: BattleScene._process_weather_layer is gone — this file's premise is stale")
	## ⛔ WORD-BOUNDARIED, NOT `contains`. `contains("_storm_bolt(")` is unbounded on the LEFT, so
	## `_weather_storm_bolt(` satisfies a control whose subject is gone — and this control is what
	## separates "drawn silently" from "not drawn at all", which is this file's entire claim. Zero
	## such identifiers exist in BattleScene today, so it is latent; re-measuring buys until the
	## next rename and bounding it does not expire (cowir-battle, 2026-09-18).
	assert_ne(RegEx.create_from_string("\\b_storm_bolt\\(").search(battle), null,
		"CONTROL: the battle function must still DRAW the bolt, or 'draws it silently' is not the claim")
	var silent: Array = []
	if not overworld.contains(THUNDER):
		silent.append("WeatherSystem._trigger_lightning")
	if not battle.contains(THUNDER):
		silent.append("BattleScene._process_weather_layer")
	assert_eq(silent, [],
		"%d of the 2 surfaces that render a lightning strike do not sound it — the same storm thunders on one and flashes silently on the other: %s" % [
			silent.size(), silent])


func test_the_thunder_is_not_cut_by_the_next_attack() -> void:
	## THE reason it needed a voice rather than a call: 4.00s on the channel every hit lands on.
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	assert_true(sm._sfx_manifest.has(THUNDER), "CONTROL: %s must be in the manifest" % THUNDER)
	sm.play_weather_oneshot(THUNDER)
	var voice: AudioStreamPlayer = sm._weather_player
	assert_not_null(voice, "the weather one-shot has no dedicated voice")
	if voice == null:
		return
	assert_ne(voice, sm._battle_player,
		"the weather voice IS _battle_player — every attack hit replaces the clap")
	## ⛔ NOT A LOADING CONTROL, THOUGH IT LOOKS LIKE ONE, AND THE DISTINCTION IS THE WHOLE ARM.
	## The identity assert above cannot see a re-route: send the cue to _battle_player and
	## _weather_player is still a different node, so it passes while the clap is back on the busy
	## channel. What actually detects that is THIS line — the dedicated voice must be the one
	## holding the cue. Measured on that exact mutation; I first read this red as a loading
	## problem and moved it, which fixed nothing because it was never in the wrong place.
	var held: AudioStream = voice.stream
	assert_not_null(held,
		"play_weather_oneshot left _weather_player empty — either %s failed to load, or the one-shot is being routed to a different player" % THUNDER)
	sm._sfx_cooldowns.clear()
	sm.play_attack_hit("sword", false)
	assert_eq(voice.stream, held,
		"a sword hit replaced the thunder — a 4.00s ambient one-shot cannot share the channel that sounds every strike")
	assert_not_null(sm._battle_player.stream, "CONTROL: the attack must genuinely have played")


func test_the_thunder_keeps_the_level_its_asset_was_mixed_for() -> void:
	## Not a free choice: the file is mixed 18 dB down (-17.9 dBFS against the bed's +0.3) SO THAT
	## a -6 channel lands it 3.8 dB over the rain. A quieter home channel makes it inaudible and the
	## asset would have to be remastered to follow.
	## ⚠️ THIS READS THE LEVEL THE PLAYER IS *SET TO BY THE PLAY*, NOT THE ONE IT WAS BUILT AT.
	## _play_battle_on passes an explicit level on every call, so the construction base is dead
	## state here and mutating it changes nothing — measured. What this arm defends is a re-ROUTE:
	## sending the one-shot through play_ui drops it to -16 and 10 dB under the rain.
	var sm: Node = _sm()
	if sm == null:
		return
	sm.play_weather_oneshot(THUNDER)
	assert_eq(sm._weather_player.volume_db, _c(sm, "SFX_BATTLE_BASE_DB"),
		"the weather voice plays at %.2f dB, not the %.2f its asset was mixed against" % [
			sm._weather_player.volume_db, _c(sm, "SFX_BATTLE_BASE_DB")])


func test_the_thunder_does_not_replace_the_storm_bed() -> void:
	## Anti-overcorrection, and the reason the original author reached for play_battle: routing the
	## one-shot through play_ambient would stop the 9.50s storm bed to play a 4.00s clap over nothing.
	var sm: Node = _sm()
	if sm == null:
		return
	sm.play_ambient("weather_storm_bed")
	var bed: AudioStream = sm._ambient_player.stream
	assert_not_null(bed, "CONTROL: the storm bed must be playing, or there is nothing to displace")
	var key: String = str(sm._current_ambient_key)
	sm.play_weather_oneshot(THUNDER)
	assert_eq(sm._ambient_player.stream, bed, "the thunder replaced the storm bed it is supposed to land over")
	assert_eq(str(sm._current_ambient_key), key, "the ambient slot no longer names the bed that is playing")
	sm.stop_ambient()


func test_every_member_this_file_reaches_for_still_exists() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	## ⚠️ A SNAPSHOT of this file's own sm. reaches, not a live derivation.
	for m in ["play_weather_oneshot", "play_attack_hit", "play_ambient", "stop_ambient", "reset_hit_chain"]:
		assert_true(sm.has_method(m), "SoundManager has no method %s — this file CALLS it" % m)
	for n in ["_weather_player", "_battle_player", "_ambient_player", "_sfx_cooldowns", "_sfx_manifest"]:
		assert_true(sm.get(n) != null, "SoundManager has no %s — this file reaches for it directly" % n)
	assert_true((sm.get_script().get_script_constant_map() as Dictionary).has("SFX_BATTLE_BASE_DB"),
		"SFX_BATTLE_BASE_DB is gone — this file's level arm reads it directly")
