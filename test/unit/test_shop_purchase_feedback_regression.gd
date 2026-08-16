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
	var flash_pos := body.find("_flash_gold_spend(cost)")
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


## Spend flash (struktured 2026-08-15): the counter flashes RED showing the
## DELTA ("-1000 G"), holds, then settles to the new total in the normal gold
## colour. Distinctness from the error flash comes from CONTENT — the error
## flash never rewrites the text, the spend flash always does.
func test_spend_flash_shows_delta_then_settles() -> void:
	var src := _read(SHOP_SCENE)
	var fn_idx := src.find("func _flash_gold_spend")
	assert_gt(fn_idx, 0, "spend-flash helper exists")
	var next_fn := src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_gold_spend_flash_text(cost)"),
		"the flash must SHOW the delta, not just recolour the total")
	assert_true(body.contains("GOLD_SPEND_FLASH_COLOR"),
		"spend colour is a named constant (tunable without hunting literals)")
	assert_true(body.contains("_settle_gold_label"),
		"the flash must settle back to the real total — else the counter lies forever")
	var settle_idx := src.find("func _settle_gold_label")
	assert_gt(settle_idx, 0, "settle helper exists")
	var settle_next := src.find("\nfunc ", settle_idx + 1)
	var settle: String = src.substr(settle_idx, settle_next - settle_idx) if settle_next > 0 else src.substr(settle_idx)
	assert_true(settle.contains("_update_gold_display()"),
		"settle must re-read the REAL gold total from game_state")
	assert_true(settle.contains("GOLD_LABEL_COLOR"),
		"settle restores the canonical label colour, never a snapshot of a mid-flash colour")


func test_spend_flash_delta_text_format() -> void:
	var shop = preload(SHOP_SCENE).new()
	autofree(shop)  # pure helper, no _ready / tree needed
	assert_eq(shop._gold_spend_flash_text(1000), "-1000 G", "delta reads as a reduction")
	assert_eq(shop._gold_spend_flash_text(76), "-76 G", "small costs format identically")


## The magic-shop path was SILENT commerce until 2026-08-15 — sounds on every
## error branch, nothing on success (struktured: "we need a purchase sound").
func test_magic_purchase_success_has_sound_and_flash() -> void:
	var src := _read(SHOP_SCENE)
	var fn_idx := src.find("func _attempt_magic_purchase")
	assert_gt(fn_idx, 0, "_attempt_magic_purchase present")
	var next_fn := src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	var spend_pos := body.find("spend_gold(cost)")
	var sound_pos := body.find("play_ui(\"purchase_complete\")")
	var flash_pos := body.find("_flash_gold_spend(cost)")
	assert_gt(spend_pos, 0, "magic path spends gold")
	assert_gt(sound_pos, spend_pos, "ka-ching fires AFTER the successful spend, never on an error branch")
	assert_gt(flash_pos, spend_pos, "gold spend-flash fires after the successful spend")


## Inn rests are the same commerce class — both inn flows must ka-ching on the
## paid rest (sibling enumeration: every success-side spend_gold gets a cue).
func test_inn_rests_play_the_purchase_sound() -> void:
	for path in ["res://src/exploration/VillageInn.gd", "res://src/maps/interiors/InnInterior.gd"]:
		var src := FileAccess.get_file_as_string(path)
		var spend := src.find("spend_gold(")
		assert_gt(spend, 0, "%s spends gold for a rest" % path)
		assert_gt(src.find("play_ui(\"purchase_complete\")", spend), spend,
			"%s must confirm the paid rest audibly" % path)


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
