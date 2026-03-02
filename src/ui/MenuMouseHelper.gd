extends RefCounted
class_name MenuMouseHelper

## Shared mouse support utility for menus
## Provides reusable functions to add click support alongside existing keyboard/gamepad navigation
## Pattern follows Win98Menu.gd lines 628-636: flat Button, MOUSE_FILTER_STOP, connect pressed + mouse_entered


static func make_clickable(item: Control, index: int, width: float, height: float,
		on_pressed: Callable, on_hover: Callable) -> Button:
	"""Add an invisible clickable Button overlay to a menu item"""
	var button = Button.new()
	button.flat = true
	button.position = Vector2(0, 0)
	button.size = Vector2(width, height)
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.pressed.connect(on_pressed)
	button.mouse_entered.connect(on_hover)
	item.add_child(button)
	return button


static func add_right_click_cancel(panel: Control, cancel_callback: Callable) -> void:
	"""Add right-click-to-cancel on a background panel.
	Creates an invisible button that covers the panel and listens for right-click."""
	var blocker = Control.new()
	blocker.name = "RightClickCancel"
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_PASS
	blocker.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_callback.call()
			blocker.get_viewport().set_input_as_handled()
	)
	panel.add_child(blocker)
	# Move to back so it doesn't block other clickable items
	panel.move_child(blocker, 0)


static func handle_scroll_wheel(event: InputEvent, current_index: int,
		max_index: int) -> int:
	"""Handle mouse wheel scrolling for item lists.
	Returns new index, or -1 if not a wheel event."""
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			return (current_index - 1 + max_index) % max_index if max_index > 0 else 0
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			return (current_index + 1) % max_index if max_index > 0 else 0
	return -1
