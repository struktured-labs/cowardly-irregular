extends GutTest

## Playtest 2026-07-14: "the box highlighting the target in battle rn is
## pointing to my party instead of the slime (it hits the slime though,
## it's just the box is wrongly positioned)."
##
## Root: BattleCommandMenu stored target_pos as `canvas_transform *
## sprite.global_position`, then Win98Menu placed the highlight Control at
## that position. Both the sprite AND the Control render THROUGH
## canvas_transform once at draw time, so the pre-multiply here
## double-applied it — the box was shoved by (canvas_transform - identity)
## * screen_pos. Any non-identity canvas_transform (residual camera state
## from exploration → battle, mid-shake, etc.) put the box far off.
##
## Fix: pass raw `s.global_position`; canvas_transform is applied exactly
## once by the renderer.


func test_target_pos_captures_raw_global_position_not_canvas_mapped() -> void:
	# All six target_pos assignment sites in BattleCommandMenu must be the
	# raw-global-position form. Any canvas_transform multiply would re-open
	# the bug.
	var src := FileAccess.get_file_as_string("res://src/battle/BattleCommandMenu.gd")
	var canvas_mul_count: int = src.count("target_pos = canvas_transform * s.global_position")
	assert_eq(canvas_mul_count, 0,
		"no target_pos site may pre-apply canvas_transform — the renderer applies it once, pre-multiplying double-applies and shoves the highlight")
	# 2026-07-15 iteration: raw global_position was still transient during a target's attack tween — Mage spotlight repro'd the misalignment. Prefer home_position meta (stamped by BattleScene at sprite spawn) with global_position as fallback for edge cases.
	var home_meta_count: int = src.count("s.get_meta(\"home_position\", s.global_position)")
	assert_gte(home_meta_count, 6,
		"all six target_pos sites must resolve via s.get_meta(\"home_position\", s.global_position) — plain global_position is transient during attack tweens and re-opens the Mage-spotlight misalignment")
