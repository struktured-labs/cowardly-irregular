extends GutTest

## tick 137 regression: AbilitiesMenu._get_ability_color must
## return the semantically correct color for every ability type
## that exists in data/abilities.json. Pre-fix only 4 types had
## explicit branches; the other 6 (escape, meta, mp_restore,
## revival, song, summon) silently fell through to PHYSICAL_COLOR.
## So a Bard's "Battle Hymn" rendered red-orange like a sword
## attack, and a Scriptweaver's "Edit Formula" had the same color
## as Power Strike.
##
## This is a runtime test (loads the script, invokes the function
## with synthetic data dicts) — the visible behavior matters more
## than the source shape.

const ABILITIES_MENU := "res://src/ui/AbilitiesMenu.gd"


func _color(ability_type: String) -> Color:
	var script_class = load(ABILITIES_MENU)
	var inst: Node = script_class.new()
	add_child_autofree(inst)
	return inst._get_ability_color({"type": ability_type})


func test_physical_returns_physical_color() -> void:
	var script_class = load(ABILITIES_MENU)
	var expected: Color = script_class.PHYSICAL_COLOR
	assert_eq(_color("physical"), expected,
		"physical type must return PHYSICAL_COLOR")


func test_magic_family_returns_magic_color() -> void:
	# 5 magic-family types — all should be MAGIC_COLOR.
	var script_class = load(ABILITIES_MENU)
	var expected: Color = script_class.MAGIC_COLOR
	for t in ["magic", "healing", "mp_restore", "revival", "summon"]:
		assert_eq(_color(t), expected,
			"'%s' must return MAGIC_COLOR — caster-style ability" % t)


func test_support_family_returns_support_color() -> void:
	var script_class = load(ABILITIES_MENU)
	var expected: Color = script_class.SUPPORT_COLOR
	for t in ["support", "song", "escape"]:
		assert_eq(_color(t), expected,
			"'%s' must return SUPPORT_COLOR — ally-aid or utility" % t)


func test_meta_returns_distinct_meta_color() -> void:
	# META abilities (Scriptweaver/Time Mage/Necromancer/Bossbinder)
	# manipulate save/code/reality. They need their own color so
	# the player can see the menu entry stands apart from anything
	# physical or magical.
	var script_class = load(ABILITIES_MENU)
	var expected: Color = script_class.META_COLOR
	assert_eq(_color("meta"), expected,
		"meta type must return META_COLOR — Scriptweaver/etc")


func test_meta_color_is_distinct_from_others() -> void:
	# Cross-check: META_COLOR must be visually distinguishable from
	# the other three. Otherwise adding the branch is pointless.
	var script_class = load(ABILITIES_MENU)
	var meta_c: Color = script_class.META_COLOR
	for other in [script_class.MAGIC_COLOR, script_class.PHYSICAL_COLOR, script_class.SUPPORT_COLOR]:
		assert_ne(meta_c, other,
			"META_COLOR must differ from the other ability colors — color-blindness aside, distinct hue helps the player")


func test_unknown_type_falls_back_to_physical() -> void:
	# Defensive: an ability with a type the menu doesn't know
	# about should NOT crash, must produce SOME color. Pin to
	# PHYSICAL as the safe default.
	var script_class = load(ABILITIES_MENU)
	var expected: Color = script_class.PHYSICAL_COLOR
	assert_eq(_color("brand_new_type_xyz"), expected,
		"unknown type must safely fall back to PHYSICAL_COLOR")


func test_every_data_abilities_type_handled_explicitly() -> void:
	# The match block must have an explicit branch for every type
	# present in data/abilities.json. The source-level pin guards
	# against new types being added to JSON without the menu being
	# updated.
	var src: String = FileAccess.get_file_as_string(ABILITIES_MENU)
	var idx: int = src.find("func _get_ability_color")
	assert_gt(idx, -1, "_get_ability_color must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	# Every type from `grep -oh '"type":\s*"[a-z_]*"' data/abilities.json | sort -u`.
	# If a new type is added to JSON, add it to this list AND to
	# _get_ability_color in the same commit.
	var types_in_json: Array[String] = [
		"escape", "healing", "magic", "meta", "mp_restore",
		"physical", "revival", "song", "summon", "support"
	]
	for t in types_in_json:
		var quoted: String = "\"" + t + "\""
		assert_true(body.contains(quoted),
			"_get_ability_color must explicitly mention '%s' — every type in abilities.json needs an explicit branch (no silent default)" % t)


func test_boss_persona_resolver_renamed() -> void:
	# Tick 137 cross-cutting: the renamed function name must be
	# present and the old name absent.
	var bm_src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_true(bm_src.contains("func _resolve_boss_display_name(persona_id: String)"),
		"_resolve_boss_display_name must exist — single canonical resolver")
	assert_false(bm_src.contains("func _gloat_boss_display_name(persona_id: String)"),
		"_gloat_boss_display_name must be removed — renamed to _resolve_boss_display_name")


func test_intent_picker_routes_through_resolver() -> void:
	# Pin: the intent-picker context's persona-text fallback now
	# uses the canonical resolver, not the direct BossDialogue
	# call. So a dungeon-subclass-set combatant_name wins.
	var bm_src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	# Negative pin: the old direct-call line must be gone.
	assert_false(bm_src.contains("\"%s, a boss in Cowardly Irregular.\" % boss_dlg.get_display_name(persona_id)"),
		"intent-picker persona must NOT bypass _resolve_boss_display_name")
	assert_true(bm_src.contains("\"%s, a boss in Cowardly Irregular.\" % _resolve_boss_display_name(persona_id)"),
		"intent-picker persona must use _resolve_boss_display_name — so combatant_name set by dungeons wins")
