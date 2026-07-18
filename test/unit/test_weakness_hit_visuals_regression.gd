extends GutTest

## Cycle 16 (msg 2787 #2) — weakness-hit visuals.
##
## Struktured: "if you hit monsters with weaknesses, they should have
## very specific palette swaps or reactions or special frames to
## indicate it hurt more than usual." Cut 1 (this cycle, engine-side,
## no per-sheet art): on elemental_mod > 1.0, over-flash the target
## sprite in the ELEMENT color (deeper hue + longer settle than the
## white hit flash) and apply a bigger knockback. Cut 2 (per-sheet
## special frames) stays as a cowir-sprites follow-up if struktured
## finds cut 1 insufficient after playtest.
##
## Design constraints:
##   - Enemies-only: player-side weakness hits (a boss finding a
##     party member's weakness) shouldn't over-flash a sprite the
##     player is trying to read HP/status on.
##   - Scales with elemental_mod so a 2.0x weakness hits visibly
##     harder than a 1.5x.
##   - Element-agnostic: every currently-authored element has a
##     color entry. New elements fall through to a bright default
##     rather than silent no-op.
##   - No per-sheet dependency — the whole point of shipping cut 1
##     is that it works on procedural + T1 + T2/T3 art alike.

const BS_PATH: String = "res://src/battle/BattleScene.gd"


## ── (1) Palette + helper surface exist ────────────────────────────────

func test_weakness_element_palette_defined() -> void:
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	assert_string_contains(src, "const WEAKNESS_ELEMENT_COLORS: Dictionary = {",
		"the element→color dict for weakness flashes must be defined at BS scope")
	# Every element currently authored on an ability MUST have a color
	# entry — silent lookup fallthrough would ship as "some elements
	# get the visuals, some don't" and the player can't tell why.
	# Elements sourced from abilities.json + monsters.json.
	var required_elements: Array = ["fire", "ice", "lightning", "dark", "holy", "physical", "wind", "earth", "water", "poison", "arcane"]
	for element in required_elements:
		assert_string_contains(src, "\"%s\":" % element,
			"WEAKNESS_ELEMENT_COLORS must have an entry for '%s' — every authored ability element needs a flash color" % element)


func test_weakness_flash_helper_defined() -> void:
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	assert_string_contains(src, "func _apply_weakness_hit_visuals(sprite: Node2D, element: String, elemental_mod: float) -> void:",
		"weakness flash helper signature must exist")


func test_weakness_knockback_helper_defined() -> void:
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	assert_string_contains(src, "func _apply_weakness_hit_knockback(sprite: Node2D, direction: float = 1.0, elemental_mod: float = 1.0) -> void:",
		"weakness knockback helper signature must exist")


## ── (2) Wiring: _on_damage_dealt fires the helpers on weakness ────────

func test_on_damage_dealt_fires_weakness_visuals_on_high_mod() -> void:
	# The whole point. On elemental_mod > 1.0 the handler must trigger
	# the weakness visuals — not just the WEAK! text indicator.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("func _on_damage_dealt(target: Combatant")
	assert_gt(idx, -1)
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 3000)
	assert_string_contains(body, "_apply_weakness_hit_visuals(",
		"_on_damage_dealt must call _apply_weakness_hit_visuals when elemental_mod > 1.0")
	assert_string_contains(body, "_apply_weakness_hit_knockback(",
		"_on_damage_dealt must call _apply_weakness_hit_knockback when elemental_mod > 1.0")


func test_weakness_visuals_gated_on_elemental_mod_and_enemy_side() -> void:
	# Gates matter:
	#   elemental_mod > 1.0 — resist/immune shouldn't over-flash (they
	#     already spawn RESIST/IMMUNE indicators of their own).
	#   target in BattleManager.enemy_party — player-side weakness hits
	#     over-flashing a party sprite would obscure HP/status readouts.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	# Skip past the func definition to find the CALL site inside _on_damage_dealt.
	var func_idx: int = src.find("func _apply_weakness_hit_visuals(")
	assert_gt(func_idx, -1)
	# First occurrence after the func decl is the call from _on_damage_dealt.
	var idx: int = src.find("_apply_weakness_hit_visuals(", func_idx + 32)
	assert_gt(idx, -1, "there must be a call site distinct from the func definition")
	# Walk backwards to find the enclosing `if` block guard.
	var before: String = src.substr(maxi(0, idx - 400), 400)
	assert_string_contains(before, "elemental_mod > 1.0",
		"the call must sit inside an `if elemental_mod > 1.0` gate")
	assert_string_contains(before, "target in BattleManager.enemy_party",
		"the call must sit inside an enemies-only gate — player sprites shouldn't over-flash")


