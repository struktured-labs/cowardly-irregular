extends GutTest

## The autobattle editor's profile pill ("◀ 1/3: Default ▶") was a fixed 170 x 22 at the right edge with its label at a
## fixed x. The rename keyboard takes 16 characters, and at Text Size 2.0 the widest such name runs the label off the
## pill and off the screen. The pill now grows LEFT and DOWN to hold its label, and "AUTO: ON/OFF" steps below it. With
## a name that fits, at 1.0, nothing moves.
##
## ⛔ Widths are judged with the label's theme font measured here (get_string_size), not with the minimum-size query the
## fix uses to place it.

const ED := "res://src/ui/autobattle/AutobattleGridEditor.gd"
const ABProfiles := preload("res://test/unit/helpers/autobattle_profiles.gd")
const SCALES := [1.0, 2.0, 2.5]
## The longest name the rename keyboard accepts (16), all of the face's widest glyphs (5 columns).
const LONGEST := "WWWWWWWWWWWWWWWW"

var _ed: Control = null
var _saved_persist := false
var _saved_scale = null
var _ab_profiles_entry: Dictionary = {}


func before_all() -> void:
	_ab_profiles_entry = ABProfiles.snapshot(get_tree().root.get_node_or_null("AutobattleSystem"))


func after_all() -> void:
	ABProfiles.restore(get_tree().root.get_node_or_null("AutobattleSystem"), _ab_profiles_entry)


func before_each() -> void:
	_saved_persist = AutobattleSystem._test_disable_persistence
	AutobattleSystem._test_disable_persistence = true
	_saved_scale = GameState.text_size_scale
	ABProfiles.restore(get_tree().root.get_node_or_null("AutobattleSystem"), _ab_profiles_entry)


func after_each() -> void:
	AutobattleSystem._test_disable_persistence = _saved_persist
	GameState.text_size_scale = _saved_scale
	if _ed and is_instance_valid(_ed):
		_ed.queue_free()
	_ed = null


func _name_active(n: String) -> void:
	var idx: int = AutobattleSystem.get_active_profile_index("hero")
	assert_true(AutobattleSystem.rename_profile("hero", idx, n), "CONTROL: the active profile took the name '%s'" % n)


func _open(scale: float, n: String) -> void:
	if _ed and is_instance_valid(_ed):
		_ed.queue_free()
	GameState.text_size_scale = scale
	_name_active(n)
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


func _judge(tag: String) -> void:
	var l: Label = _ed._profile_label
	var p: ColorRect = _ed._profile_pill
	var st: Label = _ed._status_label
	var w := _text_w(l)
	assert_lte(l.position.x + w, _ed.size.x - 4.0, "%s: '%s' ends on screen (%.0f + %.0f)" % [tag, l.text, l.position.x, w])
	assert_gte(l.position.x, p.position.x, "%s: the name starts inside its pill" % tag)
	assert_lte(l.position.x + w, p.position.x + p.size.x + 0.5, "%s: the name ends inside its pill" % tag)
	assert_lte(l.position.y + l.get_line_height(), p.position.y + p.size.y + 0.5, "%s: the name's line ends inside its pill" % tag)
	assert_gte(st.position.y, p.position.y + p.size.y, "%s: AUTO sits below the pill" % tag)
	assert_lte(st.position.x + _text_w(st), _ed.size.x - 4.0, "%s: AUTO still ends on screen" % tag)


func test_the_longest_typed_name_fits_its_pill() -> void:
	for s in SCALES:
		for n in ["Default", LONGEST]:
			await _open(s, n)
			assert_string_contains(_ed._profile_label.text, n, "CONTROL @%s: the pill shows the name" % s)
			_judge("@%s '%s'" % [s, n])


func test_at_2x_the_longest_name_overran_the_old_pill() -> void:
	await _open(2.0, LONGEST)
	var w := _text_w(_ed._profile_label)
	assert_gt(5.0 + w, 170.0, "CONTROL: in the old 170 px pill the name would end past it (%.0f px)" % w)
	assert_gt(_ed._profile_pill.size.x, 170.0, "so the pill grew")


func test_a_rename_re_places_the_pill() -> void:
	await _open(2.0, "Default")
	_name_active(LONGEST)
	_ed._update_profile_indicator()
	assert_string_contains(_ed._profile_label.text, LONGEST, "CONTROL: the indicator shows the new name")
	_judge("after a rename")


func test_at_1x_a_name_that_fits_moves_nothing() -> void:
	await _open(1.0, "Default")
	assert_eq(_ed._profile_pill.position, Vector2(_ed.size.x - 180.0, 4.0), "the pill starts where it did")
	assert_eq(_ed._profile_pill.size, Vector2(170.0, 22.0), "and is the size it was")
	assert_eq(_ed._profile_label.position, Vector2(_ed.size.x - 175.0, 6.0), "the name is where it was")
	assert_eq(_ed._status_label.position, Vector2(_ed.size.x - 120.0, 28.0), "AUTO is where it was")
