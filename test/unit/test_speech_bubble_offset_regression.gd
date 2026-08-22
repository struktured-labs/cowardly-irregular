extends GutTest

## Regression: struktured playtest 2026-08-22 — "speech bubbles obscured the players, make
## them more like a bubble, more translucent, style the bubble away from them, not directly
## above, like above and slightly to left or right".
##
## Root cause of the occlusion: BattleScene nudged the ANCHOR left (-50/-70), then
## BattleSpeechBubble CENTRED the bubble on that anchor (anchor_x - bw/2.0). A ~276px bubble
## centred on a point 50px left of the speaker still spans the speaker. The nudge changed
## which point it sat on, never whether it sat on them.

const RESERVED_RIGHT_PX: float = 210.0

var _b: BattleSpeechBubble = null


func before_each() -> void:
	_b = BattleSpeechBubble.new()
	add_child_autofree(_b)


func _vp_w() -> float:
	var vp := _b.get_viewport()
	return vp.get_visible_rect().size.x if vp else 1280.0


# CONTROL: the predicate must report the OLD centred placement as covering the speaker.
# If this fails, every "does not cover" assertion below is vacuous.
func test_covers_anchor_flags_the_old_centred_placement() -> void:
	var anchor_x: float = 400.0
	var bw: float = 276.0
	var centred_x: float = anchor_x - bw / 2.0
	assert_true(_b._covers_anchor(centred_x, bw, anchor_x),
		"the pre-fix centred placement MUST register as covering the speaker — otherwise " +
		"the offset assertions below prove nothing")


func test_bubble_never_covers_the_speaker_across_the_field() -> void:
	var bw: float = 276.0
	var w: float = _vp_w()
	var covered: Array = []
	for frac in [0.08, 0.2, 0.35, 0.5, 0.65, 0.8]:
		var anchor_x: float = w * frac
		for prefer_right in [true, false]:
			var x: float = _b._side_placed_x(anchor_x, bw, prefer_right)
			if _b._covers_anchor(x, bw, anchor_x):
				covered.append("x=%.0f prefer_right=%s" % [anchor_x, prefer_right])
	assert_eq(covered.size(), 0,
		"the bubble must sit beside the speaker, never spanning them. Covering cases: " + str(covered))


func test_preferred_side_is_honoured_when_there_is_room() -> void:
	var bw: float = 200.0
	var w: float = _vp_w()
	var left_speaker: float = w * 0.25
	var right_x: float = _b._side_placed_x(left_speaker, bw, true)
	assert_gt(right_x, left_speaker,
		"a left-half speaker with room should get the bubble to their RIGHT")

	var right_speaker: float = w * 0.55
	var left_x: float = _b._side_placed_x(right_speaker, bw, false)
	assert_lt(left_x + bw, right_speaker,
		"a right-half speaker should get the bubble to their LEFT, clear of the party panel")


func test_reserved_right_column_is_still_respected() -> void:
	var bw: float = 240.0
	var w: float = _vp_w()
	var max_right: float = w - RESERVED_RIGHT_PX
	for frac in [0.5, 0.7, 0.9]:
		var anchor_x: float = w * frac
		for prefer_right in [true, false]:
			var x: float = _b._side_placed_x(anchor_x, bw, prefer_right)
			assert_lte(x + bw, max_right + 0.5,
				"bubble right edge %.0f must not enter the reserved party-panel column (max %.0f)" % [x + bw, max_right])


# (a) more translucent and (b) more like a bubble — read off the REAL StyleBox, not the source text.
func test_bubble_is_translucent_and_rounded() -> void:
	_b._present(Vector2(400, 300), "Fighter", "Testing one two.", Color(1, 0.85, 0.2), true)
	var panel: PanelContainer = null
	for c in _b.get_children():
		if c is PanelContainer:
			panel = c
			break
	assert_not_null(panel, "_present must build a PanelContainer body")
	var sb: StyleBoxFlat = panel.get_theme_stylebox("panel")
	assert_not_null(sb, "the body must carry a StyleBoxFlat override")
	assert_gt(sb.bg_color.a, 0.0, "a fully transparent bubble would be invisible")
	assert_lt(sb.bg_color.a, 0.85,
		"fill must be MORE translucent than the 0.85 struktured called too opaque")
	assert_gt(sb.corner_radius_top_left, 4,
		"corners must be rounder than the pre-fix 4px panel look")


# WIRING, not just correctness. Reverting _present's call site to the old centred form left
# every arm above GREEN — they exercise _side_placed_x directly and never prove _present
# CALLS it. This spawns a real bubble and measures where it actually lands.
func test_a_spawned_bubble_lands_beside_the_speaker_not_on_them() -> void:
	var host := Control.new()
	host.size = Vector2(1280, 720)
	add_child_autofree(host)
	var anchor := Vector2(320, 400)
	var b = BattleSpeechBubble.spawn(host, anchor, "Fighter", "Testing placement end to end.", Color(1, 0.85, 0.2), 5.0, "", true)
	assert_not_null(b, "spawn must return a bubble at default time_scale")
	for i in 6:
		await get_tree().process_frame
	var panel: PanelContainer = null
	for c in b.get_children():
		if c is PanelContainer:
			panel = c
			break
	assert_not_null(panel, "the bubble must have built its body")
	var left: float = b.position.x
	var right: float = left + panel.size.x
	assert_gt(panel.size.x, 0.0, "the body must have settled to a real width or this assert is vacuous")
	assert_false(anchor.x > left - 10.0 and anchor.x < right + 10.0,
		"a SPAWNED bubble must not span the speaker: anchor %.0f, bubble [%.0f..%.0f]" % [anchor.x, left, right])
