extends GutTest

## A trigger_voices element may become {"line","when"} at the same index; its text, and so its clip, must not change.

var _saved_rogue: Dictionary = {}
var _saved_last: Dictionary = {}


func before_each() -> void:
	_saved_rogue = (PartyPersonas._data.get("rogue", {}) as Dictionary).duplicate(true)
	_saved_last = PartyPersonas._last_variant.duplicate()


func after_each() -> void:
	PartyPersonas._data["rogue"] = _saved_rogue
	PartyPersonas._last_variant = _saved_last


func _rogue_says(lines: Variant) -> void:
	var entry: Dictionary = _saved_rogue.duplicate(true)
	var tv: Dictionary = entry.get("trigger_voices", {})
	tv["turn_start"] = lines
	entry["trigger_voices"] = tv
	PartyPersonas._data["rogue"] = entry


func test_a_string_and_its_tagged_object_have_the_same_text() -> void:
	var s := "Cleric. When you're ready."
	assert_eq(VoiceLines.text_of(s), s)
	assert_eq(VoiceLines.text_of({"line": s, "when": "ally_alive:cleric"}), s,
		"tagging a line in place must not change its text, or its clip goes stale")


func test_tags_read_from_either_shape() -> void:
	assert_eq(VoiceLines.tags_of("plain"), [] as Array[String])
	assert_eq(VoiceLines.tags_of({"line": "x", "when": "none_down"}), ["none_down"] as Array[String])
	assert_eq(VoiceLines.tags_of({"line": "x", "when": ["ally_alive:mage", "ally_alive:rogue"]}),
		["ally_alive:mage", "ally_alive:rogue"] as Array[String])


func test_entries_keep_their_original_index_across_a_skipped_one() -> void:
	var e: Array = VoiceLines.entries_of(["zero", "", {"line": "two", "when": "ally_down"}])
	assert_eq(e.size(), 2, "the empty entry is skipped")
	assert_eq(int(e[0]["index"]), 0)
	assert_eq(int(e[1]["index"]), 2,
		"the entry after a skipped one must keep index 2, or it plays another line's clip")
	assert_eq(str(e[1]["line"]), "two")


func test_variant_key_matches_the_clip_contract() -> void:
	assert_eq(VoiceLines.variant_key("low_hp", 0), "low_hp")
	assert_eq(VoiceLines.variant_key("low_hp", 7), "low_hp_7")


func test_a_pick_names_its_own_clip_even_after_a_skipped_entry() -> void:
	_rogue_says(["zero", "", "two"])
	var seen := {}
	for i in 60:
		var p: Dictionary = PartyPersonas.pick_trigger_voice("rogue", "turn_start")
		seen[p["voice_key"]] = p["line"]
	assert_eq(seen.get("turn_start_2"), "two",
		"'two' sits at index 2 and must play voice_rogue_turn_start_2, not _1")
	assert_false(seen.has("turn_start_1"), "no line lives at index 1, so its clip must never be named")


func test_an_object_entry_is_spoken_as_its_line() -> void:
	_rogue_says([{"line": "Only when it's true.", "when": "none_down"}, "Plain."])
	for i in 40:
		var p: Dictionary = PartyPersonas.pick_trigger_voice("rogue", "turn_start")
		assert_false(str(p["line"]).begins_with("{"),
			"an object entry must be spoken as its line, got %s" % p["line"])


func test_every_list_reader_reads_the_line_not_the_element() -> void:
	for path in ["res://test/unit/test_party_voice_pack_regression.gd",
			"res://test/unit/test_persona_signature_line_names_current_ability.gd",
			"res://test/unit/test_a_long_quip_widens_before_it_grows_tall_regression.gd"]:
		var src: String = FileAccess.get_file_as_string(path)
		assert_ne(src, "", "could not read %s" % path)
		assert_true(src.contains("VoiceLines.text_of("),
			"%s must read a line through VoiceLines.text_of, or a tagged entry is hashed as JSON" % path)
