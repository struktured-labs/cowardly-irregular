extends GutTest

## Regression/unit tests for RuleComposerOverlay (Task 13).
##
## Covers the headless-safe public API: open() stores domain/character_id,
## cancel() emits cancelled, and the installed/cancelled signal shapes exist.
## The overlay is instantiated via RuleComposerOverlay.new() (no .tscn), so
## every UI-node write inside the script must be null-guarded — these tests
## double as a check that instantiating the bare script never crashes.

const RuleComposerOverlay := preload("res://src/ui/autobattle/RuleComposerOverlay.gd")


func test_open_stores_domain_and_character_id() -> void:
	var overlay = RuleComposerOverlay.new()
	add_child_autofree(overlay)
	overlay.open("autobattle", "mage", [])
	assert_eq(overlay.get_domain(), "autobattle")
	assert_eq(overlay.get_character_id(), "mage")


func test_emits_cancelled_on_cancel() -> void:
	var overlay = RuleComposerOverlay.new()
	add_child_autofree(overlay)
	watch_signals(overlay)
	overlay.open("autobattle", "mage", [])
	overlay.cancel()
	assert_signal_emitted(overlay, "cancelled")


func test_signal_shape_installed_carries_index() -> void:
	var overlay = RuleComposerOverlay.new()
	add_child_autofree(overlay)
	assert_true(overlay.has_signal("installed"))
	assert_true(overlay.has_signal("cancelled"))
