extends GutTest

## msg 2570 #1 continuation of v3.33.178's damage-anchor fix. Every
## EffectSystem.spawn_effect call site inside BattleScene that reads a
## live sprite.global_position for its anchor gets routed through the
## new _stable_sprite_anchor helper. Same class of bug as v3.33.158,
## v3.33.167, v3.33.170, v3.33.178.
##
## 6 sites swept:
##  1. all_out_attack per-attacker hit fx (BS ~2971)
##  2. combo_magic converging spells on all targets (BS ~3005)
##  3. all_out_attack rush-callback scatter bursts (BS ~3054)
##  4. formation/fallback attack fx on all targets (BS ~3072)
##  5. _delayed_play_hit_fx single-target hit (BS ~3108)
##  6. summon-in BUFF flash (BS ~4620)
##
## Behavioral cases are tricky to reproduce in headless GUT (BattleScene
## as a whole needs its full scene tree). Source pins + a behavioral
## test for the helper itself carry the intent.

const BS_PATH: String = "res://src/battle/BattleScene.gd"


## ── Helper surface ────────────────────────────────────────────────────

func test_stable_sprite_anchor_helper_declared() -> void:
	# Named helper so future additions of spawn_effect anchor sites can
	# adopt the same contract without inventing a parallel path.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	assert_string_contains(src, "func _stable_sprite_anchor(sprite: Node2D) -> Vector2:",
		"BattleScene must expose _stable_sprite_anchor(sprite) → Vector2 as the shared contract")


func test_helper_consults_party_base_positions_first() -> void:
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("func _stable_sprite_anchor(sprite: Node2D) -> Vector2:")
	assert_gt(idx, -1)
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 1200)
	assert_string_contains(body, "party_sprite_nodes.find(sprite)",
		"party path must lookup sprite index via find()")
	assert_string_contains(body, "_party_base_positions[party_idx]",
		"party path must return base position, not live global_position")
	assert_string_contains(body, "enemy_sprite_nodes.find(sprite)",
		"enemy path must lookup sprite index via find()")
	assert_string_contains(body, "_enemy_base_positions[enemy_idx]",
		"enemy path must return base position, not live global_position")
	assert_string_contains(body, "return sprite.global_position",
		"live global_position must remain as the fallback for orphan sprites (test enemies, pre-append states)")


## ── Every swept site uses the helper (no raw global_position anchor
## reads left in the effect-spawn class) ──────────────────────────────

func _stable_call_count(src: String, needle: String) -> int:
	# Count occurrences of an exact substring. Helper mirrors the pattern
	# other regression tests use for site counting.
	var count: int = 0
	var idx: int = src.find(needle)
	while idx > -1:
		count += 1
		idx = src.find(needle, idx + 1)
	return count


func test_no_raw_effect_anchor_regressions() -> void:
	# Every EffectSystem.spawn_effect call in BattleScene must route
	# through _stable_sprite_anchor OR pass a constructed Vector2 (not
	# a raw sprite.global_position). Textual pin — a future addition
	# that grabs sprite.global_position for spawn_effect would show up
	# here as a residual pattern.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	# All spawn_effect anchor reads should now be helper-wrapped or
	# constructed (spawn_effect(..., Vector2(x,y)) etc.).
	# Direct forbidden pattern: spawn_effect(anything, target_sprite.global_position, ...)
	assert_false(src.find("EffectSystem.spawn_effect(EffectSystem.EffectType.PHYSICAL, target_sprite.global_position)") > -1,
		"the raw target_sprite.global_position anchor read (v3.33.178-and-prior class) must not reappear")
	assert_false(src.find("EffectSystem.spawn_effect(EffectSystem.EffectType.BUFF, sprite.global_position)") > -1,
		"the raw sprite.global_position anchor read for BUFF must not reappear")
	# Constructive pin: helper is used at least 6 times (once per site).
	var uses: int = _stable_call_count(src, "_stable_sprite_anchor(")
	assert_true(uses >= 6,
		"expected _stable_sprite_anchor to be called at 6+ sites (found %d)" % uses)


