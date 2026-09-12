extends GutTest

## The Jukebox binds four controls and its footer named three.
##
## 165 manifest rows at 14 visible, so paging is the only fast route through the list — and
## it was the one nobody advertised. Reaching the last row took ~17 page presses a player
## did not know they had, or 165 single presses.
##
## ⛔ THE OBVIOUS FIX CREATES THE OPPOSITE DEFECT. MenuPaging reuses battle_defer /
## battle_advance for the PAD only; on a keyboard it reads KEY_PAGEUP / KEY_PAGEDOWN. Those
## actions' keyboard bindings are L and R, which do nothing on this screen — so deriving
## both sides from hint_for_action() advertises a dead key. Measured on the live InputMap,
## not project.godot (whose events list ran past the window I first read):
##
##     battle_defer     keys ["L"]  joypad ["InputEventJoypadMotion", "JOY_9"]
##     battle_advance   keys ["R"]  joypad ["InputEventJoypadMotion", "JOY_10"]
##
## So the guard checks BOTH directions: the control is named, and the name is not a key that
## does nothing here.

const MENU := "res://src/ui/JukeboxMenu.gd"
const PAGING := "res://src/ui/MenuPaging.gd"


func _src(p: String) -> String:
	var s: String = FileAccess.get_file_as_string(p)
	assert_gt(s.length(), 500, "SCOPE control: %s read back %d chars" % [p, s.length()])
	return s


func test_control_the_screen_really_does_bind_paging() -> void:
	## Without this the footer could name a control the screen no longer has — the
	## named-but-unbound direction, which is what @cowir-controller's lane spent today on.
	var menu: String = _src(MENU)
	assert_gt(menu.find("MenuPaging.page_delta"), 0,
		"JukeboxMenu no longer pages, so the footer must stop advertising it — delete the Page clause in build_footer_text rather than leaving this guard to defend a dead control")
	var paging: String = _src(PAGING)
	for token in ["battle_defer", "battle_advance", "KEY_PAGEUP", "KEY_PAGEDOWN"]:
		assert_gt(paging.find(token), 0,
			"MenuPaging no longer binds %s — the footer's Page hint is derived from this pairing and would go stale silently" % token)


func test_the_footer_names_the_paging_control() -> void:
	var footer: String = JukeboxMenu.build_footer_text("")
	assert_true(footer.contains("Page"),
		"the footer does not name paging: '%s'. 165 rows at 14 visible and the fast route is undocumented — add it to build_footer_text, derived per device" % footer)


func test_the_key_the_keyboard_footer_NAMES_actually_pages() -> void:
	## ⛔ THIS ARM USED TO ASSERT A FALSEHOOD. It forbade "L/R: Page" on the grounds that
	## those keys "do nothing in this menu". They do: page_delta checks
	## is_action_pressed("battle_defer"), which a KEY event satisfies, so KEY_L returns -1
	## and KEY_R returns +1 next to KEY_PAGEUP/KEY_PAGEDOWN (@cowir-controller, msg 10697).
	## The old arm would have blocked a correct future caption while citing a dead-key
	## reason that was never true.
	##
	## The truthful version: whatever the footer advertises for paging must ACTUALLY page.
	var footer: String = JukeboxMenu.build_footer_text("")
	assert_true(footer.contains("PgUp/PgDn"),
		"the keyboard footer advertises something other than PgUp/PgDn for paging: '%s'. If that is deliberate, the key it names must satisfy MenuPaging.page_delta — extend the check below rather than deleting it" % footer)
	for probe in [[KEY_PAGEUP, "PgUp", -1], [KEY_PAGEDOWN, "PgDn", 1]]:
		var ev := InputEventKey.new()
		ev.keycode = probe[0]
		ev.pressed = true
		assert_eq(MenuPaging.page_delta(ev), probe[2],
			"the footer advertises %s but MenuPaging.page_delta returns %d for it, not %d — the caption names a key that does not page" % [probe[1], MenuPaging.page_delta(ev), probe[2]])


func test_control_the_shoulder_keys_also_page_so_the_choice_is_a_judgement() -> void:
	## Pins the fact that corrected the arm above, so nobody re-derives "L is dead" from
	## the footer's silence about it. If these stop paging, the comment in JukeboxMenu
	## explaining why PgUp/PgDn was CHOSEN becomes wrong and should be revisited.
	for probe in [[KEY_L, -1], [KEY_R, 1]]:
		var ev := InputEventKey.new()
		ev.keycode = probe[0]
		ev.pressed = true
		assert_eq(MenuPaging.page_delta(ev), probe[1],
			"the battle shoulder KEY no longer pages (page_delta=%d, expected %d) — then PgUp/PgDn is the only keyboard route and JukeboxMenu's comment calling it a judgement is stale" % [MenuPaging.page_delta(ev), probe[1]])

func test_a_pad_gets_its_own_familys_shoulders() -> void:
	## Three families, three renderings: a frozen string cannot satisfy this.
	var xbox: String = JukeboxMenu.build_footer_text("Xbox Series Controller")
	var switch: String = JukeboxMenu.build_footer_text("Nintendo Switch Pro Controller")
	var ps: String = JukeboxMenu.build_footer_text("Sony DualSense")
	assert_true(xbox.contains("LB/RB: Page"), "Xbox pad should page with LB/RB, got '%s'" % xbox)
	assert_true(ps.contains("L1/R1: Page"), "PlayStation pad should page with L1/R1, got '%s'" % ps)
	assert_true(switch.contains("L/R: Page"), "Switch pad should page with L/R, got '%s'" % switch)
	assert_ne(xbox, ps,
		"two pad families render an identical footer — the hint is frozen, not derived")
	assert_false(xbox.contains("PgUp"),
		"a pad player is told to press PageUp, a key they may not have: '%s'" % xbox)


func test_every_control_the_screen_binds_appears_once() -> void:
	## The join: four bound controls, four advertised. Counting is what catches a fifth
	## binding added later without a row, which is how the autogrind reference drifted.
	var footer: String = JukeboxMenu.build_footer_text("Xbox Series Controller")
	for clause in ["Navigate", "Page", "Play", "Stop"]:
		assert_eq(footer.count(clause), 1,
			"'%s' appears %d times in the footer — each control is named exactly once: '%s'" % [clause, footer.count(clause), footer])
