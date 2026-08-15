extends GutTest

## Phase A: the battle sprite flash shader replaces HDR-modulate "flashes" (which tint
## instead of reaching true white on dark pixels). Pins: the shader parses with its three
## uniforms, materials are UNIQUE per sprite (a shared material would flash every
## combatant at once), and the legacy hit-flash entry point delegates.

const SHADER_PATH := "res://src/shaders/battle_sprite_flash.gdshader"


func test_shader_loads_with_expected_uniforms() -> void:
	var shader: Shader = load(SHADER_PATH)
	assert_not_null(shader, "shader resource must load")
	var src := shader.code
	for u in ["flash_amount", "flash_color", "dissolve_amount"]:
		assert_true("uniform" in src and u in src, "uniform %s present" % u)


func test_ensure_flash_material_is_unique_per_sprite() -> void:
	var a := Sprite2D.new()
	var b := Sprite2D.new()
	add_child_autofree(a)
	add_child_autofree(b)
	var ma: ShaderMaterial = BattleJuice.ensure_flash_material(a)
	var mb: ShaderMaterial = BattleJuice.ensure_flash_material(b)
	assert_not_null(ma, "material created")
	assert_ne(ma, mb, "each sprite gets its OWN material — shared would flash everyone")
	assert_eq(BattleJuice.ensure_flash_material(a), ma, "idempotent: second call returns the same material")


func test_flash_sprite_drives_shader_when_material_present() -> void:
	var s := Sprite2D.new()
	add_child_autofree(s)
	var mat: ShaderMaterial = BattleJuice.ensure_flash_material(s)
	BattleJuice.flash_sprite(s)
	assert_almost_eq(float(mat.get_shader_parameter("flash_amount")), 1.0, 0.001, "flash sets shader amount, not modulate")
	assert_eq(s.modulate, Color.WHITE, "modulate untouched on the shader path")


func test_hit_flash_delegates_and_spawn_sites_attach_material() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_gt(src.length(), 1000, "CONTROL: read a real file")
	var i := src.find("func _apply_hit_flash")
	assert_gt(i, -1, "_apply_hit_flash must exist (external callers keep the name)")
	var fn_end := src.find("\nfunc ", i + 1)
	var body := src.substr(i, (fn_end - i) if fn_end > -1 else 800)
	assert_true("BattleJuice.flash_sprite" in body, "hit flash delegates to the shared primitive")
	assert_eq(src.count("BattleJuice.ensure_flash_material"), 3, "all three sprite spawn sites (party/enemy/summon) attach the material")
