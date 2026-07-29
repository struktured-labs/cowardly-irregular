extends GutTest

## Regression test for silent binding LOSS when a controller profile is applied.
##
## InputProfileManager._replace_joypad_buttons is destructive by design: it erases every
## InputEventJoypadButton on an action, then adds the profile's list. So a profile that lists fewer
## buttons than project.godot declares silently DELETES the remainder — no warning, no error, and
## nothing on screen. `ui_menu` is declared [6, 7] and two profiles listed only [6], so button 7 was
## dropped at boot for a week before anyone noticed (cowir-main called it out while fixing
## PROFILE_STANDARD, and the same drop was left in SN30 and ULTIMATE_PRO_2).
##
## The invariant is deliberately about COUNT, not exact indices: a profile MAY remap (the Ultimate
## Pro 2 profile intentionally swaps advance/defer to match that device's hardware) but must not
## quietly reduce how many ways an action can be triggered. That distinction is what keeps this a
## real guard instead of an allowlist — every current profile passes with zero exceptions.

var _ipm


## Built-in profiles, DERIVED at runtime from the script's own constant map.
##
## This was a hand-written list of three, built on my conclusion that consts are unreachable —
## Object.get() does silently return null for them, which is true and was the wrong lesson. They ARE
## reachable via Script.get_script_constant_map(), values included, so the list is deleted rather
## than guarded: a fourth profile is covered by every test in this file the moment it is declared.
##
## Keyed on VALUE SHAPE, not on the PROFILE_ naming convention — cowir-sfx's sharpening of
## cowir-ai's rule (2026-07-29): derive from something true of the THING, not true of how the thing
## is WRITTEN. A binding profile is a dict of action -> button-list; that is what one IS. Matching
## the name prefix would be matching a spelling, and a profile named anything else would silently
## leave the set and take its own assertions with it.
func _profiles() -> Dictionary:
	var out := {}
	var script: Script = load("res://src/input/InputProfileManager.gd")
	for key in script.get_script_constant_map():
		var value = script.get_script_constant_map()[key]
		if not value is Dictionary or (value as Dictionary).is_empty():
			continue
		var every_value_is_a_button_list := true
		for action in value:
			if not value[action] is Array:
				every_value_is_a_button_list = false
		if every_value_is_a_button_list:
			out[str(key)] = value
	return out


## Vacuity control for the derivation above. If the shape filter stops matching — a renamed API, a
## profile that grows a non-Array member — every loop in this file iterates an empty set and all of
## it passes having checked no profile at all. A derived set fails silently in a way a hand list
## cannot, and that is the price of deleting the list.
func test_the_profile_derivation_actually_finds_the_profiles() -> void:
	var found := _profiles()
	assert_gt(found.size(), 2, "the shape filter must still match real binding profiles — an empty or tiny set makes every other test here vacuous")
	for known in ["PROFILE_STANDARD", "PROFILE_SN30", "PROFILE_ULTIMATE_PRO_2"]:
		assert_true(found.has(known), "derivation must still find the known profile '%s'" % known)
	assert_false(found.has("PROFILE_NAMES"), "PROFILE_NAMES is an Array of labels, not a binding profile — the filter must discriminate, or it is matching everything")
	assert_false(found.has("ACTION_LABELS"), "ACTION_LABELS maps action -> String, not action -> button list; if it enters the set the shape filter is not filtering")


func before_each() -> void:
	_ipm = load("res://src/input/InputProfileManager.gd").new()


func after_each() -> void:
	if is_instance_valid(_ipm):
		_ipm.free()


## project.godot's ORIGINAL declaration, read from ProjectSettings so it is unaffected by whatever
## the live InputMap has been rewritten to at runtime.
func _declared_joypad_buttons(action: String) -> Array:
	var setting := "input/%s" % action
	if not ProjectSettings.has_setting(setting):
		return []
	var buttons: Array = []
	for event in ProjectSettings.get_setting(setting).get("events", []):
		if event is InputEventJoypadButton:
			buttons.append((event as InputEventJoypadButton).button_index)
	buttons.sort()
	return buttons


