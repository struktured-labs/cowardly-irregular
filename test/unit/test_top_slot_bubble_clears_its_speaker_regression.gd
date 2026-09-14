extends GutTest

## Regression: the top party slot's head sits above the bubble clamp, so its bubble was pushed DOWN onto its own speaker, stacked with neighbours and covered the SELECT banner (store capture v3.33.345; Advance aura frames 2026-09-14).

const TOP_SLOT_CENTRE := Vector2(950.0, 140.0)
const HALF_W := 105.0
const CEILING := 66.0
const MENU := Rect2(540.0, 98.0, 210.0, 222.0)
const LONG_LINE := "My turn. Hand on the stick, not the script. Good."

var _host: Control = null
var _time_scale_before: float = 1.0


func before_each() -> void:
	BattleSpeechBubble._live.clear()
	_time_scale_before = Engine.time_scale
	Engine.time_scale = 1.0
	_host = Control.new()
	add_child_autofree(_host)


func after_each() -> void:
	Engine.time_scale = _time_scale_before
	BattleSpeechBubble._live.clear()


func _sprite_rect(centre: Vector2) -> Rect2:
	return Rect2(centre - Vector2(HALF_W, HALF_W), Vector2(HALF_W * 2.0, HALF_W * 2.0))


func _spawn(centre: Vector2, speaker: String, half_w: float, keep_out: Callable = Callable()) -> BattleSpeechBubble:
	var anchor := Vector2(centre.x, centre.y - HALF_W)
	return BattleSpeechBubble.spawn(_host, anchor, speaker, LONG_LINE, Color.GOLD, 1.5, "", false, half_w, CEILING, keep_out)


func _laid_out() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


## The bug: a ceiling-pinned bubble landed on the speaker's own head.
func test_top_slot_bubble_does_not_cover_its_speaker() -> void:
	var b := _spawn(TOP_SLOT_CENTRE, "Fighter", HALF_W)
	assert_not_null(b, "the bubble must spawn")
	await _laid_out()
	var r: Rect2 = b._screen_rect()
	assert_gt(r.size.x, 0.0, "the layout pass must have run, else this measures an empty rect")
	assert_false(r.intersects(_sprite_rect(TOP_SLOT_CENTRE)),
		"bubble %s covers its speaker %s — the ceiling pushed it into the body and it did not clear sideways" % [r, _sprite_rect(TOP_SLOT_CENTRE)])


## Canary: without the speaker width (the pre-fix call) the same bubble DOES cover the speaker, or the assert above is free.
func test_canary_the_old_placement_covers_the_speaker() -> void:
	var b := _spawn(TOP_SLOT_CENTRE, "Fighter", 0.0)
	await _laid_out()
	var r: Rect2 = b._screen_rect()
	assert_gt(r.size.x, 0.0, "layout must have run")
	assert_true(r.intersects(_sprite_rect(TOP_SLOT_CENTRE)),
		"the pre-fix placement must reproduce the defect in this harness — if it doesn't, the geometry here is wrong")


## Flavor never covers selection: a pinned bubble may not float up into the banner.
func test_pinned_bubble_never_rises_above_the_ceiling() -> void:
	var b := _spawn(TOP_SLOT_CENTRE, "Fighter", HALF_W)
	await _laid_out()
	assert_gte(b.position.y - b._float_px, CEILING - 0.01,
		"the bubble's highest point over its float must stay at or below the banner's bottom (%.1f)" % CEILING)


## A speaker with headroom keeps today's behaviour exactly.
func test_a_speaker_with_headroom_is_unchanged() -> void:
	var b := _spawn(Vector2(860.0, 360.0), "Rogue", HALF_W)
	await _laid_out()
	assert_eq(b._side_clear, 0.0, "a bubble that fits above the head needs no sideways clearance")
	assert_eq(b._float_px, BattleSpeechBubble.FLOAT_UP_PX, "and still floats the full distance")


## Two ceiling-pinned bubbles stacked into one illegible band — the newer line must win.
func test_overlapping_bubbles_do_not_stack() -> void:
	var elder := _spawn(TOP_SLOT_CENTRE, "Cleric", HALF_W)
	await _laid_out()
	var newer := _spawn(TOP_SLOT_CENTRE + Vector2(-45.0, 0.0), "Fighter", HALF_W)
	await _laid_out()
	assert_true(is_instance_valid(newer) and not newer.is_queued_for_deletion(), "the newer bubble must survive")
	assert_true(not is_instance_valid(elder) or elder.is_queued_for_deletion(),
		"the older bubble it overlaps must be retired, not left stacked under it")


## Canary for the retire rule: bubbles that do NOT overlap both survive.
func test_separate_bubbles_both_survive() -> void:
	var a := _spawn(TOP_SLOT_CENTRE, "Fighter", HALF_W)
	await _laid_out()
	var c := _spawn(Vector2(860.0, 560.0), "Bard", HALF_W)
	await _laid_out()
	assert_true(is_instance_valid(a) and not a.is_queued_for_deletion(), "a non-overlapping elder must not be retired")
	assert_true(is_instance_valid(c) and not c.is_queued_for_deletion(), "nor the newer one")


## Slot 1's side is where its own command menu opens — the bubble must slide past it, not hide under it.
func test_bubble_slides_past_the_open_command_menu() -> void:
	var b := _spawn(TOP_SLOT_CENTRE, "Fighter", HALF_W, func() -> Array: return [MENU])
	await _laid_out()
	var r: Rect2 = b._screen_rect()
	assert_gt(r.size.x, 0.0, "layout must have run")
	assert_false(r.intersects(MENU), "bubble %s sits under the command menu %s (z 100 hides it)" % [r, MENU])
	assert_false(r.intersects(_sprite_rect(TOP_SLOT_CENTRE)), "and sliding must not put it back on the speaker")


## Canary: with no keep-out the same bubble DOES land under the menu, or the slide above proves nothing.
func test_canary_without_keep_out_the_menu_is_covered() -> void:
	var b := _spawn(TOP_SLOT_CENTRE, "Fighter", HALF_W)
	await _laid_out()
	assert_true(b._screen_rect().intersects(MENU),
		"without the keep-out the bubble must reproduce the menu overlap in this harness")
