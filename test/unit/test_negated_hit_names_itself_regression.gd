extends GutTest

## A negated hit used to lie, or say nothing, on the sprite.
##
## Physical immunity (null_entity) emitted attack_missed, so the floating text
## said MISS while the log said IMMUNE. Barrier and magic_block wrote a log line
## and left the sprite blank — the swing played and the ward vanished with no
## word where the damage number should be. The number that lands is unchanged;
## the popup now names the reason.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")
const ResultsScript = preload("res://src/battle/BattleResultsDisplay.gd")

var _bm
var _missed: bool
var _banners: Array


func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)
	_missed = false
	_banners = []
	_bm.attack_missed.connect(func(_t): _missed = true)
	_bm.hit_negated.connect(func(_t, banner): _banners.append(str(banner)))


func _reset() -> void:
	_missed = false
	_banners.clear()


func _fighter(name: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": 5000, "max_mp": 200,
		"attack": 80, "defense": 5, "magic": 40, "speed": 10})
	add_child_autofree(c)
	c.current_hp = c.max_hp
	c.current_ap = 4
	return c


func _null_entity() -> Combatant:
	var c := _fighter("Null Entity")
	c.set_meta("monster_type", "null_entity")
	return c


func test_a_physical_immunity_says_immune_and_not_miss() -> void:
	assert_true(_bm._monster_immune_to_category(_null_entity(), "physical"),
		"CONTROL: null_entity is physically immune, or this arm is not about the popup")
	var attacker := _fighter("Fighter")
	var target := _null_entity()
	target.add_status("barrier", 2)
	var saw_immune := false
	for s in range(1, 40):
		seed(s)
		target.current_hp = target.max_hp
		_reset()
		_bm._execute_attack(attacker, target)
		assert_eq(target.current_hp, target.max_hp, "immunity must still deal 0 — seed %d" % s)
		assert_true(target.has_status("barrier"),
			"immunity is checked before the ward, so the swing must not spend it — seed %d" % s)
		if _banners.has("IMMUNE"):
			assert_false(_missed, "the sprite must not also say MISS — seed %d" % s)
			assert_eq(_banners, ["IMMUNE"], "one banner, and it names the immunity — seed %d" % s)
			saw_immune = true
			break
		assert_true(_missed, "a swing that is not IMMUNE must be the phase-out miss, not silent damage — seed %d" % s)
		assert_eq(_banners.size(), 0, "a phase-out stays a miss — seed %d" % s)
	assert_true(saw_immune, "40 seeds must include a swing that reaches the immunity gate")


func test_a_physical_ability_on_an_immune_target_says_immune() -> void:
	var ability: Dictionary = JobSystem.get_ability("power_strike")
	assert_false(ability.is_empty(), "CONTROL: power_strike is a physical ability")
	var caster := _fighter("Fighter")
	var target := _null_entity()
	var saw_immune := false
	for s in range(1, 40):
		seed(s)
		target.current_hp = target.max_hp
		_reset()
		_bm._execute_physical_ability(caster, ability, [target])
		assert_eq(target.current_hp, target.max_hp, "the ability must still deal 0 — seed %d" % s)
		if _banners.has("IMMUNE"):
			assert_false(_missed, "an immune strike must not also read as a miss")
			saw_immune = true
			break
	assert_true(saw_immune, "40 seeds must include a physical ability that reaches the immunity gate")


func test_a_barrier_says_block_and_a_real_miss_does_not() -> void:
	var attacker := _fighter("Striker")
	attacker.add_status("blind", 5)
	var warded := _fighter("Warded")
	var saw_block := false
	var saw_miss := false
	for s in range(1, 40):
		seed(s)
		warded.current_hp = warded.max_hp
		warded.add_status("barrier", 2)
		_reset()
		_bm._execute_attack(attacker, warded)
		if _missed:
			assert_eq(_banners.size(), 0, "a miss is not a block — seed %d" % s)
			assert_true(warded.has_status("barrier"), "a miss must not spend the ward — seed %d" % s)
			saw_miss = true
			continue
		assert_eq(_banners, ["BLOCK"], "the swing the ward ate must say BLOCK — seed %d" % s)
		assert_eq(warded.current_hp, warded.max_hp)
		assert_false(warded.has_status("barrier"), "one hit still spends the ward")
		saw_block = true
		if saw_miss:
			break
	assert_true(saw_block, "a blind attacker must still land a swing the ward can eat")
	assert_true(saw_miss, "CONTROL: the same attacker must also miss, so BLOCK is not what every swing says")


func test_magic_block_and_a_warded_spell_say_block() -> void:
	var fire: Dictionary = JobSystem.get_ability("fire")
	assert_false(fire.is_empty(), "CONTROL: fire is the spell")
	var caster := _fighter("Mage")
	var blocked := _fighter("Blocked")
	blocked.add_status("magic_block", 1)
	_bm._execute_magic_ability(caster, fire, [blocked])
	assert_eq(_banners, ["BLOCK"], "magic block must name itself on the sprite")
	assert_false(_missed, "a cancelled spell is not a miss")
	assert_eq(blocked.current_hp, blocked.max_hp)
	assert_false(blocked.has_status("magic_block"), "one spell still spends magic block")
	var warded := _fighter("Warded")
	warded.add_status("barrier", 2)
	_reset()
	_bm._execute_magic_ability(caster, fire, [warded])
	assert_eq(_banners, ["BLOCK"], "a barrier on a spell must name itself too")
	assert_eq(warded.current_hp, warded.max_hp)
	assert_false(warded.has_status("barrier"))


func test_the_floating_word_is_the_banner_and_a_miss_stays_miss() -> void:
	var scene := Node2D.new()
	add_child_autofree(scene)
	var display = ResultsScript.new(scene)
	display.spawn_banner(Vector2(80, 80), "IMMUNE")
	display.spawn_banner(Vector2(80, 80), "BLOCK")
	display.spawn_miss_number(Vector2(400, 80))
	var words: Array = []
	for child in scene.get_children():
		if child.get_child_count() == 0:
			continue
		var label = child.get_child(0)
		if label is Label:
			words.append(label.text)
	assert_true(words.has("IMMUNE"), "the immunity popup says IMMUNE, not MISS — got %s" % str(words))
	assert_true(words.has("BLOCK"), "the ward popup says BLOCK — got %s" % str(words))
	assert_true(words.has("MISS"), "a real miss still says MISS — got %s" % str(words))


func test_the_battle_scene_shows_the_banner() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_true(src.contains("hit_negated.connect(_on_hit_negated)"),
		"BattleScene must listen — the signal alone never reaches the sprite")
	assert_true(src.contains("_results_display.on_hit_negated(target, banner)"),
		"the handler must spawn the banner rather than the miss popup")
