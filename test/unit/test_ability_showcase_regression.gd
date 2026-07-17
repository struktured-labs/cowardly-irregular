extends GutTest

## struktured 2026-07-16 (fable pass cut 2): "imagine I want to spotlight
## each attack and ability and exaggerate what it would look like and how
## long it would take... autobattle is kind of the other mode we have now."
##
## Ability Showcase: manual party turns at showcase speed (engine <= 0.3)
## perform non-physical abilities as a staged beat — dim, caster glow +
## gather, element release, impact where the DAMAGE NUMBER lands. Autobattle
## turns, turbo, console mode, and 2x+ speeds keep the quick path.

const SCENE := "res://src/battle/BattleScene.gd"


func _src() -> String:
	var t: String = FileAccess.get_file_as_string(SCENE)
	assert_ne(t, "", "BattleScene must be readable")
	return t


func _body_of(fn: String) -> String:
	var src := _src()
	var i := src.find("func %s" % fn)
	assert_gt(i, -1, "%s must exist" % fn)
	var next: int = src.find("\nfunc ", i + 1)
	return src.substr(i, (next - i) if next > -1 else 8000)


func test_ability_branch_routes_through_showcase_gate() -> void:
	var src := _src()
	var i := src.find("elif _showcase_active():")
	assert_gt(i, -1, "non-physical ability path must consult the showcase gate")
	assert_gt(src.find("_play_ability_showcase(attacker_sprite, animator, ability, targets)", i), -1,
		"gate-true routes to the showcase performance")


func test_gate_excludes_fast_modes_and_autobattle() -> void:
	var body := _body_of("_showcase_active")
	assert_true("turbo_mode or autogrind_console_mode or Engine.time_scale > 0.3" in body,
		"showcase only at showcase speed — 2x/4x/turbo keep the quick path he praised")
	assert_true("not AutobattleSystem.is_autobattle_enabled(char_id)" in body,
		"autobattle IS the other mode — its turns must never slow down")
	assert_true("BattleManager.player_party" in body,
		"cut 1 scopes to party casters (enemy showcase is a later beat)")


func test_damage_buffers_until_impact() -> void:
	var dmg := _body_of("_on_damage_dealt")
	assert_true("_showcase_dmg_buffer.append(" in dmg,
		"damage presentation must buffer during a showcase — a number popping ~1s before the bolt lands reads broken")
	var show := _body_of("_play_ability_showcase")
	var flash_at := show.find("_spawn_screen_flash")
	var flush_at := show.find("_flush_showcase_damage()", flash_at)
	assert_gt(flash_at, -1)
	assert_gt(flush_at, flash_at, "buffered damage must land AT the impact flash, not before")
	assert_gt(show.find("_flush_showcase_damage()"), -1)
	assert_lt(show.find("_flush_showcase_damage()"), show.find("_showcase_dmg_buffer = []"),
		"re-arming must flush any prior beat first — advance chains would otherwise strand numbers")


func test_flush_replays_and_disarms() -> void:
	var gl = load(SCENE).new()
	autofree(gl)
	# Disarmed flush is a no-op
	gl._showcase_dmg_buffer = null
	gl._flush_showcase_damage()
	assert_eq(gl._showcase_dmg_buffer, null)
	# Armed-but-empty flush disarms without replay
	gl._showcase_dmg_buffer = []
	gl._flush_showcase_damage()
	assert_eq(gl._showcase_dmg_buffer, null, "flush must disarm the buffer")


func test_element_styles_map_shapes() -> void:
	var gl = load(SCENE).new()
	autofree(gl)
	assert_eq(str(gl._showcase_element_style({"element": "fire"})["shape"]), "bolt")
	assert_eq(str(gl._showcase_element_style({"element": "ice"})["shape"]), "shards")
	assert_eq(str(gl._showcase_element_style({"element": "lightning"})["shape"]), "strike")
	var heal: Dictionary = gl._showcase_element_style({"type": "healing"})
	assert_eq(int(heal["effect"]), EffectSystem.EffectType.HEAL, "heals bloom green, never play a hit reaction")
	var buff: Dictionary = gl._showcase_element_style({"element": "unknown_thing"})
	assert_eq(str(buff["shape"]), "bloom", "unknown elements degrade to a bloom, never crash")


func test_dim_sits_between_background_and_sprites() -> void:
	var body := _body_of("_showcase_set_dim")
	assert_true("z_index = -5" in body,
		"dim at z -5: above the parallax layers (-100..-10), below combatant sprites (0) — sprites pop, backdrop recedes")
