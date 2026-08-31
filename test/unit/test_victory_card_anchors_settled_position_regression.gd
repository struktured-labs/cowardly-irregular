extends GutTest

## Regression: struktured cap 2026-08-31 — "cleric shows +72 exp after battle and its way too
## far away from her." Four cards matched the formation math (marker - CARD_W - 36) to the
## pixel; the Cleric's alone sat ~246px further left: her sprite was mid-return from a heal
## lunge when the cards were placed, then settled home, stranding the card at the transient
## spot. Same class + same fix as the bubble anchor (bda760e6): apply the settled-minus-current
## delta from home_position.

const OVERLAY_SRC := "res://src/battle/VictoryOverlay.gd"


func _card_position_body() -> String:
	var src := FileAccess.get_file_as_string(OVERLAY_SRC)
	var i := src.find("func _card_position")
	assert_gt(i, -1, "_card_position must exist")
	var next: int = src.find("\nfunc ", i + 1)
	return src.substr(i, (next - i) if next > -1 else 1800)


func test_card_anchor_settles_to_home_position() -> void:
	var body := _card_position_body()
	assert_true('has_meta("home_position")' in body,
		"the card anchor must consult home_position — a sprite mid-tween at victory reports a " +
		"transient canvas position, which is exactly the stranded Cleric card in the cap")
	assert_true("home - sprite.position" in body,
		"the correction must be the settled-minus-current DELTA applied to the canvas anchor; " +
		"assigning home directly would mix local and canvas space")


func test_home_position_is_still_the_shared_settled_authority() -> void:
	# The bubble fix, the attack tweens, and now the cards all read one meta. If BattleScene
	# stops stamping it, every consumer silently degrades to the transient position at once.
	var scene_src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_gt(scene_src.count('set_meta("home_position"'), 0,
		"BattleScene must still stamp home_position, or the card correction reads a meta nobody writes")


func test_body_reader_reports_a_fabricated_token_as_absent() -> void:
	var body := _card_position_body()
	assert_false("zzz_not_a_real_token" in body,
		"a fabricated token must read absent — if this passes trivially the reader still works")
	assert_true("LOG_CLEAR_X" in body,
		"and a token KNOWN to be present must read present, else the reader grabbed the wrong text")
