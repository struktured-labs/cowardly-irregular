extends GutTest

## msg 2569 sprite-misplacement sweep — same class of bug cowir-main killed
## twice already (v3.33.158 melee tween targets; v3.33.170 bubbles;
## v3.33.167 highlight box). Reading sprite.global_position while the
## sprite's own tween is in flight anchors visuals to the transitional
## position, not the rest position where the popup "belongs."
##
## Damage numbers were the highest-impact remaining site — every hit in
## every battle routes through BattleResultsDisplay._get_combatant_
## sprite_position, which returned raw sprite.global_position. When the
## target was mid-knockback (or was a heal recipient mid-lunge) the
## number floated from the wrong spot for a frame or two before the
## sprite settled.
##
## Fix: prefer the stable base position (BattleScene._party_base_positions
## / _enemy_base_positions, stamped once at sprite spawn — the rest
## position). Live global_position remains the graceful fallback when
## the base isn't tracked yet (e.g. summons before their base is
## appended).

const BRDScript = preload("res://src/battle/BattleResultsDisplay.gd")
const CombatantScript = preload("res://src/battle/Combatant.gd")


## Minimal scene stub — BRD reads party_sprite_nodes, enemy_sprite_nodes,
## _party_base_positions, _enemy_base_positions off _scene.
class _SceneStub extends Node:
	var party_sprite_nodes: Array = []
	var enemy_sprite_nodes: Array = []
	var _party_base_positions: Array[Vector2] = []
	var _enemy_base_positions: Array[Vector2] = []


func _make_sprite(at_pos: Vector2) -> Node2D:
	# Node2D stands in for AnimatedSprite2D — the only surface BRD touches
	# is is_instance_valid + global_position.
	var s := Node2D.new()
	s.position = at_pos
	add_child_autofree(s)
	return s


func _make_combatant(name: String) -> Combatant:
	var c: Combatant = CombatantScript.new()
	c.combatant_name = name
	c.is_alive = true
	add_child_autofree(c)
	return c


func _setup(party_size: int, enemy_size: int, party_bases: Array = [], enemy_bases: Array = []) -> Dictionary:
	# Build a stub scene + BRD + party/enemy sprites + register combatants
	# in BattleManager so BRD's index lookup finds them.
	var scene := _SceneStub.new()
	add_child_autofree(scene)
	var brd = BRDScript.new(scene)
	var party: Array = []
	var enemies: Array = []
	for i in range(party_size):
		var c := _make_combatant("PartyPC%d" % i)
		party.append(c)
		var s := _make_sprite(Vector2(600, 100 + i * 60))
		scene.party_sprite_nodes.append(s)
		scene._party_base_positions.append(party_bases[i] if i < party_bases.size() else s.position)
	for i in range(enemy_size):
		var e := _make_combatant("Enemy%d" % i)
		enemies.append(e)
		var s := _make_sprite(Vector2(200, 200 + i * 60))
		scene.enemy_sprite_nodes.append(s)
		scene._enemy_base_positions.append(enemy_bases[i] if i < enemy_bases.size() else s.position)
	# BattleManager is an autoload; wire its party arrays for the find() calls in BRD.
	var bm: Node = get_tree().root.get_node_or_null("BattleManager")
	if bm != null:
		bm.player_party = party
		bm.enemy_party = enemies
	return {"brd": brd, "scene": scene, "party": party, "enemies": enemies}


## ── Base position preferred over live position when they diverge ──────

func test_party_base_position_wins_when_sprite_is_mid_tween() -> void:
	# The exact class of bug: sprite is mid-knockback (position != base).
	# Damage popup MUST anchor to the base, not the transient live position.
	var bm: Node = get_tree().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload not available in headless")
		return
	var setup = _setup(1, 0, [Vector2(600, 100)])
	var brd = setup["brd"]
	var sprite = setup["scene"].party_sprite_nodes[0]
	# Simulate mid-tween: sprite moved off its base by 40 px.
	sprite.position = Vector2(560, 100)
	var pos: Vector2 = brd._get_combatant_sprite_position(setup["party"][0])
	assert_eq(pos, Vector2(600, 100),
		"party damage anchor must return the stable base (600,100), NOT the mid-tween live position (560,100)")


