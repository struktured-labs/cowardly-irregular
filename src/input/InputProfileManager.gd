extends Node

## InputProfileManager - Manages controller button profiles and runtime remapping.
## Handles 8BitDo SN30, 8BitDo Ultimate Pro 2, and Custom profiles.
## Persists custom bindings to user://input/controls.json.

const CONFIG_PATH = "user://input/controls.json"
const CONFIG_VERSION = 3

## Remappable actions (gamepad only - keyboard stays fixed)
const REMAPPABLE_ACTIONS = [
	"ui_accept",
	"ui_cancel",
	"battle_advance",
	"battle_defer",
	"battle_toggle_auto",
	"ui_menu",
	"battle_open_log",
	"ui_field_menu",
]

## Human-readable labels for actions
const ACTION_LABELS = {
	## ⛔ WAS "Menu" — THE SAME STRING ui_menu CARRIES, on the screen whose entire job is naming
	## controls. Settings → Controls listed two rows both reading "Menu", one bound to the north face
	## and one to Start, with nothing on either row saying which opened what; the conflict line and
	## the Test Buttons overlay read them out of the same table, so sharing a button printed
	## "Menu & Menu". The same ambiguity already cost a hint: TutorialHints' quest-log line used
	## {menu} — ui_menu, which opens SETTINGS in the field — and sent a lost player to a menu with no
	## Quest Log. This action only ever opens the overworld menu (party, items, quests, save), and
	## "field" is already player-facing vocabulary in the controls reference ("Party Chat (in the
	## field)"). ui_menu keeps the bare "Menu": it is context-dependent (Settings in exploration,
	## the autobattle editor in battle, the grind toggle in autogrind), so no one screen name fits.
	"ui_field_menu": "Field Menu",
	"ui_accept": "Confirm",
	"ui_cancel": "Cancel",
	"battle_advance": "Advance",
	"battle_defer": "Defer",
	"battle_toggle_auto": "Toggle Auto",
	"ui_menu": "Menu",
	"battle_open_log": "Battle Log",
}

## Confirm sits on the EAST face when true — the SNES layout (Y X / B A). False puts it on
## SOUTH, native for Xbox and PlayStation. Every profile below is authored EAST-confirm and
## this derives the other convention, so there is one table instead of two that can drift.
var nintendo_mode: bool = true

## NON-FACE buttons have no glyph — FACE_GLYPHS only covers 0-3 — so glyph_for_action returns "?"
## for Select, Start, L3 and the shoulders, and a legend that fell back to the keyboard key then
## showed "Tab" to a pad player. These are the five indices the profiles actually bind.
const BUTTON_NAMES := {
	"nintendo": {4: "Minus", 6: "Plus", 7: "L-Stick", 9: "L", 10: "R"},
	"xbox": {4: "Back", 6: "Start", 7: "L3", 9: "LB", 10: "RB"},
	"playstation": {4: "Share", 6: "Options", 7: "L3", 9: "L1", 10: "R1"},
}

## Face glyphs keyed by BUTTON INDEX (position) — SDL numbers by position, the silkscreen
## differs per family. All verified to render through FontFallbacks; squared 🅰/🅱 are tofu.
const FACE_GLYPHS := {
	"nintendo": {0: "Ⓑ", 1: "Ⓐ", 2: "Ⓨ", 3: "Ⓧ"},
	"xbox": {0: "Ⓐ", 1: "Ⓑ", 2: "Ⓧ", 3: "Ⓨ"},
	"playstation": {0: "✕", 1: "○", 2: "□", 3: "△"},
}

## Device-name substrings -> face-glyph family. First match wins; unmatched gets xbox, because
## an unknown pad on Windows is overwhelmingly an XInput device.
const FACE_FAMILY_HINTS := [
	["dualsense", "playstation"], ["dualshock", "playstation"], ["ps5", "playstation"],
	["ps4", "playstation"], ["playstation", "playstation"], ["sony", "playstation"],
	["switch", "nintendo"], ["nintendo", "nintendo"], ["pro controller", "nintendo"],
	["snes", "nintendo"], ["sn30", "nintendo"], ["8bitdo", "nintendo"],
]

## Built-in profile definitions: action -> button index(es)
## Button indices use the GODOT 4 JoyButton enum (matches SDL2 normalized):
##   0  = A          (Nintendo B / PS Cross / Xbox A — SOUTH face button)
##   1  = B          (Nintendo A / PS Circle / Xbox B — EAST face button)
##   2  = X          (Nintendo Y / PS Square / Xbox X — WEST face button)
##   3  = Y          (Nintendo X / PS Triangle / Xbox Y — NORTH face button)
##   4  = BACK       (Nintendo MINUS / PS Select / Xbox Back)
##   5  = GUIDE      (Nintendo HOME / PS Home / Xbox Guide)
##   6  = START      (Nintendo PLUS / PS Start / Xbox Start)
##   7  = LEFT_STICK (L3 click)
##   8  = RIGHT_STICK (R3 click)
##   9  = LEFT_SHOULDER  (Nintendo L / PS L1 / Xbox LB)
##   10 = RIGHT_SHOULDER (Nintendo R / PS R1 / Xbox RB)
##   11-14 = D-Pad U/D/L/R
##   Triggers (ZL/ZR / L2/R2 / LT/RT) are AXES 4/5, not buttons —
##   handled by motion events in project.godot, not here.
##
## Bug fix (2026-05-02): the prior PROFILE_ULTIMATE_PRO_2 used Godot 3's
## button numbers (4=LB, 5=RB, 6=Back, 7=Start) which silently misfired in
## Godot 4 — Start (button 6) was bound to battle_toggle_auto, so pressing
## Plus on Switch Pro would auto-enable autobattle every time. Both
## profiles now use Godot 4 numbers consistently.
## Mirrors project.godot exactly — correct for any pad SDL NORMALIZES, i.e. one `Input.is_joy_known()` reports true for.
## Standard semantics come from SDL having a GUID mapping, NOT from the device's evdev codes being tidy. The 8BitDo
## Ultimate 2 IS bound by xpad (1-9.2:1.0 -> xpad, measured 2026-07-25) and so reports textbook BTN_A/BTN_TL/ABS_HAT0 —
## and it STILL arrives raw, because Godot's bundled DB lacks its product id. Tidy codes are necessary, not sufficient:
## without a GUID entry Godot passes evdev ORDER through, so BTN_TL lands on index 4 (Back) instead of 9 (LeftShoulder).
## That is what put toggle-all-autobattle on struktured's physical L for ~6 months. ControllerMappings supplies the
## missing mapping; without that autoload this profile is wrong for that pad.
const PROFILE_STANDARD = {
	"ui_accept": [1],          # B (East face)
	"ui_cancel": [0],          # A (South face)
	"battle_advance": [10],    # RIGHT_SHOULDER (R) — matches "[R] Advance" hint bar
	"battle_defer": [9],       # LEFT_SHOULDER (L) — matches "[L] Defer" hint bar
	"battle_toggle_auto": [4], # BACK (Select/Minus)
	"ui_menu": [6],             # START. L3 moved to battle_open_log 2026-10-04 (struktured: "reuse L3"), deliberately, not dropped
	"battle_open_log": [7],    # L3 — the full battle log
	"ui_field_menu": [3],     # NORTH face — the field menu, rebindable since 2026-10-12
}

