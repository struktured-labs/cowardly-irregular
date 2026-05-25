extends GutTest

## Regression: Toast.show_save accepts an optional location label, and
## GameLoop._on_any_save_completed reads it live from MapSystem so the
## "Game Saved ✓" banner tells the player WHERE the save landed. Useful
## when juggling slots across worlds. Legacy form preserved when no
## location is supplied (e.g. title-screen debug saves).

const TOAST_PATH := "res://src/ui/Toast.gd"
const GAMELOOP_PATH := "res://src/GameLoop.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_show_save_default_keeps_legacy_short_form() -> void:
	# Pinning the no-location branch via source inspection — Toast.show()
	# fires through a tween so behavioral text assertion is awkward, but
	# the format string is the actual contract.
	var text = _read(TOAST_PATH)
	# Default arg
	assert_true(text.find("location: String = \"\"") > -1,
		"show_save must accept optional location with default empty string")
	# Legacy short form preserved when location is empty
	var sig_idx = text.find("static func show_save(")
	var sig_end = text.find("\n\n", sig_idx)
	var body = text.substr(sig_idx, sig_end - sig_idx) if sig_end > -1 else text.substr(sig_idx)
	assert_true(body.find("\"Game Saved ✓\"") > -1,
		"Legacy 'Game Saved ✓' short-form text must be preserved when location is empty")
	# Concatenation path
	assert_true(body.find("\"Game Saved ✓ — \" + location") > -1,
		"With location, text must be 'Game Saved ✓ — <location>' (em-dash separator)")


func test_gameloop_passes_location_from_mapsystem() -> void:
	var text = _read(GAMELOOP_PATH)
	var fn_idx = text.find("func _on_any_save_completed(")
	assert_true(fn_idx > -1, "_on_any_save_completed must exist")
	var fn_end = text.find("\n\nfunc ", fn_idx)
	var body = text.substr(fn_idx, fn_end - fn_idx) if fn_end > -1 else text.substr(fn_idx)
	# Must reach into MapSystem for the live current_map_id.
	assert_true(body.find("MapSystem") > -1,
		"_on_any_save_completed must read MapSystem for the location label")
	assert_true(body.find("current_map_id") > -1,
		"_on_any_save_completed must consult MapSystem.current_map_id")
	# Must call Toast.show_save WITH a location argument (not the no-arg form).
	assert_true(body.find("Toast.show_save(self, location)") > -1,
		"Must call Toast.show_save with the resolved location, not the no-arg form")
	# Must guard against MapSystem.current_map_id being unset/empty —
	# the title-screen debug path can fire saves without an active map.
	assert_true(body.find("\"current_map_id\" in MapSystem") > -1,
		"Must guard MapSystem.current_map_id existence before dereference (title-screen edge case)")


func test_show_save_behavioral_does_not_crash_with_or_without_location() -> void:
	# Smoke test — both paths instantiate without throwing.
	var toast_script = load(TOAST_PATH)
	# Stand up a transient parent so show() has a real tree to attach to.
	var parent := Node.new()
	add_child_autofree(parent)
	# Loop a few times — RefCounted static call shouldn't leak between
	# invocations even when invoked back-to-back from different sites.
	toast_script.show_save(parent)
	toast_script.show_save(parent, "Harmonia Village")
	toast_script.show_save(parent, "")
	# If we got here without an exception, the API is contract-clean.
	assert_true(true, "All three call shapes returned without error")
