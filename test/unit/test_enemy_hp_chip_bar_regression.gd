extends GutTest

## Phase B: HP bars stop snapping. Enemy floating bars gain a chip-damage trail (pale bar
## lagging the fill so the lost chunk reads); fills tween except at OFF tier (autogrind
## churn stays cheap). Party ProgressBars tween the same way with prior-tween kill.

func test_enemy_bar_has_trail_and_tiered_tween() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var i := src.find("func _create_enemy_hp_bar")
	assert_gt(i, -1)
	var body := src.substr(i, src.find("\nfunc ", i + 1) - i)
	assert_true("bar_trail" in body, "trail bar created")
	var order_trail := body.find("sprite.add_child(bar_trail)")
	var order_fill := body.find("sprite.add_child(bar_fill)")
	assert_true(order_trail < order_fill, "trail added BEFORE fill so it renders underneath")
	var u := src.find("func _update_enemy_hp_bars")
	var ubody := src.substr(u, src.find("\nfunc ", u + 1) - u)
	assert_true("Tier.OFF" in ubody, "OFF tier snaps directly")
	assert_true("tween_property(bar_fill" in ubody, "fill is tweened otherwise")
	assert_true("tween_interval(0.30)" in ubody, "trail lags the fill — that delay IS the chip effect")
	assert_true('bars.get("fill_tween")' in ubody and ".kill()" in ubody, "prior tween killed so rapid ticks don't fight")


func test_party_hp_bar_tweened_with_kill_guard() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleUIManager.gd")
	assert_gt(src.length(), 1000, "CONTROL: read a real file")
	assert_true('hp_bar.get_meta("hp_tween"' in src, "prior party tween tracked")
	assert_true('tween_property(hp_bar, "value"' in src, "party HP fill tweened")
	assert_true("_scene._tier()" in src, "tier gate consulted via the scene helper")