const PROFILE_SN30 = {
	"ui_accept": [1],          # B (East face)
	"ui_cancel": [0],          # A (South face)
	"battle_advance": [10],    # RIGHT_SHOULDER (R)
	"battle_defer": [9],       # LEFT_SHOULDER (L)
	"battle_toggle_auto": [4], # BACK (Select/Minus)
	"ui_menu": [6],             # START. L3 moved to battle_open_log 2026-10-04 (struktured: "reuse L3"), deliberately, not dropped
	"battle_open_log": [7],    # L3 — the full battle log
	"ui_field_menu": [3],     # NORTH face — the field menu, rebindable since 2026-10-12
}

const PROFILE_ULTIMATE_PRO_2 = {
	"ui_accept": [1],          # B (East face)
	"ui_cancel": [0],          # A (South face)
	# struktured 2026-07-18: on the actual 8BitDo Ultimate Pro 2 hardware, L physically sends button 10 and R sends button 9 — the Godot JOY_BUTTON_LEFT/RIGHT_SHOULDER constants (9/10) don't match this device's reported indices. Hint bar reads "[L] Defer · [R] Advance"; keep hardware matching the hint bar, not the constant names.
	# 2026-07-29 ALIGNED. The swap above was measured on real hardware BEFORE ControllerMappings
	# existed, when a raw index genuinely did not mean what the constant said. With a mapping
	# registered, 9 IS the left shoulder and 10 IS the right by definition, so keeping the swap
	# INVERTED Defer and Advance against the hint bar for anyone who picked this profile.
	# Autodetect never reaches it (neither Ultimate 2 identity contains "ultimate pro 2", pinned
	# by test) but it stays MANUALLY selectable, and it is the listed name closest to struktured's
	# actual pad — the tempting choice. Aligning is correct under either half of the open
	# retire-vs-keep ruling; that ruling now only decides whether the entry exists at all.
	"battle_advance": [10],    # RIGHT_SHOULDER — aligned with Standard and the hint bar
	"battle_defer": [9],       # LEFT_SHOULDER — aligned with Standard and the hint bar
	"battle_toggle_auto": [4], # BACK (Select/Minus)
	"ui_menu": [6],             # START. L3 moved to battle_open_log 2026-10-04 (struktured: "reuse L3"), deliberately, not dropped
	"battle_open_log": [7],    # L3 — the full battle log
	"ui_field_menu": [3],     # NORTH face — the field menu, rebindable since 2026-10-12
}

## Profile names
const PROFILE_NAMES = ["Standard", "8BitDo SN30", "8BitDo Ultimate Pro 2", "Custom"]

## Device-name substrings (lowercased) → profile. First match wins; anything unmatched gets Standard.
const PROFILE_AUTODETECT = [
	["ultimate pro 2", "8BitDo Ultimate Pro 2"],
	["sn30", "8BitDo SN30"],
	["sf30", "8BitDo SN30"],
]

## Listed profiles that are DELIBERATELY identical to PROFILE_STANDARD, each with the reason its
## entry still exists. Declaring it here is what makes the sameness a decision instead of a
## coincidence — `test_a_listed_profile_says_what_it_is` reds on a listed profile that resolves to
## Standard without an entry, AND on an entry whose profile has since diverged.
##
## ⛔ THE DEFECT THIS DEFENDS IS REACHABLE, NOT COSMETIC: `get_profile_bindings`' `_:` arm returns
## PROFILE_STANDARD, so a name added to PROFILE_NAMES without a `match` arm becomes a profile the
## player can select from ControlsMenu that silently changes nothing. That failure is invisible from
## both sides — the picker shows the name, and the bindings are a valid profile.
##
## 📌 Reasons, not permission: there is no flag here that silences the guard. An entry is a sentence
## a reader can disagree with, which is the only form that cannot become muscle memory.
const PROFILE_ALIASES := {
	"8BitDo SN30":
		"Identical to Standard since the 2026-05-02 Godot-4 button renumbering. Kept because "
		+ "PROFILE_AUTODETECT routes the 'sn30' and 'sf30' device-name substrings here, so the "
		+ "name is what an SN30 owner sees their own pad called, and it is where a real SN30 "
		+ "divergence would land.",
	"8BitDo Ultimate Pro 2":
		"Aligned to Standard on 2026-07-29 when ControllerMappings made the hardware shoulder "
		+ "swap wrong rather than right. Autodetect never reaches it (neither Ultimate 2 identity "
		+ "contains 'ultimate pro 2', pinned by test) but it stays manually selectable and is the "
		+ "listed name closest to struktured's actual pad. Its existence is the open half of the "
		+ "retire-vs-keep ruling.",
}

## Human-readable button labels by index — Godot 4 JoyButton enum.
## (Pre-2026-05-02 these labels were transcribed from Godot 3, which silently
## misled user-facing remap UI when the underlying button numbers shifted.)
const BUTTON_LABELS = {
	0: "A / South (Nintendo B)",
	1: "B / East (Nintendo A)",
	2: "X / West (Nintendo Y)",
	3: "Y / North (Nintendo X)",
	# ⛔ These FOUR omitted PlayStation entirely until 2026-09-12. This is the "every family at
	# once" vocabulary the Controls screen shows with NO pad attached, so a PlayStation player
	# read "Back / Select / Minus" and "Start / Plus" — neither of which is on their pad. The
	# per-family BUTTON_NAMES table had Share/Options/L1/R1 the whole time; only the label that
	# claims to name them all was short.
	4: "Back / Select / Minus / Share",
	5: "Guide / Home / PS",
	6: "Start / Plus / Options",
	7: "L3 / L-Stick (Left Stick Click)",
	8: "R3 / R-Stick (Right Stick Click)",
	9: "L / LB / L1 (Left Shoulder)",
	10: "R / RB / R1 (Right Shoulder)",
	11: "D-Up",
	12: "D-Down",
	13: "D-Left",
	14: "D-Right",
	15: "Misc1",
	16: "Paddle 1",
	17: "Paddle 2",
	18: "Paddle 3",
	19: "Paddle 4",
}

