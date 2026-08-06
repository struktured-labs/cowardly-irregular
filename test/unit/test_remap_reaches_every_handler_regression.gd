extends GutTest

## A rebind in Settings → Controls rewrites the InputMap. A handler that compares
## event.button_index to a raw JOY_BUTTON_* constant never sees it, so the same feature
## follows the rebind in one game state and ignores it in another. battle_toggle_auto did
## exactly that: BattleScene reads the action, GameLoop and the grid editor read raw BACK.
## Player rebinds it, the new button works in battle, and the old one still toggles outside.

const PROFILES_OWNER := "res://src/input/InputProfileManager.gd"

## Keyed file::TOKEN, not by file: GameLoop holds both a legitimate chord and (pre-fix) a real
## bypass, so file-level granularity would have exempted the defect along with the chord.
## The value is the argument for the exemption, not a mute switch — a bare allowlist gets
## waved through by muscle memory on the second entry.
const RAW_SITES_WITH_REASONS := {
	"src/GameLoop.gd::JOY_BUTTON_LEFT_SHOULDER":
		"L+R chord cycles the autogrind tier — guarded by is_joy_button_pressed on BOTH, so it "
		+ "is a physical two-button gesture, not a single action a player can rebind.",
	"src/GameLoop.gd::JOY_BUTTON_RIGHT_SHOULDER":
		"the other half of the same L+R autogrind tier chord; see the LEFT_SHOULDER entry.",
	"src/ui/MenuScene.gd::JOY_BUTTON_LEFT_SHOULDER":
		"party cycling in the overworld menu. Shares the physical shoulders with battle_defer "
		+ "but is a different function in a different context — a Defer rebind should not move it.",
	"src/ui/MenuScene.gd::JOY_BUTTON_RIGHT_SHOULDER":
		"party cycling, the other shoulder; see the LEFT_SHOULDER entry.",
	"src/ui/VirtualKeyboard.gd::JOY_BUTTON_BACK":
		"backspace inside the on-screen keyboard. Shares the physical button with "
		+ "battle_toggle_auto but is a different function, and the keyboard is modal.",
	"src/ui/autogrind/AutogrindInputHelper.gd::JOY_BUTTON_BACK":
		"pauses the autogrind dashboard. Same physical button as battle_toggle_auto, different "
		+ "function, and only while the dashboard is open.",
	"src/ui/autogrind/AutogrindInputHelper.gd::JOY_BUTTON_LEFT_SHOULDER":
		"L+R chord cycles tier from the dashboard — both halves required, so no single rebind "
		+ "maps onto it.",
	"src/ui/autogrind/AutogrindInputHelper.gd::JOY_BUTTON_RIGHT_SHOULDER":
		"the other half of the dashboard L+R tier chord; see the LEFT_SHOULDER entry.",
	"src/ui/autogrind/AutogrindInputHelper.gd::JOY_BUTTON_START":
		"opens rule adjustment from the dashboard. ui_menu is bound to START but is the pause "
		+ "menu; the dashboard is modal and owns the button while open.",
}


func _consts(path: String) -> Dictionary:
	var script: Script = load(path)
	assert_not_null(script, "%s must load — without it this proves nothing" % path)
	return script.get_script_constant_map() if script else {}


## Engine values, never hardcoded numerals: the claim is about the binding, not about "4".
func _token_to_index() -> Dictionary:
	return {
		"JOY_BUTTON_A": JOY_BUTTON_A, "JOY_BUTTON_B": JOY_BUTTON_B,
		"JOY_BUTTON_X": JOY_BUTTON_X, "JOY_BUTTON_Y": JOY_BUTTON_Y,
		"JOY_BUTTON_BACK": JOY_BUTTON_BACK, "JOY_BUTTON_START": JOY_BUTTON_START,
		"JOY_BUTTON_LEFT_STICK": JOY_BUTTON_LEFT_STICK,
		"JOY_BUTTON_RIGHT_STICK": JOY_BUTTON_RIGHT_STICK,
		"JOY_BUTTON_LEFT_SHOULDER": JOY_BUTTON_LEFT_SHOULDER,
		"JOY_BUTTON_RIGHT_SHOULDER": JOY_BUTTON_RIGHT_SHOULDER,
	}


func _gd_files(root: String) -> Array[String]:
	var out: Array[String] = []
	var dirs: Array[String] = [root]
	while not dirs.is_empty():
		var d: String = dirs.pop_back()
		var da := DirAccess.open(d)
		if da == null:
			continue
		da.list_dir_begin()
		var n := da.get_next()
		while n != "":
			var full: String = d + "/" + n
			if da.current_is_dir():
				dirs.append(full)
			elif n.ends_with(".gd"):
				out.append(full)
			n = da.get_next()
		da.list_dir_end()
	return out


## Both raw forms. `button_index == JOY_BUTTON_X` is the obvious one; a `match button_index`
## block dispatches on bare case labels and is invisible to an equality regex — which is how
## AutogrindInputHelper's five sites hid from the first version of this guard.
func _raw_tokens_in(txt: String) -> Array[String]:
	var found := {}
	var eq := RegEx.new()
	eq.compile("button_index\\s*==\\s*(JOY_BUTTON_[A-Z_]+)")
	for m in eq.search_all(txt):
		found[m.get_string(1)] = true
	if txt.contains("match event.button_index"):
		var arm := RegEx.new()
		arm.compile("(?m)^\\s*(JOY_BUTTON_[A-Z_]+(?:\\s*,\\s*JOY_BUTTON_[A-Z_]+)*)\\s*:")
		for m in arm.search_all(txt):
			for tok in m.get_string(1).split(","):
				found[tok.strip_edges()] = true
	var out: Array[String] = []
	for k in found:
		out.append(str(k))
	return out


