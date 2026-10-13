extends GutTest

## A critical hit from a physical ABILITY was audibly identical to a normal one.
##
## BattleScene._on_damage_dealt returns early for abilities ("ability sound already played at cast
## time"), which is right about the WEAPON layer and was also discarding the CRIT. Every crit cue
## sat below that return: play_attack_hit's `_crit` variant, the `critical_hit` key, and
## play_crit_thud -- whose ONLY caller in the repo is this function.
##
## Reachable through the Rogue's own kit, not a corner case:
##   shadow_step (rogue + ninja, support, 8 MP) -> BattleManager:5509 forces crit_chance = 1.0
##     for a physical ability ("Shadow Step guarantees the next attack, including a physical one")
##   backstab (rogue, physical, 2.0x) carries a standing crit_chance of 0.3
## So Shadow Step -> Backstab is a GUARANTEED crit for double damage that sounded like a tap.
##
## The fix is an ORDER, so this guard asserts an order: the crit accent is signalled above the
## return, the weapon layer stays below it.

const BATTLE_SCENE := "res://src/battle/BattleScene.gd"
const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"
const ABILITIES := "res://data/abilities.json"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
## Statement anchors, never delimiters: a statement cannot occur inside a type annotation or a
## nested value, so neither end of this range can land somewhere plausible and wrong.
const FUNC_HEAD := "func _on_damage_dealt(target: Combatant"
const EARLY_RETURN := '_current_ability_id != ""'
const CRIT_ACCENT := "SoundManager.play_crit_thud()"
const WEAPON_LAYER := "SoundManager.play_attack_hit("


func _body() -> String:
	var src: String = GdSource.code_of(BATTLE_SCENE)
	var i: int = src.find(FUNC_HEAD)
	if i < 0:
		return ""
	var j: int = src.find("\nfunc ", i + FUNC_HEAD.length())
	return src.substr(i, (j - i) if j > i else src.length() - i)


func _abilities() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ABILITIES))
	if not (parsed is Dictionary):
		return {}
	var d: Dictionary = parsed as Dictionary
	return (d.get("abilities", d) as Dictionary)


func test_the_anchors_this_guard_reads_still_exist() -> void:
	## FLOOR. Every arm below indexes into this body; if the function is renamed they all read -1
	## and the comparisons would be between two absences.
	var b: String = _body()
	assert_ne(b, "", "FLOOR: %s is gone from BattleScene — every arm below would compare -1 to -1" % FUNC_HEAD)
	if b == "":
		return
	for anchor in [EARLY_RETURN, CRIT_ACCENT, WEAPON_LAYER]:
		assert_true(b.contains(anchor),
			"FLOOR: `%s` is no longer in _on_damage_dealt; this guard's subject moved and the ordering arms are vacuous" % anchor)
	assert_lt(b.length(), GdSource.code_of(BATTLE_SCENE).length(),
		"FLOOR: the extracted body is the whole file — the `\\nfunc ` bound did not close")


func test_the_crit_accent_is_signalled_above_the_ability_return() -> void:
	## THE DEFECT. Order IS the behaviour here: below the return, an ability never reaches it.
	var b: String = _body()
	if b == "":
		return
	var accent: int = b.find(CRIT_ACCENT)
	var ret: int = b.find(EARLY_RETURN)
	assert_gt(accent, -1, "precondition: the crit accent is in this function")
	assert_gt(ret, -1, "precondition: the ability early-return is in this function")
	assert_lt(accent, ret,
		("the crit accent sits at %d and the ability early-return at %d, so an ability's crit is "
		+ "discarded: play_crit_thud has no other caller in the repo, and a Shadow-Step Backstab "
		+ "(forced crit, 2.0x) sounds identical to a normal one.") % [accent, ret])


func test_the_weapon_layer_stays_BELOW_the_ability_return() -> void:
	## CONTROL against the over-correction: hoisting the whole hit block would put a sword thump
	## under every spell. Only the crit ACCENT belongs above the return.
	var b: String = _body()
	if b == "":
		return
	var weapon: int = b.find(WEAPON_LAYER)
	var ret: int = b.find(EARLY_RETURN)
	assert_gt(weapon, -1, "precondition: the weapon-hit layer is in this function")
	assert_gt(weapon, ret,
		"play_attack_hit sits at %d, ABOVE the ability return at %d — a spell would now carry a weapon layer" % [weapon, ret])


func test_a_physical_ability_can_actually_crit() -> void:
	## PREMISE. If no physical ability could crit, the ordering above would be defending nothing.
	## Two independent routes, so the arm does not rest on one datum.
	var ab: Dictionary = _abilities()
	assert_gt(ab.size(), 50, "abilities.json did not load (%d entries)" % ab.size())
	var declared: Array = []
	for aid in ab.keys():
		var a: Variant = ab[aid]
		if a is Dictionary and str((a as Dictionary).get("type", "")) == "physical" \
				and float((a as Dictionary).get("crit_chance", 0.0)) > 0.0:
			declared.append(str(aid))
	assert_true(declared.has("backstab"),
		"backstab no longer declares a crit_chance; physical abilities that can crit are now %s" % [declared])
	## ⛔ THIS WAS TWO FILE-WIDE `contains` ANDed, which is two defects at once: they could be
	## satisfied at UNRELATED sites (a quantifier error no better pattern fixes), and
	## `crit_chance = 1.0 if cond else 0.5` satisfies the substring while making the crit
	## CONDITIONAL — a false green on the arm's own word, "forces". Co-located, and the value is
	## PARSED rather than prefixed.
	var bm: String = GdSource.code_of(BATTLE_MANAGER)
	var at: int = bm.find('has_status("shadow_step")')
	assert_gt(at, -1, "FLOOR: BattleManager no longer tests for the shadow_step status at all")
	if at < 0:
		return
	var near: String = bm.substr(at, 240)
	var forced: int = near.find("crit_chance = 1.0")
	assert_gt(forced, -1,
		("the crit_chance forcing is not within 240 chars of the shadow_step test, so the two "
		+ "halves of the guaranteed-crit route are no longer the same site"))
	if forced < 0:
		return
	var nl: int = near.find("\n", forced)
	var stmt: String = near.substr(forced, (nl - forced) if nl > forced else 60).strip_edges()
	assert_eq(stmt, "crit_chance = 1.0",
		("the forcing line is `%s`; anything past the bare assignment makes the crit CONDITIONAL, "
		+ "and this guard's premise is that shadow_step FORCES it") % stmt)
