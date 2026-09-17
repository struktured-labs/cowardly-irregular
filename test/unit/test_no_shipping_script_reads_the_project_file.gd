extends GutTest

## `res://project.godot` IS NOT IN ANY EXPORTED PACK. The exporter packs the project file as
## `project.binary`, so a runtime read of the original path returns "" in every shipped build
## while being perfectly correct in the editor and under run_tests.sh.
##
## FOUND 2026-09-17 (cowir-deploy, from the shipped pck's own file table). `GamepadDiagnostic`
## parsed `[input]` out of `res://project.godot` to list the player's actions. In the editor it
## returned 14; in every export it returned ZERO and the F11 overlay's action list was empty.
## Same class as the W2-W6 map bug one release earlier: editor-true, export-false, and no test
## in the tree could have caught it because all ten files that read that path run from a working
## copy where it is just a file.
##
## The repair is the CLASS, not the site: nothing that ships may read it. `InputMap` is the
## export-safe source, and for a gamepad diagnostic the joypad-bound subset is the right one —
## measured at 15 against the 14 authored, the extra being `ui_select`'s default pad binding.

const SHIPPING_ROOT := "res://src"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")


func _gd_files(dir_path: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var entry := d.get_next()
	while entry != "":
		var full := dir_path + "/" + entry
		if d.current_is_dir():
			if not entry.begins_with("."):
				_gd_files(full, out)
		elif entry.ends_with(".gd"):
			out.append(full)
		entry = d.get_next()
	d.list_dir_end()


func _shipping_scripts() -> Array:
	var out: Array = []
	_gd_files(SHIPPING_ROOT, out)
	out.sort()
	return out


func test_the_corpus_is_derived_and_not_vacuous() -> void:
	## SCOPE CONTROL. A sweep over an empty corpus passes without looking at anything, and a
	## rename or a moved root would collapse it silently. The threshold is a floor, not a count.
	var files := _shipping_scripts()
	assert_gt(files.size(), 100, "derived only %d shipping scripts under %s — the sweep below cannot answer anything on a corpus this small" % [files.size(), SHIPPING_ROOT])
	gut.p("shipping scripts swept: %d" % files.size())


func test_no_shipping_script_reads_res_project_godot() -> void:
	var offenders: Array = []
	for p in _shipping_scripts():
		var raw := FileAccess.get_file_as_string(p)
		if raw == "":
			continue
		# Comments only DESCRIBE the hazard -- several files name the path while explaining it.
		var code: String = str(GdSource.split(raw)["code"])
		if code.contains("res://project.godot"):
			offenders.append(p.replace("res://", ""))
	assert_eq(offenders.size(), 0, "these shipping scripts read res://project.godot, which NO exported pack contains (it is packed as project.binary) -- the read returns \"\" in every shipped build and is correct only in the editor: %s. Use InputMap / ProjectSettings instead." % str(offenders))


func test_the_gamepad_overlay_lists_actions_a_pad_can_press() -> void:
	## The site the class rule was found at. This must hold on the SHIPPED path, so it asks
	## InputMap rather than re-reading any file.
	var GamepadDiagnostic = load("res://src/ui/GamepadDiagnostic.gd")
	assert_not_null(GamepadDiagnostic, "GamepadDiagnostic.gd does not load")
	if GamepadDiagnostic == null:
		return
	var actions: Array = GamepadDiagnostic.project_actions()
	assert_gt(actions.size(), 5, "project_actions() returned %d -- the overlay's action list is empty, which is exactly what the project.godot read produced in every export" % actions.size())
	# Every one it names must be real and must actually carry a pad binding.
	var unbound: Array = []
	for a in actions:
		if not InputMap.has_action(a):
			unbound.append("%s (no such action)" % str(a))
			continue
		var has_pad := false
		for ev in InputMap.action_get_events(a):
			if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
				has_pad = true
				break
		if not has_pad:
			unbound.append("%s (no joypad event)" % str(a))
	assert_eq(unbound, [], "a GAMEPAD diagnostic listed actions with no gamepad binding: %s" % str(unbound))
	# The authored set is the floor: every action declared in [input] with a pad event must appear.
	for authored in ["battle_advance", "battle_defer", "battle_toggle_auto", "dash"]:
		assert_true(actions.has(authored), "'%s' is authored with a pad binding and the overlay does not list it" % authored)
