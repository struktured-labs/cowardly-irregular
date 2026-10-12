extends GutTest
## Every third battle with no scripted enemies is a miniboss battle (GameLoop:4778,
## `(battles_won + 1) % 3 == 0`), routed to BattleEnemySpawner.spawn_miniboss(). That path set
## `is_miniboss` and NOT `is_boss` -- alone among four spawn paths, the other three setting both
## for any monster flagged boss OR miniboss in monsters.json.
## Cave Troll and Shadow Knight ARE flagged miniboss there, so the SAME monster was boss-like
## through an encounter and an ordinary enemy through this door. Five is_boss consumers have no
## is_miniboss fallback: BattleScene:795, :3441, :5603 and VictoryOverlay:161, :186 -- so a
## miniboss took no boss dialogue, no danger-HP treatment, and no ELITE grade on the victory screen.
## Found with cowir-music's recurred-class grep, applied to the path my own .654 fix did not cover.
const SpawnerScript = preload("res://src/battle/BattleEnemySpawner.gd")

const VictoryOverlayScript = preload("res://src/battle/VictoryOverlay.gd")

const STUB_SCENE := """
extends Node2D
var enemy_positions: Array = [Vector2(100, 100)]
var test_enemies: Array = []
var party_members: Array = []
var lines: Array = []
func log_message(t): lines.append(t)
func _update_ui(): pass
func _on_enemy_died(_e): pass
func _on_enemy_hp_changed(_a, _b): pass
func _on_status_added(_a, _b): pass
func _on_status_removed(_a, _b): pass
func _on_status_tick_damage(_a, _b, _c): pass
func _on_status_tick_heal(_a, _b, _c): pass
"""

var _scene_ref: Node2D = null


func _spawn_miniboss() -> Combatant:
	var script := GDScript.new()
	script.source_code = STUB_SCENE
	script.reload()
	var scene: Node2D = script.new()
	add_child_autofree(scene)
	_scene_ref = scene
	var spawner = SpawnerScript.new(scene)
	spawner.spawn_miniboss()
	assert_eq(scene.test_enemies.size(), 1, "FLOOR: the miniboss path must have spawned exactly one enemy")
	if scene.test_enemies.is_empty():
		return null
	return scene.test_enemies[0]


func test_a_miniboss_is_boss_like_through_this_door_too() -> void:
	var e: Combatant = _spawn_miniboss()
	if e == null:
		return
	assert_true(e.has_meta("is_boss") and bool(e.get_meta("is_boss")),
		"the five is_boss consumers with no miniboss fallback must see this enemy, as they do for the same monster from an encounter")


func test_it_keeps_the_miniboss_meta_the_music_reads() -> void:
	var e: Combatant = _spawn_miniboss()
	if e == null:
		return
	assert_true(e.has_meta("is_miniboss") and bool(e.get_meta("is_miniboss")),
		"CONTROL: is_miniboss drives music selection and must survive the fix, not be replaced by it")


## The PREMISE of the inconsistency: these ids are flagged miniboss in the catalog, which is exactly
## why the other three paths set is_boss for them. If that flag is ever cleared, this arm says so.
func test_the_catalog_agrees_these_are_minibosses() -> void:
	var raw := FileAccess.get_file_as_string("res://data/monsters.json")
	assert_gt(raw.length(), 0, "FLOOR: monsters.json must be readable")
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "FLOOR: monsters.json must parse")
	if not (parsed is Dictionary):
		return
	var monsters: Dictionary = (parsed as Dictionary).get("monsters", parsed)
	for entry in SpawnerScript.MINIBOSS_TYPES:
		var mid: String = str(entry.get("id", ""))
		assert_true(monsters.has(mid), "%s must exist in the catalog" % mid)
		var m: Dictionary = monsters.get(mid, {})
		assert_true(bool(m.get("boss", false)) or bool(m.get("miniboss", false)),
			"%s must be flagged boss/miniboss, or the other spawn paths would NOT set is_boss and this fix would be the odd one out" % mid)


func test_the_banner_still_says_miniboss() -> void:
	var e: Combatant = _spawn_miniboss()
	if e == null:
		return
	var joined: String = "\n".join(_scene_ref.lines)
	assert_string_contains(joined, "MINIBOSS BATTLE", "a miniboss must keep its own wording, not inherit the boss title")
	assert_false(joined.contains("BOSS BATTLE!  👑"), "and must not be announced as a full boss")
	assert_string_contains(joined, "appeared!", "and must still name what showed up")


## The six hand-rolled log lines were a copy of the shared helper, which exists so the paths cannot drift.
func test_the_banner_came_from_the_shared_helper() -> void:
	var e: Combatant = _spawn_miniboss()
	if e == null:
		return
	var rules := 0
	for line in _scene_ref.lines:
		if str(line).contains("═══"):
			rules += 1
	assert_eq(rules, 2, "the banner must be the shared helper's two rules, not a divergent hand-rolled copy")
	assert_eq(str(_scene_ref.lines[0]), "", "and keep the helper's leading blank line")


## THE CONSEQUENCE, measured rather than inferred: VictoryOverlay grades a kill by is_boss, with no
## is_miniboss fallback. NORMAL vs ELITE is font 48->58, one ring->two, 0.45s hold->0.62s, yellow->
## pink, and _headline_foe -- "the name billed under VICTORY on a boss kill" -- returns "" without it.
func test_the_victory_screen_grades_it_like_the_miniboss_it_is() -> void:
	var e: Combatant = _spawn_miniboss()
	if e == null:
		return
	var vo = VictoryOverlayScript.new()
	autofree(vo)
	vo._scene = _scene_ref
	assert_eq(vo._victory_grade(), VictoryOverlayScript.Grade.ELITE,
		"a miniboss kill must not be graded as an ordinary encounter on the victory screen")
	assert_ne(vo._headline_foe(), "",
		"and the foe must be billed by name, which _headline_foe can only do through is_boss")
