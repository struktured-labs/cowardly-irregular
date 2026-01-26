extends CanvasLayer

## In-game debug log overlay (autoload singleton)
## Shows recent debug messages in a semi-transparent panel

const MAX_LINES = 12
const LOG_RETENTION_TIME = 10.0  # Seconds before old logs fade

var _log_container: VBoxContainer
var _background: ColorRect
var _logs: Array = []  # Array of {text: String, time: float}
var _enabled: bool = true


func _ready() -> void:
	layer = 99  # Above most UI
	_build_ui()

	# Check if debug logging is enabled in GameState
	if GameState and "debug_log_enabled" in GameState:
		_enabled = GameState.debug_log_enabled
	_update_visibility()


func _build_ui() -> void:
	# Semi-transparent background panel in bottom-left
	_background = ColorRect.new()
	_background.color = Color(0.0, 0.0, 0.0, 0.6)
	_background.position = Vector2(8, 400)
	_background.size = Vector2(500, 180)
	add_child(_background)

	# Container for log lines
	_log_container = VBoxContainer.new()
	_log_container.position = Vector2(12, 404)
	_log_container.size = Vector2(492, 172)
	add_child(_log_container)

	# Title
	var title = Label.new()
	title.text = "Debug Log (toggle in Settings)"
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_log_container.add_child(title)


func _process(delta: float) -> void:
	if not _enabled:
		return

	# Remove old logs
	var current_time = Time.get_ticks_msec() / 1000.0
	var changed = false
	while _logs.size() > 0 and current_time - _logs[0]["time"] > LOG_RETENTION_TIME:
		_logs.pop_front()
		changed = true

	if changed:
		_rebuild_log_display()


func add_log(message: String) -> void:
	"""Add a log message to the overlay"""
	if not _enabled:
		return

	var current_time = Time.get_ticks_msec() / 1000.0
	_logs.append({"text": message, "time": current_time})

	# Trim to max lines
	while _logs.size() > MAX_LINES:
		_logs.pop_front()

	_rebuild_log_display()


func _rebuild_log_display() -> void:
	"""Rebuild the visual log display"""
	# Clear existing log labels (keep title)
	var children = _log_container.get_children()
	for i in range(1, children.size()):
		children[i].queue_free()

	# Add log lines
	for log_entry in _logs:
		var label = Label.new()
		label.text = log_entry["text"]
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", _get_log_color(log_entry["text"]))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(480, 0)
		_log_container.add_child(label)


func _get_log_color(text: String) -> Color:
	"""Color-code log messages based on content"""
	if "[BOSS]" in text or "BOSS" in text:
		return Color(1.0, 0.3, 0.3)  # Red for boss
	elif "[INTERACT]" in text:
		return Color(0.3, 1.0, 0.3)  # Green for interaction
	elif "[SETTINGS]" in text:
		return Color(0.3, 0.7, 1.0)  # Blue for settings
	elif "Floor" in text or "[CAVE]" in text:
		return Color(1.0, 0.8, 0.3)  # Yellow for floor/cave
	elif "ERROR" in text or "error" in text:
		return Color(1.0, 0.2, 0.2)  # Bright red for errors
	elif "WARNING" in text:
		return Color(1.0, 0.6, 0.2)  # Orange for warnings
	else:
		return Color(0.9, 0.9, 0.9)  # White default


func set_enabled(enabled: bool) -> void:
	"""Enable or disable the debug overlay"""
	_enabled = enabled
	_update_visibility()

	# Save to GameState
	if GameState:
		GameState.debug_log_enabled = enabled


func _update_visibility() -> void:
	"""Update visibility based on enabled state"""
	if _background:
		_background.visible = _enabled
	if _log_container:
		_log_container.visible = _enabled


## Helper to log from anywhere (call as DebugLogOverlay.log())
func log(message: String) -> void:
	print(message)  # Also print to console
	if _enabled:
		add_log(message)