## DISTINCT buttons, not list length. The invariant is "how many ways can the player trigger this",
## and `[6, 6]` is one way written twice — raw length says two and means one.
##
## cowir-sfx's predicate question (2026-07-29): a count is a proxy for the thing it counts, exactly
## as `contains` is a proxy for equality. Measured before changing it: `ui_menu: [6, 7]` mutated to
## `[6, 6]` does go red today, but via the NAMED PIN below, not via this general guard — and
## `ui_menu` is the only action in any profile with more than one button, so the loose predicate
## here is currently unexercisable. Caught by luck of which action happens to have two bindings, and
## a second multi-button action would arrive uncovered.
func _distinct_count(values: Array) -> int:
	var seen := {}
	for v in values:
		seen[v] = true
	return seen.size()


func test_no_profile_silently_reduces_a_binding_count() -> void:
	var losses: Array[String] = []
	var profiles := _profiles()
	for profile_name in profiles:
		var profile: Dictionary = profiles[profile_name]
		for action in _ipm.REMAPPABLE_ACTIONS:
			var declared := _declared_joypad_buttons(action)
			if declared.is_empty() or not profile.has(action):
				continue
			var mapped: Array = profile[action]
			if _distinct_count(mapped) < _distinct_count(declared):
				losses.append("%s.%s has %d distinct binding(s) but project.godot declares %d (%s vs %s)"
					% [profile_name, action, _distinct_count(mapped), _distinct_count(declared), str(mapped), str(declared)])
	assert_eq(losses, [] as Array[String],
		"applying a profile erases ALL joypad buttons then re-adds only its own, so a shorter list is silent deletion:\n%s" % "\n".join(losses))


## The specific case that regressed. Pinned by name so a future "tidy up, 7 isn't Start" edit has to
## be deliberate — under Godot 4 button 7 is L3, and project.godot binds it on purpose.
func test_ui_menu_keeps_both_declared_buttons_in_every_profile() -> void:
	var declared := _declared_joypad_buttons("ui_menu")
	assert_eq(declared, [6, 7], "project.godot is expected to declare START and L3 for ui_menu")
	var profiles := _profiles()
	for profile_name in profiles:
		var profile: Dictionary = profiles[profile_name]
		assert_eq(profile["ui_menu"], [6, 7],
			"%s must keep both — dropping 7 makes the menu unreachable from L3 with no warning" % profile_name)


## Remapping must stay legal, or the guard above would forbid the Ultimate Pro 2's measured
## hardware quirk. Same count, different index = fine.
func test_deliberate_remapping_is_still_permitted() -> void:
	var pro2: Dictionary = _ipm.PROFILE_ULTIMATE_PRO_2
	var standard: Dictionary = _ipm.PROFILE_STANDARD
	assert_ne(pro2["battle_advance"], standard["battle_advance"],
		"the Ultimate Pro 2 profile is expected to differ — it encodes a device-specific swap")
	assert_eq(pro2["battle_advance"].size(), standard["battle_advance"].size(),
		"a remap preserves the binding COUNT; only the index changes")


## Closes a hole in this file's OWN exemption, found by re-reading it rather than by a failure.
##
## The count invariant above deliberately permits REMAPPING — same number of bindings, different
## index — so the Ultimate Pro 2's measured swap stays legal. But "count preserved" says nothing
## about whether the new index exists: [6, 7] -> [6, 99] passes the count check while binding a
## button no controller sends, and the action would be silently unreachable on every pad.
##
## BUTTON_LABELS is the right authority because it is the same table the remap UI renders — an index
## outside it displays as a bare "Button 99" to the player, which is the visible symptom.
func test_every_profile_button_index_is_a_real_button() -> void:
	var unknown: Array[String] = []
	var profiles := _profiles()
	for profile_name in profiles:
		var profile: Dictionary = profiles[profile_name]
		for action in profile:
			for index in profile[action]:
				if not _ipm.BUTTON_LABELS.has(index):
					unknown.append("%s.%s -> button %s" % [profile_name, action, str(index)])
	assert_eq(unknown, [] as Array[String],
		"a profile binds an index with no known button — the count guard permits remapping, so nothing else catches an index that simply does not exist: %s" % str(unknown))


## Every remappable action must actually be covered by every profile, or applying that profile
## erases the action's joypad bindings and leaves nothing behind.
func test_every_profile_covers_every_remappable_action() -> void:
	var profiles := _profiles()
	for profile_name in profiles:
		var profile: Dictionary = profiles[profile_name]
		for action in _ipm.REMAPPABLE_ACTIONS:
			assert_true(profile.has(action),
				"%s is missing '%s' — apply_profile skips absent actions, so it would keep whatever the previous profile left behind" % [profile_name, action])
