extends GutTest

## Every derived caption in this game resolves at BUILD time. That is only half the job: the answer
## is frozen at the moment the screen was drawn, and a pad can arrive or leave afterwards.
##
## The scenario the codebase already cares about — its own comment says a wireless pad that sleeps
## mid-battle "left them watching a fight they could not control, with nothing on screen saying why",
## which is why the disconnect Toast exists. But the Toast says "keyboard still works" while the hint
## bar keeps naming Ⓑ and LB, because _update_hint_bar runs only on an AP change and _process never
## calls it. The player is told the keyboard works and shown the pad's buttons.
##
## InputProfileManager emitted NO signals at all — four systems listened to joy_connection_changed
## and not one of them re-rendered text. It emits input_device_changed now, and the surfaces whose
## captions are derived rebuild on it.

const IPM := "res://src/input/InputProfileManager.gd"
const BATTLE := "res://src/battle/BattleScene.gd"


func _src(p: String) -> String:
	var s := FileAccess.get_file_as_string(p)
	assert_gt(s.length(), 1000, "PRECONDITION: %s must be readable" % p)
	return s


## THE SIGNAL, observed rather than read: drive the real handler and watch it fire.
func test_a_device_change_announces_itself() -> void:
	var chosen: bool = InputProfileManager.profile_chosen_by_user
	var profile: String = InputProfileManager.active_profile
	InputProfileManager.profile_chosen_by_user = true   # don't let the probe re-detect a profile
	watch_signals(InputProfileManager)
	InputProfileManager._on_joy_connection_changed(0, true)
	assert_signal_emitted(InputProfileManager, "input_device_changed",
		"a pad arriving must announce itself — nothing could react before, because this autoload " +
		"emitted no signals at all")
	InputProfileManager._on_joy_connection_changed(0, false)
	assert_signal_emit_count(InputProfileManager, "input_device_changed", 2,
		"a pad LEAVING must announce too — that is the wireless-pad-sleeps case the Toast exists for")
	InputProfileManager.profile_chosen_by_user = chosen
	InputProfileManager.active_profile = profile


## THE ARTIFACT: the bar's TEXT must change, not merely the connection exist. Builds the real
## InputHintBar the menu looks for, plants a sentinel, fires the real signal.
func test_the_queue_bar_re_derives_when_the_device_changes() -> void:
	var bar := Control.new()
	bar.name = "InputHintBar"
	var label := Label.new()
	label.name = "HintLabel"
	bar.add_child(label)
	get_tree().root.add_child(bar)

	var menu = load("res://src/ui/Win98Menu.gd").new()
	add_child_autofree(menu)          # _ready connects it

	label.text = "SENTINEL-NOT-REBUILT"
	InputProfileManager.input_device_changed.emit(false)
	var after: String = label.text

	bar.queue_free()
	assert_ne(after, "SENTINEL-NOT-REBUILT",
		"the hint bar must RE-DERIVE when the device changes. The connection existing is not the " +
		"same as the text being rebuilt — that is the whole defect this file is named for")
	assert_eq(after, Win98Menu.hint_text(),
		"and it must re-derive to the CURRENT device's caption")


## The battle scene's own static bar. Register-level deliberately: instantiating BattleScene pulls
## the whole combat stack, and the behaviour above already proves the signal path works.
func test_battlescene_refreshes_its_bar_too() -> void:
	var src := _src(BATTLE)
	assert_true(src.contains("input_device_changed.connect(_refresh_input_hint_bar)"),
		"BattleScene must re-derive its static bar on a device change")
	var at := src.find("func _refresh_input_hint_bar")
	assert_gt(at, -1, "the refresh function must exist")
	var body := src.substr(at, 420)
	assert_true(body.contains("Win98Menu.hint_text()"),
		"and it must re-derive through the same single source, not restate the caption")


## CONTROL: the probe must be able to observe a NON-rebuild, or the arm above is unfalsifiable.
func test_an_unrelated_signal_does_not_rebuild_the_bar() -> void:
	var bar := Control.new()
	bar.name = "InputHintBar"
	var label := Label.new()
	label.name = "HintLabel"
	bar.add_child(label)
	get_tree().root.add_child(bar)

	var menu = load("res://src/ui/Win98Menu.gd").new()
	add_child_autofree(menu)

	label.text = "SENTINEL-NOT-REBUILT"
	# no emit at all
	var after: String = label.text
	bar.queue_free()
	assert_eq(after, "SENTINEL-NOT-REBUILT",
		"CONTROL: without the signal the text must STAY — otherwise the arm above proves nothing")


## The autoload must still announce to the player as well as to the UI. If the Toast goes, the
## signal alone leaves a silent reconnection.
func test_the_player_is_still_told() -> void:
	var src := _src(IPM)
	assert_true(src.contains("Controller disconnected"),
		"the disconnect Toast must survive — the caption refresh complements it, not replaces it")
	assert_true(src.contains("input_device_changed.emit"), "and the signal must be emitted")
