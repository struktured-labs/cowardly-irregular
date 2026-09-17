extends GutTest

## Sanity test for Task 14 — AutogrindGridEditor Rule Composer wiring.
## Mirrors test_rule_composer_overlay.gd's headless-safe instantiation pattern.

const AutogrindGridEditor := preload("res://src/ui/autogrind/AutogrindGridEditor.gd")


func before_each() -> void:
	## Drives a UI node that reaches AutogrindSystem's savers; the one-hop ratchet cannot see it
	AutogrindSystem._test_disable_persistence = true


func after_each() -> void:
	AutogrindSystem._test_disable_persistence = false


func test_editor_script_exposes_open_rule_composer_overlay() -> void:
	var editor = AutogrindGridEditor.new()
	add_child_autofree(editor)
	assert_true(editor.has_method("_open_rule_composer_overlay"),
		"AutogrindGridEditor must expose _open_rule_composer_overlay")


func test_editor_script_exposes_composer_installed_handler() -> void:
	var editor = AutogrindGridEditor.new()
	add_child_autofree(editor)
	assert_true(editor.has_method("_on_composer_installed"),
		"AutogrindGridEditor must expose _on_composer_installed")
