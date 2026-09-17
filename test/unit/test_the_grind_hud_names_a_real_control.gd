extends GutTest

## The strip at the bottom of GameLoop's `_autogrind_overlay` is the legend a player reads WHILE a
## grind runs — AutogrindUI hides itself for the duration, so this is the live surface. It read:
##
##     "Y: Turbo    T: Dashboard    P: Pause    %s: Exit"   (only Exit derived)
##
## ⛔ THREE OF THE FOUR TOKENS WERE KEYBOARD LITERALS on a surface built for unattended PAD sessions.
## Turbo is JOY_BUTTON_Y, the NORTH face — on a Switch pad the letter Y sits on the WEST face, so the
## strip named a different PHYSICAL BUTTON there, not merely the wrong family's letter.
##
## 📌 "T: Dashboard" WAS CORRECT AND I FIRST "FIXED" IT INTO "T: Tier", WHICH WAS WRONG.
## `GrindTier` is {ACCELERATED, DASHBOARD}; `cycle_tier()` toggles the two, GameLoop logs
## "Dashboard shown (Tier 2)" at the other end of the same call, and the dashboard's own button
## calls the same function. There is no monster tier in this path. I took the phrase from
## `grind_reference_rows`' "Cycle monster tier" — the ONLY occurrence of it in the tree, and itself
## the mislabel. @cowir-adhoc and @cowir-autogrind caught the inversion before it folded.
##
## 🔑 SO THE LABEL IS NOW PINNED TO THE ENUM RATHER THAN TO A STRING I BELIEVE: the control that
## toggles GrindTier.DASHBOARD must be labelled for it. A future rename of the enum value reds this,
## which is the check that would have stopped me.
##
## 🔑 AND THIS SURFACE SAT OUTSIDE ALL THREE EXISTING AUTOGRIND LEGEND GUARDS, which scope to
## src/ui/autogrind/. The derivation defect they were written for lived one directory up, in the
## only legend on screen while the grind actually runs.

const HELPER := preload("res://src/ui/autogrind/AutogrindInputHelper.gd")
const GAMELOOP_SRC := "res://src/GameLoop.gd"

const XBOX := "Xbox Wireless Controller"
const SWITCH := "Nintendo Switch Pro Controller"
const SONY := "Sony DualSense Wireless Controller"


func _ipm() -> Node:
	return get_tree().root.get_node_or_null("/root/InputProfileManager")


## ⛔ NO EXISTENCE FLOOR FOR grind_hud_strip, DELIBERATELY. It is a STATIC reached through a
## class_name, so it resolves at PARSE time: rename it and this file does not load at all —
## `run_tests.sh` exits 3, "nothing ran", which is louder than the Risky an abort would score. A
## has_method() floor here is dead code, and my first draft of it did not even compile (has_method
## is non-static and cannot be called on the class). The autoload IS worth a control: it resolves at
## runtime and its absence would silently empty every token below.
func test_the_profile_manager_is_present() -> void:
	assert_ne(_ipm(), null,
		"CONTROL: InputProfileManager autoload must be present, or every derived token below is \"\"")


## ⛔ DERIVED FROM THE ENUM, NOT FROM A STRING. cycle_tier() switches into GrindTier.DASHBOARD, so
## that is what the control must be called. Asserting the literal "Dashboard" alone would have
## passed just as happily on my wrong version if I had written the literal the other way.
func test_the_tier_control_is_labelled_for_what_it_switches_to() -> void:
	var ctrl = load("res://src/autogrind/AutogrindController.gd")
	var tiers: Array = ctrl.GrindTier.keys()
	assert_true(tiers.has("DASHBOARD"),
		"CONTROL: GrindTier must still carry DASHBOARD, or this arm is about a vanished enum: %s" % [tiers])
	assert_false(str(tiers).to_lower().contains("monster"),
		"CONTROL: there is no monster tier — if one ever appears, this label needs rethinking: %s" % [tiers])
	var want: String = "DASHBOARD".capitalize()
	for dev in ["", XBOX, SWITCH, SONY]:
		var s: String = HELPER.grind_hud_strip(dev)
		assert_true(s.contains(want),
			"the control that toggles GrindTier.DASHBOARD must be labelled '%s' (device '%s'): %s"
				% [want, dev, s])


## The four controls the AUTOGRIND branch actually dispatches. A strip missing one advertises less
## than the surface offers, which is the under-claim half of the same defect.
func test_the_strip_covers_every_control_the_branch_binds() -> void:
	for dev in ["", XBOX, SWITCH, SONY]:
		var s: String = HELPER.grind_hud_strip(dev)
		for label in ["Turbo", "Dashboard", "Pause", "Exit"]:
			assert_true(s.contains(label), "'%s' missing from the strip on device '%s': %s" % [label, dev, s])


