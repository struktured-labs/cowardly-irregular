extends GutTest

## The grind Dashboard's battle readout re-fitted its px to each round's lines: whenever a line ("Party 9999/9999 HP · 4 up",
## a long cast) was wider than its box, the font stepped back toward 11 px, so the text changed size mid-grind and lost the
## Text Size. The ruling is that text grows, wraps or scrolls and never shrinks: it now keeps the Text Size and wraps inside
## its authored box. Arms: CONTROL (the widest round is wider than the box at the largest preset) · every preset keeps the
## px and every wrapped line fits the box · the px never moves as the rounds change · 100% keeps the authored box and px.
##
## ⛔ Fit is judged from the label's own wrapped layout (line count x line height, visible lines), not from a font query.

const DASHBOARD := "res://src/ui/autogrind/AutogrindDashboard.gd"
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const LONG_CAST := "Cleric casts Anima Reddita on the Fighter"
const LONG_HIT := "Fighter hits Glacius for 9999 CRIT"

var _ag: Dictionary
var _scale_was: float = 1.0
var _players_was: Array[Combatant] = []
var _enemies_was: Array[Combatant] = []


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true
	_scale_was = float(GameState.text_size_scale)
	_players_was = BattleManager.player_party.duplicate()
	_enemies_was = BattleManager.enemy_party.duplicate()


func after_each() -> void:
	BattleManager.player_party = _players_was
	BattleManager.enemy_party = _enemies_was
	GameState.text_size_scale = _scale_was
	AutogrindState.restore(_ag)


func _presets() -> Array:
	var p: Array = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must resolve, got %s" % [p])
	return p


func _dashboard_at(scale: float) -> Control:
	GameState.text_size_scale = scale
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	add_child_autofree(vp)
	var d: Control = load(DASHBOARD).new()
	d.size = Vector2(1280, 720)
	vp.add_child(d)
	await wait_frames(3)
	assert_eq(d.get_viewport().get_visible_rect().size, Vector2(1280, 720), "CONTROL: the Dashboard is laid out on the player's 1280x720 screen")
	return d


func _fighter(n: String, hp: int) -> Combatant:
	var c: Combatant = Combatant.new()
	add_child_autofree(c)
	c.initialize({"name": n, "max_hp": hp, "max_mp": 10, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	return c


## The widest round the readout shows (autogrind 27956): four 9999 HP members and six enemies, so the party line is the
## producer's real "Party 39996/39996 HP · 4 up"; a cast wider than any "Who → Name"; a crit.
func _widest_round(d: Control) -> void:
	var players: Array[Combatant] = []
	for n in ["Fighter", "Cleric", "Mage", "Rogue"]:
		players.append(_fighter(n, 9999))
	var enemies: Array[Combatant] = []
	for i in 6:
		enemies.append(_fighter("Glacius %d" % i, 9999))
	BattleManager.player_party = players
	BattleManager.enemy_party = enemies
	d._readout_round = 99
	d._readout_action = LONG_CAST
	d._readout_last_hit = LONG_HIT
	d._refresh_battle_readout()
	await wait_frames(2)


func _px(d: Control) -> int:
	return (d._battle_readout as Label).get_theme_font_size("font_size")


## Measured at the Text Size's px, NOT the label's: a fix that shrank the label would otherwise shrink the CONTROL with it.
func _longest_line_w(l: Label, px: int) -> float:
	var f: Font = l.get_theme_font("font")
	var w := 0.0
	for line in l.text.split("\n"):
		w = maxf(w, f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x)
	return w


func test_the_widest_round_is_wider_than_its_box() -> void:
	var top: float = float(_presets().max())
	var d: Control = await _dashboard_at(top)
	await _widest_round(d)
	var l: Label = d._battle_readout
	assert_string_contains(l.text, "Party 39996/39996 HP · 4 up", "CONTROL: the readout shows the real four-member party line")
	assert_gt(_longest_line_w(l, TextScale.scaled(d.READOUT_BASE_PX)), d._readout_box.x, "CONTROL @%sx: on one line the widest round is wider than its %s box, so a fit has to happen" % [top, d._readout_box])


func test_every_preset_keeps_the_text_size_and_wraps_inside_the_box() -> void:
	for s in _presets():
		var d: Control = await _dashboard_at(float(s))
		await _widest_round(d)
		var l: Label = d._battle_readout
		assert_eq(_px(d), TextScale.scaled(d.READOUT_BASE_PX), "@%sx: the readout keeps the Text Size (was stepped back toward 11)" % s)
		assert_eq(l.size.x, d._readout_box.x, "@%sx: the readout keeps its box's width" % s)
		assert_eq(l.get_visible_line_count(), l.get_line_count(), "@%sx: every wrapped line is shown (%d of %d)" % [s, l.get_visible_line_count(), l.get_line_count()])
		var h := l.get_line_count() * l.get_line_height()
		assert_lte(h, d._readout_box.y + 0.5, "@%sx: %d lines x %d px = %.0f px fit the %.0f px box" % [s, l.get_line_count(), l.get_line_height(), h, d._readout_box.y])
		assert_false(l.clip_text, "@%sx: nothing is clipped" % s)


func test_the_px_never_moves_as_the_rounds_change() -> void:
	var top: float = float(_presets().max())
	var d: Control = await _dashboard_at(top)
	var seen := {}
	d._on_readout_round_started(1)
	seen[_px(d)] = d._battle_readout.text
	d._readout_action = LONG_CAST
	d._refresh_battle_readout()
	seen[_px(d)] = d._battle_readout.text
	d._readout_last_hit = LONG_HIT
	d._refresh_battle_readout()
	seen[_px(d)] = d._battle_readout.text
	d._on_readout_battle_ended(true)
	seen[_px(d)] = d._battle_readout.text
	assert_eq(seen.keys(), [TextScale.scaled(d.READOUT_BASE_PX)], "@%sx: one px across a round, its cast, its hit and the idle line, got %s" % [top, seen.keys()])


func test_100_percent_keeps_the_authored_readout() -> void:
	var d: Control = await _dashboard_at(1.0)
	await _widest_round(d)
	var l: Label = d._battle_readout
	assert_eq(_px(d), 11, "the readout stays 11 px at 100%")
	assert_eq(l.position, Vector2(14, 24), "the readout sits where it did")
	assert_eq(d._readout_box, Vector2(296.0 - 28.0, (720.0 - 52.0 - 64.0) * 0.55 - 34.0), "its box is the authored one")
