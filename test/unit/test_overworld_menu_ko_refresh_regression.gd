extends GutTest

## Playtest 2026-07-15: gave Phoenix Down to Bard in the field menu,
## Bard still shows KO status even though HP restored.
##
## Root: _create_party_card only appended the DeadOverlay + DeadLabel
## nodes when member.is_alive was false at first build. _update_party_stats
## (the fast-refresh path called by _on_submenu_closed) refreshed HP/MP
## text and bars but never touched the KO overlay. Revive → HP bar filled
## but red overlay + "KO" label persisted.
##
## Fix: always stamp DeadOverlay + DeadLabel nodes on card build (named,
## visibility=is_alive gated); refresh their .visible in _update_party_stats.


func test_dead_overlay_always_added_with_name() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/OverworldMenu.gd")
	# Anchor on the create-card function's KO-indicator region.
	var i := src.find("var dead_overlay = ColorRect.new()")
	assert_gt(i, -1, "DeadOverlay creation must exist")
	var window := src.substr(i, 500)
	assert_true("dead_overlay.name = \"DeadOverlay\"" in window,
		"overlay must have a stable name so _update_party_stats can look it up on refresh")
	assert_true("dead_overlay.visible = not member.is_alive" in window,
		"overlay visibility must be driven by is_alive at build — refresh path toggles the same property")


func test_dead_label_always_added_with_name() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/OverworldMenu.gd")
	var i := src.find("dead_label.text = \"KO\"")
	assert_gt(i, -1, "KO label creation must exist")
	var window := src.substr(maxi(0, i - 200), 500)
	assert_true("dead_label.name = \"DeadLabel\"" in window,
		"KO label must have a stable name for refresh lookup")
	assert_true("dead_label.visible = not member.is_alive" in window,
		"KO label visibility must be driven by is_alive at build")


func test_update_party_stats_refreshes_ko_visibility() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/OverworldMenu.gd")
	var i := src.find("func _update_party_stats")
	assert_gt(i, -1)
	var next: int = src.find("\nfunc ", i + 1)
	var body := src.substr(i, (next - i) if next > -1 else 1200)
	assert_true("get_node_or_null(\"DeadOverlay\")" in body,
		"_update_party_stats must look up DeadOverlay by name")
	assert_true("get_node_or_null(\"DeadLabel\")" in body,
		"_update_party_stats must look up DeadLabel by name")
	assert_true("dead_overlay.visible = not member.is_alive" in body,
		"overlay .visible must be re-driven from is_alive on every refresh — the whole point of the fix")
	assert_true("dead_label.visible = not member.is_alive" in body,
		"label .visible must be re-driven from is_alive on every refresh")
