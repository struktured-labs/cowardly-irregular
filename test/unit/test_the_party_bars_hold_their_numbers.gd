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


## controller 26234: at 200% the battle PARTY panel cut its "HP: 90/90" glyphs, because the bars kept the ruled 22/18 (16/12)
## while their numbers scaled. Each bar now grows with its number; at 100% it is still the ruled bar.
const SETTINGS := "res://src/ui/SettingsMenu.gd"
const SLACK := 0.5


func _presets() -> Array:
	var p: Array = (load(SETTINGS) as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must hold more than one step")
	return p


func _measure(s: float, members: int) -> Dictionary:
	var saved := float(GameState.text_size_scale)
	GameState.text_size_scale = s
	var box := _box(_party(members))
	GameState.text_size_scale = saved
	await wait_physics_frames(2)
	var out := {}
	for pair in [["HP", "HPLabel"], ["MP", "MPLabel"]]:
		var bar: ProgressBar = box.get_node(pair[0])
		var label: Label = bar.get_node(pair[1])
		var px: int = label.get_theme_font_size("font_size")
		out[pair[0]] = {"bar": bar.size.y, "px": px}
	return out


func test_the_floor_names_what_this_file_drives() -> void:
	assert_true(UIM.new(null).has_method("_create_character_status_box"), "BattleUIManager._create_character_status_box must exist")
	assert_true(UIM.new(null).has_method("bar_height_for_text"), "BattleUIManager.bar_height_for_text must exist")


## Arm 1: the numbers' font really grows with Text Size, or the fit arm below judges nothing.
func test_the_numbers_grow_with_the_text() -> void:
	for members in [4, 5]:
		var base: Dictionary = await _measure(1.0, members)
		var grew := 0
		for s in _presets():
			if float(s) <= 1.0:
				continue
			var m: Dictionary = await _measure(float(s), members)
			for k in ["HP", "MP"]:
				assert_gt(int(m[k]["px"]), int(base[k]["px"]), "@%s x%d the %s number's font grew" % [s, members, k])
				grew += 1
		assert_gt(grew, 0, "CONTROL x%d: a preset above 100%% was judged" % members)


## Arm 2 (THE DEFECT): the number never takes a bigger share of its bar than at 100%, where the ruled bar holds the digits.
## Judged on the BUILT bar against the label's font px; get_height is the fallback chain's line box (12->24->36), not the digits.
func test_each_bar_grows_with_its_number_at_every_text_size() -> void:
	var bad: Array = []
	for members in [4, 5]:
		var base: Dictionary = await _measure(1.0, members)
		for s in _presets():
			var m: Dictionary = await _measure(float(s), members)
			for k in ["HP", "MP"]:
				var need: float = float(base[k]["bar"]) * maxf(1.0, float(m[k]["px"]) / float(base[k]["px"]))
				if float(m[k]["bar"]) < need - SLACK:
					bad.append("@%s x%d %s bar %.0f px for a %d px number (100%%: %.0f for %d) needs %.1f" % [s, members, k, m[k]["bar"], m[k]["px"], base[k]["bar"], base[k]["px"], need])
	assert_eq(bad, [], "a party bar holds its number at every Text Size:\n%s" % "\n".join(PackedStringArray(bad)))


## CONTROL: at 100% (and below) the bars are exactly the ruled 22/18 and 16/12 a player sees today.
func test_at_100_percent_the_bars_are_the_ruled_bars() -> void:
	var four: Dictionary = await _measure(1.0, 4)
	var five: Dictionary = await _measure(1.0, 5)
	assert_almost_eq(float(four["HP"]["bar"]), 22.0, 0.01, "4-party HP bar")
	assert_almost_eq(float(four["MP"]["bar"]), 18.0, 0.01, "4-party MP bar")
	assert_almost_eq(float(five["HP"]["bar"]), 16.0, 0.01, "5-party HP bar")
	assert_almost_eq(float(five["MP"]["bar"]), 12.0, 0.01, "5-party MP bar")
	var small: Dictionary = await _measure(0.8, 5)
	assert_almost_eq(float(small["HP"]["bar"]), 16.0, 0.01, "80% never shrinks a bar under its ruled height")