func test_enemy_base_position_wins_when_sprite_is_mid_knockback() -> void:
	# Same as above for enemies — most damage numbers land on enemies, so
	# this is the most-often-exercised path.
	var bm: Node = get_tree().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload not available in headless")
		return
	var setup = _setup(0, 1, [], [Vector2(200, 200)])
	var brd = setup["brd"]
	var sprite = setup["scene"].enemy_sprite_nodes[0]
	sprite.position = Vector2(206, 200)  # mid-knockback (6-px tween in _apply_hit_knockback)
	var pos: Vector2 = brd._get_combatant_sprite_position(setup["enemies"][0])
	assert_eq(pos, Vector2(200, 200),
		"enemy damage anchor must return the stable base, not the knocked-back live position")


func test_base_position_equals_live_position_at_rest() -> void:
	# Sanity: when the sprite IS at rest, base == live, no behavioral change.
	# Pre-fix behavior preserved for the common case.
	var bm: Node = get_tree().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload not available in headless")
		return
	var setup = _setup(1, 0, [Vector2(600, 100)])
	var brd = setup["brd"]
	# sprite.position defaults to (600, 100) — same as base, at rest.
	var pos: Vector2 = brd._get_combatant_sprite_position(setup["party"][0])
	assert_eq(pos, Vector2(600, 100),
		"at rest, anchor still returns the sprite position — no change to the common case")


## ── Fallback to live position when base tracking hasn't caught up ─────

func test_fallback_to_live_position_when_base_array_short() -> void:
	# Summons and other late-spawn sprites are appended to sprite_nodes but
	# might not have a base_positions entry yet (append order matters).
	# When the base index is out of range, fall back to live global_position
	# rather than returning ZERO or crashing.
	var bm: Node = get_tree().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload not available in headless")
		return
	var setup = _setup(0, 1, [], [])  # 1 enemy sprite, 0 base positions
	var brd = setup["brd"]
	var sprite = setup["scene"].enemy_sprite_nodes[0]
	sprite.position = Vector2(999, 999)  # arbitrary — no base to prefer
	var pos: Vector2 = brd._get_combatant_sprite_position(setup["enemies"][0])
	# Node2D's global_position without a real scene tree just equals its position.
	assert_eq(pos, Vector2(999, 999),
		"when base index is out of range, fall back to live position — no crash, no ZERO")


func test_returns_zero_when_combatant_not_in_either_party() -> void:
	# Preserved contract: the caller checks for ZERO and skips popup ("Could
	# not find sprite position for X"). If this changes to something else,
	# every damage-number consumer needs a matching update.
	var bm: Node = get_tree().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload not available in headless")
		return
	var setup = _setup(1, 1)
	var brd = setup["brd"]
	var orphan := _make_combatant("Orphan")  # not in either party array
	var pos: Vector2 = brd._get_combatant_sprite_position(orphan)
	assert_eq(pos, Vector2.ZERO,
		"combatant not in either party must still return Vector2.ZERO — caller-side skip contract unchanged")


## ── Source pin: consult the base arrays before global_position ────────

func test_source_prefers_base_over_live_position() -> void:
	# Textual guard against a future refactor that reverts to the raw
	# global_position read (undoing the msg 2569 fix).
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleResultsDisplay.gd")
	var idx: int = src.find("func _get_combatant_sprite_position(combatant: Combatant) -> Vector2:")
	assert_gt(idx, -1)
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 2000)
	assert_string_contains(body, "_scene._party_base_positions",
		"party path must consult _party_base_positions before falling back to global_position")
	assert_string_contains(body, "_scene._enemy_base_positions",
		"enemy path must consult _enemy_base_positions before falling back to global_position")
	assert_string_contains(body, "return sprite.global_position",
		"live global_position must remain as the fallback for pre-base-appended sprites")