## ── (3) Flash timing outlives the white hit flash ─────────────────────

func test_weakness_flash_settle_is_longer_than_white_flash() -> void:
	# The white hit flash uses 0.12s. A weakness flash that settles
	# in <0.12s would fight the white flash's fade + look like a
	# nothing-happened-here twitch. Struktured's brief: "deeper +
	# longer than the white hit flash".
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("func _apply_weakness_hit_visuals(sprite: Node2D")
	assert_gt(idx, -1)
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 800)
	# We're doing a light structural pin: total tween duration = hold
	# + ease-out > 0.12s. Look for a 0.28 or 0.3 range settle.
	# (Text-based; if the numbers get tuned, update this assert with
	# the new floor.)
	assert_string_contains(body, "0.28",
		"the settle tween must be >= ~0.28s so the color reads before it fades — longer than the 0.12s white hit flash")


## ── (4) Knockback scales with elemental_mod, capped ──────────────────

func test_weakness_knockback_scales_with_mod_and_is_capped() -> void:
	# Sanity on the numerical formula: base ~= 12 at 1.5x, ~= 16 at
	# 2.0x, no runaway on wild multipliers. Text-scan for the clamp.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("func _apply_weakness_hit_knockback(sprite: Node2D")
	assert_gt(idx, -1)
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 800)
	assert_string_contains(body, "clampf(",
		"knockback must be clamped so an omega-weakness (unlikely but authored elsewhere) doesn't rocket the sprite offscreen")
	assert_string_contains(body, "6.0",
		"clamp floor should be the regular knockback magnitude — never LESS forceful than a normal hit")
	assert_string_contains(body, "16.0",
		"clamp ceiling caps the visible knockback — no offscreen escape")


## ── (5) Flash intensity scales with mod, capped ──────────────────────

func test_weakness_flash_intensity_scales_with_mod_and_is_capped() -> void:
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("func _apply_weakness_hit_visuals(sprite: Node2D")
	assert_gt(idx, -1)
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 800)
	assert_string_contains(body, "clampf(",
		"intensity boost must clamp so a runaway multiplier doesn't saturate")


## ── (6) Elemental-mod plumbing already reaches BS ────────────────────

func test_damage_dealt_signal_carries_element_and_mod() -> void:
	# The whole cut relies on damage_dealt already carrying the element
	# + elemental_mod args. Cowir-main's showcase flush path documented
	# this (msg 2787). Pin the shape so a signal-signature refactor
	# would fail here rather than silently drop the visuals.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_string_contains(src, "signal damage_dealt(target: Combatant, amount: int, is_crit: bool, element: String, elemental_mod: float)",
		"BattleManager.damage_dealt signature must carry (target, amount, is_crit, element, elemental_mod) — the weakness visuals key off the last two args")


## ── (7) Player-facing safety: not applied to party members ────────────

func test_weakness_visuals_body_names_enemies_only() -> void:
	# Anti-regression: if a future refactor removes the enemy_party
	# gate, the party sprite over-flashes and the player can't read
	# their HP/status during a boss combo. Pin the check.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var func_idx: int = src.find("func _apply_weakness_hit_visuals(")
	assert_gt(func_idx, -1)
	var idx: int = src.find("_apply_weakness_hit_visuals(", func_idx + 32)
	assert_gt(idx, -1, "there must be a call site distinct from the func definition")
	# Prior 400 chars must mention enemy_party for the gate.
	var context: String = src.substr(maxi(0, idx - 400), 400)
	assert_true(context.find("enemy_party") > -1,
		"the visuals call must sit inside an enemy_party gate — no over-flash on party sprites")
