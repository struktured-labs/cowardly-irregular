extends GutTest

## struktured, 2026-09-25, on a laptop: "L/R gamepad buttons mapped to L/R keyboard is awful" — the
## keyboard shoulders moved to Q/W (the emulator default for L/R, beside Z/X). Both grid editors read
## battle_advance as Add Action AND nudged a condition's value on raw W/S, so with Advance on W one
## key would have done two jobs on one screen — the dash-opened-the-menu class, on a keyboard. The
## nudge moved to -/=.
##
## ⛔ NOTHING CAUGHT IT: putting the raw W branch back left all 31 files covering these keys green.
## test_raw_key_must_not_contradict_its_action only flags a raw key doing ANOTHER ACTION's function,
## and a value nudge is not an action.
##
## So: no .gd that reads a SHOULDER action may also raw-read a key bound to it. Derived both ways —
## keys from the live InputMap, readers from comment-stripped src/. 📌 SCOPED to the two shoulders on
## purpose: ui_accept/ui_cancel carry many deliberate raw duplicates that do the SAME job (raw X also
## closes a menu that reads ui_cancel), which is not this hazard.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const SHOULDERS := ["battle_defer", "battle_advance"]


func _src_files() -> Array:
	var out := []
	var stack := ["res://src"]
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		var d := DirAccess.open(dir)
		if d == null:
			continue
		d.list_dir_begin()
		var n := d.get_next()
		while n != "":
			if not n.begins_with("."):
				var path := dir + "/" + n
				if d.current_is_dir():
					stack.append(path)
				elif n.ends_with(".gd"):
					out.append(path)
			n = d.get_next()
	return out


## The raw-key identifiers (KEY_Q, KEY_W, …) bound to an action, from the InputMap the engine loaded.
func _raw_names_of(action: String) -> Array:
	var out := []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var kc: Key = ev.keycode if ev.keycode != KEY_NONE else ev.physical_keycode
			out.append("KEY_" + OS.get_keycode_string(kc).to_upper())
	return out


func test_control_the_shoulders_resolve_to_raw_key_names() -> void:
	assert_has(_raw_names_of("battle_defer"), "KEY_Q", "CONTROL: Defer's key resolves to its raw name")
	assert_has(_raw_names_of("battle_advance"), "KEY_W", "CONTROL: Advance's key resolves to its raw name")


func test_no_screen_gives_a_shoulder_key_a_second_job() -> void:
	var readers := 0
	var offenders := []
	for path in _src_files():
		var code := GdSource.code_of(path)
		for action in SHOULDERS:
			if not code.contains('"%s"' % action):
				continue
			readers += 1
			for raw in _raw_names_of(action):
				if RegEx.create_from_string("\\b%s\\b" % raw).search(code):
					offenders.append("%s reads %s and ALSO raw %s" % [path.get_file(), action, raw])
	assert_gt(readers, 10,
		"CONTROL: the walk must find the ~20 screens that read the shoulders, found %d" % readers)
	assert_eq(offenders, [],
		"one key doing two jobs on one screen — handle the ACTION, or move the other job off its key")
