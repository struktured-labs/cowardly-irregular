extends GutTest

## Cowir-main's Fable-pass first cut (v3.33.194, commit 18ab8648) added
## `_sprite_half_width` as a helper for HIS contact-gap math. My cycle 7
## (`feature/cowir-battle-melee-contact-alignment`, ad0a14f1) folded
## AFTER his — with its own `_sprite_visible_half_width` helper — and
## overwrote the contact-gap calc that called `_sprite_half_width`.
## `_apply_hitstop` (the surviving consumer of his fable pass) doesn't
## call the width helper; it just iterates over both sprites and
## speed_scales them.
##
## Net: `_sprite_half_width` had ZERO references in the whole codebase
## on origin/main HEAD. Dead code — a fold conflict casualty that would
## eventually rot into confusion (two similarly-named helpers, one
## unused, in the same file).
##
## Cleanup: delete `_sprite_half_width`. Keep `_sprite_visible_half_width`
## (the one the msg 2634 fix tests already pin).

const BS_PATH: String = "res://src/battle/BattleScene.gd"


func test_orphan_sprite_half_width_deleted() -> void:
	# The dead helper must not reappear — a future fold could accidentally
	# resurrect it by taking cowir-main's Fable branch verbatim without
	# checking for the existing _sprite_visible_half_width.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	assert_false(src.find("func _sprite_half_width(sprite: Node2D) -> float:") > -1,
		"the orphan `_sprite_half_width` helper must stay deleted — _sprite_visible_half_width (pinned by test_melee_contact_gap_regression) is the canonical width read")


func test_exactly_one_reach_helper_survives() -> void:
	# Sanity: the cleanup didn't take out the wrong one. The canonical helper is now
	# `sprite_figure_lead` — `_sprite_visible_half_width` measured the FRAME (padding), which stopped every
	# attacker 209-221 px short of contact (test_the_lunge_stops_at_the_body_not_the_frame, 2026-09-16).
	# Both older names must stay gone: two similarly-named helpers in one file is what this file exists for.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	assert_string_contains(src, "static func sprite_figure_lead(sprite: Node2D, toward: float) -> float:",
		"the canonical reach helper must remain — it's what _melee_contact_gap actually calls")
	assert_false(src.find("func _sprite_visible_half_width(") > -1,
		"and the frame-width helper it replaced must not linger beside it")


func test_apply_hitstop_still_present_and_unchanged() -> void:
	# The other half of cowir-main's Fable first cut is _apply_hitstop,
	# which we're deliberately leaving alone. If a future refactor drops
	# it while sweeping the width helper, hitstop dies too and struktured
	# loses the impact-frame emphasis.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	assert_string_contains(src, "func _apply_hitstop(attacker_sprite: Node2D, target_sprite: Node2D) -> void:",
		"cowir-main's _apply_hitstop (Fable pass v3.33.194) must remain — the width-helper cleanup does not touch it")


func test_no_lingering_calls_to_deleted_helper() -> void:
	# If a caller reference lingers after we delete the definition, the
	# next parse fails. Pin here so a future refactor that ADDS a caller
	# needs to also add the definition (or use the canonical helper).
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	assert_false(src.find("_sprite_half_width(") > -1,
		"no CALLS to _sprite_half_width may remain — if you need a sprite's reach, use sprite_figure_lead")
