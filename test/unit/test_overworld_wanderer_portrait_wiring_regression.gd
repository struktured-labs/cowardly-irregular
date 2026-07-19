extends GutTest

## struktured 2026-07-18 (v3.33.203 playtest): "lost pilgrim on overworld: no
## portrait." Root: OverworldScene's wanderer spawn loop set sprite_archetype
## from the "archetype" key but never touched dialogue_portrait or
## dialogue_theme — every wanderer fell back to WanderingNPC's "mysterious"
## default, so the portrait system had nothing to look up even though real
## art (traveler.png etc) shipped.

const OW := "res://src/exploration/OverworldScene.gd"


func test_spawn_loop_wires_portrait_and_theme_from_archetype() -> void:
	var src := FileAccess.get_file_as_string(OW)
	var i := src.find("if w.has(\"archetype\"):")
	assert_gt(i, -1, "the wanderer spawn loop must exist")
	var body := src.substr(i, 400)
	assert_true("npc.sprite_archetype = w[\"archetype\"]" in body,
		"sprite mapping preserved")
	assert_true("npc.dialogue_portrait = w[\"archetype\"]" in body,
		"portrait must be wired from the archetype — Lost Pilgrim's traveler.png went unused otherwise")
	assert_true("npc.dialogue_theme = w[\"archetype\"]" in body,
		"theme too, so dialogue chrome matches the archetype")
