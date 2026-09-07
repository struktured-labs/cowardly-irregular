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


func test_faceless_types_hide_the_portrait_frame() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/ui/BattleDialogue.gd")
	assert_true(src.contains("portrait_type in [\"narrator\", \"enemy\"]"),
		"narrator/enemy entries must hide the portrait frame — the fallback blob is not a face")
