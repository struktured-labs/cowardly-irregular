extends GutTest

## struktured 2026-09-07: "the lightning (fulminis or whatever) needs work. I want something
## flashier and more absurd. Fat and the whole screen is like a storm with bolts etc."
## Lightning previously shared the `bolt` shape with dark magic and rendered one thin polyline.

const SCENE := "res://src/battle/BattleScene.gd"

func _abilities() -> Dictionary:
	var raw := FileAccess.get_file_as_string("res://data/abilities.json")
	assert_gt(raw.length(), 100, "CONTROL: read a non-empty abilities.json")
	var parsed = JSON.parse_string(raw)
	assert_not_null(parsed, "CONTROL: abilities.json parses")
	return parsed.get("abilities", parsed)

func _scene_src() -> String:
	var s := FileAccess.get_file_as_string(SCENE)
	assert_gt(s.length(), 1000, "CONTROL: read BattleScene")
	return s

func test_every_lightning_ability_resolves_to_the_storm() -> void:
	var ab := _abilities()
	var checked := 0
	for id in ab:
		var a: Dictionary = ab[id]
		if str(a.get("element", "")) != "lightning":
			continue
		checked += 1
		assert_eq(str(AbilityVFX.resolve(a)["shape"]), "storm",
			"%s is lightning and must storm" % id)
	assert_gt(checked, 0, "CONTROL: found lightning abilities in data (%d)" % checked)

func test_the_storm_did_not_leak_onto_dark_or_the_physical_fallback() -> void:
	## `bolt` was shared with dark and `strike` is the fallback for every unclassified physical.
	## A storm on either would put a full-screen weather event behind a sword swing.
	var dark := {"id": "shadow_bolt", "type": "magic", "element": "dark"}
	assert_eq(str(AbilityVFX.resolve(dark)["shape"]), "bolt", "dark keeps the bolt")
	var plain := {"id": "zzz_unclassified", "type": "physical"}
	assert_eq(str(AbilityVFX.resolve(plain)["shape"]), "strike", "the physical fallback is unchanged")

func test_storm_is_a_registered_shape() -> void:
	assert_true("storm" in AbilityVFX.SHAPES,
		"an unregistered shape falls to the default bloom arm silently")

func test_the_renderer_has_exactly_one_storm_arm() -> void:
	var src := _scene_src()
	assert_eq(src.count("\n\t\t\"storm\":"), 1,
		"_full_render_release_visual needs one storm match arm — the two-tab prefix is what tells a match arm from a comparison")
	assert_true(src.contains("func _full_render_storm("), "CONTROL: the storm builder exists")
	assert_true(src.contains("func _storm_bolt("), "CONTROL: the bolt builder exists")

func test_the_storm_scales_with_the_power_tier() -> void:
	var ab := _abilities()
	var base := AbilityVFX.power_for("thunder")
	var mid := AbilityVFX.power_for("thundara")
	var top := AbilityVFX.power_for("thundaga")
	assert_gt(mid, base, "the -a tier must out-power the base or the storm cannot grow")
	assert_gt(top, mid, "the -aga tier must out-power -a")
	assert_true(_scene_src().contains("float(style.get(\"power\", 1.0))"),
		"the renderer must read power off the style, or every tier storms identically")

func test_the_legacy_style_source_also_storms() -> void:
	## Two style sources feed one surface: AbilityVFX drives the cast anticipation,
	## _full_render_element_style drives the release. Its lightning arm said "strike".
	var src := _scene_src()
	assert_eq(src.count("\"shape\": \"strike\"}"), 0,
		"no style arm may still hand back the old thin strike for lightning")
	assert_true(src.contains("EffectSystem.EffectType.LIGHTNING, \"shape\": \"storm\""),
		"the lightning arm of _full_render_element_style must storm too")

func test_screen_flashes_go_through_the_gated_helper() -> void:
	var src := _scene_src()
	var idx := src.find("func _full_render_storm(")
	assert_gt(idx, -1, "CONTROL: located the storm builder")
	var body := src.substr(idx, 1800)
	assert_true(body.contains("_spawn_screen_flash("),
		"flashes must route through _spawn_screen_flash — it self-gates on _flashes_suppressed(), and a raw ColorRect would bypass the accessibility setting")

func test_the_storm_awaits_nothing() -> void:
	## Fire-and-forget by contract: the normal path must not block, or the execution watchdog's
	## cadence shifts under every lightning cast.
	var src := _scene_src()
	var idx := src.find("func _full_render_storm(")
	var body := src.substr(idx, 2600)
	assert_eq(body.count("await"), 0,
		"the storm must not await — it is called from the fire-and-forget release path")