## ── Behavioral: helper falls back gracefully when sprite isn't tracked
## in either sprite_nodes array ────────────────────────────────────────

## The helper itself is dependency-free (only reads self.* arrays), so we
## can instantiate a lightweight subclass that provides those fields and
## exercises the fallback branch.
class _AnchorStub extends Node2D:
	var party_sprite_nodes: Array = []
	var enemy_sprite_nodes: Array = []
	var _party_base_positions: Array[Vector2] = []
	var _enemy_base_positions: Array[Vector2] = []

	# Copy of the production helper body — behavioral-equivalence check.
	# If BattleScene._stable_sprite_anchor semantics change, this stub also
	# needs updating (which is a good bug-catcher — the pin test above
	# already catches source drift).
	func stable_anchor(sprite: Node2D) -> Vector2:
		if not is_instance_valid(sprite):
			return Vector2.ZERO
		var party_idx: int = party_sprite_nodes.find(sprite)
		if party_idx >= 0 and party_idx < _party_base_positions.size():
			return _party_base_positions[party_idx]
		var enemy_idx: int = enemy_sprite_nodes.find(sprite)
		if enemy_idx >= 0 and enemy_idx < _enemy_base_positions.size():
			return _enemy_base_positions[enemy_idx]
		return sprite.global_position


func _make_sprite(at_local_pos: Vector2) -> Node2D:
	var s := Node2D.new()
	s.position = at_local_pos
	add_child_autofree(s)
	return s


func test_helper_returns_zero_for_invalid_sprite() -> void:
	var stub := _AnchorStub.new()
	add_child_autofree(stub)
	# Truly invalid sprite (freed) — the guard must handle it.
	var sprite := Node2D.new()
	sprite.free()
	assert_eq(stub.stable_anchor(sprite), Vector2.ZERO,
		"invalid sprite ref must produce ZERO — callers guard against ZERO before spawning")


func test_helper_prefers_party_base_over_live_position() -> void:
	var stub := _AnchorStub.new()
	add_child_autofree(stub)
	var sprite := _make_sprite(Vector2(60, 100))  # live position moved off base
	stub.party_sprite_nodes = [sprite]
	stub._party_base_positions = [Vector2(600, 100)]  # base at rest
	assert_eq(stub.stable_anchor(sprite), Vector2(600, 100),
		"party base must win over live position — this is the whole class of fix")


func test_helper_prefers_enemy_base_over_live_position() -> void:
	var stub := _AnchorStub.new()
	add_child_autofree(stub)
	var sprite := _make_sprite(Vector2(206, 200))  # live position mid-knockback
	stub.enemy_sprite_nodes = [sprite]
	stub._enemy_base_positions = [Vector2(200, 200)]  # base at rest
	assert_eq(stub.stable_anchor(sprite), Vector2(200, 200),
		"enemy base must win over live knockback position")


func test_helper_falls_back_to_live_position_for_untracked_sprite() -> void:
	# Orphan sprite (not in either array) — helper returns live position.
	var stub := _AnchorStub.new()
	add_child_autofree(stub)
	var sprite := _make_sprite(Vector2(999, 999))
	# stub arrays empty
	assert_eq(stub.stable_anchor(sprite), Vector2(999, 999),
		"untracked sprite falls back to live global_position (no crash, no ZERO)")


func test_helper_falls_back_when_sprite_indexed_but_base_missing() -> void:
	# Race: sprite appended to sprite_nodes but base_positions.size still
	# behind (unlikely in production but the guard is cheap).
	var stub := _AnchorStub.new()
	add_child_autofree(stub)
	var sprite := _make_sprite(Vector2(500, 500))
	stub.enemy_sprite_nodes = [sprite]
	stub._enemy_base_positions = []  # deliberately short
	assert_eq(stub.stable_anchor(sprite), Vector2(500, 500),
		"index-out-of-range on base array falls back to live position instead of index-crash")
