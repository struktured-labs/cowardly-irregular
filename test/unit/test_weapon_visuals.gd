extends GutTest

## Tests for weapon visual system
## Tests equipment data loading, weapon visual parameters, and sprite generation

const BattleAnimator = preload("res://src/battle/BattleAnimator.gd")
const SpriteUtils = preload("res://src/battle/sprites/SpriteUtils.gd")


# =============================================================================
# EQUIPMENT DATA LOADING TESTS
# =============================================================================

func test_equipment_data_loads_successfully() -> void:
	# Force reload by accessing visual params
	var visual = BattleAnimator.get_weapon_visual("iron_sword")
	assert_not_null(visual, "Should return visual params dictionary")
	assert_true(visual.size() > 0, "Visual params should not be empty")


func test_equipment_json_has_weapon_types() -> void:
	# Test that all weapon types are properly defined
	var sword_visual = BattleAnimator.get_weapon_visual("iron_sword")
	var staff_visual = BattleAnimator.get_weapon_visual("wooden_staff")
	var dagger_visual = BattleAnimator.get_weapon_visual("iron_dagger")

	assert_eq(sword_visual.get("type"), "sword", "Iron sword should be type 'sword'")
	assert_eq(staff_visual.get("type"), "staff", "Wooden staff should be type 'staff'")
	assert_eq(dagger_visual.get("type"), "dagger", "Iron dagger should be type 'dagger'")


# =============================================================================
# SWORD VISUAL TESTS
# =============================================================================

func test_bronze_sword_has_correct_colors() -> void:
	var visual = BattleAnimator.get_weapon_visual("bronze_sword")

	assert_eq(visual.get("type"), "sword")
	assert_true(visual.has("metal"), "Sword should have metal color")
	assert_true(visual.has("metal_light"), "Sword should have metal_light color")
	assert_true(visual.has("metal_dark"), "Sword should have metal_dark color")

	# Bronze should be warm/copper toned (high red, medium green, low blue)
	var metal: Color = visual.get("metal")
	assert_gt(metal.r, 0.5, "Bronze sword should have reddish tint")
	assert_gt(metal.r, metal.b, "Bronze should be more red than blue")


func test_iron_sword_has_correct_colors() -> void:
	var visual = BattleAnimator.get_weapon_visual("iron_sword")

	assert_eq(visual.get("type"), "sword")
	var metal: Color = visual.get("metal")

	# Iron should be grayish (similar RGB values)
	assert_almost_eq(metal.r, metal.g, 0.15, "Iron should have similar R and G")
	assert_almost_eq(metal.g, metal.b, 0.15, "Iron should have similar G and B")


func test_flame_sword_has_glow() -> void:
	var visual = BattleAnimator.get_weapon_visual("flame_sword")

	assert_eq(visual.get("type"), "sword")
	assert_true(visual.get("glow", false), "Flame sword should have glow enabled")
	assert_true(visual.has("glow_color"), "Flame sword should have glow_color")

	var glow: Color = visual.get("glow_color")
	assert_gt(glow.r, 0.8, "Flame glow should be reddish-orange")


func test_ice_blade_has_blue_glow() -> void:
	var visual = BattleAnimator.get_weapon_visual("ice_blade")

	assert_eq(visual.get("type"), "sword")
	assert_true(visual.get("glow", false), "Ice blade should have glow enabled")

	var glow: Color = visual.get("glow_color")
	assert_gt(glow.b, 0.8, "Ice glow should be blue")
	assert_gt(glow.b, glow.r, "Ice glow should be more blue than red")


# =============================================================================
# STAFF VISUAL TESTS
# =============================================================================

func test_wooden_staff_has_correct_colors() -> void:
	var visual = BattleAnimator.get_weapon_visual("wooden_staff")

	assert_eq(visual.get("type"), "staff")
	assert_true(visual.has("wood"), "Staff should have wood color")
	assert_true(visual.has("gem"), "Staff should have gem color")

	# Wood should be brownish
	var wood: Color = visual.get("wood")
	assert_gt(wood.r, wood.b, "Wood should be more red than blue (brown)")


