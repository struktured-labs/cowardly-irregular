extends Area2D
class_name MasteriteEncounter

## MasteriteEncounter — once-per-save W1 mini-boss trigger placed on the
## four W1 outer villages (Sandrift/Eldertree/Grimhollow/Ironhaven) per
## docs/design/w1-progression-expansion.md. Uses the BossTrigger shape
## the dragon caves ship with — collision_layer=4/mask=2, "interactables"
## group membership — but fires on body_entered (not require_interaction)
## and stakes `pending_boss_defeat` before emitting battle_triggered so
## GameLoop._apply_pending_boss_defeat sets the flag on victory. Once
## defeated, the trigger hides itself and stops monitoring.
##
## Design contract per the doc:
##  - Fires ONCE per save (gated on `w1_<archetype>_defeated` story flag).
##  - Drops that flag on victory via `pending_boss_defeat.story_flags`.
##  - Optional prereq_flag lets Sandrift's Warden wait for the Rat King
##    defeat before appearing on the trade road ("legitimate business").
##  - Framework compat: the trigger owns a small AABB (2×2 tiles) tuned
##    so `test_overworld_reachability_framework` sees no eclipsed sibling.

const TILE_SIZE: int = 32

## The archetype id — used to compose the defeat flag `w1_<id>_defeated`.
## E.g. "warden", "tempo", "arbiter", "curator".
@export var archetype: String = ""

## Full monster id in data/monsters.json (e.g. "masterite_warden_medieval").
@export var monster_id: String = ""

## Optional story-flag gate. Empty = always active; non-empty = only
## renders once GameState.get_story_flag(prereq_flag) is true.
## Design v1: Sandrift's Warden uses "cave_rat_king_defeated" here.
@export var prereq_flag: String = ""

## Display label above the pre-fight silhouette (design flavor).
@export var display_name: String = ""

var _fired: bool = false


func _ready() -> void:
	add_to_group("interactables")
	collision_layer = 4
	collision_mask = 2
	monitoring = true
	monitorable = true

	if _defeat_flag_set() or not _prereq_met():
		visible = false
		monitoring = false
		return

	_build_collision()
	_build_silhouette()
	body_entered.connect(_on_body_entered)


func defeat_flag() -> String:
	return "w1_%s_defeated" % archetype


func _defeat_flag_set() -> bool:
	if GameState == null:
		return false
	return GameState.get_story_flag(defeat_flag())


func _prereq_met() -> bool:
	if prereq_flag == "":
		return true
	if GameState == null:
		return true
	return GameState.get_story_flag(prereq_flag)


func _build_collision() -> void:
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	# 2×2 tiles — small enough that no dragon-cave / village-shop AABB
	# eclipses it, wide enough that a Mode 7-stretched sprite still lands
	# a hit at the center. Framework check: `test_overworld_reachability_framework`.
	shape.size = Vector2(TILE_SIZE * 2, TILE_SIZE * 2)
	cs.shape = shape
	add_child(cs)


func _build_silhouette() -> void:
	# A simple standing figure (silhouette) — a real sprite lands as a
	# follow-up when the art batch reaches these. Silhouette reads as
	# "someone is standing in your way" at overworld scale.
	var sprite := Sprite2D.new()
	sprite.name = "MasteriteSilhouette"
	var img := Image.create(TILE_SIZE, TILE_SIZE * 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var body := Color(0.14, 0.13, 0.18)
	var body_lt := Color(0.22, 0.20, 0.26)
	var trim := Color(0.55, 0.42, 0.20)
	# head
	for y in range(4, 14):
		for x in range(10, 22):
			var dx := float(x - 16) / 6.0
			var dy := float(y - 9) / 5.0
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, body if x < 16 else body_lt)
	# shoulders → torso
	for y in range(14, 42):
		for x in range(8, 24):
			img.set_pixel(x, y, body if x < 16 else body_lt)
	# trim (sash / belt)
	for x in range(8, 24):
		img.set_pixel(x, 30, trim)
	# legs
	for y in range(42, 60):
		for x in range(10, 15):
			img.set_pixel(x, y, body)
		for x in range(17, 22):
			img.set_pixel(x, y, body_lt)
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.centered = true
	sprite.position = Vector2(0, -TILE_SIZE / 2)
	add_child(sprite)

	if display_name != "":
		var label := Label.new()
		label.text = display_name
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.position = Vector2(-64, -TILE_SIZE * 2 - 8)
		label.size = Vector2(128, 14)
		label.add_theme_font_size_override("font_size", 10)
		label.add_theme_color_override("font_color", Color(0.92, 0.88, 0.72))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)


func _on_body_entered(body: Node2D) -> void:
	if _fired:
		return
	# Belt-and-suspenders vs _ready's monitoring=false: if the flag flips
	# after _ready (defeat lands late-frame) or an external caller invokes
	# _on_body_entered on a hidden trigger, still refuse to re-stake.
	if _defeat_flag_set():
		return
	if not (body.is_in_group("player") or body.has_method("set_can_move")):
		return
	if monster_id == "" or archetype == "":
		push_warning("[MasteriteEncounter] missing archetype/monster_id — skipping fire")
		return
	_fired = true
	# Stake pending_boss_defeat so GameLoop._apply_pending_boss_defeat writes
	# the w1_<archetype>_defeated flag on victory — matches the DragonCave
	# contract, minus dungeon_flag/unlock_world (masterites are mid-arc, they
	# don't gate world unlock).
	if GameState:
		GameState.pending_boss_defeat = {
			"story_flags": [defeat_flag()],
			"constants": [],
			"dungeon_flag": "",
		}
	monitoring = false
	_fire_battle()


func _fire_battle() -> void:
	# Parent-walk to the scene that owns the battle relay (village
	# scenes have _on_battle_triggered from BaseVillage's signal chain).
	var node = get_parent()
	while node:
		if node.has_method("_on_battle_triggered"):
			node._on_battle_triggered([monster_id])
			return
		node = node.get_parent()
	push_warning("[MasteriteEncounter] no ancestor exposes _on_battle_triggered — battle not fired")
