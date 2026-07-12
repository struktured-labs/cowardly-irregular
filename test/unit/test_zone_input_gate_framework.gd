extends GutTest

## Zone-listener input-gate framework (2026-07-12 — subagent hunt found 11
## _input handlers in src/exploration/ that grab ui_accept directly without
## gating on InputLockManager AND TutorialHint. That's the same class of bug
## as SavePoint saving on a hint-dismiss press. This test enumerates every
## src/exploration/ file with a `_input(event: InputEvent)` handler and pins
## both gates. A source-pin catches the class going forward, so a NEW zone
## listener that ships without either gate fails loudly instead of shipping
## as a mystery-dialogue leak.

const EXPLORATION_DIR := "res://src/exploration"

## Files where an _input handler intentionally doesn't need either gate
## (autoloads with no zone semantics, or non-interactable pure listeners).
## Keep this list SHORT and justified — the point is that new files aren't
## silently added here.
const EXEMPT_FILES: Dictionary = {
	"OverworldPlayer.gd": "player controller — its _input IS the input pipeline the gates protect",
	"OverworldController.gd": "scene-level input router — locks itself upstream via GameLoop state",
}


func _list_gd_files(dir_path: String) -> Array:
	var out: Array = []
	var da := DirAccess.open(dir_path)
	if da == null:
		return out
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if name != "." and name != ".." and name.ends_with(".gd"):
			out.append(name)
		name = da.get_next()
	da.list_dir_end()
	out.sort()
	return out


func test_every_exploration_input_handler_gates_on_hint_and_lock() -> void:
	var files := _list_gd_files(EXPLORATION_DIR)
	assert_gt(files.size(), 5, "sanity: exploration dir should hold many scripts")
	var missing: Array = []
	for fname in files:
		if EXEMPT_FILES.has(fname):
			continue
		var path := "%s/%s" % [EXPLORATION_DIR, fname]
		var src := FileAccess.get_file_as_string(path)
		var i := src.find("func _input(event: InputEvent)")
		if i < 0:
			continue  # no _input handler; nothing to gate
		var body := src.substr(i, 900)
		# Anything that reads ui_accept from an event object needs both gates.
		if not ("is_action_pressed(\"ui_accept\"" in body):
			continue
		var has_hint_gate := "TutorialHint.is_any_active()" in body
		var has_lock_gate := ("InputLockManager" in body) or ("ilm_gate" in body) or ("ilm.is_locked" in body)
		if not (has_hint_gate and has_lock_gate):
			missing.append("%s (hint=%s lock=%s)" % [fname, has_hint_gate, has_lock_gate])
	assert_eq(missing.size(), 0,
		"the following zone-listener _input handlers grab ui_accept without both gates — dismiss/advance press leaks:\n  " + "\n  ".join(missing))


func test_win98_menu_defer_is_debounced_like_advance() -> void:
	# Sister bug to the advance debounce: LB button + LT axis 4 both fire on
	# one squeeze, and a drifting trigger can jitter across the deadzone.
	var src := FileAccess.get_file_as_string("res://src/ui/Win98Menu.gd")
	assert_true("const DEFER_DEBOUNCE_MS" in src, "defer debounce const must exist")
	assert_true("_last_defer_ms" in src, "defer debounce state must exist")
	var i := src.find("func _handle_defer_input")
	assert_gt(i, -1)
	var body := src.substr(i, 400)
	assert_true("_last_defer_ms" in body and "DEFER_DEBOUNCE_MS" in body,
		"_handle_defer_input must debounce duplicate defers (LB button + LT axis / trigger jitter)")


func test_save_point_fast_travel_is_debounced() -> void:
	var src := FileAccess.get_file_as_string("res://src/exploration/SavePoint.gd")
	assert_true("_last_fasttrav_ms" in src,
		"SavePoint fast-travel must be debounced — RB button + RT axis 5 both fire on one squeeze, opening FastTravelMenu twice")


func test_base_village_and_interior_reset_camera_angle() -> void:
	# Defense-in-depth: OverworldPlayer.gd reads Mode7Overlay.camera_angle
	# UNCONDITIONALLY (not gated on is_active). A leaked non-zero angle would
	# rotate flat-scene movement. BaseVillage/BaseInterior already reset
	# is_active; they must also reset camera_angle.
	for path in ["res://src/maps/villages/BaseVillage.gd", "res://src/maps/interiors/BaseInterior.gd"]:
		var src := FileAccess.get_file_as_string(path)
		assert_true("Mode7Overlay.camera_angle = 0.0" in src,
			"%s must reset Mode7Overlay.camera_angle (defense-in-depth)" % path.get_file())
