extends GutTest

## PROBE (fail-first evidence, kept as the regression arm): BattleScene picks a monster's world
## costume from SoundManager's suffix, which during a battle resolves through the `_:` fallthrough
## to a CACHE whose only writer is play_area_music. Every other sprite surface resolves from
## GameState via HybridSpriteLoader.world_suffix(). When the cache lags, the two disagree and the
## costume is not merely missed — it is ANOTHER WORLD'S SHEET, because both ids are registered.

const Loader = preload("res://src/battle/sprites/HybridSpriteLoader.gd")


func _sm() -> Object:
	return get_tree().root.get_node_or_null("SoundManager")


func _gs() -> Object:
	return get_tree().root.get_node_or_null("GameState")


## The divergence, driven rather than argued. This is what makes the wiring arm load-bearing.
func test_a_lagged_audio_cache_names_a_different_world_than_the_player_is_in() -> void:
	var sm: Object = _sm()
	var gs: Object = _gs()
	assert_not_null(sm, "SCOPE: SoundManager autoload absent — every arm below is vacuous")
	assert_not_null(gs, "SCOPE: GameState autoload absent — every arm below is vacuous")

	var prior_world: int = int(gs.get("current_world"))
	var prior_area: String = str(sm.get("_current_area"))
	var prior_cache: String = str(sm.get("_current_world_suffix"))

	# The battle path: play_music clears _current_area, so the resolver takes `_:` and
	# returns the cache. Plant world 4's suffix there while the player stands in world 5.
	sm.set("_current_area", "")
	sm.set("_current_world_suffix", "industrial")
	gs.set("current_world", 5)

	var audio_says: String = str(sm.call("_get_current_world_suffix"))
	var sheets_say: String = Loader.world_suffix()

	gs.set("current_world", prior_world)
	sm.set("_current_area", prior_area)
	sm.set("_current_world_suffix", prior_cache)

	assert_eq(audio_says, "industrial",
		"CONTROL: the plant did not take — the cleared-area fallthrough no longer returns the cache, so this probe proves nothing")
	assert_eq(sheets_say, "digital",
		"CONTROL: GameState world 5 must resolve to the sheet suffix 'digital'")
	assert_ne(audio_says, sheets_say,
		"CONTROL: the two sources agreed under a planted lag — the divergence this file guards cannot occur")


## Both ids are REGISTERED, so the lag does not fall back to base art. It serves world 4's slime
## to a world 5 player, which is why this is a wrong costume rather than a missing one.
func test_both_sides_of_the_divergence_are_real_sheets() -> void:
	var raw := FileAccess.get_file_as_string("res://data/sprite_manifest.json")
	var data = JSON.parse_string(raw)
	assert_true(data is Dictionary, "SCOPE: sprite_manifest.json did not parse")
	var sheets: Dictionary = data.get("monster_sheets", {})
	assert_true(sheets.has("slime_industrial"),
		"SCOPE: slime_industrial is gone — the lag would now miss to base art, not to another world")
	assert_true(sheets.has("slime_digital"),
		"SCOPE: slime_digital is gone — the world-5 costume this file defends no longer exists")


## WIRING: the costume world has ONE owner. BattleScene reaching back into the audio autoload's
## private resolver is the whole defect; `current_world_suffix()` is the loader's documented
## single fetch site and reads GameState, which changes on every map load.
func test_the_battle_picker_resolves_the_world_through_the_sprite_owner() -> void:
	var src := _code("res://src/battle/BattleScene.gd")
	var at := src.find("func _get_monster_sprite_frames")
	assert_gt(at, -1, "SCOPE: _get_monster_sprite_frames is gone — this arm no longer describes a live picker")
	var next := src.find("\nfunc ", at + 1)
	var body: String = src.substr(at, (next if next > -1 else src.length()) - at)

	assert_false(body.contains("SoundManager._get_current_world_suffix()"),
		"OWNER: the monster costume picker reads the AUDIO autoload's private suffix again. During a battle that resolves to a cache whose only writer is play_area_music, so a costume follows the last music transition instead of the player's world")
	assert_true(body.contains("= HybridSpriteLoaderClass.current_world_suffix()"),
		"WIRING: the picker no longer sources its world from the sprite owner — the four other sprite surfaces all do")


## Comments leave the corpus before any pin runs: a commented-out line carries every boundary a
## pattern can put on it (cowir-controller, 2026-09-18). A `#` inside a string truncates that line,
## which can only cost a false RED.
static func _code(path: String) -> String:
	var out := ""
	for line in FileAccess.get_file_as_string(path).split("\n"):
		out += line.split("#")[0] + "\n"
	return out