func test_the_sweep_and_the_binding_source_are_both_live() -> void:
	var profiles := _consts(PROFILES_OWNER)
	assert_gt(int(profiles.get("PROFILE_STANDARD", {}).size()), 0, "PROFILE_STANDARD must be readable")
	assert_gt(int(profiles.get("REMAPPABLE_ACTIONS", []).size()), 0, "REMAPPABLE_ACTIONS must be readable")
	var files := _gd_files("res://src")
	assert_gt(files.size(), 100, "the sweep must find src/ — an empty read makes this vacuous: %d" % files.size())
	var named := false
	for f in files:
		if f.ends_with("GameLoop.gd"):
			named = true
	assert_true(named, "control: GameLoop.gd is a known-present member and must appear in the sweep")
	var helper := FileAccess.get_file_as_string("res://src/ui/autogrind/AutogrindInputHelper.gd")
	assert_true("JOY_BUTTON_BACK" in _raw_tokens_in(helper),
		"control: the match-arm form must be detected — an equality-only regex misses it silently")


## The load-bearing test. A raw comparison against a button that a REMAPPABLE action is bound
## to is a handler a rebind cannot reach — unless there is a stated reason it is not one.
func test_no_raw_handler_shadows_a_remappable_binding() -> void:
	var profiles := _consts(PROFILES_OWNER)
	var standard: Dictionary = profiles.get("PROFILE_STANDARD", {})
	var remappable: Array = profiles.get("REMAPPABLE_ACTIONS", [])
	var t2i := _token_to_index()

	var bound_index_to_action := {}
	for action in remappable:
		for idx in standard.get(action, []):
			bound_index_to_action[int(idx)] = str(action)

	var offenders: Array[String] = []
	for full in _gd_files("res://src"):
		var rel: String = full.replace("res://", "")
		var txt := FileAccess.get_file_as_string(full)
		for token in _raw_tokens_in(txt):
			if RAW_SITES_WITH_REASONS.has("%s::%s" % [rel, token]):
				continue
			if not t2i.has(token):
				continue
			var idx: int = int(t2i[token])
			if bound_index_to_action.has(idx):
				offenders.append("%s handles raw %s, but '%s' is remappable and bound to it — a rebind leaves this handler behind"
					% [rel, token, bound_index_to_action[idx]])
	offenders.sort()
	assert_eq(offenders, [] as Array[String],
		"a raw button handler shadows a rebindable action: %s" % str(offenders))


## The mechanism the source guard is a proxy for: a rebind rewrites the InputMap, so an
## action-based handler follows the new button AND stops answering the old one. A raw
## button_index comparison does neither. Restores the binding — InputMap leaks across tests.
func test_a_rebind_moves_the_action_off_the_old_button() -> void:
	var action := "battle_toggle_auto"
	assert_true(InputMap.has_action(action), "control: the action must exist before rebinding it")
	var saved: Array[InputEvent] = []
	for e in InputMap.action_get_events(action):
		saved.append(e)

	var before := InputEventJoypadButton.new()
	before.button_index = JOY_BUTTON_BACK
	before.pressed = true
	assert_true(before.is_action_pressed(action), "control: BACK must fire the action BEFORE the rebind")

	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton:
			InputMap.action_erase_event(action, e)
	var rebound := InputEventJoypadButton.new()
	rebound.button_index = JOY_BUTTON_Y
	rebound.pressed = true
	rebound.device = -1
	InputMap.action_add_event(action, rebound)

	var probe_new := InputEventJoypadButton.new()
	probe_new.button_index = JOY_BUTTON_Y
	probe_new.pressed = true
	var probe_old := InputEventJoypadButton.new()
	probe_old.button_index = JOY_BUTTON_BACK
	probe_old.pressed = true

	var new_fires: bool = probe_new.is_action_pressed(action)
	var old_fires: bool = probe_old.is_action_pressed(action)

	for e in InputMap.action_get_events(action):
		InputMap.action_erase_event(action, e)
	for e in saved:
		InputMap.action_add_event(action, e)

	assert_true(new_fires, "after a rebind the NEW button must fire the action — this is what a raw handler never sees")
	assert_false(old_fires, "after a rebind the OLD button must stop firing it — a raw JOY_BUTTON_BACK handler keeps toggling here")
	assert_true(before.is_action_pressed(action), "the binding must be restored — a leaked InputMap drags into later tests")


## Exemptions must expire. An entry for a site that no longer exists is stale permission, and
## stale permission is how the next real one gets waved through.
func test_every_exemption_still_describes_a_real_raw_site() -> void:
	var stale: Array[String] = []
	for key in RAW_SITES_WITH_REASONS:
		var parts: PackedStringArray = str(key).split("::")
		if parts.size() != 2:
			stale.append("%s: malformed key, want file::TOKEN" % key)
			continue
		var txt := FileAccess.get_file_as_string("res://" + parts[0])
		if txt == "":
			stale.append("%s: exempted but unreadable" % key)
		elif not (parts[1] in _raw_tokens_in(txt)):
			stale.append("%s: exempted but that file no longer handles that button — delete the entry" % key)
		elif str(RAW_SITES_WITH_REASONS[key]).length() < 60:
			stale.append("%s: reason too short to be an argument" % key)
	stale.sort()
	assert_eq(stale, [] as Array[String], "stale exemptions: %s" % str(stale))
