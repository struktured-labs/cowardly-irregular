extends GutTest

## The PARTY panel drew each HP number on the seam between the HP and MP bars and each MP number below the
## MP bar, over bars the default theme painted grey on grey (a full bar looked empty). A 5-member party
## used 16/12px bars for a 15/13px label anchored INSIDE them, so the label outgrew its bar downward.
## The bars keep the ruled 16/12 (top-clip) and the numbers 15/13 (readability); the number is centred on
## its bar instead, and the bar is styled (dark track, green / blue fill) and clipped.

const UIM := preload("res://src/battle/BattleUIManager.gd")

var _saved: Array = []


func before_each() -> void:
	_saved = BattleManager.player_party.duplicate()


func after_each() -> void:
	BattleManager.player_party.assign(_saved.filter(func(x): return is_instance_valid(x)))


func _party(n: int) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for i in n:
		var c := Combatant.new()
		c.initialize({"name": "PC%d" % i, "max_hp": 1948, "max_mp": 132, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
		add_child_autofree(c)
		out.append(c)
	return out


func _box(party: Array[Combatant]) -> VBoxContainer:
	BattleManager.player_party.assign(party)
	var holder := Control.new()
	holder.size = Vector2(200, 400)
	add_child_autofree(holder)
	var box: VBoxContainer = UIM.new(null)._create_character_status_box(0, party[0])
	box.custom_minimum_size = Vector2(190, 0)
	holder.add_child(box)
	return box


func test_each_number_fits_inside_its_bar_for_a_full_party() -> void:
	var box := _box(_party(5))
	await wait_physics_frames(2)
	var bad: Array[String] = []
	for pair in [["HP", "HPLabel"], ["MP", "MPLabel"]]:
		var bar: ProgressBar = box.get_node_or_null(pair[0])
		var label: Label = bar.get_node_or_null(pair[1]) if bar else null
		if bar == null or label == null:
			bad.append("%s/%s missing (BattleScene and two tests resolve this exact path)" % pair)
			continue
		## The label's line box is ~2x the digits (the fallback chain); it must be centred ON the bar and
		## grow both ways. Anchored full-rect it grew down from the bar's top, onto the next bar.
		if not (is_equal_approx(label.anchor_top, 0.5) and is_equal_approx(label.anchor_bottom, 0.5) \
				and label.grow_vertical == Control.GROW_DIRECTION_BOTH):
			bad.append("%s number is not centred on its bar (anchors %.1f/%.1f), so its oversized line box drops below it" % [pair[0], label.anchor_top, label.anchor_bottom])
		if not bar.clip_contents:
			bad.append("%s does not clip, so an overflow lands on the next bar" % pair[0])
	assert_eq(bad, [] as Array[String], "the HP/MP numbers must sit inside their own bars: %s" % str(bad))


func test_each_bar_has_a_fill_that_reads_as_a_bar() -> void:
	var box := _box(_party(5))
	for name_ in ["HP", "MP"]:
		var bar: ProgressBar = box.get_node(name_)
		assert_true(bar.has_theme_stylebox_override("fill") and bar.has_theme_stylebox_override("background"),
			"%s must not use the default grey-on-grey theme, where a full bar looks empty" % name_)
	var hp_fill: StyleBoxFlat = (box.get_node("HP") as ProgressBar).get_theme_stylebox("fill")
	var mp_fill: StyleBoxFlat = (box.get_node("MP") as ProgressBar).get_theme_stylebox("fill")
	assert_ne(hp_fill.bg_color, mp_fill.bg_color, "HP and MP read apart at a glance")
