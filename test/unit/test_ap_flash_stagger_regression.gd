extends GutTest

## Phase D item 4 — the party's AP flash cascades across slots instead of firing as one block.
##
## The defect this guards is subtler than "no stagger": the pre-Phase-D code set the flash
## colour and scale BEFORE creating the tween, so delaying only the tween would light every
## box simultaneously and stagger nothing but the fade back. The visible effect would be
## almost unchanged, and no timing assertion on the tween could tell the difference.

const UI_SRC := "res://src/battle/BattleUIManager.gd"
const UIManagerClass = preload("res://src/battle/BattleUIManager.gd")


func _read() -> String:
	var f := FileAccess.open(UI_SRC, FileAccess.READ)
	assert_not_null(f, "CONTROL: BattleUIManager.gd unreadable — every source assertion below is vacuous")
	return f.get_as_text() if f else ""


func _body_of(src: String, header: String) -> String:
	var start := src.find(header)
	if start == -1:
		return ""
	var rest := src.substr(start + header.length())
	## Bounded by the next top-level func, never a line count — a fixed window returns
	## well-formed text from an incomplete region and reads as a whole body.
	var end := rest.find("\nfunc ")
	return rest.substr(0, end) if end != -1 else rest


func test_source_and_anchor_resolve() -> void:
	var src := _read()
	assert_gt(src.length(), 0, "CONTROL: source read empty")
	assert_gt(_body_of(src, "func flash_ap_labels() -> void:").length(), 0,
		"CONTROL: flash_ap_labels was renamed — this test lost its subject and would pass on nothing")


func test_the_flash_state_is_applied_INSIDE_the_tween() -> void:
	## The load-bearing property. If the colour/scale write happens before the tween, the
	## stagger delays only the fade-back and every box lights at once.
	var body := _body_of(_read(), "func flash_ap_labels() -> void:")
	assert_eq(body.count("modulate = Color(2.2"), 0,
		"the flash colour must NOT be written directly in flash_ap_labels — it belongs in the callback, or the stagger only delays the fade and every box lights simultaneously")
	assert_true(body.find("tween_callback(_apply_ap_flash") != -1,
		"the flash state must be applied via tween_callback so the delay precedes it")


func test_the_stagger_is_per_slot_and_skips_the_first() -> void:
	var body := _body_of(_read(), "func flash_ap_labels() -> void:")
	assert_true(body.find("AP_FLASH_STAGGER") != -1, "the stagger constant must be used")
	assert_true(body.find("if slot > 0:") != -1,
		"the first box must not be delayed — a stagger that delays slot 0 adds latency to the whole effect for no cascade")
	assert_true(body.find("slot += 1") != -1,
		"slot must advance, or every box gets the same delay and there is no cascade")


func test_slot_advances_only_for_boxes_that_actually_flash() -> void:
	## If slot incremented on skipped boxes, an invalid box would leave a silent gap in the
	## cascade — visible as an uneven rhythm, and invisible to any count-based check.
	var body := _body_of(_read(), "func flash_ap_labels() -> void:")
	var inc := body.find("slot += 1")
	var null_guard := body.find("if ap_label == null:")
	assert_gt(inc, -1, "slot += 1 is missing")
	assert_gt(null_guard, -1, "the null guard moved")
	assert_true(null_guard < inc,
		"slot must advance AFTER the skip guards, so a skipped box does not consume a slot and leave a hole in the cascade")


func test_the_callback_survives_a_label_freed_during_the_delay() -> void:
	## BEHAVIOURAL. The callback fires up to 4 slots later; a box can be freed in between,
	## and a property write on a freed instance ABORTS the enclosing function in GDScript.
	## _init(scene) requires an argument; _apply_ap_flash touches no instance state, so a
	## null scene is sufficient and keeps this off the real BattleScene's autoload graph.
	var mgr = UIManagerClass.new(null)
	var label := Control.new()
	add_child_autofree(label)

	mgr._apply_ap_flash(label)
	assert_eq(label.scale, Vector2(1.3, 1.3), "a live label must receive the flash scale")
	assert_almost_eq(label.modulate.r, 2.2, 0.01, "a live label must receive the flash colour")

	mgr._apply_ap_flash(null)
	assert_true(true, "a null label must not abort the callback — reaching this line IS the assertion")


func test_the_motion_still_exists() -> void:
	## VACUITY GUARD. Every assertion above is satisfied by a flash_ap_labels that does
	## nothing at all — "no direct colour write" is also true of an empty function.
	var body := _body_of(_read(), "func flash_ap_labels() -> void:")
	assert_true(body.find("tween_property(ap_label, \"scale\"") != -1,
		"the scale return tween is GONE — the absence checks above are equally satisfied by a deleted animation")
	assert_true(body.find("tween_property(ap_label, \"modulate\"") != -1,
		"the modulate return tween is GONE")
	assert_true(body.find("create_tween()") != -1, "no tween is created at all")
