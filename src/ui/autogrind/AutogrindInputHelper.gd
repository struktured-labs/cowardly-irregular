extends RefCounted
class_name AutogrindInputHelper

## Shared input classification for AutogrindMonitor/AutogrindDashboard.
## Both panels react to the same controller/keyboard shortcuts, so we route
## events to named actions here to avoid duplicating the dispatch table.
##
## Returns one of: "pause", "adjust_rules", "exit", "tier_cycle", or "".
static func classify_event(event: InputEvent) -> String:
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_BACK:
				return "pause"
			JOY_BUTTON_START:
				return "adjust_rules"
			JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER:
				if Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER) \
						and Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER):
					return "tier_cycle"
	elif event.is_action_pressed("ui_cancel") and not event.is_echo():
		return "exit"
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_P:
				return "pause"
			KEY_R:
				return "adjust_rules"
			KEY_T:
				return "tier_cycle"
	return ""


## The KEY this classifier binds for each action — the single place the fallbacks are written down,
## so a footer legend cannot name a key classify_event does not accept.
## The KEYBOARD key each action offers. "exit" is here too, so the no-profile-manager fallback below
## reads from this one table instead of carrying its own literal.
const ACTION_KEYS := {"pause": "P", "adjust_rules": "R", "tier_cycle": "T", "exit": "X"}


## The button token a legend should print for one of classify_event's actions, resolved against the
## pad in the player's hands. It lives HERE, beside the dispatch table, because both footers named
## "Select" and "Start" — the SNES vocabulary — for raw indices 4 and 6, which no Xbox, PlayStation
## or Switch pad carries, and told a keyboard player nothing at all about P/R/T.
static func hint_for(action_name: String, device_name: String = "") -> String:
	if action_name == "exit":
		# ui_cancel is a face button: hint_for_action already names it per family AND falls back to
		# the key, so "exit" needs no branch of its own here.
		var ipm := _profile_manager()
		## ⛔ The fallback was the literal "B" — a NINTENDO/SNES name, in the one helper whose own
		## docstring says it exists because footers "named 'Select' and 'Start' — the SNES vocabulary".
		## Only reachable with no InputProfileManager (absent autoload / bare instance), so no player
		## saw it, but it is the same defect this file was written to remove and it would print "B" to
		## every family the moment it became live. The keyboard key is the honest answer when nothing
		## is known about the pad, and it now comes from ACTION_KEYS rather than from a literal here.
		return str(ipm.hint_for_action("ui_cancel", device_name)) if ipm else str(ACTION_KEYS.get("exit", ""))
	var pad := _pad_token(action_name, device_name)
	return pad if pad != "" else str(ACTION_KEYS.get(action_name, ""))


static func _pad_token(action_name: String, device_name: String = "") -> String:
	var ipm := _profile_manager()
	if ipm == null:
		return ""
	match action_name:
		"pause":
			return str(ipm.button_name_for_index(JOY_BUTTON_BACK, device_name))
		"adjust_rules":
			return str(ipm.button_name_for_index(JOY_BUTTON_START, device_name))
		"tier_cycle":
			# Both shoulders, each named by the family: L+R · LB+RB · L1+R1.
			var l: String = str(ipm.button_name_for_index(JOY_BUTTON_LEFT_SHOULDER, device_name))
			var r: String = str(ipm.button_name_for_index(JOY_BUTTON_RIGHT_SHOULDER, device_name))
			return "%s+%s" % [l, r] if l != "" and r != "" else ""
	return ""


## Static context, so the SettingsMenu idiom needs the tree reached explicitly.
static func _profile_manager() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree and loop.root:
		var n: Node = loop.root.get_node_or_null("/root/InputProfileManager")
		if n and n.has_method("button_name_for_index") and n.has_method("hint_for_action"):
			return n
	return null


## The F1 reference's WHILE AUTOGRINDING rows, resolved against the pad in the player's hands.
## ⛔ These describe GameLoop's `LoopState.AUTOGRIND` branch, NOT classify_event above. While a grind
## runs, AutogrindUI sets `visible = false` and nothing calls `_show_monitor()`, so the dispatch table
## in this file is not the live surface -- that branch is. The reference was written against this file
## and advertised two controls the branch did not have: "Back (Minus): Pause" (pause was KEY_P only
## there -- index 4 is now bound, so the row keeps a pad cell) and "Start (Plus): Adjust rules", which
## is bound on neither device and whose signal GameLoop never connects. It also called turbo's button
## the "west face" when JOY_BUTTON_Y is the NORTH face, and named stop "B", which is the south face's
## Nintendo letter -- Xbox prints A there and PlayStation prints Cross.
const REFERENCE_PAD_NONE := "—"
const REFERENCE_COL := 18


## `device_name` is the test hook the rest of this lane uses: both helpers below take the pad path
## when given one, so a guard can pin the Xbox/PlayStation/Switch rendering with no pad attached.
static func grind_reference_rows(device_name: String = "") -> String:
	var ipm := _profile_manager()
	# No pad, no pad cell: naming one family's button to a player holding another IS the defect.
	var pad_ok: bool = ipm != null and (device_name != "" or not Input.get_connected_joypads().is_empty())
	var turbo: String = str(ipm.button_name_for_index(JOY_BUTTON_Y, device_name)) if pad_ok else ""
	var l: String = str(ipm.button_name_for_index(JOY_BUTTON_LEFT_SHOULDER, device_name)) if pad_ok else ""
	var r: String = str(ipm.button_name_for_index(JOY_BUTTON_RIGHT_SHOULDER, device_name)) if pad_ok else ""
	var stop: String = str(ipm.hint_for_action("ui_cancel", device_name)) if pad_ok else ""
	# By ACTION, so the cell follows a Controls rebind the way the handler does. A raw index here
	# would keep printing "Back" after the player moved the button.
	var pause: String = str(ipm.hint_for_action("battle_toggle_auto", device_name)) if pad_ok else ""
	var tier: String = ("%s+%s" % [l, r]) if l != "" and r != "" else ""
	var rows: Array = [
		[_reference_cell(pause), str(ACTION_KEYS["pause"]), "[color=lime]Pause / resume the grind[/color]"],
		[_reference_cell(tier), str(ACTION_KEYS["tier_cycle"]), "Cycle monster tier"],
		[_reference_cell(turbo), "Y", "Turbo — run it faster"],
		[_reference_cell(stop), "%s / Esc" % str(ACTION_KEYS["exit"]), "Stop grinding and return"],
	]
	var out := ""
	for row in rows:
		out += "%-*s%-*s%s\n" % [REFERENCE_COL, row[0], REFERENCE_COL, row[1], row[2]]
	return out


static func _reference_cell(token: String) -> String:
	return token if token != "" else REFERENCE_PAD_NONE

