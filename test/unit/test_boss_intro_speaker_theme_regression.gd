extends GutTest

## Duel-smoke find 2026-07-03: show_boss_intro's speaker mapping was
## rat-king-era — any named speaker that wasn't "hero" or "rat/king"
## fell back to the HERO portrait/theme, so "Skeleton Knight: I offer
## you a proper duel" rendered with the hero's face in every spotlight
## duel. Named unknown speakers now get the "enemy" theme, and since
## narrator/enemy have no drawn portrait, the frame hides instead of
## showing the abstract fallback blob (seen on the duel's narrator line).

const DialogueScript = preload("res://src/ui/BattleDialogue.gd")


func _entries(lines: Array) -> Array:
	var d = DialogueScript.new()
	add_child_autofree(d)
	d.show_boss_intro("Skeleton Knight", lines)
	return d._dialogue_queue


func test_named_boss_speaker_gets_enemy_theme() -> void:
	var q := _entries(["Skeleton Knight: I offer you a proper duel."])
	assert_eq(q[0]["theme"], "enemy",
		"unknown named speakers are the boss — hero theme was the regression")
	assert_eq(q[0]["portrait"], "enemy")
	assert_eq(q[0]["speaker"], "Skeleton Knight")


func test_narrator_lines_still_narrate() -> void:
	var q := _entries(["*A skeleton in polished plate steps forward.*"])
	assert_eq(q[0]["theme"], "narrator")
	assert_eq(q[0]["speaker"], "")


func test_rat_king_mapping_preserved() -> void:
	var q := _entries(["Rat King: My cave!"])
	assert_eq(q[0]["theme"], "rat_king")


## "curator".contains("rat") is true, so every Curator masterite intro — Flame, Budget,
## Pipeline, Memory Pool, Entropy — was drawn with the Rat King's face and gold theme.
## The player meets the Curator of the Flame in World 1. Only a speaker that is the Rat King
## keeps that portrait; a name that merely contains those letters does not.
func test_a_curator_is_not_drawn_as_the_rat_king() -> void:
	var q := _entries(["Curator of the Flame: Resources are finite. The Master knows this truth."])
	assert_eq(q[0]["speaker"], "Curator of the Flame")
	assert_eq(q[0]["theme"], "enemy",
		"the Curator of the Flame spoke with the Rat King's face — 'curator' contains 'rat'")
	assert_eq(q[0]["portrait"], "enemy")
	var box := DialogueScript.new()
	add_child_autofree(box)
	box.show_boss_intro("Curator of the Flame", ["Curator of the Flame: Resources are finite. The Master knows this truth."])
	assert_false(box._portrait_frame.visible,
		"enemy lines hide the portrait frame; a visible frame here is the rat-king bust")


## Same rule against the live monster intros, so a later boss whose name happens to contain
## "rat" or "king" cannot quietly inherit the crown.
func test_only_the_rat_king_wears_that_face_in_the_monster_intros() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	assert_typeof(data, TYPE_DICTIONARY)
	var misdrawn: Array[String] = []
	var seen := {}
	for id in data.keys():
		var mon: Dictionary = data[id]
		var dlg: Dictionary = mon.get("dialogue", {})
		for bucket in ["intro", "low_hp", "defeat"]:
			for line in dlg.get(bucket, []):
				if typeof(line) != TYPE_STRING:
					continue
				if line.begins_with("*") and line.ends_with("*"):
					continue
				if not (":" in line):
					continue
				var speaker: String = str(line).split(":", true, 1)[0].strip_edges()
				if seen.has(speaker):
					continue
				seen[speaker] = true
				var theme: String = _entries([str(line)])[0]["theme"]
				if "rat king" in speaker.to_lower():
					if theme != "rat_king":
						misdrawn.append("%s should be the Rat King, got %s" % [speaker, theme])
				elif theme == "rat_king":
					misdrawn.append("%s (%s) was drawn as the Rat King" % [speaker, id])
	assert_eq(misdrawn, [], "\n".join(misdrawn))


func test_faceless_types_hide_the_portrait_frame() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/ui/BattleDialogue.gd")
	assert_true(src.contains("portrait_type in [\"narrator\", \"enemy\"]"),
		"narrator/enemy entries must hide the portrait frame — the fallback blob is not a face")
