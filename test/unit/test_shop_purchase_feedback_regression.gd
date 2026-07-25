extends GutTest

## Shop purchase feedback (struktured msg 2775 item 1: "more obvious that
## you purchase something... a nice little ka-ching... more visual
## indication, not just a closing of a menu").
##
## ORPHAN-KEY FINDING (2026-07-25): cowir-sfx shipped `purchase_complete`
## to the manifest in their cycle #8 believing it was wired to ShopScene,
## but `grep -rn purchase_complete src/` returned ZERO consumers —
## ShopScene played the generic `menu_select` on a successful buy. The
## asset was fine; the consumer wire was this lane's item and the
## 2026-07-18 OOM ate the tick. Canonical silent-failure class: asset
## ships, nobody greps, nobody notices.
##
## Why a ratchet instead of a runtime fallback: SoundManager.play_ui()
## already degrades silently on a missing key (manifest miss → procedural
## SOUNDS miss → bare `return`). A runtime `item_obtain` fallback would
## keep the shop audible but hide the asset going missing. Asserting the
## manifest key at commit time converts that silent runtime degradation
## into a loud test failure instead — the project's stated preference
## (CLAUDE.md principle #7). It also keeps this lane out of
## src/audio/SoundManager.gd, which is cowir-sfx's surface.

const SHOP_SCENE := "res://src/exploration/ShopScene.gd"
const SFX_MANIFEST := "res://data/sfx_manifest.json"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


## The asset half of the contract. If cowir-sfx ever retires the key, this
## fails loudly here rather than the shop silently going quiet in-game.
func test_purchase_complete_key_exists_in_manifest() -> void:
	var raw := _read(SFX_MANIFEST)
	assert_ne(raw, "", "sfx manifest readable")
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "sfx manifest parses")
	var sfx: Dictionary = (parsed as Dictionary).get("sfx", {})
	assert_true(sfx.has("purchase_complete"),
		"purchase_complete must exist in the manifest — ShopScene plays it on a successful buy")


## The consumer half. This is the assertion that would have caught the
## orphan: the key exists in data/ but nothing in src/ ever asks for it.
func test_shop_scene_actually_plays_purchase_complete() -> void:
	var src := _read(SHOP_SCENE)
	assert_ne(src, "", "ShopScene readable")
	assert_true(src.contains("play_ui(\"purchase_complete\")"),
		"ShopScene must play purchase_complete — it was an orphan key until 2026-07-25")


## All three feedback beats must fire on the SAME success path, after the
## gold spend and the item handoff both succeed. Pinning them together
## guards the actual bug shape: a refund/early-return path that plays the
## celebration sound for a transaction that didn't happen.
func test_all_three_beats_fire_on_the_success_path_only() -> void:
	var src := _read(SHOP_SCENE)
	var fn_idx := src.find("func _attempt_purchase")
	assert_gt(fn_idx, 0, "_attempt_purchase present")
	var next_fn := src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)

	var sound_pos := body.find("play_ui(\"purchase_complete\")")
	var flash_pos := body.find("_flash_gold_label_success()")
	var toast_pos := body.find("_show_purchase_toast(")
	var emit_pos := body.find("item_purchased.emit(")
	assert_gt(sound_pos, 0, "ka-ching fires in _attempt_purchase")
	assert_gt(flash_pos, 0, "gold flash fires in _attempt_purchase")
	assert_gt(toast_pos, 0, "purchase toast fires in _attempt_purchase")

	# The refund guard returns early ABOVE all of these. If any beat ever
	# migrates above that return, a failed purchase would celebrate.
	var refund_pos := body.find("game_state.add_gold(cost)")
	assert_gt(refund_pos, 0, "refund path still present (atomicity guard from tick 257)")
	assert_lt(refund_pos, sound_pos, "refund/early-return sits ABOVE the celebration beats")
	assert_lt(refund_pos, flash_pos, "refund/early-return sits ABOVE the gold flash")
	assert_lt(refund_pos, toast_pos, "refund/early-return sits ABOVE the toast")

	# All three land before the signal, so external listeners (quest hooks,
	# achievements) can't race the presentation.
	assert_gt(emit_pos, 0, "item_purchased still emitted")
	assert_lt(sound_pos, emit_pos, "presentation precedes the item_purchased emit")


## The success flash must be visually distinct from the pre-existing red
## error flash, or the two outcomes read the same at a glance.
func test_success_flash_is_distinct_from_error_flash() -> void:
	var src := _read(SHOP_SCENE)
	assert_true(src.contains("func _flash_gold_label_success"),
		"dedicated success-flash helper exists")
	assert_true(src.contains("GOLD_FLASH_SUCCESS_COLOR"),
		"success colour is a named constant (tunable without hunting literals)")
	# The error path keeps its red flash — unchanged behaviour.
	var err_idx := src.find("func _flash_gold_label(")
	assert_gt(err_idx, 0, "error flash helper still present")
	var err_next := src.find("\nfunc ", err_idx + 1)
	var err_body: String = src.substr(err_idx, err_next - err_idx) if err_next > 0 else src.substr(err_idx)
	assert_true(err_body.contains("Color.RED"), "error flash still flashes red")
	assert_false(err_body.contains("GOLD_FLASH_SUCCESS_COLOR"),
		"success colour must not leak into the error path")


## Toast hygiene: presentational only. It must not capture input (a
## MOUSE_FILTER default would eat clicks meant for the menu underneath)
## and it must free itself (rapid repeat-buys otherwise leak Labels).
func test_purchase_toast_is_non_capturing_and_self_freeing() -> void:
	var src := _read(SHOP_SCENE)
	var fn_idx := src.find("func _show_purchase_toast")
	assert_gt(fn_idx, 0, "_show_purchase_toast present")
	var next_fn := src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("MOUSE_FILTER_IGNORE"),
		"toast must not capture input meant for the shop menu")
	assert_true(body.contains("queue_free()"),
		"toast must self-free — repeat purchases would otherwise leak Labels")
	assert_true(body.contains("is_instance_valid(toast)"),
		"free is guarded — the scene can close mid-tween")