func test_crystal_staff_has_glow() -> void:
	var visual = BattleAnimator.get_weapon_visual("crystal_staff")

	assert_eq(visual.get("type"), "staff")
	assert_true(visual.get("glow", false), "Crystal staff should have glow enabled")
	assert_true(visual.has("glow_color"), "Crystal staff should have glow_color")


func test_shadow_rod_has_dark_colors() -> void:
	var visual = BattleAnimator.get_weapon_visual("shadow_rod")

	assert_eq(visual.get("type"), "staff")
	assert_true(visual.get("glow", false), "Shadow rod should have glow enabled")

	var wood: Color = visual.get("wood")
	assert_lt(wood.r, 0.3, "Shadow rod wood should be dark")
	assert_lt(wood.g, 0.2, "Shadow rod wood should be dark")


func test_holy_staff_has_bright_colors() -> void:
	var visual = BattleAnimator.get_weapon_visual("holy_staff")

	assert_eq(visual.get("type"), "staff")
	assert_true(visual.get("glow", false), "Holy staff should have glow enabled")

	var wood: Color = visual.get("wood")
	assert_gt(wood.r, 0.8, "Holy staff wood should be bright")


# =============================================================================
# DAGGER VISUAL TESTS
# =============================================================================

func test_iron_dagger_has_correct_colors() -> void:
	var visual = BattleAnimator.get_weapon_visual("iron_dagger")

	assert_eq(visual.get("type"), "dagger")
	assert_true(visual.has("blade"), "Dagger should have blade color")
	assert_true(visual.has("blade_light"), "Dagger should have blade_light color")


func test_poison_dagger_has_green_tint() -> void:
	var visual = BattleAnimator.get_weapon_visual("poison_dagger")

	assert_eq(visual.get("type"), "dagger")

	var blade: Color = visual.get("blade")
	assert_gt(blade.g, blade.r, "Poison dagger should have green tint")
	assert_gt(blade.g, blade.b, "Poison dagger should have green tint")


func test_assassin_blade_is_dark() -> void:
	var visual = BattleAnimator.get_weapon_visual("assassin_blade")

	assert_eq(visual.get("type"), "dagger")

	var blade: Color = visual.get("blade")
	assert_lt(blade.r, 0.3, "Assassin blade should be dark")
	assert_lt(blade.g, 0.3, "Assassin blade should be dark")


# =============================================================================
# DEFAULT VISUAL TESTS
# =============================================================================

func test_empty_weapon_returns_default_sword() -> void:
	var visual = BattleAnimator.get_weapon_visual("")

	assert_eq(visual.get("type"), "sword", "Empty weapon should default to sword")
	assert_true(visual.has("metal"), "Default should have metal color")


func test_invalid_weapon_returns_default() -> void:
	var visual = BattleAnimator.get_weapon_visual("nonexistent_weapon_xyz")

	assert_eq(visual.get("type"), "sword", "Invalid weapon should default to sword")
	assert_true(visual.has("metal"), "Default should have metal color")


func test_default_sword_visual() -> void:
	var visual = SpriteUtils._get_default_weapon_visual("sword")

	assert_eq(visual.get("type"), "sword")
	assert_true(visual.has("metal"))
	assert_true(visual.has("metal_light"))
	assert_true(visual.has("metal_dark"))
	assert_false(visual.get("glow", false), "Default sword should not glow")


func test_default_staff_visual() -> void:
	var visual = SpriteUtils._get_default_weapon_visual("staff")

	assert_eq(visual.get("type"), "staff")
	assert_true(visual.has("wood"))
	assert_true(visual.has("gem"))
	assert_false(visual.get("glow", false), "Default staff should not glow")


func test_default_dagger_visual() -> void:
	var visual = SpriteUtils._get_default_weapon_visual("dagger")

	assert_eq(visual.get("type"), "dagger")
	assert_true(visual.has("blade"))
	assert_true(visual.has("blade_light"))


func test_unknown_type_returns_sword_default() -> void:
	var visual = SpriteUtils._get_default_weapon_visual("unknown_type")

	assert_eq(visual.get("type"), "sword", "Unknown type should default to sword")


