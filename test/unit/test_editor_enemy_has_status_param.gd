extends GutTest

## Bugfix 2026-07-05: the enemy_has_status condition (v3.33.16) was wired into the
## engine + LLM grammar but NOT the grid editor's param-seeding — so choosing it
## in the MANUAL editor never set its 'status' field (worked via LLM/JSON only,
## silently no-op'd via the editor). Also gave enemy_has_status AND its sibling
## ally_has_status friendly cell labels (both fell through to the raw type-string
## default before). Completes the manual-editor path for the condition.

const GE := preload("res://src/ui/autobattle/AutobattleGridEditor.gd")


func _fmt(cond: Dictionary) -> String:
	var ed = GE.new()
	autofree(ed)
	return ed._format_condition(cond)


func test_enemy_has_status_has_friendly_label() -> void:
	assert_string_contains(_fmt({"type": "enemy_has_status", "status": "stun"}), "Enemy has",
		"enemy_has_status must render a friendly cell label, not the raw type string")


func test_ally_has_status_has_friendly_label() -> void:
	assert_string_contains(_fmt({"type": "ally_has_status", "status": "poison"}), "Ally has",
		"ally_has_status label was raw before — now friendly (sibling consistency)")


func test_seeding_branch_covers_enemy_has_status() -> void:
	# Source-pin: _apply_condition_type must seed a default 'status' for
	# enemy_has_status, else the editor leaves it unset and the condition no-ops.
	var src: String = FileAccess.get_file_as_string("res://src/ui/autobattle/AutobattleGridEditor.gd")
	var idx: int = src.find("func _apply_condition_type")
	assert_gt(idx, -1, "_apply_condition_type must exist")
	var body: String = src.substr(idx, src.find("\nfunc ", idx + 1) - idx)
	var branch_idx: int = body.find("\"has_status\", \"ally_has_status\"")
	assert_gt(branch_idx, -1, "the status-seeding branch must exist")
	assert_string_contains(body.substr(branch_idx, 90), "enemy_has_status",
		"enemy_has_status must be in the status-param seeding branch")
