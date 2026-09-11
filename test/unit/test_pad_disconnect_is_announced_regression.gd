extends GutTest

## FOUR systems listened for joy_connection_changed and NONE of them told the player:
##   ControlsMenu (refresh) · GamepadFilter · ControllerMappings (audit) · InputProfileManager
##   (re-autodetect)
## All of that is internal bookkeeping. A wireless pad that sleeps mid-battle therefore left the
## player watching a fight they could not control, with nothing on screen saying why — and
## "pad went dead" is a scenario struktured has actually reported.
##
## ⚠️ SCOPE: this announces, it does not PAUSE. Pausing mid-battle touches combat flow and the stall
## watchdog, which is a bigger change than the problem warrants and not mine to make unasked. The
## toast also says "keyboard still works", which is the actionable half.

const IPM := "res://src/input/InputProfileManager.gd"


func _handler_body() -> String:
	var src := FileAccess.get_file_as_string(IPM)
	var at := src.find("func _announce_pad_change(")
	assert_gt(at, -1, "the announcement helper must exist")
	var stop := src.find("\nfunc ", at + 1)
	return src.substr(at, (stop - at) if stop > at else -1)


## The signal must actually reach the announcement — a helper nothing calls announces nothing.
func test_the_connection_signal_reaches_the_announcement() -> void:
	var src := FileAccess.get_file_as_string(IPM)
	var at := src.find("func _on_joy_connection_changed(")
	assert_gt(at, -1, "the signal handler must exist")
	var stop := src.find("\nfunc ", at + 1)
	var body := src.substr(at, (stop - at) if stop > at else -1)
	assert_true(body.contains("_announce_pad_change("),
		"the joy_connection_changed handler must call the announcement — four other listeners do " +
		"internal bookkeeping only, which is how this went unnoticed")


## ONLY THE LAST PAD. Unplugging one of two controllers is not the player losing control, and a
## toast then is noise. Matching the emptiness check, not the word "disconnect".
func test_only_the_last_pad_leaving_warns() -> void:
	var body := _handler_body()
	assert_true(body.contains("Input.get_connected_joypads().is_empty()"),
		"the warning must be gated on NO pads remaining, not on any single one leaving")
	var gate := body.find("is_empty()")
	var warn := body.find("show_warning")
	assert_gt(warn, gate,
		"and the gate must come BEFORE the warning, or it warns on every unplug regardless")


## The message must name the way out. "Controller disconnected" alone tells a stuck player nothing
## they can act on; this game is fully playable on a keyboard and should say so at that moment.
func test_the_message_names_the_way_out() -> void:
	var body := _handler_body()
	assert_true(body.to_lower().contains("keyboard"),
		"the disconnect toast must mention the keyboard — the actionable half of the message")


## Reconnecting must confirm, or the player cannot tell a woken pad from a dead one.
func test_reconnecting_confirms() -> void:
	var body := _handler_body()
	assert_true(body.contains("show_success"),
		"a reconnect must confirm — otherwise a player who wakes the pad still does not know")


## HEADLESS MUST BE SILENT. Toast builds a CanvasLayer; a deploy smoke or a test run has no window
## and no business spawning UI on a signal.
func test_headless_is_silent() -> void:
	var body := _handler_body()
	assert_true(body.contains("DisplayServer.get_name() == \"headless\""),
		"the announcement must bail headless before touching Toast")
	var guard := body.find("headless")
	var first_toast := body.find("Toast.")
	assert_gt(first_toast, guard,
		"and the headless bail must precede any Toast call, or it builds UI in a windowless run")


## CONTROL: Toast really does expose the two variants this depends on — a rename upstream would
## otherwise leave the asserts above matching text that no longer resolves.
func test_the_toast_api_it_calls_exists() -> void:
	var toast := FileAccess.get_file_as_string("res://src/ui/Toast.gd")
	assert_true(toast.contains("static func show_warning("), "Toast.show_warning must exist")
	assert_true(toast.contains("static func show_success("), "Toast.show_success must exist")
	assert_false(toast.contains("static func show_zzq("), "CONTROL: this check can report absence")
