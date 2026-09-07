extends GutTest

## Regression: struktured playtest 2026-08-29 — "speech bubbles are not quite aligned to who says them in battle".

const SCENE_SRC := "res://src/battle/BattleScene.gd"


func _spawn_body() -> String:
	var src := FileAccess.get_file_as_string(SCENE_SRC)
	var i := src.find("func _spawn_quip_bubble")
	assert_gt(i, -1, "_spawn_quip_bubble must exist")
	var next: int = src.find("\nfunc ", i + 1)
	return src.substr(i, (next - i) if next > -1 else 1800)


## The bug: a lunging speaker's global_position is where the sprite IS, not where the character sits.
func test_anchor_settles_to_home_position_when_the_sprite_has_moved() -> void:
	var body := _spawn_body()
	assert_true('has_meta("home_position")' in body,
		"the bubble anchor must consult home_position — a speaker mid-lunge reports a transient global_position, " +
		"which is exactly the misalignment the playtest reported")
	assert_true("home - sprite.position" in body,
		"the correction must be the settled-minus-current DELTA applied to the global anchor; " +
		"assigning home directly would mix local and global space")


## Same authority the attack tweens already use — divergence here is how the two drift apart.
func test_home_position_is_the_established_settled_authority() -> void:
	var src := FileAccess.get_file_as_string(SCENE_SRC)
	assert_gt(src.count('set_meta("home_position"'), 0,
		"BattleScene must still stamp home_position, or the bubble correction reads a meta nobody writes")
	assert_gt(src.count('get_meta("home_position")'), 1,
		"home_position must have consumers besides the bubble — it is the shared settled-position contract")


## CONTROL: the reader must be able to report absence, or both assertions above are free.
func test_body_reader_reports_a_fabricated_token_as_absent() -> void:
	var body := _spawn_body()
	assert_false("zzz_not_a_real_token" in body,
		"a fabricated token must read absent — if this passes trivially the substring reader still works")
	assert_true("BattleSpeechBubble.spawn" in body,
		"and a token KNOWN to be present must read present, else the reader is looking at the wrong text")


## The side-placement fix stays: the anchor must carry no lateral nudge of its own.
func test_anchor_carries_no_lateral_bias() -> void:
	var body := _spawn_body()
	assert_false("anchor.x -= 50.0" in body,
		"the old centred-bubble nudge must stay gone — BattleSpeechBubble places to a side and clamps, " +
		"so an anchor offset only aims the tail away from the speaker")
	assert_false("anchor.x -= 70.0" in body,
		"same for the party-side nudge")