## With NO pad, every token must be the KEY the branch binds — naming one family's button to a
## keyboard player is the defect this helper exists to remove.
func test_with_no_pad_the_strip_names_keys() -> void:
	var s: String = HELPER.grind_hud_strip("")
	assert_true(s.begins_with("%s: Turbo" % HELPER.BRANCH_KEYS["turbo"]),
		"turbo is KEY_Y in the branch and must print that key with no pad attached: %s" % s)
	assert_true(s.contains("%s: Dashboard" % HELPER.ACTION_KEYS["tier_cycle"]),
		"the dashboard toggle is KEY_T in the branch: %s" % s)
	assert_true(s.contains("%s: Pause" % HELPER.ACTION_KEYS["pause"]),
		"pause is KEY_P in the branch — NOT battle_toggle_auto's keyboard binding, which is a "
		+ "different key the AUTOGRIND branch does not accept: %s" % s)


## ⛔ RELATIONSHIP, NOT LITERAL. Asserting "Ⓨ" here would pin a coincidental glyph and go red on a
## correct table change; asserting the token EQUALS what the profile manager derives for that index
## reds only when the strip stops deriving.
func test_the_pad_token_is_derived_not_written() -> void:
	var ipm := _ipm()
	for dev in [XBOX, SWITCH, SONY]:
		var want: String = str(ipm.button_name_for_index(JOY_BUTTON_Y, dev))
		assert_ne(want, "", "CONTROL: the profile manager must name the north face for '%s'" % dev)
		assert_true(HELPER.grind_hud_strip(dev).begins_with("%s: Turbo" % want),
			"turbo must be whatever %s calls JOY_BUTTON_Y, not a written letter" % dev)


## Turbo is the NORTH face. On a Switch pad the letter Y sits on the WEST face, so a literal "Y"
## names a different physical button there than on Xbox — the failure a family-blind legend hides.
func test_two_families_do_not_render_identically() -> void:
	var x: String = HELPER.grind_hud_strip(XBOX)
	var n: String = HELPER.grind_hud_strip(SWITCH)
	assert_ne(x, n,
		"Xbox and Nintendo render the SAME strip — the legend is frozen, not derived per family")


## ⛔ THIS ARM PROVES PAUSE IS *DERIVED*, NOT THAT IT FOLLOWS THE ACTION — and it was named for the
## stronger claim until mutation said otherwise. Swapping the action lookup for hint_for("pause"),
## which resolves the RAW JOY_BUTTON_BACK, left this GREEN: every built-in profile binds
## battle_toggle_auto to [4], and JOY_BUTTON_BACK *is* 4, so both paths print the same token. Only a
## CUSTOM binding separates them and setting one calls save_config() — a real write to the player's
## controls.json, which no test may do. So the distinction is unobservable behaviourally here and is
## defended by test_pause_is_read_from_the_action_in_source instead.
func test_pause_is_derived_for_the_players_pad() -> void:
	var ipm := _ipm()
	for dev in [XBOX, SONY]:
		var want: String = str(ipm.hint_for_action("battle_toggle_auto", dev))
		assert_ne(want, "", "CONTROL: battle_toggle_auto must resolve on '%s'" % dev)
		assert_true(HELPER.grind_hud_strip(dev).contains("%s: Pause" % want),
			"pause must be derived from the battle_toggle_auto ACTION on %s" % dev)


func _src(path: String) -> String:
	var GdSource = load("res://test/unit/helpers/gd_source.gd")
	return GdSource.code_of(path)


## Source-level, because the defect was a LITERAL in GameLoop rather than a wrong derivation.
func test_gameloop_builds_the_strip_from_the_helper() -> void:
	var code: String = _src(GAMELOOP_SRC)
	assert_ne(code, "", "CONTROL: GameLoop source must survive the comment strip")
	assert_true(code.contains("AutogrindInputHelper.grind_hud_strip("),
		"GameLoop must build the grind legend through the shared helper, not from literals")
	assert_false(code.contains('"Y: Turbo'),
		"the hardcoded legend must not come back — the tokens are per-device and GameLoop cannot "
		+ "know which pad is attached at build time")


## The strip is built ONCE and a grind runs unattended for a long time. Without this, a pad pulled
## mid-session leaves the legend naming buttons for a device that is gone.
func test_gameloop_re_derives_on_a_device_change() -> void:
	var code: String = _src(GAMELOOP_SRC)
	assert_true(code.contains("input_device_changed.connect(_refresh_autogrind_hints)"),
		"GameLoop must re-derive the grind legend when a pad is connected or removed")
	assert_true(code.contains("func _refresh_autogrind_hints"),
		"the refresh handler must exist by the name the connect names")


## The half the arm above cannot reach. A raw index keeps printing "Back" after a Controls rebind
## moves the action — invisible at the default binding, which is exactly why it needs a source arm.
func test_pause_is_read_from_the_action_in_source() -> void:
	var code: String = _src("res://src/ui/autogrind/AutogrindInputHelper.gd")
	assert_ne(code, "", "CONTROL: helper source must survive the comment strip")
	var body: String = code.split("static func grind_hud_strip")[-1].split("static func ")[0]
	assert_ne(body, "", "CONTROL: grind_hud_strip's body must be found, or this arm is vacuous")
	assert_true(body.contains('hint_for_action("battle_toggle_auto"'),
		"pause must resolve through the ACTION so a Controls rebind moves the label with the handler")
	assert_false(body.contains('hint_for("pause"'),
		"hint_for(\"pause\") resolves the RAW JOY_BUTTON_BACK — it prints the old button forever "
		+ "after a rebind, and at the default binding nothing on screen reveals it")