## Runtime state
var active_profile: String = "Standard"
var custom_bindings: Dictionary = {}
## True once the player picks a profile in Settings or a saved config supplies one — autodetect never overrides an explicit choice.
## A pad arrived or the last one left. Surfaces whose captions are DERIVED rebuild on this —
## deriving them is only half the job if the answer is frozen at the moment the screen was built.
signal input_device_changed(connected: bool)

## ⛔ THE SAME PROBLEM, THE OTHER TRIGGER. The docstring above says a derived caption is only half
## the job "if the answer is frozen at the moment the screen was built" — and input_device_changed
## fires ONLY from _on_joy_connection_changed. A profile cycle, a rebind and the Nintendo toggle all
## change what every caption should say and told nobody, so the screen a player backs out to after
## changing their controls named the OLD buttons. Worse than wrong: the toggle SWAPS ui_accept and
## ui_cancel, so the stale caption names the button that now does the opposite thing.
signal bindings_changed

var profile_chosen_by_user: bool = false


func _ready() -> void:
	custom_bindings = PROFILE_STANDARD.duplicate(true)
	load_config()
	match profile_chosen_by_user:
		true: apply_profile(active_profile)
		false: _autodetect_and_apply()
	# The pad may enumerate AFTER boot (hotplug, or a wireless dongle settling) — redetect so it isn't stuck on the no-device default.
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _on_joy_connection_changed(_device: int, connected: bool) -> void:
	if connected and not profile_chosen_by_user:
		_autodetect_and_apply()
	_announce_pad_change(connected)
	# Every derived caption in the game resolves at BUILD time. Four systems listened for the
	# connection change and none of them re-rendered text, so a wireless pad that sleeps mid-battle
	# left the hint bar naming Ⓑ and LB at a player the Toast had just told "keyboard still works".
	input_device_changed.emit(connected)


