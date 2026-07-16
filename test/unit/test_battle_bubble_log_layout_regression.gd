extends GutTest

## Playtest 2026-07-15, two battle-readability complaints:
## 1. "chat bubbles for the monsters pop up in a place where it obscures
##    part of the monster and even the players win98 menu at times" —
##    bubbles anchored at sprite CENTER (mid-body on a 300px monster).
##    Fix: anchor above the head (frame height * scale / 2) and bias
##    enemies (left 45% of screen) 50px further left.
## 2. "the chat box / status box thingy cut offs the text awkwardly on
##    top" — log viewport was ~4.8 lines tall; scrolled-to-bottom always
##    half-clipped the top visible line. Fix: _snap_battle_log_height
##    shrinks the panel by the fractional line post-layout.


func test_quip_bubble_anchors_above_head_not_center() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var i := src.find("func _spawn_quip_bubble")
	assert_gt(i, -1)
	var next: int = src.find("\nfunc ", i + 1)
	var body := src.substr(i, (next - i) if next > -1 else 1500)
	assert_true("get_frame_texture" in body,
		"bubble anchor must derive the sprite's frame height — raw global_position is mid-body on tall monsters")
	assert_true("anchor.y -= tex.get_height() * absf(anim_sprite.scale.y) * 0.5" in body,
		"anchor must lift by half the rendered frame height so the bubble clears the head")
	assert_true("anchor.x -= 50.0" in body,
		"enemy-side bubbles (left 45% of viewport) must bias left, clear of the center command menu")
	assert_true("anchor.x -= 70.0" in body,
		"party-side bubbles (right 55%+) must bias toward mid-field — smoke showed them colliding with the AUTO button + party panel")
	assert_false("BattleSpeechBubble.spawn(self, sprite.global_position" in body,
		"the raw-global-position spawn is the bug — must pass the adjusted anchor")


func test_battle_log_height_snap_wired() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_true("call_deferred(\"_snap_battle_log_height\")" in src,
		"log-height snap must be deferred post-layout — measuring before layout settles reads a zero size")
	# 2026-07-16 smoke: deferred alone still raced PanelContainer layout (size 0 → no-op → top line stayed clipped) — resized fires after REAL layout.
	assert_true("battle_log.resized.connect(_snap_battle_log_height)" in src,
		"snap must ALSO hook battle_log.resized — the deferred call can run before layout settles")
	var i := src.find("func _snap_battle_log_height")
	assert_gt(i, -1, "_snap_battle_log_height must exist")
	var next: int = src.find("\nfunc ", i + 1)
	var body := src.substr(i, (next - i) if next > -1 else 1200)
	assert_true("fmod(text_h, line_h)" in body,
		"snap must compute the fractional line via fmod — that fraction IS the half-clipped top line")
	assert_true("log_panel.offset_top += frac" in body,
		"panel must shrink by the fraction so the visible area is a whole number of lines")
