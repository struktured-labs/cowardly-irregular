extends GutTest

## struktured 2026-09-10: "which is R… or should be R… one should be L one should be R." He could
## not remember, because BattleScene bound raw KEY_R to player_defer() while project.godot binds R
## to battle_ADVANCE and the hint bar prints "[R] Advance". The keyboard did the opposite of every
## surface that documents it.
##
## The general rule it broke: A RAW KEYCODE HANDLER MUST NOT DO WHAT A DIFFERENT ACTION DOES.
## Handle the action, and a rebind follows you; handle the key, and you have hardcoded one device's
## opinion of what that key means.
##
## ⚠️ SCOPE, STATED TO MATCH THE INSTRUMENT — deliberately narrow, because the alternative fails
## toward ALARM and alarm is the direction that gets acted on. It checks ONLY the three project
## battle actions below. It does NOT check Godot's built-ins: ui_copy binds C, ui_undo binds Z,
## ui_cut binds Delete, and a raw KEY_C handler is not a defect. Widening past this set needs a
## measurement of the false-positive rate first, which I have not done.
##
## ⚠️ It also cannot see CROSS-NODE shadowing, which is how the R/L pair survived —
## test_no_shadowed_key_handler_regression is same-function only, and the menu that consumed these
## actions lives in a different scene. Neither instrument sees that; this one sees the
## CONTRADICTION instead, which is the half that made it a bug rather than dead code.

## action -> the function that IS that action. A raw handler for a key bound to action A must not
## call the function of action B.
const ACTION_FN := {
	"battle_defer": "player_defer",
	"battle_advance": "player_advance",
	"battle_toggle_auto": "_toggle_all_autobattle",
}


func _keys_of(action: String) -> Array:
	var out := []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and ev.keycode != 0:
			out.append(OS.get_keycode_string(ev.keycode).to_upper())
	return out


func _gd_files(dir_path: String, acc: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir_path + "/" + name
		if d.current_is_dir():
			if not name.begins_with("."):
				_gd_files(full, acc)
		elif name.ends_with(".gd"):
			acc.append(full)
		name = d.get_next()
	d.list_dir_end()


## THE RATCHET.
func test_no_raw_key_handler_performs_a_different_actions_job() -> void:
	var files: Array = []
	_gd_files("res://src", files)
	assert_gt(files.size(), 100, "CONTROL: the sweep must walk src/, got %d files" % files.size())

	var checked := 0
	var offences: Array = []
	for f in files:
		var src := FileAccess.get_file_as_string(f)
		for action in ACTION_FN:
			for key in _keys_of(action):
				var re := RegEx.new()
				re.compile("keycode\\s*==\\s*KEY_%s\\b" % key)
				for m in re.search_all(src):
					checked += 1
					var body := src.substr(m.get_start(), 300)
					for other in ACTION_FN:
						if other == action:
							continue
						if body.contains(ACTION_FN[other]):
							offences.append("%s: raw KEY_%s (bound to %s) calls %s, which is %s's job"
								% [f.get_file(), key, action, ACTION_FN[other], other])
	for o in offences:
		gut.p("  🔴 %s" % o)
	assert_eq(offences.size(), 0,
		"%d raw key handler(s) do a different action's job — handle the ACTION, not the key" % offences.size())
	assert_gt(checked, 0,
		"CONTROL: the sweep must have found raw handlers for these keys to inspect at all, got %d" % checked)


## The premise. If the bindings ever move, this file is guarding a shape that no longer exists.
func test_the_actions_still_bind_the_keys_this_rests_on() -> void:
	assert_has(_keys_of("battle_defer"), "L", "battle_defer must bind L")
	assert_has(_keys_of("battle_advance"), "R", "battle_advance must bind R")
	assert_does_not_have(_keys_of("battle_advance"), "L",
		"CONTROL: advance must not also claim L, or 'a different action's job' is meaningless")
