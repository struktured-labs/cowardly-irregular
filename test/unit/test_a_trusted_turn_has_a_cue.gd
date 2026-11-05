extends GutTest

## cowir-main 21913: the 1.0 s trusted-turn window gets a soft audible offer beside cowir-controller's pill, so a player
## across the room hears the chance. Short and quiet by design: an offer, not a turn. No close cue.

const KEY := "trust_window_open"
const MAX_SECONDS := 0.5


func test_the_cue_exists_and_is_short() -> void:
	var e: Dictionary = SoundManager._sfx_manifest.get(KEY, {})
	assert_false(e.is_empty(), "the trusted-turn cue is in the manifest")
	var s = load(str(e.get("file", ""))) if not e.is_empty() else null
	assert_not_null(s, "and loads")
	if s != null:
		assert_lt(float(s.get_length()), MAX_SECONDS, "an offer inside a 1.0 s window must end well before it closes")


func test_it_is_not_the_turn_cue() -> void:
	var a: Dictionary = SoundManager._sfx_manifest.get(KEY, {})
	var b: Dictionary = SoundManager._sfx_manifest.get("player_turn", {})
	assert_false(b.is_empty(), "CONTROL: the turn cue exists to compare with")
	assert_ne(str(a.get("file", "")), str(b.get("file", "")), "the offer must not sound like a turn starting")
