extends GutTest

## Every status a battler carries is ANIMATED on the battler, not only named in a badge above it.
##
## struktured 2026-11-01: "the sleep indicator could be animated, the poison, all stats, more of that polish."
## StatusAura draws a looping motif per status (Zzz, bubbles, circling stars, an arrow per stat in that stat's colour).
##
## THE CORPUS IS CHAINED, NOT LISTED. test_status_icons_cover_applied_statuses derives every status the engine applies
## and makes BattleScene.STATUS_ICON_CONFIG cover it; this file makes StatusAura.MOTIF cover that config. So a new status
## reds the badge guard first, then this one, and nobody keeps a list. The FALLBACK mote exists so a runtime battler never
## shows nothing, and that is exactly why a status mapped only by falling back counts as UNMAPPED here.

const SCENE_SRC := "res://src/battle/BattleScene.gd"

var _scene = null


func before_each() -> void:
	_scene = load(SCENE_SRC).new()


func after_each() -> void:
	if _scene != null and is_instance_valid(_scene):
		_scene.free()
	_scene = null
	Engine.time_scale = 1.0


func _config_statuses() -> Array:
	var cfg: Dictionary = load(SCENE_SRC).get_script_constant_map().get("STATUS_ICON_CONFIG", {})
	var out: Array = cfg.keys()
	out.append("doom_counter")  # a Combatant field the badge row surfaces as a status; it gets the same treatment
	return out


func _aura(statuses: Array) -> StatusAura:
	var a := StatusAura.new()
	add_child_autofree(a)
	a.set_statuses(statuses)
	return a


func test_the_corpus_is_the_badge_config() -> void:
	var corpus := _config_statuses()
	assert_gt(corpus.size(), 25, "CONTROL: STATUS_ICON_CONFIG must load; found %d keys" % corpus.size())
	assert_true(corpus.has("sleep") and corpus.has("attack_up"), "CONTROL: named members of the config must be present")


func test_every_status_has_its_own_motif() -> void:
	var unmapped: Array = []
	for s in _config_statuses():
		if not StatusAura.MOTIF.has(s):
			unmapped.append(s)
	assert_eq(unmapped, [],
		"a status the battle applies has no animated motif, so it falls to the generic mote. Map it in StatusAura.MOTIF: %s" % str(unmapped))


func test_every_stat_buff_and_debuff_is_an_arrow_in_its_stats_colour() -> void:
	var bad: Array = []
	var seen := 0
	for s in _config_statuses():
		var st := str(s)
		if not (st.ends_with("_up") or st.ends_with("_down")):
			continue
		seen += 1
		var a := StatusAura.arrow_of(st)
		if StatusAura.motif_for(st) != "arrow" or not StatusAura.STAT_COLOR.has(a[0]) or a[1] != st.ends_with("_up"):
			bad.append(st)
	assert_gt(seen, 6, "CONTROL: the config has the stat buff/debuff pairs; saw %d" % seen)
	assert_eq(bad, [], "a stat buff/debuff is not an arrow pointing its way in its stat's colour: %s" % str(bad))


func test_arrows_stack_in_columns_that_never_overlap() -> void:
	var a := _aura(["attack_up", "defense_down", "magic_up", "speed_down", "sleep"])
	var xs: Array = []
	for slot in 4:
		xs.append(a.arrow_x(slot, 4))
	for i in range(1, xs.size()):
		assert_gt(float(xs[i]) - float(xs[i - 1]), 11.9, "arrow columns %d and %d overlap: %s" % [i - 1, i, str(xs)])
	assert_eq(a.shown_kinds().count("arrow"), 4, "four stat statuses, four arrows")
	assert_true(a.shown_kinds().has("zzz"), "the sleep motif shows beside the arrows")


func test_nothing_shown_means_nothing_drawn() -> void:
	var a := _aura(["poison"])
	assert_true(a.visible and a.is_processing(), "CONTROL: a status shows and animates")
	a.set_statuses([])
	assert_false(a.visible, "no status, no overlay")
	assert_false(a.is_processing(), "no status, no per-frame redraw")
	a.set_statuses(["permakilled"])
	assert_false(a.visible, "a permakilled battler is gone; nothing is drawn on it")


func test_an_unknown_status_still_shows_something() -> void:
	var a := _aura(["zz_not_a_real_status"])
	assert_true(a.visible, "a status nobody mapped must still show at runtime")
	assert_eq(a.shown_kinds(), [StatusAura.FALLBACK], "it falls to the generic mote")


func test_a_status_is_not_hidden_at_four_times_speed() -> void:
	Engine.time_scale = 4.0
	var a := _aura(["stun", "attack_down"])
	await get_tree().process_frame
	assert_true(a.visible and a.is_processing(), "statuses are state, so they show at every battle speed")


func _sprite() -> AnimatedSprite2D:
	var img := Image.create(32, 48, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(8, 6, 16, 40), Color.WHITE)
	var frames := SpriteFrames.new()
	frames.add_frame(&"idle", ImageTexture.create_from_image(img))
	var sp := AnimatedSprite2D.new()
	sp.sprite_frames = frames
	sp.scale = Vector2(2.0, 2.0)
	add_child_autofree(sp)
	return sp


func test_the_battle_scene_gives_each_battler_an_aura() -> void:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Sleeper"
	var sp := _sprite()
	_scene._setup_status_icons(c, sp)
	var aura = sp.get_node_or_null("StatusAura")
	assert_not_null(aura, "the battle scene must hang a StatusAura on every battler it sets a badge row up for")
	if aura == null:
		return
	c.add_status("sleep", 2)
	assert_eq(aura.shown_kinds(), ["zzz"], "a status added mid-battle reaches the aura through the badge refresh")
	assert_almost_eq(aura.scale.x, 0.5, 0.001, "the aura is counter-scaled to screen pixels (sprite at 2x)")
	assert_gt(aura.body.size.y, 60.0, "the body comes from the idle frame's FIGURE at screen scale (40 px tall x 2)")
