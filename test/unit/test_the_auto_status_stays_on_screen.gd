extends GutTest

## The autobattle editor's "AUTO: ON/OFF" sat at a fixed size.x - 120. At Text Size 2.0 the pixel face's 3x step made
## "AUTO: OFF" wider than those 120 px and the frame read "AUTO: OF" at the right edge. It now keeps its old spot while it
## fits and moves left just enough to end on screen. At 1.0 nothing moves.
##
## ⛔ Width is judged with the label's theme font measured here (get_string_size), not with the minimum-size query the
## fix uses to place it.

const ED := "res://src/ui/autobattle/AutobattleGridEditor.gd"
const ABProfiles := preload("res://test/unit/helpers/autobattle_profiles.gd")
const SCALES := [1.0, 2.0, 2.5]

var _ed: Control = null
var _saved_persist := false
var _saved_scale = null
var _saved_enabled: Dictionary = {}
var _ab_profiles_entry: Dictionary = {}


func before_all() -> void:
	_ab_profiles_entry = ABProfiles.snapshot(get_tree().root.get_node_or_null("AutobattleSystem"))


func after_all() -> void:
	ABProfiles.restore(get_tree().root.get_node_or_null("AutobattleSystem"), _ab_profiles_entry)


func before_each() -> void:
	_saved_persist = AutobattleSystem._test_disable_persistence
	AutobattleSystem._test_disable_persistence = true
	_saved_scale = GameState.text_size_scale
	_saved_enabled = (AutobattleSystem.autobattle_enabled as Dictionary).duplicate(true)


func after_each() -> void:
	AutobattleSystem._test_disable_persistence = _saved_persist
	GameState.text_size_scale = _saved_scale
	AutobattleSystem.autobattle_enabled = _saved_enabled
	if _ed and is_instance_valid(_ed):
		_ed.queue_free()
	_ed = null


## Set the flag directly: set_autobattle_enabled also fires a first-time party-chat event flag.
func _open(scale: float, enabled: bool) -> void:
	if _ed and is_instance_valid(_ed):
		_ed.queue_free()
	GameState.text_size_scale = scale
	AutobattleSystem.autobattle_enabled["hero"] = enabled
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	add_child_autofree(vp)
	_ed = load(ED).new()
	_ed.size = Vector2(1280, 720)
	vp.add_child(_ed)
	_ed.setup("hero", "Hero")
	await get_tree().process_frame
	await get_tree().process_frame


func _text_w(l: Label) -> float:
	return l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x


func test_the_status_ends_on_screen() -> void:
	for s in SCALES:
		for on in [false, true]:
			await _open(s, on)
			var l: Label = _ed._status_label
			assert_eq(l.text, "AUTO: ON" if on else "AUTO: OFF", "CONTROL @%s: the status reads its state" % s)
			assert_lte(l.position.x + _text_w(l), _ed.size.x - 4.0, "@%s: '%s' ends on screen (%.0f + %.0f)" % [s, l.text, l.position.x, _text_w(l)])
			assert_gte(l.position.x, _ed.size.x * 0.5, "@%s: '%s' stays in the top right" % [s, l.text])


func test_at_2x_the_old_spot_ran_off_so_it_moved() -> void:
	await _open(2.0, false)
	var l: Label = _ed._status_label
	assert_gt(_ed.size.x - 120.0 + _text_w(l), _ed.size.x, "CONTROL: at the old spot 'AUTO: OFF' ends off screen (%.0f px wide)" % _text_w(l))
	assert_lt(l.position.x, _ed.size.x - 120.0, "so it moved left")


func test_toggling_keeps_it_on_screen() -> void:
	## The text changes width when it toggles (ON is shorter than OFF); the placement must follow the CURRENT text.
	await _open(2.5, true)
	var l: Label = _ed._status_label
	AutobattleSystem.autobattle_enabled["hero"] = false
	_ed._update_status_label()
	assert_eq(l.text, "AUTO: OFF", "CONTROL: the toggle changed the text")
	assert_lte(l.position.x + _text_w(l), _ed.size.x - 4.0, "after toggling, '%s' still ends on screen" % l.text)


func test_at_1x_nothing_moves() -> void:
	for on in [false, true]:
		await _open(1.0, on)
		assert_eq(_ed._status_label.position, Vector2(_ed.size.x - 120.0, 28.0), "@1.0 '%s' is where it was" % _ed._status_label.text)
