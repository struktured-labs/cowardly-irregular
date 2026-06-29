extends GutTest

## tick 393: HeadlessBattleResolver._resolve_ability dispatches on
## `type` (canonical abilities.json schema) instead of `category`
## (which no ability authors).
##
## Pre-fix:
##   var category = ability.get("category", "magic")
##   match category:
##       "healing": ...
##       "magic": ...
##       "physical": ...
##       _: ...
##
## Since no ability authors `category`, every ability ran the magic
## damage branch. Heal abilities dealt magic damage TO their target
## instead of healing. Support abilities silently no-op'd into magic
## damage too. Major divergence between live combat and autogrind
## simulation, silently corrupting reward / tier calculations
## whenever a non-physical-non-magic ability fired.
##
## Post-fix reads `type` first, falls back to `category` if present
## (back-compat), and uses damage_multiplier as a power fallback so
## the canonical magic shape (damage_multiplier=X) doesn't read the
## default 1.0.

const HBR_PATH := "res://src/autogrind/HeadlessBattleResolver.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_dispatches_on_type_field() -> void:
	var src := _read(HBR_PATH)
	# The reads must prefer `type` over `category`.
	assert_true(src.contains("ability.get(\"type\", ability.get(\"category\""),
		"_resolve_ability must read `type` first, fall back to `category` for back-compat")
	# damage_multiplier fallback so eidolon casts read the right power.
	assert_true(src.contains("ability.get(\"damage_multiplier\""),
		"power resolution must accept damage_multiplier as a fallback for canonical magic shape")


func test_heal_ability_actually_heals_in_sim() -> void:
	# Probe a real heal ability through the resolver. Pre-fix this
	# would have dealt magic damage to the target; post-fix it heals.
	var js = Engine.get_main_loop().root.get_node_or_null("JobSystem")
	if js == null:
		pending("JobSystem autoload required")
		return
	# Find a heal-type ability.
	var heal_ability_id: String = ""
	for id in js.abilities:
		var ab: Dictionary = js.abilities[id]
		if str(ab.get("type", "")) == "healing":
			heal_ability_id = id
			break
	if heal_ability_id == "":
		pending("no healing-type ability found")
		return

	var script: GDScript = load(HBR_PATH)
	var hbr: Object = script.new()
	add_child_autofree(hbr)

	var c_script: GDScript = load("res://src/battle/Combatant.gd")
	var caster: Combatant = c_script.new()
	caster.initialize({"name": "Cleric", "max_hp": 100, "max_mp": 200,
		"attack": 10, "defense": 10, "magic": 30, "speed": 10})
	add_child_autofree(caster)
	var target: Combatant = c_script.new()
	target.initialize({"name": "Wounded", "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(target)
	target.current_hp = 30

	var hp_before: int = target.current_hp
	hbr._resolve_ability(caster, heal_ability_id, [target])
	# Pre-fix: target would have TAKEN damage (current_hp dropped).
	# Post-fix: target current_hp rises (or stays same if heal=0).
	assert_true(target.current_hp >= hp_before,
		"healing ability must NOT reduce target HP — pre-fix every heal dealt magic damage instead")
