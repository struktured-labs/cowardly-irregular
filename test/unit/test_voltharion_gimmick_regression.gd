extends GutTest

## Cycle 15 (msg 2787 #1) — Voltharion gimmick: Storm Gathering.
##
## Struktured: "make sure the dragon is kind of fun — maybe add some
## more gimmicks." Ship: a telegraphed self-buff. On cast, Voltharion
## announces the storm gathering + adds storm_charging status
## (visible in the enemy HUD). On its NEXT damaging move, the
## _next_attack_multiplier meta consumes at 1.8x — the existing
## physical-path consume already works; this cycle added the
## same-shape consume to the magic damage path since Voltharion's
## kit is 4/5 magic.
##
## Player counterplay: Defer reduces incoming damage — the
## telegraphed nature of the gimmick rewards the Defer mechanic
## (which is the whole design brief).
##
## Data-only extension for future dragons: any support ability with
## next_attack_multiplier now works on magic-heavy bosses, not just
## physical (burrow-shape). Storm Gathering is the first author but
## the seam is general.


## ── (1) Data: storm_gathering ability shape ───────────────────────────

func test_storm_gathering_ability_authored() -> void:
	var f: FileAccess = FileAccess.open("res://data/abilities.json", FileAccess.READ)
	assert_not_null(f)
	var ab: Dictionary = JSON.parse_string(f.get_as_text())
	assert_true(ab.has("storm_gathering"), "storm_gathering must be in abilities.json")
	var a: Dictionary = ab["storm_gathering"]
	assert_eq(a.get("type", ""), "support", "must be support type — routes to _execute_support_ability")
	assert_eq(a.get("target_type", ""), "self", "must target self — the buff lives on Voltharion")
	assert_eq(a.get("effect", ""), "storm_charging", "must add storm_charging status via the dedicated arm")
	assert_eq(a.get("duration", -1), 2, "duration 2 turns — the gather and the strike")
	assert_true(a.has("next_attack_multiplier"), "must carry next_attack_multiplier — the seam")
	assert_almost_eq(float(a.get("next_attack_multiplier", 0.0)), 1.8, 0.01,
		"1.8x is struktured's conservative starting value — flag for tuning")


func test_voltharion_kit_includes_storm_gathering() -> void:
	var f: FileAccess = FileAccess.open("res://data/monsters.json", FileAccess.READ)
	assert_not_null(f)
	var ms: Dictionary = JSON.parse_string(f.get_as_text())
	assert_true(ms.has("lightning_dragon"), "Voltharion must exist in monsters.json")
	var v: Dictionary = ms["lightning_dragon"]
	assert_true(v.get("abilities", []).has("storm_gathering"),
		"lightning_dragon.abilities must include storm_gathering — gimmick data-driven at the AI picker")


## ── (2) BM: storm_charging status arm ─────────────────────────────────

func test_storm_charging_has_dedicated_status_arm() -> void:
	# Separate arm from the "afflicted with..." pool because storm_charging is a self-buff, not a debuff. Log line names the counterplay explicitly.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var idx: int = src.find("\"storm_charging\":")
	assert_gt(idx, -1, "storm_charging must have its own match arm in _execute_support_ability")
	# The arm body should call add_status(effect, duration) — same shape as the sibling simple-status pool.
	var window: String = src.substr(idx, 900)
	assert_string_contains(window, "target.add_status(effect, duration)",
		"storm_charging arm must add the status via add_status")
	assert_string_contains(window, "gathers the storm",
		"the log line must name the gimmick — telegraph is the whole point")
	assert_string_contains(window, "Defer",
		"the log line must name the counterplay — Struktured's brief was 'rewards the Defer mechanic'")


## ── (3) BM: magic-path _next_attack_multiplier consume ────────────────

func test_magic_path_consumes_next_attack_multiplier() -> void:
	# The seam. Pre-fix only the physical damage calc consumed
	# _next_attack_multiplier (burrow shape). Voltharion's kit is 4/5
	# magic (thunder_breath / chain_lightning / static_field /
	# overcharge / lightning_dash — the last is physical). Storm
	# Gathering would have burned MP with no payoff without the magic
	# consume.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	# Locate _execute_magic_ability body specifically — physical
	# consume is elsewhere and shouldn't count.
	var magic_idx: int = src.find("func _execute_magic_ability(caster: Combatant")
	assert_gt(magic_idx, -1)
	var next: int = src.find("\nfunc ", magic_idx + 1)
	var body: String = src.substr(magic_idx, (next - magic_idx) if next > -1 else 4000)
	assert_string_contains(body, "caster.get_meta(\"_next_attack_multiplier\", 0.0)",
		"magic path must read the same _next_attack_multiplier meta the physical path consumes")
	assert_string_contains(body, "caster.set_meta(\"_next_attack_multiplier\", 0.0)",
		"magic path must CLEAR the meta after consuming — otherwise the buff sticks and applies to every future spell")
	assert_string_contains(body, "unleashes the gathered storm",
		"consume must emit a distinct log line so player correlates gather ↔ unleash")


func test_magic_path_consumes_before_target_loop() -> void:
	# Correctness: on an AoE spell (chain_lightning targets
	# all_enemies), consuming inside the target loop would either
	# (a) apply the multiplier to only the first target and revert
	# to 1.0x for the rest, or (b) apply repeatedly if consume runs
	# post-damage-calc. Neither shape matches "next attack" intent.
	# Consume must run ONCE before the target loop.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var magic_idx: int = src.find("func _execute_magic_ability(caster: Combatant")
	assert_gt(magic_idx, -1)
	var loop_idx: int = src.find("for target in targets:", magic_idx)
	assert_gt(loop_idx, magic_idx, "target loop must exist in _execute_magic_ability")
	var consume_idx: int = src.find("\"_next_attack_multiplier\", 0.0)", magic_idx)
	# The get_meta consume read should sit BEFORE the target loop.
	assert_gt(loop_idx, consume_idx,
		"consume must precede the target loop — AoE spells need the multiplier once, applied uniformly to all targets")


## ── (4) The story is now general (not Voltharion-hardcoded) ───────────

func test_no_ability_id_hardcode_in_consume() -> void:
	# The consume must be data-driven — reading the meta and the
	# ability's next_attack_multiplier field. A hardcoded string match
	# on "storm_gathering" or "chain_lightning" would tie the gimmick
	# to Voltharion and rot when a future boss reuses the shape.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var magic_idx: int = src.find("func _execute_magic_ability(caster: Combatant")
	var next: int = src.find("\nfunc ", magic_idx + 1)
	var body: String = src.substr(magic_idx, (next - magic_idx) if next > -1 else 4000)
	assert_false(body.find("\"storm_gathering\"") > -1,
		"magic consume must not hardcode storm_gathering — it's data-driven via next_attack_multiplier")
	assert_false(body.find("\"chain_lightning\"") > -1,
		"magic consume must not hardcode chain_lightning — the multiplier applies to whichever spell fires next")
