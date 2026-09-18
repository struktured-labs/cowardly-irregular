extends GutTest

## Umbraxis (shadow_dragon, W1) casts null_field — 22 MP, all enemies, "suppresses all abilities
## for one turn" — and it silenced nobody. It authors effect `ability_silence` and is type "magic",
## so it lands through _apply_ability_status, which spelled the AUTHORED name. The gate is
## has_status("silence") — JobSystem:721, BattleManager:4669 and :7767 — and nothing reads
## "ability_silence" except a BattleScene SFX arm keyed on the EFFECT.
##
## Third instance of the same class in one session (fester, memory_leak, this), and the same reason
## each time: an arm composing the right key exists in _execute_support_ability, and no shipped
## ability authoring these effects is typed support/song/status, so it is unreachable.
##
## ⚠️ This fix made the KEY correct on both engines; the grind still IGNORED silence when it
## landed, so the divergence only became observable here. Closed separately — see
## test_a_grind_ignored_silence_regression, which gates _resolve_ability the way live gates
## _execute_ability. The declared-gap arm that lived here was deleted when that shipped, as its
## own comment instructed.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")

var _res


func before_each() -> void:
	_res = ResolverScript.new()
	for n in ["AutogrindSystem", "AutobattleSystem"]:
		var sys: Node = get_node_or_null("/root/" + n)
		if sys != null and "_test_disable_persistence" in sys:
			sys._test_disable_persistence = true


func _combatant(nm: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": nm, "max_hp": 100, "max_mp": 99,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	c.current_mp = c.max_mp
	return c


func _certain(ability_id: String) -> Dictionary:
	## The authored ability with its roll removed — null_field authors effect_chance 0.3.
	var js: Node = get_node_or_null("/root/JobSystem")
	if js == null or not js.has_method("get_ability"):
		return {}
	var ab: Dictionary = js.get_ability(ability_id).duplicate(true)
	if ab.is_empty():
		return {}
	ab["effect_chance"] = 1.0
	return ab


func test_null_field_lands_the_key_the_gate_reads() -> void:
	var bm: Node = get_node_or_null("/root/BattleManager")
	var ab: Dictionary = _certain("null_field")
	if bm == null or not bm.has_method("_apply_ability_status") or ab.is_empty():
		pass_test("autoloads unavailable")
		return
	assert_eq(str(ab.get("effect", "")), "ability_silence", "CONTROL: null_field still authors ability_silence")
	var target := _combatant("Party Member")
	bm._apply_ability_status(_combatant("Umbraxis"), target, ab)
	assert_true(target.has_status("silence"),
		"null_field must land the key the gate reads — nothing reads 'ability_silence'")
	assert_false(target.has_status("ability_silence"), "the authored effect name is the junk key")


func test_a_silenced_member_cannot_cast() -> void:
	## The consequence. The key landing is not the point; the ability being suppressed is.
	var js: Node = get_node_or_null("/root/JobSystem")
	var bm: Node = get_node_or_null("/root/BattleManager")
	var ab: Dictionary = _certain("null_field")
	if js == null or bm == null or not js.has_method("can_use_ability") or ab.is_empty():
		pass_test("autoloads unavailable")
		return
	var target := _combatant("Mage")
	## can_use_ability ends at knows_ability, so a bare fixture fails the CONTROL for the wrong
	## reason — teach it the spell, then the only variable left is the silence.
	target.learned_abilities.append("fire")
	assert_true(js.can_use_ability(target, "fire"),
		"CONTROL: an unsilenced mage can cast, or the assert below proves nothing")
	bm._apply_ability_status(_combatant("Umbraxis"), target, ab)
	assert_false(js.can_use_ability(target, "fire"),
		"a member hit by Null Field must be unable to cast — that is the whole ability")


func test_the_grind_lands_the_same_key() -> void:
	## The engines must agree on the key even where only one of them acts on it.
	var ab: Dictionary = _certain("null_field")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var target := _combatant("Party Member")
	_res._maybe_inflict_status(_combatant("Umbraxis"), target, ab, "null_field")
	assert_true(target.has_status("silence"), "the grind must spell the same key live does")
	assert_false(target.has_status("ability_silence"), "and not the authored name")


func test_the_support_arm_stays_and_stays_unreachable() -> void:
	## The arm that composes the right key is in _execute_support_ability and never ran, because no
	## shipped ability authoring this effect is typed support/song/status. Pinned both ways: deleting
	## it is a silent loss if something is ever typed that way, and re-typing null_field to reach it
	## would route a 22 MP whole-party attack through the support executor instead.
	var js: Node = get_node_or_null("/root/JobSystem")
	if js == null or not js.has_method("get_ability"):
		pass_test("JobSystem autoload unavailable")
		return
	assert_eq(str(js.get_ability("null_field").get("type", "")), "magic",
		"null_field is type magic — that is why the support arm never saw it")
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_gt(src.find("\n\t\t\"ability_silence\":"), -1,
		"the support arm must remain for anything later typed support/song/status")
