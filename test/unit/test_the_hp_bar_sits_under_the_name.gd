extends GutTest

## An enemy's HP bar floated on its body, detached from its name — the Cave Rat King's sat on his belly ~65px
## above "CAVE RAT KING" in a watched real boss battle. _add_sprite_label seats the name on the FIGURE (the idle
## frame's drawn body, because the monster sheets pad their frames differently), but _create_enemy_hp_bar kept a
## hard-coded local (-20, 52) "below the name label": the sibling the label fix missed. The bar now places itself
## from the label. Derived: every registered monster sheet, through the real label and bar builders.

const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const BattleState := preload("res://test/unit/helpers/battle_state.gd")
const SCENE := "res://src/battle/BattleScene.tscn"
## The bar's top may sit this far under the name's bottom, and its centre this far off the name's centre.
const MAX_GAP := 6.0
const MAX_OFF_CENTRE := 2.0

var _guard: RefCounted = null


func before_each() -> void:
	_guard = BattleState.new()
	_guard.snapshot()


func after_each() -> void:
	if _guard != null:
		_guard.restore()


func after_all() -> void:
	SoundState.restore()


func _name_label(sprite: Node) -> Label:
	for c in sprite.get_children():
		if c is Label:
			return c
	return null


func test_every_monster_s_bar_sits_right_under_its_name() -> void:
	var scene = load(SCENE).instantiate()
	add_child_autofree(scene)
	var m = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	var ids: Array = (m.get("monster_sheets", {}) as Dictionary).keys()
	ids.sort()
	var bad: Array = []
	var judged := 0
	for id in ids:
		var frames = HybridSpriteLoader.load_monster_sprite_frames(str(id))
		if frames == null or not frames.has_animation(&"idle"):
			continue
		var spr := AnimatedSprite2D.new()
		spr.sprite_frames = frames
		spr.animation = &"idle"
		add_child_autofree(spr)
		scene._add_sprite_label(spr, str(id).to_upper(), 40.0)
		var enemy := Combatant.new()
		autofree(enemy)
		scene._create_enemy_hp_bar(enemy, spr)
		var label := _name_label(spr)
		var bar: ColorRect = scene._enemy_hp_bars[enemy]["bar_bg"]
		if label == null or bar == null:
			bad.append("%s: no label or bar" % id)
			continue
		judged += 1
		var name_bottom := label.position.y + label.get_minimum_size().y
		var gap := bar.position.y - name_bottom
		var off := absf((bar.position.x + bar.size.x * 0.5) - (label.position.x + label.size.x * 0.5))
		if gap < 0.0 or gap > MAX_GAP:
			bad.append("%s: bar %.0fpx from the name's bottom" % [id, gap])
		elif off > MAX_OFF_CENTRE:
			bad.append("%s: bar %.0fpx off the name's centre" % [id, off])
	assert_gt(judged, 50, "CONTROL: the monster sheets were judged (%d)" % judged)
	assert_eq(bad, [], "%d monster(s) with a bar detached from the name: %s" % [bad.size(), str(bad.slice(0, 8))])
