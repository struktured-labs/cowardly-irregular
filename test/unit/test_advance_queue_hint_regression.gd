extends GutTest

## Item 22 (user: "there should be a button to undo an advance with
## unwinding the menu if there isn't already"). The unwind EXISTED —
## B pops one queued action, L undoes-or-defers — but nothing surfaced
## it, so the user asked for a feature the game already had. The
## battle hint bar now swaps to queue context while actions are
## queued and restores the default when the queue drains or the
## menu closes.

const Win98MenuScript = preload("res://src/ui/Win98Menu.gd")


func _make_bar(host: Node) -> Label:
	var bar := PanelContainer.new()
	bar.name = "InputHintBar"
	var label := Label.new()
	label.name = "HintLabel"
	label.text = Win98MenuScript.HINT_DEFAULT_TEXT
	bar.add_child(label)
	host.add_child(bar)
	return label


func test_hint_swaps_with_queue_and_restores() -> void:
	var host := Node.new()
	add_child_autofree(host)
	var label := _make_bar(host)
	var menu: Control = Win98MenuScript.new()
	host.add_child(menu)
	menu._queued_actions.append({"id": "attack_0"})
	menu._queued_actions.append({"id": "attack_0"})
	menu._update_hint_bar()
	assert_true(label.text.contains("Undo last"),
		"queued state must advertise the undo control")
	assert_true(label.text.contains("2/"), "queue count must display")
	menu._queued_actions.clear()
	menu._update_hint_bar()
	assert_eq(label.text, Win98MenuScript.HINT_DEFAULT_TEXT,
		"empty queue restores the default hints")
	menu.queue_free()


func test_menu_close_restores_default_hint() -> void:
	var host := Node.new()
	add_child_autofree(host)
	var label := _make_bar(host)
	var menu: Control = Win98MenuScript.new()
	host.add_child(menu)
	menu._queued_actions.append({"id": "attack_0"})
	menu._update_hint_bar()
	assert_true(label.text.contains("Undo last"))
	host.remove_child(menu)
	menu.free()
	assert_eq(label.text, Win98MenuScript.HINT_DEFAULT_TEXT,
		"root menu leaving must never strand queue-context text into execution")


func test_undo_path_still_exists() -> void:
	# The mechanism the hint advertises: source pins on the real handlers.
	var src: String = FileAccess.get_file_as_string("res://src/ui/Win98Menu.gd")
	assert_true(src.contains("func _undo_last_action"), "undo handler must exist")
	assert_true(src.contains("_queued_actions.pop_back()"), "undo must pop exactly one")
