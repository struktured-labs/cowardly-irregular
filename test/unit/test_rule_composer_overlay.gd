extends GutTest

## Regression/unit tests for RuleComposerOverlay (Task 13).
##
## Covers the headless-safe public API: open() stores domain/character_id,
## cancel() emits cancelled, and the installed/cancelled signal shapes exist.
## The overlay is instantiated via RuleComposerOverlay.new() (no .tscn), so
## every UI-node write inside the script must be null-guarded — these tests
## double as a check that instantiating the bare script never crashes.

const RuleComposerOverlay := preload("res://src/ui/autobattle/RuleComposerOverlay.gd")


func test_open_stores_domain_and_character_id() -> void:
	var overlay = RuleComposerOverlay.new()
	add_child_autofree(overlay)
	overlay.open("autobattle", "mage", [])
	assert_eq(overlay.get_domain(), "autobattle")
	assert_eq(overlay.get_character_id(), "mage")


func test_emits_cancelled_on_cancel() -> void:
	var overlay = RuleComposerOverlay.new()
	add_child_autofree(overlay)
	watch_signals(overlay)
	overlay.open("autobattle", "mage", [])
	overlay.cancel()
	assert_signal_emitted(overlay, "cancelled")


func test_signal_shape_installed_carries_index() -> void:
	var overlay = RuleComposerOverlay.new()
	add_child_autofree(overlay)
	assert_true(overlay.has_signal("installed"))
	assert_true(overlay.has_signal("cancelled"))


func test_confirm_new_profile_at_cap_shows_error_not_success() -> void:
	# Regression: cap-reached (-1 return) must NOT emit installed as success.
	var autobattle = get_node_or_null("/root/AutobattleSystem")
	assert_not_null(autobattle)
	var test_pc := "test_overlay_pc_at_cap"
	# Wipe first (idempotent cleanup).
	if autobattle.character_profiles.has(test_pc):
		autobattle.character_profiles.erase(test_pc)
	# Fill to cap.
	for i in range(8):
		var _idx = autobattle.install_composition_as_new_profile(test_pc, {"name": "fill_%d" % i, "description":"", "rules": []})
	# Confirm we're at cap.
	var at_cap: int = autobattle.install_composition_as_new_profile(test_pc, {"name": "overflow", "description":"", "rules": []})
	assert_eq(at_cap, -1, "sanity: install at cap must return -1")
	# Now build overlay, force a composition, attempt confirm with replace_current=false.
	var overlay = RuleComposerOverlay.new()
	add_child_autofree(overlay)
	watch_signals(overlay)
	overlay.open("autobattle", test_pc, [])
	# Directly set _last_composition (simulating a compose success).
	overlay._last_composition = {"name": "capped_attempt", "description": "", "rules": [{"condition": [], "actions": []}]}
	overlay.confirm(false)
	# Overlay must NOT emit installed on cap-reached.
	assert_signal_not_emitted(overlay, "installed",
		"confirm at cap must not silently claim success — emit no installed signal")
	# Cleanup.
	autobattle.character_profiles.erase(test_pc)
	autobattle._save_character_profiles()


func test_confirm_replace_current_carries_description() -> void:
	# Regression: replace-in-place must copy composition.description into stored script.
	var autobattle = get_node_or_null("/root/AutobattleSystem")
	var test_pc := "test_overlay_pc_replace_desc"
	if autobattle.character_profiles.has(test_pc):
		autobattle.character_profiles.erase(test_pc)
	# Prime with an install (creates a profile).
	autobattle.install_composition_as_new_profile(test_pc, {"name": "seed", "description": "seed_desc", "rules": []})
	var overlay = RuleComposerOverlay.new()
	add_child_autofree(overlay)
	overlay.open("autobattle", test_pc, [])
	overlay._last_composition = {"name": "replaced", "description": "new_desc_marker", "rules": [{"condition": [], "actions": []}]}
	overlay.confirm(true)  # replace_current
	# Check the active profile now carries the description.
	var active_idx: int = autobattle.character_profiles[test_pc]["active"]
	var profile: Dictionary = autobattle.character_profiles[test_pc]["profiles"][active_idx]
	var script: Dictionary = profile.get("script", {})
	assert_eq(str(script.get("description", "")), "new_desc_marker",
		"replace-in-place must carry composition.description into the stored script")
	# Cleanup.
	autobattle.character_profiles.erase(test_pc)
	autobattle._save_character_profiles()
