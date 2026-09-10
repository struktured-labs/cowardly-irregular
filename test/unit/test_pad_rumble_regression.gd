extends GutTest

## The game shipped with SIXTY screen-shake sites and ZERO calls to start_joy_vibration — nothing a
## player's hands could feel, on a game whose reference context is a couch, a TV and a pad.
##
## Rumble now rides BattleJuice.add_trauma, so every existing impact site gets it with no change to
## its caller, correctly tiered by the machinery that already degrades juice with battle speed.
##
## 🛑 WHY THE DECISION IS TESTED AND NOT THE EFFECT: headless has no joypads, so rumble() returns at
## the pad check every time. A test that called rumble() and asserted "nothing crashed" would pass
## with every gate DELETED — the vacuous shape this lane has been finding all day. should_rumble()
## is the decision without the environment, so each gate can be shown to actually gate.

var _flags_before: Dictionary = {}


func before_each() -> void:
	if GameState and "battle_fx_flags" in GameState:
		_flags_before = GameState.battle_fx_flags.duplicate(true)
	BattleJuice._last_rumble_at = -1.0
	BattleJuice.burst_host = null
	Engine.time_scale = 1.0


func after_each() -> void:
	if GameState and "battle_fx_flags" in GameState:
		GameState.battle_fx_flags = _flags_before
	BattleJuice._last_rumble_at = -1.0
	Engine.time_scale = 1.0


## A real impact must want to rumble, or every arm below is testing a feature that never fires.
func test_a_real_impact_wants_to_rumble() -> void:
	assert_true(BattleJuice.should_rumble(0.5),
		"PRECONDITION: a mid-strength impact must want the motors at normal speed with the flag on")
	assert_false(BattleJuice.should_rumble(0.0),
		"a zero-strength impact must not — clampf would floor it to a silent buzz anyway")


## The toggle must actually gate. Unknown flags default TRUE, so this also pins that the feature is
## reachable before the Settings menu learns its name.
func test_the_flag_gates_it() -> void:
	assert_true(BattleJuice.should_rumble(0.5), "default: on")
	GameState.battle_fx_flags["rumble"] = false
	assert_false(BattleJuice.should_rumble(0.5),
		"turning the rumble flag off must stop it — a toggle that does not gate is decoration")
	GameState.battle_fx_flags["rumble"] = true
	assert_true(BattleJuice.should_rumble(0.5), "and back on again")


## AUTOGRIND AND TURBO MUST BE SILENT. A grind runs thousands of battles unattended; a pad buzzing
## on every hit for an hour is the worst version of this feature, and it drains a wireless pad flat.
func test_turbo_and_autogrind_are_silent() -> void:
	assert_eq(BattleJuice.presentation_tier(1.0, false, false), BattleJuice.Tier.REDUCED,
		"PRECONDITION: normal speed is not already OFF, or the arms below prove nothing")
	assert_eq(BattleJuice.presentation_tier(1.0, true, false), BattleJuice.Tier.OFF, "turbo is OFF")
	assert_eq(BattleJuice.presentation_tier(1.0, false, true), BattleJuice.Tier.OFF, "autogrind is OFF")
	assert_eq(BattleJuice.presentation_tier(4.0, false, false), BattleJuice.Tier.OFF, "4x is OFF")


## The tier gate must be wired into the decision, not merely exist. Engine.time_scale 4.0 is the
## same OFF the arm above measures, reached through the real code path.
func test_high_speed_stops_the_decision() -> void:
	assert_true(BattleJuice.should_rumble(0.5), "PRECONDITION: on at 1x")
	Engine.time_scale = 4.0
	assert_false(BattleJuice.should_rumble(0.5),
		"at 4x the tier is OFF and rumble must stop — otherwise a sped-up battle buzzes continuously")
	Engine.time_scale = 1.0


## A flurry of hits must not restart the motors every frame — that reads as one long buzz, not hits.
func test_a_flurry_is_throttled() -> void:
	BattleJuice._last_rumble_at = 100.0
	assert_false(BattleJuice.should_rumble(0.5, 100.0 + BattleJuice.RUMBLE_MIN_GAP * 0.5),
		"a second hit inside the minimum gap must be suppressed")
	assert_true(BattleJuice.should_rumble(0.5, 100.0 + BattleJuice.RUMBLE_MIN_GAP * 2.0),
		"and allowed once the gap has passed — a throttle that never opens is a mute")


## THE FREE COVERAGE CLAIM. Rumble is worth having because every existing impact already routes
## through add_trauma; if that call is removed, the feature silently covers nothing and no other
## test in the suite would notice.
func test_add_trauma_drives_it() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleJuice.gd")
	var at := src.find("func add_trauma(")
	assert_gt(at, -1, "add_trauma must exist")
	var stop := src.find("\nfunc ", at + 1)
	var body := src.substr(at, (stop - at) if stop > at else -1)
	assert_true(body.contains("rumble("),
		"add_trauma must drive rumble — that is the whole reason this needs no changes at the " +
		"impact sites themselves")


## Wall clock, not battle time. A 0.25s thump stretched by Engine.time_scale becomes a buzz, and
## this codebase has a documented history of bulk-multiplying durations by time_scale.
func test_the_duration_is_not_scaled_by_time_scale() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleJuice.gd")
	var at := src.find("func rumble(")
	var stop := src.find("\nfunc ", at + 1)
	var body := src.substr(at, (stop - at) if stop > at else -1)
	assert_true(body.contains("start_joy_vibration"), "rumble must actually call the engine")
	assert_false(body.contains("time_scale"),
		"vibration duration is WALL CLOCK — multiplying it by time_scale turns a thump into a buzz")


## AN UNADVERTISED FEATURE IS THE DEFECT THIS LANE HAS BEEN FIXING ALL DAY. The flag registry
## defaults unknown names to TRUE, so rumble would work while being invisible and un-turn-off-able —
## and rumble is exactly the feature some players need to disable.
func test_the_toggle_is_reachable_in_settings() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/SettingsMenu.gd")
	var at := src.find("BATTLE_FX_FLAGS := [")
	assert_gt(at, -1, "the fx toggle list must exist")
	# Bound at the LIST's end, not the first "]" — every row is itself an array, so the naive
	# find("]") returns only entry one and reports every later flag as missing. It did.
	var stop := src.find("\n]", at)
	assert_gt(stop, at, "the fx list must terminate")
	var list := src.substr(at, stop - at)
	assert_true(list.contains("\"rumble\""),
		"rumble must appear in the Settings fx list — the flag works either way, which is exactly " +
		"why an invisible one is worse than a missing one")
	assert_false(list.contains("\"zzq_not_a_flag\""), "CONTROL: this scan can report a flag ABSENT")


## Calling it with no pad attached must be a silent no-op, which is also every headless run.
func test_no_pad_is_a_silent_no_op() -> void:
	assert_true(Input.get_connected_joypads().is_empty(),
		"PRECONDITION: this harness has no pad, which is what makes the arm below meaningful")
	BattleJuice.rumble(0.9)
	assert_eq(BattleJuice._last_rumble_at, -1.0,
		"with no pad it must not even record a rumble — otherwise the throttle blocks the first " +
		"real one after a pad is plugged in")