# =============================================================================
# SPRITE FRAME CREATION TESTS
# =============================================================================

func test_hero_sprite_frames_created_with_weapon() -> void:
	var frames = BattleAnimator.create_hero_sprite_frames("flame_sword")

	assert_not_null(frames, "Should create sprite frames")
	assert_true(frames.has_animation("idle"), "Should have idle animation")
	assert_true(frames.has_animation("attack"), "Should have attack animation")
	assert_true(frames.has_animation("defend"), "Should have defend animation")
	assert_true(frames.has_animation("hit"), "Should have hit animation")
	assert_true(frames.has_animation("victory"), "Should have victory animation")
	assert_true(frames.has_animation("defeat"), "Should have defeat animation")


func test_hero_sprite_frames_created_without_weapon() -> void:
	var frames = BattleAnimator.create_hero_sprite_frames("")

	assert_not_null(frames, "Should create sprite frames with empty weapon")
	assert_true(frames.has_animation("idle"), "Should have idle animation")


func test_mage_sprite_frames_created_with_weapon() -> void:
	var frames = BattleAnimator.create_mage_sprite_frames(Color(0.9, 0.9, 1.0), "crystal_staff")

	assert_not_null(frames, "Should create sprite frames")
	assert_true(frames.has_animation("idle"), "Should have idle animation")
	assert_true(frames.has_animation("cast"), "Should have cast animation")


func test_mage_sprite_frames_created_without_weapon() -> void:
	var frames = BattleAnimator.create_mage_sprite_frames(Color(0.9, 0.9, 1.0), "")

	assert_not_null(frames, "Should create sprite frames with empty weapon")
	assert_true(frames.has_animation("idle"), "Should have idle animation")


func test_thief_sprite_frames_created_with_weapon() -> void:
	var frames = BattleAnimator.create_thief_sprite_frames("poison_dagger")

	assert_not_null(frames, "Should create sprite frames")
	assert_true(frames.has_animation("idle"), "Should have idle animation")
	assert_true(frames.has_animation("attack"), "Should have attack animation")


func test_thief_sprite_frames_created_without_weapon() -> void:
	var frames = BattleAnimator.create_thief_sprite_frames("")

	assert_not_null(frames, "Should create sprite frames with empty weapon")
	assert_true(frames.has_animation("idle"), "Should have idle animation")


# =============================================================================
# SPRITE FRAME CONTENT TESTS
# =============================================================================

func test_hero_idle_animation_has_frames() -> void:
	var frames = BattleAnimator.create_hero_sprite_frames("iron_sword")

	var frame_count = frames.get_frame_count("idle")
	assert_eq(frame_count, 2, "Hero idle should have 2 frames")


func test_hero_attack_animation_has_frames() -> void:
	var frames = BattleAnimator.create_hero_sprite_frames("iron_sword")

	var frame_count = frames.get_frame_count("attack")
	assert_eq(frame_count, 4, "Hero attack should have 4 frames")


func test_mage_cast_animation_has_frames() -> void:
	var frames = BattleAnimator.create_mage_sprite_frames(Color.WHITE, "wooden_staff")

	var frame_count = frames.get_frame_count("cast")
	assert_eq(frame_count, 4, "Mage cast should have 4 frames")


func test_thief_attack_animation_has_frames() -> void:
	var frames = BattleAnimator.create_thief_sprite_frames("iron_dagger")

	var frame_count = frames.get_frame_count("attack")
	assert_eq(frame_count, 4, "Thief attack should have 4 frames")


# =============================================================================
# DIFFERENT WEAPONS PRODUCE DIFFERENT SPRITES
# =============================================================================

