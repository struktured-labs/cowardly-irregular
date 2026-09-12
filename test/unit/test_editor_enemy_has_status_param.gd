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


func test_every_condition_type_has_a_friendly_label() -> void:
	# Sync guard (mirrors the target-label guard): no engine condition may render
	# as raw snake_case in the grid. Pre-fix ally_mp_percent / item_count /
	# setup_complete (and the two status ones) fell through to the raw default.
	var ed = GE.new()
	autofree(ed)
	for key in AutobattleSystem.CONDITION_TYPES.keys():
		var label: String = ed._format_condition({"type": str(key)})
		assert_ne(label, str(key),
			"condition '%s' falls through to raw snake_case in the grid — add a _format_condition label" % key)


func test_seeding_branch_covers_EVERY_status_condition() -> void:
	# Source-pin: _apply_condition_type must seed a default 'status' for every condition that
	# takes one, else the editor leaves it unset and the condition no-ops in the manual path.
	#
	# ⚠️ Was pinned to the literal `"has_status", "ally_has_status"` and a 90-char window after it,
	# so it asserted the ORDER of an unordered list: adding not_has_status BETWEEN those two redded
	# a correct change while a genuinely unseeded condition appended to the end would have passed.
	# The corpus is now DERIVED from CONDITION_REQUIRED_FIELD, so the next status condition is
	# covered the day it is added rather than the day someone remembers this file.
	var abs_node = Engine.get_main_loop().root.get_node_or_null("AutobattleSystem")
	if abs_node == null:
		pending("AutobattleSystem autoload required")
		return
	var want: Array = []
	for k in (abs_node.CONDITION_REQUIRED_FIELD as Dictionary).keys():
		if str((abs_node.CONDITION_REQUIRED_FIELD as Dictionary)[k]) == "status":
			want.append(str(k))
	want.sort()
	assert_gt(want.size(), 2, "CONTROL: several conditions take a status (%s)" % str(want))

	var src: String = FileAccess.get_file_as_string("res://src/ui/autobattle/AutobattleGridEditor.gd")
	var idx: int = src.find("func _apply_condition_type")
	assert_gt(idx, -1, "_apply_condition_type must exist")
	var body: String = src.substr(idx, src.find("\nfunc ", idx + 1) - idx)
	var branch: String = ""
	for line in body.split("\n"):
		if line.contains("new_type in [") and line.contains("has_status"):
			branch = line
			break
	assert_ne(branch, "", "the status-seeding branch must exist in _apply_condition_type")
	var missing: Array = []
	for id in want:
		if not branch.contains("\"%s\"" % id):
			missing.append(id)
	assert_eq(missing.size(), 0,
		"a condition takes a 'status' but the editor never seeds one, so picking it in the manual "
		+ "editor leaves the field unset and the rule no-ops: " + str(missing))
