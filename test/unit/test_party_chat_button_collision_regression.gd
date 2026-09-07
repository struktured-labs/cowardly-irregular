extends GutTest

## Regression test for the Select/Back (gamepad button 4) double-bind bug.
##
## Bug (2026-06-14): In project.godot's [input] section, both
## battle_toggle_auto AND party_chat were bound to InputEventJoypadButton
## button_index 4 (BACK/Select/Minus). GameLoop._input() is a single function
## that, on a button-4 press in EXPLORATION, first calls _toggle_all_autobattle()
## (the JOY_BUTTON_BACK guard) and then — because set_input_as_handled() does NOT
## abort the local handler — falls through to the party_chat branch and opens the
## chat menu. Net effect: one Select press both flipped ALL autobattle and opened
## party chat (and when no chats were available, silently flipped autobattle).
##
## Fix: rebind party_chat's gamepad event off button 4 onto the L shoulder
## (button_index 9) — matching the advertised "[L] Party Chat" hint in
## PartyChatIndicator.gd — so it no longer collides with battle_toggle_auto.
## battle_defer also uses button 9, but only in BATTLE; party_chat only fires in
## EXPLORATION, so the two never compete on the same physical button in the same
## context.
##
## This test scans the live InputMap (loaded from project.godot) and asserts no
## gamepad button_index is shared by two exploration-relevant actions.

# Actions that GameLoop._input() can act on during EXPLORATION. If any two of
# these share a gamepad button_index, a single press double-fires.
const EXPLORATION_ACTIONS := ["battle_toggle_auto", "party_chat"]


func _joypad_buttons_for(action: String) -> Array:
	var buttons := []
	if not InputMap.has_action(action):
		return buttons
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton:
			buttons.append(ev.button_index)
	return buttons


func test_no_shared_gamepad_button_among_exploration_actions() -> void:
	# Map each gamepad button_index -> list of exploration actions using it.
	var button_owners := {}
	for action in EXPLORATION_ACTIONS:
		assert_true(InputMap.has_action(action), "action should exist: %s" % action)
		for btn in _joypad_buttons_for(action):
			if not button_owners.has(btn):
				button_owners[btn] = []
			button_owners[btn].append(action)

	for btn in button_owners.keys():
		var owners: Array = button_owners[btn]
		assert_eq(
			owners.size(), 1,
			"gamepad button_index %d is shared by exploration actions %s — a single press double-fires" % [btn, str(owners)]
		)


func test_party_chat_uses_l_shoulder_not_select() -> void:
	# party_chat must NOT use button 4 (Select/Back, owned by battle_toggle_auto)
	# and should use the L shoulder (button 9) to match the in-game hint.
	var party_buttons := _joypad_buttons_for("party_chat")
	assert_false(party_buttons.has(4), "party_chat must not bind gamepad button 4 (Select/Back collides with battle_toggle_auto)")
	assert_true(party_buttons.has(9), "party_chat should bind the L shoulder (gamepad button 9)")


func test_battle_toggle_auto_still_owns_select() -> void:
	# Sanity: the fix should NOT have moved battle_toggle_auto off Select.
	var toggle_buttons := _joypad_buttons_for("battle_toggle_auto")
	assert_true(toggle_buttons.has(4), "battle_toggle_auto should still bind gamepad button 4 (Select/Back)")