func test_different_swords_produce_different_visuals() -> void:
	var bronze_visual = BattleAnimator.get_weapon_visual("bronze_sword")
	var iron_visual = BattleAnimator.get_weapon_visual("iron_sword")
	var flame_visual = BattleAnimator.get_weapon_visual("flame_sword")

	var bronze_metal: Color = bronze_visual.get("metal")
	var iron_metal: Color = iron_visual.get("metal")
	var flame_metal: Color = flame_visual.get("metal")

	# Each sword should have distinct colors
	assert_ne(bronze_metal, iron_metal, "Bronze and iron should have different colors")
	assert_ne(iron_metal, flame_metal, "Iron and flame should have different colors")
	assert_ne(bronze_metal, flame_metal, "Bronze and flame should have different colors")


func test_different_staffs_produce_different_visuals() -> void:
	var wooden_visual = BattleAnimator.get_weapon_visual("wooden_staff")
	var crystal_visual = BattleAnimator.get_weapon_visual("crystal_staff")
	var shadow_visual = BattleAnimator.get_weapon_visual("shadow_rod")

	var wooden_gem: Color = wooden_visual.get("gem")
	var crystal_gem: Color = crystal_visual.get("gem")
	var shadow_gem: Color = shadow_visual.get("gem")

	# Each staff should have distinct gem colors
	assert_ne(wooden_gem, crystal_gem, "Wooden and crystal should have different gems")
	assert_ne(crystal_gem, shadow_gem, "Crystal and shadow should have different gems")


# =============================================================================
# GLOW PROPERTY TESTS
# =============================================================================

func test_non_magical_weapons_dont_glow() -> void:
	var bronze = BattleAnimator.get_weapon_visual("bronze_sword")
	var iron = BattleAnimator.get_weapon_visual("iron_sword")
	var wooden = BattleAnimator.get_weapon_visual("wooden_staff")
	var iron_dagger = BattleAnimator.get_weapon_visual("iron_dagger")

	assert_false(bronze.get("glow", false), "Bronze sword should not glow")
	assert_false(iron.get("glow", false), "Iron sword should not glow")
	assert_false(wooden.get("glow", false), "Wooden staff should not glow")
	assert_false(iron_dagger.get("glow", false), "Iron dagger should not glow")


func test_magical_weapons_glow() -> void:
	var flame = BattleAnimator.get_weapon_visual("flame_sword")
	var ice = BattleAnimator.get_weapon_visual("ice_blade")
	var crystal = BattleAnimator.get_weapon_visual("crystal_staff")
	var shadow = BattleAnimator.get_weapon_visual("shadow_rod")
	var holy = BattleAnimator.get_weapon_visual("holy_staff")

	assert_true(flame.get("glow", false), "Flame sword should glow")
	assert_true(ice.get("glow", false), "Ice blade should glow")
	assert_true(crystal.get("glow", false), "Crystal staff should glow")
	assert_true(shadow.get("glow", false), "Shadow rod should glow")
	assert_true(holy.get("glow", false), "Holy staff should glow")


# =============================================================================
# COLOR VALUE VALIDATION TESTS
# =============================================================================

func test_all_colors_are_valid() -> void:
	var weapons = ["bronze_sword", "iron_sword", "flame_sword", "ice_blade",
				   "wooden_staff", "oak_staff", "crystal_staff", "shadow_rod", "holy_staff",
				   "iron_dagger", "poison_dagger", "assassin_blade"]

	for weapon_id in weapons:
		var visual = BattleAnimator.get_weapon_visual(weapon_id)
		var weapon_type = visual.get("type")

		match weapon_type:
			"sword":
				var metal: Color = visual.get("metal")
				assert_between(metal.r, 0.0, 1.0, "%s metal.r should be valid" % weapon_id)
				assert_between(metal.g, 0.0, 1.0, "%s metal.g should be valid" % weapon_id)
				assert_between(metal.b, 0.0, 1.0, "%s metal.b should be valid" % weapon_id)
			"staff":
				var wood: Color = visual.get("wood")
				var gem: Color = visual.get("gem")
				assert_between(wood.r, 0.0, 1.0, "%s wood.r should be valid" % weapon_id)
				assert_between(gem.r, 0.0, 1.0, "%s gem.r should be valid" % weapon_id)
			"dagger":
				var blade: Color = visual.get("blade")
				assert_between(blade.r, 0.0, 1.0, "%s blade.r should be valid" % weapon_id)
