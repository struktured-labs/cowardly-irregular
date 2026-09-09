extends GutTest

## cowir-sprites registered 16 authored ability animations that had never rendered. Registration
## is only half: the engine asked for the ability's `animation` FIELD, which is a shared bucket
## ("buff", "skill", "cast_meta"), so a sheet carrying `battle_hymn` or `cleave` was still never
## requested BY THAT NAME. These pin the consumer half.

const SCENE := "res://src/battle/BattleScene.gd"
const ANIMATOR := "res://src/battle/BattleAnimator.gd"

func _abilities() -> Dictionary:
	var raw := FileAccess.get_file_as_string("res://data/abilities.json")
	assert_gt(raw.length(), 100, "CONTROL: read a non-empty abilities.json")
	var parsed = JSON.parse_string(raw)
	assert_not_null(parsed, "CONTROL: abilities.json parses")
	return parsed.get("abilities", parsed)

func _scene() -> String:
	var s := FileAccess.get_file_as_string(SCENE)
	assert_gt(s.length(), 1000, "CONTROL: read BattleScene")
	return s

func test_the_animation_field_really_is_a_shared_bucket() -> void:
	## The premise. If ids and animation fields matched, none of this would be needed.
	var ab := _abilities()
	var shared := 0
	var checked := 0
	for id in ab:
		var anim := str(ab[id].get("animation", ""))
		if anim == "":
			continue
		checked += 1
		if anim != str(id):
			shared += 1
	assert_gt(checked, 20, "CONTROL: examined real abilities (%d)" % checked)
	assert_gt(shared, 10,
		"most abilities name a shared bucket, not themselves — that is why the id must be preferred (%d of %d)" % [shared, checked])

func test_the_engine_prefers_the_ability_id_when_the_sheet_has_it() -> void:
	var s := _scene()
	assert_true(s.contains("func _ability_anim_name("),
		"a resolver must choose between the ability id and the animation field")
	assert_false(s.contains("animator.play_named_animation(str(ability.get(\"animation\", \"cast\")))"),
		"the raw animation-field call is what made bespoke art unreachable")

func test_the_preference_is_gated_on_the_sheet_actually_having_it() -> void:
	## Strictly additive: an unregistered id must fall back exactly as before, or every ability
	## without bespoke art changes animation at once.
	var s := _scene()
	var i := s.find("func _ability_anim_name(")
	var body := s.substr(i, 420)
	assert_true(body.contains("has_named_animation(id)"),
		"the id may only win when the sheet carries it")
	assert_true(body.contains("ability.get(\"animation\", \"cast\")"),
		"the old field must remain the fallback")

func test_the_animator_exposes_the_query() -> void:
	var a := FileAccess.get_file_as_string(ANIMATOR)
	assert_gt(a.length(), 500, "CONTROL: read BattleAnimator")
	assert_true(a.contains("func has_named_animation("),
		"BattleScene cannot ask about the sheet without this")

func test_advance_requests_its_animation_at_all() -> void:
	## The advance arm was a bare `pass`, so bespoke advance art could never render for any job.
	var s := _scene()
	var i := s.find("\t\t\"advance\":")
	assert_gt(i, -1, "CONTROL: located the advance arm")
	var arm := s.substr(i, 400)
	assert_true(arm.contains("play_named_animation(\"advance\")"),
		"the advance beat must request its animation")
	assert_true(arm.contains("has_named_animation(\"advance\")"),
		"and only when the job actually ships the art")

func test_defer_still_requests_its_own() -> void:
	assert_true(_scene().contains("play_named_animation(\"defer\")"),
		"CONTROL: defer already worked and must keep working — it is the arm that proves the pattern")