## Four systems listened for this signal and NONE told the player. A wireless pad that sleeps
## mid-battle left them watching a fight they could not control, with nothing on screen saying why.
func _announce_pad_change(connected: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if connected:
		Toast.show_success(self, "Controller connected")
		return
	# Only when the LAST pad goes — unplugging one of two is not the player losing control.
	if Input.get_connected_joypads().is_empty():
		Toast.show_warning(self, "Controller disconnected — keyboard still works")


## Picks a profile from the connected pad's reported name. Standard is the default because Godot/SDL already normalizes conforming devices.
func detect_profile_for_device(device_name: String) -> String:
	var lowered := device_name.to_lower()
	for entry in PROFILE_AUTODETECT:
		if lowered.find(entry[0]) != -1:
			return entry[1]
	return "Standard"


func _autodetect_and_apply() -> void:
	var pads := Input.get_connected_joypads()
	match pads.is_empty():
		true:
			print("[InputProfileManager] No gamepad connected — applying Standard until one appears")
			apply_profile("Standard")
		false:
			var pad_name: String = Input.get_joy_name(pads[0])
			var detected := detect_profile_for_device(pad_name)
			print("[InputProfileManager] Detected '%s' -> profile '%s'" % [pad_name, detected])
			apply_profile(detected)


func get_profile_bindings(profile_name: String) -> Dictionary:
	match profile_name:
		"Standard":
			return PROFILE_STANDARD
		"8BitDo SN30":
			return PROFILE_SN30
		"8BitDo Ultimate Pro 2":
			return PROFILE_ULTIMATE_PRO_2
		"Custom":
			return custom_bindings
		_:
			return PROFILE_STANDARD


func apply_profile(profile_name: String) -> void:
	active_profile = profile_name
	var bindings = get_profile_bindings(profile_name)

	print("[InputProfileManager] Applying profile: %s (nintendo_mode=%s)" % [profile_name, nintendo_mode])
	for action in REMAPPABLE_ACTIONS:
		if not bindings.has(action):
			continue
		var indices = face_convention_indices(action, bindings[action])
		print("[InputProfileManager]   %s -> buttons %s" % [action, str(indices)])
		_replace_joypad_buttons(action, indices)

	print("[InputProfileManager] Profile applied: %s" % profile_name)
	bindings_changed.emit()


## Swaps SOUTH<->EAST for confirm/cancel when nintendo_mode is off. Pure, so it is testable
## without a pad; every other action passes through untouched.
func face_convention_indices(action: String, indices: Array) -> Array:
	if nintendo_mode or action not in ["ui_accept", "ui_cancel"]:
		return indices
	var swapped: Array = []
	for i in indices:
		match i:
			0: swapped.append(1)
			1: swapped.append(0)
			_: swapped.append(i)
	return swapped


## Sets the convention and re-applies, so the InputMap and the flag can never disagree.
func set_nintendo_mode(enabled: bool) -> void:
	if nintendo_mode == enabled:
		return
	nintendo_mode = enabled
	apply_profile(active_profile)
	save_config()


## The face layout as it is PRINTED, written west-north / south-east — the notation people
## actually use, so a Nintendo pad reads "Ⓨ Ⓧ / Ⓑ Ⓐ" and an Xbox one "Ⓧ Ⓨ / Ⓐ Ⓑ".
func face_layout_diagram(family: String) -> String:
	var t: Dictionary = FACE_GLYPHS.get(family, FACE_GLYPHS["xbox"])
	return "%s %s / %s %s" % [t.get(2, "?"), t.get(3, "?"), t.get(0, "?"), t.get(1, "?")]


## Glyph family for a pad NAME. Unmatched returns "xbox" — an unknown pad on Windows is
## almost always XInput, and that is the demo case.
func face_family_for_device(device_name: String) -> String:
	var lowered := device_name.to_lower()
	for entry in FACE_FAMILY_HINTS:
		if lowered.find(entry[0]) != -1:
			return entry[1]
	return "xbox"


## The glyph printed on the physical button an action currently fires from.
func glyph_for_action(action: String, device_name: String = "") -> String:
	var name := device_name
	if name == "":
		var pads := Input.get_connected_joypads()
		name = Input.get_joy_name(pads[0]) if not pads.is_empty() else ""
	var family: String = face_family_for_device(name)
	var bindings := get_profile_bindings(active_profile)
	if not bindings.has(action):
		return "?"
	var indices := face_convention_indices(action, bindings[action])
	if indices.is_empty():
		return "?"
	var table: Dictionary = FACE_GLYPHS[family]
	return table.get(indices[0], "?")


## What the live pad's family PRINTS on a raw button index: the glyph for a face button (0-3), the
## name for a non-face one (4/6/7/9/10), and "" for anything neither table covers.
##
## ⛔ NO CONVENTION SWAP, DELIBERATELY. A raw JOY_BUTTON_* binding fires from that physical position
## whatever `nintendo_mode` says — callers here are naming a BUTTON, not resolving an ACTION. The
## action-shaped readers (glyph_for_action, button_name_for_action) do apply the swap.
##
## ⛔ "" WITH NO PAD IS THE CONTRACT, NOT A FAILURE. Naming one family's button to a keyboard player
## is the Win98Menu defect; the caller names the KEY instead. Three call sites say so in their own
## comments. And hardcoded "[A] Confirm [B] Cancel" legends are wrong twice over — they name a pad
## button to keyboard players, and this game puts Confirm on the EAST face, so Ⓐ/Ⓑ are INVERTED on
## Xbox and PlayStation.
##
## BUTTON_LABELS is the REMAP-SCREEN vocabulary ("Back / Select / Minus" — every family at once,
## correct there); this is the one a HUD wants.
##
## 📌 FOUR STACKED DOCSTRINGS SAT HERE AND TWO CONTRADICTED THE CODE: one promised "the keyboard key
## when no pad is connected" (it returns ""), and one promised "empty when the index is a face
## button" (it returns the glyph — which is what all 30-odd call sites want, several passing
## JOY_BUTTON_X/Y). A reader cannot tell which paragraph describes the function, and the wrong one
## is as authoritative as the right one.
##
## ⛔ THE MECHANISM IS ACCRETION, AND ONE CLAIM WAS FALSE THE DAY IT WAS WRITTEN — measured in git,
## after I had guessed "merged functions" and was wrong. Three commits on 2026-09-11 each ADDED a
## paragraph above this function and none removed or reconciled the earlier ones. The face-button
## claim arrived in 530da5fd0, describing the non-face NAME branch that commit was adding; the
## FACE_GLYPHS fallback it contradicts was already there, added by eeb260aff, which CREATED the
## function. So each author documented THEIR BRANCH in the place a reader takes for the FUNCTION's
## contract. No refactor is needed for this to happen — three fixes to one function is enough.
func button_name_for_index(button_index: int, device_name: String = "") -> String:
	var name := device_name
	if name == "":
		var pads := Input.get_connected_joypads()
		if pads.is_empty():
			return ""   # NO PAD: naming one is the Win98Menu defect — let the caller name the KEY
		name = Input.get_joy_name(pads[0])
	var family: String = face_family_for_device(name)
	if FACE_GLYPHS.has(family) and FACE_GLYPHS[family].has(button_index):
		return FACE_GLYPHS[family][button_index]
	if BUTTON_NAMES.has(family) and BUTTON_NAMES[family].has(button_index):
		return BUTTON_NAMES[family][button_index]
	return ""


func button_name_for_action(action: String, device_name: String = "") -> String:
	var name := device_name
	if name == "":
		var pads := Input.get_connected_joypads()
		name = Input.get_joy_name(pads[0]) if not pads.is_empty() else ""
	var bindings := get_profile_bindings(active_profile)
	if not bindings.has(action):
		return ""
	## ⛔ THE CONVENTION, LIKE ITS TWIN glyph_for_action DIRECTLY ABOVE. The table stores
	## PRE-convention indices; without this the name is the button the player would press only
	## while nintendo_mode is on. Two siblings reading one table, one of them applying the swap.
	var indices: Array = face_convention_indices(action, bindings[action])
	if indices.is_empty():
		return ""
	var table: Dictionary = BUTTON_NAMES[face_family_for_device(name)]
	return str(table.get(int(indices[0]), ""))


## `device_name` is a TEST SEAM as well as an override: pass one and the function answers as if that
## pad were connected. Without it the pad branch is unreachable headless, and a mutation deleting the
## whole non-face lookup stayed GREEN — measured, which is why the parameter exists.
func hint_for_action(action: String, device_name: String = "") -> String:
	if device_name != "" or not Input.get_connected_joypads().is_empty():
		var g := glyph_for_action(action, device_name)
		if g != "?" and g != "":
			return g
		# Non-face button: name it rather than dropping to the keyboard key, which a pad player
		# cannot press. This is the gap recorded when the legends were first derived.
		var b := button_name_for_action(action, device_name)
		if b != "":
			return b
	var keys := get_action_key_label(action)
	if keys == "—" or keys == "":
		return ""
	# First binding only; a legend is a reminder, not the full list.
	return keys.split(" / ")[0]


## The face a button sits on, which is the ONLY name that is true on every pad. Indices match
## FACE_GLYPHS: 0/1/2/3 are south/east/west/north on Nintendo, Xbox and PlayStation alike.
const FACE_POSITIONS = {0: "South", 1: "East", 2: "West", 3: "North"}


## For a surface that must name a face button with NO pad attached — where a glyph would be an
## xbox guess — this is the family-neutral answer rather than a wrong specific one.
func face_position_for_action(action: String) -> String:
	var indices = get_current_button_indices(action)
	if indices.is_empty():
		return ""
	return FACE_POSITIONS.get(indices[0], "")


func face_glyph_for_index(button_index: int, device_name: String = "") -> String:
	var name := device_name
	if name == "":
		var pads := Input.get_connected_joypads()
		name = Input.get_joy_name(pads[0]) if not pads.is_empty() else ""
	var table: Dictionary = FACE_GLYPHS[face_family_for_device(name)]
	return table.get(button_index, "?")


func _replace_joypad_buttons(action: String, button_indices: Array) -> void:
	# Remove existing joypad button events (keep keyboard + joypad motion)
	var existing_events = InputMap.action_get_events(action)
	for event in existing_events:
		if event is InputEventJoypadButton:
			InputMap.action_erase_event(action, event)

	# Add new joypad button events
	for btn_index in button_indices:
		var new_event = InputEventJoypadButton.new()
		new_event.button_index = btn_index
		new_event.pressed = true
		new_event.device = -1  # All devices (GamepadFilter handles device filtering)
		InputMap.action_add_event(action, new_event)


## ⛔ THE ONE BIND THAT LOCKS THE PLAYER IN. Confirm and Cancel on the same button is not merely a
## conflict — ControlsMenu checks ui_accept BEFORE ui_cancel in an elif chain, so the shared button
## fires Confirm and the Controls screen never closes. Measured: stock cancel closes it, the remap
## does not. Every other conflict is survivable and stays the player's business; this one removes
## the only way to undo itself, on the one screen where you would be standing when you made it.
## Keyboard X/Escape still works, which is exactly the consolation a couch player does not have.
## ⛔ SECOND REFUSED PAIR, 2026-10-12: the field menu on Confirm or Cancel. struktured's first
## controls report was "I enter the overworld menu with a confirm button or something" — dash shared
## the opener's face, so every dash opened the menu. Making the menu REBINDABLE hands a player the
## same defect to build by hand, on the two buttons they press most, so it is refused like the
## lock-in rather than left as "the player's business" (struktured's call, 2026-10-12).
## PAIRS, not a Dictionary of Arrays: the binding-coverage guard derives "a profile" from VALUE
## SHAPE (deliberately, so a profile cannot hide by being named oddly), and a dict-of-arrays const
## here read as a fourth profile whose buttons were action names.
const FIELD_MENU_ACTION_ID := "ui_field_menu"

const REFUSED_SHARES := [
	["ui_accept", "ui_cancel"],
]

## Moving the MENU onto one of these is refused (struktured 2026-10-12). DIRECTIONAL, deliberately:
## ⛔ I had it symmetric first and measured the cost — it also forbids moving CONFIRM onto the north
## face, which is a binding players have always been allowed and which three existing guards use as
## their free parking button. The asked-for rule was "refuse binding the menu onto Confirm/Cancel",
## and the reverse direction is not a lock-in (Cancel still cancels, the Controls screen still
## closes), so it stays the player's business like every other survivable conflict in this file.
const FIELD_MENU_REFUSES := ["ui_accept", "ui_cancel"]


## The actions that may not share a button with `action`.
func _refused_partners(action: String) -> Array:
	var out: Array = []
	for pair in REFUSED_SHARES:
		if pair[0] == action:
			out.append(pair[1])
		elif pair[1] == action:
			out.append(pair[0])
	if action == FIELD_MENU_ACTION_ID:
		out.append_array(FIELD_MENU_REFUSES)
	return out


func binding_would_trap_the_player(action: String, button_indices: Array) -> Dictionary:
	for other in _refused_partners(action):
		var other_buttons: Array = get_current_button_indices(other)
		for b in button_indices:
			if int(b) in other_buttons:
				var why := "the Controls screen could not be closed on a pad"
				if action == "ui_field_menu" or other == "ui_field_menu":
					## Name the button the PLAYER presses, which is whichever of the pair is not the
					## menu — "every Menu press would also open the field menu" says nothing.
					var presser: String = other if action == "ui_field_menu" else action
					why = "every %s press would also open the field menu" % ACTION_LABELS.get(presser, presser)
				return {
					"trapped": true,
					"reason": "%s and %s would share %s — %s"
						% [ACTION_LABELS.get(action, action), ACTION_LABELS.get(other, other),
						   get_button_label(int(b)), why],
				}
	return {"trapped": false, "reason": ""}


## ⛔ PAD BUTTONS HANDLED RAW IN BATTLE BY CONTROLS THAT HAVE NO InputMap ACTION. Battle speed is
## `JOY_BUTTON_Y` and Repeat-last-turn is `JOY_BUTTON_X`, both read straight off the event in
## `BattleScene._input` -- so neither can be rebound and neither appears on the Controls screen.
##
## ⛔ A REMAPPABLE ACTION MOVED ONTO ONE OF THESE WINS, AND THE FIXED CONTROL GOES SILENTLY DEAD.
## `BattleScene._input` checks the action arms FIRST (`:5390`-`:5458`) and the raw arms after
## (`:5483`/`:5488`), and every arm calls `set_input_as_handled()` and returns. So rebinding the
## battle log onto the north face opens the log and battle speed simply stops working -- with no
## warning, nothing on the Controls screen naming it, and no way to discover the cause.
## `binding_would_trap_the_player` cannot see this: it compares against other ACTIONS' indices, and
## these are not actions at all.
## ⛔ PAIRS, NOT A DICTIONARY OF ARRAYS -- the same choice `REFUSED_SHARES` makes above, for the
## same reason, and I made the opposite one here and had the branch dropped from `.681` for it.
## `test_input_profile_binding_coverage_regression._profiles()` derives "a profile" from VALUE
## SHAPE -- any non-empty Dictionary whose every value is an Array -- deliberately, so a profile
## cannot hide by being named oddly. A dict-of-arrays here IS that shape, so it was counted as a
## fourth pad profile whose buttons were control names, and every arm demanding a profile cover
## `ui_accept`/`ui_cancel` red.
##
## ⚠️ ONE BUTTON CAN CARRY MORE THAN ONE FIXED CONTROL, and they are lost in DIFFERENT contexts
## from the same rebind (@cowir-autogrind, verified in GameLoop): `JOY_BUTTON_Y` is battle speed in
## `BattleScene._input` AND the autogrind turbo toggle at `GameLoop._input:1279`, gated on
## `LoopState.AUTOGRIND` with `ui_cancel` consuming above it at `:1274`. So the names stay a LIST --
## the pair's second element -- and only the outer container changed.
const FIXED_PAD_CONTROLS := [
	[JOY_BUTTON_Y, ["Battle speed", "the autogrind turbo toggle"]],
	[JOY_BUTTON_X, ["Repeat last turn"]],
]


## The control names a given pad button carries, or an empty list.
func fixed_controls_on(button_index: int) -> Array:
	for pair in FIXED_PAD_CONTROLS:
		if int(pair[0]) == button_index:
			return pair[1]
	return []

## The remappable actions whose arm runs BEFORE the raw arms in `BattleScene._input`, and which can
## therefore shadow one. PINNED HERE, DERIVED IN THE GUARD: `test_a_rebind_cannot_silently_kill_a_
## fixed_control` reads BattleScene's own source and reds if this list and the arm order disagree,
## because the ordering lives in that file and a copy here would drift the day an arm moves.
const SHADOWING_ACTIONS := ["ui_cancel", "battle_open_log", "battle_toggle_auto"]


## ✅ A WARNING, NOT A REFUSAL, and the asymmetry is deliberate. This is recoverable -- the player
## rebinds away and the fixed control returns -- and the north face is a binding players have always
## been allowed (see FIELD_MENU_REFUSES for why the symmetric rule was rejected). What is missing is
## not permission but INFORMATION: the shadowed control is absent from the Controls screen, so the
## player cannot find out what they broke. So this names the cost and lets them choose.
func binding_would_shadow_a_fixed_control(action: String, button_indices: Array) -> Dictionary:
	if action not in SHADOWING_ACTIONS:
		return {"shadows": false, "reason": ""}
	for b in button_indices:
		var idx := int(b)
		var names: Array = fixed_controls_on(idx)
		if not names.is_empty():
			var lost: String = " and ".join(PackedStringArray(names))
			var label: String = str(ACTION_LABELS.get(action, action))
			return {
				"shadows": true,
				"reason": "%s is now %s, which also triggers %s. That cannot be rebound, so it will stop working until you move %s."
					% [label, get_button_label(idx), lost, label],
			}
	return {"shadows": false, "reason": ""}


func set_custom_binding(action: String, button_indices: Array) -> void:
	if action not in REMAPPABLE_ACTIONS:
		return
	# Refused at the API, not only in the capture UI: a caller that bypasses ControlsMenu must not
	# be able to strand the player either, and the UI checks first so it can explain rather than
	# just decline. See binding_would_trap_the_player for why this one conflict is special.
	var trap := binding_would_trap_the_player(action, button_indices)
	if trap.get("trapped", false):
		push_warning("[InputProfileManager] refused: %s" % str(trap.get("reason", "")))
		return
	# A rebind on a stock profile stored the button and NEVER applied it: this InputMap write was
	# gated on already being Custom, and nothing switched. Measured — Standard, rebind ui_accept to
	# 3: custom_bindings holds [3], InputMap still reports [1], and the saved profile stays
	# "Standard" so the choice is discarded on restart too.
	if active_profile != "Custom":
		# Seed from the profile the player is ON, not from _ready's Standard copy, or their other
		# bindings silently revert — an SN30 player rebinding one button would lose the rest.
		custom_bindings = get_profile_bindings(active_profile).duplicate(true)
		active_profile = "Custom"
	## ⛔ THE CAPTURED INDEX IS PHYSICAL; THE TABLE HOLDS PRE-CONVENTION INDICES. Storing the raw
	## capture put two coordinate systems in one dictionary: the binding worked immediately and then
	## MOVED on the next apply_profile, because that swaps ui_accept/ui_cancel while nintendo_mode is
	## off. Measured — rebind Confirm to physical 1, reload, it is on 0. The swap is its own inverse,
	## so converting on the way IN is what makes the round-trip stable.
	custom_bindings[action] = face_convention_indices(action, button_indices)
	_replace_joypad_buttons(action, button_indices)
	save_config()
	bindings_changed.emit()


## ⛔ READS THE LIVE InputMap, NOT THE PROFILE TABLE, AND THE DIFFERENCE IS A COORDINATE SYSTEM.
## The table stores PRE-convention indices — `apply_profile` runs them through
## `face_convention_indices`, which swaps SOUTH<->EAST for ui_accept/ui_cancel while
## `nintendo_mode` is off. So with the Xbox/PlayStation convention on, the table said Confirm was
## on button 1 while the pad had it on button 0, and everything downstream of this function
## inherited that: the trap guard compared a captured PHYSICAL button against RAW indices and
## permitted binding Confirm onto Cancel's button; the Controls screen named the wrong one.
## "Current" can only mean what is bound right now, and that is the map.
func get_current_button_indices(action: String) -> Array:
	if not InputMap.has_action(action):
		return []
	var out: Array = []
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton:
			out.append((e as InputEventJoypadButton).button_index)
	out.sort()
	return out


func get_button_label(button_index: int) -> String:
	if BUTTON_LABELS.has(button_index):
		return BUTTON_LABELS[button_index]
	return "Button %d" % button_index


func get_action_button_label(action: String) -> String:
	var indices = get_current_button_indices(action)
	if indices.is_empty():
		return "None"
	var labels = []
	for idx in indices:
		labels.append(get_button_label(idx))
	return " / ".join(labels)


## The FIRST keyboard key bound to an action ("X" for ui_accept in the emulator layout), or `fallback`
## when it has none. Captions that name one key read it here, so a rebind moves them with it.
func first_key_label(action: String, fallback: String) -> String:
	var label := get_action_key_label(action)
	if label == "" or label == "—":
		return fallback
	return label.split(" / ")[0]


## Read-only: derive a human-readable keyboard label for an action by
## scanning its current InputMap events. Used by ControlsMenu to surface
## kb bindings alongside gamepad bindings (per user request 2026-05-03:
## "make sure ... bindings for them is visible in the settings").
##
## Returns "—" if the action has no key event. Joins multiple keys with
## " / " (matches the gamepad label format).
func get_action_key_label(action: String) -> String:
	if not InputMap.has_action(action):
		return "—"
	var events := InputMap.action_get_events(action)
	var labels: Array[String] = []
	for ev in events:
		if ev is InputEventKey:
			var ke := ev as InputEventKey
			# Prefer keycode (logical) over physical_keycode for display so
			# users see the printed key name, e.g. "L" instead of "OS-keycode-76".
			var kc: Key = ke.keycode if ke.keycode != 0 else ke.physical_keycode
			if kc == 0:
				continue
			var name := OS.get_keycode_string(kc)
			if name == "":
				continue
			labels.append(name)
	return " / ".join(labels) if labels.size() > 0 else "—"


## Read-only: same idea for mouse bindings. Returns "—" if no mouse event
## is bound. Most actions in this game don't have explicit mouse bindings
## (mouse is handled at UI level via MenuMouseHelper), but ui_accept and
## ui_cancel often map to L/R-click logically; this surfaces anything
## actually wired up at the InputMap layer.
func get_action_mouse_label(action: String) -> String:
	if not InputMap.has_action(action):
		return "—"
	var events := InputMap.action_get_events(action)
	var labels: Array[String] = []
	for ev in events:
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			match mb.button_index:
				MOUSE_BUTTON_LEFT:    labels.append("LMB")
				MOUSE_BUTTON_RIGHT:   labels.append("RMB")
				MOUSE_BUTTON_MIDDLE:  labels.append("MMB")
				MOUSE_BUTTON_WHEEL_UP:    labels.append("Wheel↑")
				MOUSE_BUTTON_WHEEL_DOWN:  labels.append("Wheel↓")
				MOUSE_BUTTON_XBUTTON1: labels.append("X1")
				MOUSE_BUTTON_XBUTTON2: labels.append("X2")
				_: labels.append("Mouse %d" % mb.button_index)
	return " / ".join(labels) if labels.size() > 0 else "—"


## Compares what is ACTUALLY bound, for the same reason get_current_button_indices does: reading the
## pre-convention table reported no conflict while two actions genuinely shared a physical button.
func detect_conflicts() -> Array:
	var conflicts = []
	var button_to_actions: Dictionary = {}

	for action in REMAPPABLE_ACTIONS:
		var live: Array = get_current_button_indices(action)
		if live.is_empty():
			continue
		for btn_index in live:
			if not button_to_actions.has(btn_index):
				button_to_actions[btn_index] = []
			button_to_actions[btn_index].append(action)

	for btn_index in button_to_actions:
		var actions = button_to_actions[btn_index]
		if actions.size() > 1:
			conflicts.append({
				"button": btn_index,
				"actions": actions,
				"label": get_button_label(btn_index),
			})

	return conflicts


func reset_custom_to_preset() -> void:
	var source = get_profile_bindings(active_profile)
	if active_profile == "Custom":
		source = PROFILE_STANDARD
	custom_bindings = source.duplicate(true)
	if active_profile == "Custom":
		apply_profile("Custom")
	save_config()


func cycle_profile(delta: int) -> String:
	var idx = PROFILE_NAMES.find(active_profile)
	if idx < 0:
		idx = 0
	idx = wrapi(idx + delta, 0, PROFILE_NAMES.size())
	profile_chosen_by_user = true
	apply_profile(PROFILE_NAMES[idx])
	save_config()
	return active_profile


func save_config() -> void:
	# Ensure directory exists
	var dir = DirAccess.open("user://")
	if dir and not dir.dir_exists("input"):
		dir.make_dir("input")

	var data = {
		"version": CONFIG_VERSION,
		"active_profile": active_profile,
		# Persisted because a SAVED profile is not a CHOSEN one — see load_config.
		"profile_chosen_by_user": profile_chosen_by_user,
		"nintendo_mode": nintendo_mode,
		"custom_bindings": {},
	}

	# Serialize custom bindings (convert arrays for JSON)
	for action in custom_bindings:
		var indices = custom_bindings[action]
		if indices is Array:
			data["custom_bindings"][action] = indices
		else:
			data["custom_bindings"][action] = [indices]

	var json_str = JSON.stringify(data, "\t")
	## Tick 168: surface save failures. Pre-fix a silent
	## `if file:` short-circuit meant a player who customized
	## their controls would think their bindings were saved (no
	## error toast, no warning) when the write actually failed
	## (perms, disk full, RO filesystem). Next launch reverts to
	## defaults — surprise loss of config.
	## ⛔ STAGED, NOT WRITTEN IN PLACE. `FileAccess.open(CONFIG_PATH, WRITE)` TRUNCATES ON OPEN, so
	## between that call and `store_string` the file IS the 0-byte state — the window is not a race
	## against another writer, it is a race against this process dying, and what comes back empty is
	## the player's profile, face convention and every custom binding. Writing beside the target and
	## renaming into place has no window at all, and a save that cannot be completed now costs the
	## player nothing instead of costing them the last good config.
	var staged: String = CONFIG_PATH + ".new"
	var file = FileAccess.open(staged, FileAccess.WRITE)
	if file == null:
		push_warning("[InputProfileManager] Could not open %s for write — custom input bindings will NOT persist across launches (error: %s). The config already on disk is untouched." % [staged, FileAccess.get_open_error()])
		return
	file.store_string(json_str)
	## Same reason as ControlsMenu's writer: a short write is invisible to `store_string`, and a
	## rename would put the partial config in place. The last good config is better than half of a
	## new one.
	##
	## 📌 `get_error()` and not a read-back, for the same bought reason as ControlsMenu's writer:
	## nothing downstream of this destroys anything, so refusing is a complete answer. Only a write
	## that gates a destructive step needs its contents verified.
	var werr := file.get_error()
	file.close()
	if werr != OK:
		push_warning("[InputProfileManager] Write to %s was incomplete (error %d) — REFUSING to replace %s. The config already on disk is intact and this change applies to this session only." % [staged, werr, CONFIG_PATH])
		DirAccess.remove_absolute(staged)
		return
	var err := DirAccess.rename_absolute(staged, CONFIG_PATH)
	if err != OK:
		push_warning("[InputProfileManager] Could not move %s into place (error %d) — the previous config is intact and this change applies to this session only." % [staged, err])
		DirAccess.remove_absolute(staged)
		return
	print("[InputProfileManager] Config saved")


## ⛔ ENFORCES STRUKTURED'S 2026-10-04 RULING ON CONFIGS THAT PREDATE IT. That day L3 moved from
## `ui_menu` to `battle_open_log` ("reuse L3" — see PROFILE_STANDARD's own comment, "moved,
## deliberately, not dropped"). The DEFAULTS were updated; saved Customs were not, and no version
## bump migrated them. Measured on his own machine from the .684 log:
##
##     ui_menu         -> buttons [6, 7]      6 = START, 7 = L3
##     battle_open_log -> buttons [7]         7 = L3
##
## Button 7 serves both, and in battle `GameLoop`'s ui_menu branch wins and opens the AUTOBATTLE
## EDITOR instead of the log, consuming the press. The comment beside that branch records the same
## shape being read before as "a pause menu he could not escape".
##
## 🔑 KEYED ON THE COLLISION AND ON THE DEFAULT, NOT ON THE BUTTON NUMBER. A button is reclaimed
## only if it is in `ui_menu`, ALSO in `battle_open_log`, and NOT in the default `ui_menu` — i.e.
## this config is holding a copy the default has since moved. That keeps a deliberate rebind: one
## made AFTER this fix is written at version 3 and never reaches this code, and 6 (START) survives
## because the default still claims it.
func _migrate_moved_log_button(cfg_version: int) -> void:
	if cfg_version >= 3:
		return
	if not (custom_bindings.has("ui_menu") and custom_bindings.has("battle_open_log")):
		return
	var menu: Array = custom_bindings["ui_menu"]
	var log_btns: Array = custom_bindings["battle_open_log"]
	var default_menu: Array = PROFILE_STANDARD.get("ui_menu", [])
	var reclaimed: Array = []
	for btn in menu.duplicate():
		if btn in log_btns and not (btn in default_menu):
			menu.erase(btn)
			reclaimed.append(btn)
	if reclaimed.is_empty():
		return
	## ⚠️ NEVER LEAVE ui_menu EMPTY. A config with ui_menu == battle_open_log exactly would strip
	## every button and leave the player no way to open the menu — worse than the collision.
	if menu.is_empty():
		custom_bindings["ui_menu"] = default_menu.duplicate()
		print("[InputProfileManager] ui_menu would have been emptied by the 2026-10-04 L3 move; restored the default %s" % str(default_menu))
		return
	custom_bindings["ui_menu"] = menu
	print("[InputProfileManager] moved %s from Menu to Battle Log, per the 2026-10-04 default" % str(reclaimed))


func load_config() -> void:
	## Tick 167: file-missing stays silent (legitimate first-launch
	## state — no config yet to load). FileAccess.open-fail and
	## root-type-mismatch were silent pre-fix; both deserve warnings
	## because they indicate a real problem (perms / corruption)
	## that the player would experience as "my custom input
	## profile didn't load" with no console hint.
	if not FileAccess.file_exists(CONFIG_PATH):
		return

	var file = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if not file:
		push_warning("[InputProfileManager] Config exists at %s but FileAccess.open failed — using default profile" % CONFIG_PATH)
		return

	var json_str = file.get_as_text()
	file.close()

	var json = JSON.new()
	var err = json.parse(json_str)
	if err != OK:
		push_warning("[InputProfileManager] Failed to parse config: %s" % json.get_error_message())
		return

	var data = json.data
	if not (data is Dictionary):
		push_warning("[InputProfileManager] Config parsed but root is not a Dictionary — using default profile")
		return

	# An unrecognized saved profile was silently discarded — the player's explicit Settings choice
	# vanished with no console hint, presenting as "the game forgot my controller profile". Benign
	# while PROFILE_NAMES only ever grows; the moment a profile is renamed or retired it becomes the
	# difference between a diagnosable message and a mystery. Warn, then fall through to autodetect.
	if data.has("active_profile") and not (data["active_profile"] in PROFILE_NAMES):
		push_warning("[InputProfileManager] Saved profile '%s' is not a known profile (known: %s) — falling back to autodetect. A profile was likely renamed or retired." % [str(data["active_profile"]), str(PROFILE_NAMES)])

	if data.has("active_profile") and data["active_profile"] in PROFILE_NAMES:
		active_profile = data["active_profile"]
		## ⛔ A SAVED PROFILE IS NOT A CHOSEN ONE, AND READING IT AS ONE PERMANENTLY DISABLED
		## AUTODETECT. `save_config` persists `active_profile` unconditionally, and it is called by
		## `set_nintendo_mode`, `set_custom_binding` and `reset_custom_to_preset` — none of which is
		## a profile choice. Only `cycle_profile` is. Measured:
		##     autodetect picks "8BitDo SN30"        chosen=false
		##     player toggles the face convention    persisted, with no record of a choice
		##     next boot                             chosen=TRUE
		##     -> plug in a different pad family     autodetect never runs again
		## So toggling one setting froze the player on whatever pad they happened to own that day.
		##
		## ⚠️ ABSENT KEY DEFAULTS TO `true`, WHICH IS TODAY'S BEHAVIOUR AND IS THE CONSERVATIVE
		## DIRECTION. A config written before this fix cannot say whether the choice was real, and
		## silently overriding a deliberate Settings choice is the worse of the two errors — the
		## same reasoning as the unrecognised-profile warning above. Presence of the key IS the
		## discriminator, so no version bump is needed: absent means pre-fix.
		profile_chosen_by_user = bool(data.get("profile_chosen_by_user", true))
		# v1 hardcoded "8BitDo Ultimate Pro 2" as the startup default, so a persisted copy of it is indistinguishable from a real choice — treat it as unset and let autodetect decide.
		# ⚠️ ITS ORIGINAL REASON IS STALE AND SAYING SO IS THE POINT: this read "so autodetect can
		# correct the L/R inversion it carries". That inversion came from a7bcec0d, which encoded one
		# device's quirk and applied it to every pad; it was reverted, and PROFILE_ULTIMATE_PRO_2 is
		# now byte-identical to PROFILE_STANDARD. So the migration no longer corrects any BINDING —
		# what it still does is clear a choice the player never made, which is reason enough to keep
		# it. A comment that justifies code by a mechanism that no longer exists is read as current.
		var cfg_version: int = int(data.get("version", 1))
		if cfg_version < 2 and active_profile == "8BitDo Ultimate Pro 2":
			profile_chosen_by_user = false

	# Absent key keeps the east-confirm default rather than flipping a returning player's
	# convention on upgrade — v2 configs predate this flag and must not read as "off".
	if data.has("nintendo_mode"):
		nintendo_mode = bool(data["nintendo_mode"])

	if data.has("custom_bindings") and data["custom_bindings"] is Dictionary:
		for action in data["custom_bindings"]:
			if not (action in REMAPPABLE_ACTIONS):
				push_warning("[InputProfileManager] Saved custom binding for '%s' ignored — not a remappable action. Its persisted button choice is being dropped silently otherwise." % str(action))
				continue
			# JSON has no integers, so a loaded index is a FLOAT. Coerce at the boundary: FACE_GLYPHS
			# is int-keyed and `.get(3.0)` MISSES, so a rebind that survived a restart rendered "?"
			# in the F1 reference, the hint bar and every cutscene prompt. Measured: int 3 -> "Ⓨ",
			# float 3.0 -> "?". Same class as the typed-array save coercion in CLAUDE.md.
			var val = data["custom_bindings"][action]
			var coerced: Array = []
			if val is Array:
				for x in val:
					coerced.append(int(x))
			else:
				coerced.append(int(val))
			custom_bindings[action] = coerced

	## cfg_version is declared inside a nested block above, so it is OUT OF SCOPE here -- read the
	## version again from `data`, which is function-level.
	_migrate_moved_log_button(int(data.get("version", 1)))

	print("[InputProfileManager] Config loaded (profile: %s)" % active_profile)
