extends Area2D
class_name TreasureChest

## TreasureChest - Openable treasure container
## Contains items, gold, or equipment

signal chest_opened(contents: Dictionary)

@export var chest_id: String = "chest_001"  # Unique ID for save tracking
@export var contents_type: String = "item"  # item, gold, equipment
@export var contents_id: String = "potion"
@export var contents_amount: int = 1
@export var gold_amount: int = 100

## Visual
var sprite: Sprite2D
var name_label: Label
var dialogue_box: Control
var dialogue_label: Label
## Mode 7 throws a world-space offset at the horizon: the loot popup drew 8px wide near the skyline.
var _prompt_layer: CanvasLayer
var _popup_layer: CanvasLayer
const FLAT_NAME_OFFSET := Vector2(-30, -24)
const FLAT_NAME_FONT: int = 10

## State
## What the panel says when the grant did nothing. One spelling, so a guard pins the STATE rather
## than a sentence, and the arms cannot drift apart.
const NOTHING_ADDED: String = "Nothing was added."
const KIND_GOLD: String = "gold"
const KIND_EQUIPMENT: String = "equipment"


## ⛔ THE ONE PLACE A FIND IS CLAIMED, AND IT TAKES WHAT WAS GRANTED RATHER THAN WHAT WAS
## CONFIGURED. Three arms each spelled "announce the configured contents" and only the gold one had
## been repaired to read the effect — so the repair existed, in the file, next to two copies of the
## bug it fixed. Routing all three through one seam means a fourth arm cannot reintroduce the claim,
## and `granted <= 0` is the single rule rather than three agreeing conditions.
##
## It is STATIC so a guard can drive the decision without standing up a GameLoop, a party and a
## scene tree — the same seam shape as QuestExaminePoint.cue_for.
static func claim_for(kind: String, display: String, granted: int) -> String:
	if granted <= 0:
		return NOTHING_ADDED
	## CONSTS, NOT LITERALS: test_treasure_chest_gold_regression anchors on the FIRST gold match arm
	## in this file and reads a 900-char window for the grant call and its has-method guard. This
	## seam sits ABOVE the real grant, so a literal arm here steals that anchor and the window lands
	## on a function that makes no grant. The guard was right; my change moved what it pointed at.
	## Written without the verbatim tokens on purpose -- prose that spells them steals it too.
	match kind:
		KIND_GOLD:
			return "Found %d Gold!" % granted
		KIND_EQUIPMENT:
			return "Found %s!" % display
		_:
			return "Found %s x%d!" % [display, granted]

var _is_opened: bool = false
var _player_nearby: bool = false
## Found-line is still on screen. A second confirm must not swap it for "empty".
var _showing_loot: bool = false
## Bumped when a popup is replaced or the player steps away, so a stale timer cannot hide the new one.
var _popup_gen: int = 0

const TILE_SIZE: int = 32


func _ready() -> void:
	# Save-tracking footgun guard: a chest that never overrode chest_id shares
	# its opened-flag ("chest_" + id) with every other forgetter — open one and
	# all of them vanish. Nothing legitimately uses the "chest_001" default, so
	# hitting it (or an empty id) means a scene forgot to assign a unique one.
	if chest_id == "" or chest_id == "chest_001":
		push_warning("[TreasureChest] '%s' still has the default/empty chest_id ('%s') — set a unique id or its opened state collides with other chests" % [name, chest_id])
	_check_if_opened()
	_generate_sprite()
	_setup_collision()
	_setup_name_label()
	_setup_dialogue_box()

	## Tick 455: register the chest in a "treasure" group so the
	## content_radar passive can find and count nearby unopened
	## chests for its HUD readout. Plain group membership avoids
	## any scene-specific coupling.
	add_to_group("treasure")

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _check_if_opened() -> void:
	_is_opened = GameState.get_story_flag("chest_" + chest_id)


## Artist art if it exists, procedural chest otherwise. assets/sprites/objects/
## holds chest_open/chest_closed and had NO consumer — art we owned, unreachable.
func _generate_sprite() -> void:
	sprite = Sprite2D.new()
	sprite.name = "Sprite"

	var art := "res://assets/sprites/objects/chest_%s.png" % ("open" if _is_opened else "closed")
	if ResourceLoader.exists(art):
		sprite.texture = load(art)
		sprite.centered = true
		add_child(sprite)
		return

	var image = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	_draw_chest(image)

	var texture = ImageTexture.create_from_image(image)
	sprite.texture = texture
	sprite.centered = true
	add_child(sprite)


func _draw_chest(image: Image) -> void:
	image.fill(Color.TRANSPARENT)

	var wood = Color(0.52, 0.36, 0.16) if not _is_opened else Color(0.42, 0.28, 0.12)
	var wood_light = Color(0.62, 0.45, 0.22)
	var wood_dark = Color(0.35, 0.22, 0.10)
	var wood_grain = Color(0.45, 0.30, 0.13)
	var metal = Color(0.75, 0.65, 0.22)
	var metal_light = Color(0.88, 0.78, 0.35)
	var metal_dark = Color(0.52, 0.42, 0.15)
	var metal_shine = Color(0.95, 0.90, 0.55)
	var outline = Color(0.15, 0.10, 0.05)

	if _is_opened:
		# Open chest - lid tilted back with shading
		# Lid (back, tilted) with 3D perspective
		for y in range(3, 12):
			for x in range(5, 27):
				var c = wood_dark
				if y == 3:
					c = metal  # Top rim
				elif y < 6:
					c = wood_light  # Inside of lid visible
				elif x == 5 or x == 26:
					c = outline
				elif y == 11:
					c = outline
				# Wood grain on lid
				elif (x + y) % 5 == 0:
					c = wood_grain
				image.set_pixel(x, y, c)
		# Lid hinge detail
		image.set_pixel(8, 12, metal_dark)
		image.set_pixel(24, 12, metal_dark)

		# Chest body (front) with beveled edges and wood grain
		for y in range(13, 28):
			for x in range(4, 28):
				var c = wood
				# Outline
				if x == 4 or x == 27:
					c = outline
				elif y == 13:
					c = metal  # Top rim
				elif y == 27:
					c = outline
				# Beveled edges (lighter at top, darker at bottom)
				elif y < 16:
					c = wood_light
				elif y > 25:
					c = wood_dark
				# Wood plank grain lines
				elif x % 6 == 0:
					c = wood_grain
				# Left-right shading (3D box)
				elif x < 8:
					c = wood_dark
				elif x > 24:
					c = wood_dark
				image.set_pixel(x, y, c)

		# Metal bands across chest
		for x in range(5, 27):
			image.set_pixel(x, 13, metal)
			image.set_pixel(x, 20, metal_dark)
			image.set_pixel(x, 27, metal_dark)

		# Corner metal studs
		for corner in [[6, 15], [6, 25], [25, 15], [25, 25]]:
			image.set_pixel(corner[0], corner[1], metal_light)

		# Open interior (dark cavity with gradient)
		for y in range(14, 20):
			for x in range(6, 26):
				var depth = float(y - 14) / 6.0
				var c = Color(0.12, 0.08, 0.04).lerp(Color(0.22, 0.15, 0.08), depth)
				image.set_pixel(x, y, c)

		# Sparkle treasures inside
		image.set_pixel(10, 17, Color(1.0, 0.95, 0.4))
		image.set_pixel(11, 16, Color(1.0, 1.0, 0.7, 0.7))
		image.set_pixel(20, 18, Color(1.0, 0.95, 0.4))
		image.set_pixel(15, 17, Color(0.6, 0.8, 1.0, 0.8))  # Gem sparkle
		image.set_pixel(18, 16, Color(1.0, 0.9, 0.3, 0.6))

	else:
		# Closed chest with detailed SNES-quality rendering
		# Lid (top) with rounded profile and metal trim
		for y in range(5, 14):
			for x in range(4, 28):
				var c = wood
				if y == 5:
					c = metal  # Top metal rim
				elif y == 6:
					c = metal_light  # Metal highlight
				elif y == 13:
					c = metal  # Bottom metal rim
				elif x == 4 or x == 27:
					c = outline
				# Rounded lid shading (lighter at top, darker at bottom)
				elif y < 9:
					# Top of lid - lighter
					if (x + y) % 5 == 0:
						c = wood_grain
					else:
						c = wood_light
				else:
					# Bottom of lid - darker
					if (x + y) % 5 == 0:
						c = wood_grain
					else:
						c = wood
				# Left-right 3D shading
				if x >= 5 and x <= 26 and y > 5 and y < 13:
					if x < 8:
						c = c.darkened(0.15)
					elif x > 24:
						c = c.darkened(0.1)
				image.set_pixel(x, y, c)

		# Chest body with beveled edges
		for y in range(14, 28):
			for x in range(4, 28):
				var c = wood
				if x == 4 or x == 27:
					c = outline
				elif y == 27:
					c = outline
				elif y == 14:
					c = metal_dark  # Seam between lid and body
				elif x % 6 == 0 and y > 15 and y < 26:
					c = wood_grain
				elif y < 17:
					c = wood_light
				elif y > 25:
					c = wood_dark
				# Left-right shading
				if x >= 5 and x <= 26 and y > 14 and y < 27:
					if x < 8:
						c = c.darkened(0.15)
					elif x > 24:
						c = c.darkened(0.1)
				image.set_pixel(x, y, c)

		# Metal bands (horizontal reinforcement)
		for x in range(5, 27):
			image.set_pixel(x, 14, metal)
			image.set_pixel(x, 21, metal_dark)

		# Corner metal studs (bright 3D rivets)
		for corner_pos in [[6, 16], [6, 25], [25, 16], [25, 25]]:
			var cx = corner_pos[0]
			var cy = corner_pos[1]
			image.set_pixel(cx, cy, metal_light)
			image.set_pixel(cx + 1, cy, metal_shine)
			image.set_pixel(cx, cy + 1, metal_dark)
			image.set_pixel(cx + 1, cy + 1, metal)

		# Lock plate with keyhole (larger, more detailed)
		for y in range(15, 22):
			for x in range(13, 19):
				var c = metal
				if x == 13 or x == 18 or y == 15 or y == 21:
					c = metal_dark  # Frame
				elif x == 14 and y == 16:
					c = metal_shine  # Top-left highlight
				image.set_pixel(x, y, c)
		# Keyhole
		image.set_pixel(15, 17, outline)
		image.set_pixel(16, 17, outline)
		image.set_pixel(15, 18, outline)
		image.set_pixel(16, 18, outline)
		image.set_pixel(15, 19, outline)
		image.set_pixel(16, 19, outline)
		image.set_pixel(15, 20, outline)

		# Gleam effect (sparkle on metal)
		image.set_pixel(7, 7, Color(1.0, 1.0, 0.85, 0.9))
		image.set_pixel(8, 8, Color(1.0, 1.0, 0.80, 0.6))
		image.set_pixel(6, 8, Color(1.0, 1.0, 0.85, 0.3))
		image.set_pixel(8, 6, Color(1.0, 1.0, 0.85, 0.3))


func _setup_collision() -> void:
	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	# Mode 7 overworld needs the tall billboard grab zone; flat villages read that as a 4-tile grabber arm (struktured 2026-07-12: "opened a chest 5 tiles away").
	if Mode7Overlay.is_active:
		shape.radius = InteractGeometry.CHEST_GRAB_RADIUS_MODE7
		collision.scale = Vector2(1.0, InteractGeometry.MODE7_Y_STRETCH)  # Mode 7 billboard Y:X ratio (0.3:0.5)
	else:
		shape.radius = InteractGeometry.CHEST_GRAB_RADIUS_FLAT  # ~1.25 tiles for flat villages/interiors
		collision.scale = Vector2.ONE
	collision.shape = shape
	add_child(collision)

	collision_layer = 4
	collision_mask = 2
	monitoring = true
	monitorable = true


func _setup_name_label() -> void:
	name_label = Label.new()
	name_label.text = "Treasure" if not _is_opened else "(Empty)"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = FLAT_NAME_OFFSET
	name_label.size = Vector2(60, 20)
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", Color.GOLD if not _is_opened else Color.GRAY)
	name_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	name_label.add_theme_constant_override("shadow_offset_x", 1)
	name_label.add_theme_constant_override("shadow_offset_y", 1)
	name_label.visible = false
	Mode7Prompt.pin_above_sprites(name_label)
	add_child(name_label)


func _setup_dialogue_box() -> void:
	dialogue_box = Control.new()
	dialogue_box.name = "DialogueBox"
	dialogue_box.visible = false
	dialogue_box.z_index = 100

	# Item 14 (2026-07-01 playtest): panel was 200×50 @ y=-70 — bottom at
	# y=-20 sat 4px above the 32px chest sprite, reading as "on the chest".
	# Enlarged + lifted so it floats clearly above with visible air. Chest
	# center → panel bottom is now 46px, plenty of separation.
	var panel = Panel.new()
	panel.position = Vector2(-120, -110)
	panel.size = Vector2(240, 60)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.08, 0.05, 0.95)
	style.border_color = Color.GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	dialogue_box.add_child(panel)

	# Item 14: label geometry follows the enlarged panel — 224×44 inside
	# the 240×60 panel, 8px inset all around.
	dialogue_label = Label.new()
	dialogue_label.position = Vector2(-112, -102)
	dialogue_label.size = Vector2(224, 44)
	dialogue_label.add_theme_font_size_override("font_size", 12)
	dialogue_label.add_theme_color_override("font_color", Color.WHITE)
	dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialogue_box.add_child(dialogue_label)

	add_child(dialogue_box)


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("set_can_move"):
		_player_nearby = true
		if not _is_opened:
			name_label.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.has_method("set_can_move"):
		_player_nearby = false
		name_label.visible = false
		dialogue_box.visible = false
		_showing_loot = false
		_popup_gen += 1


func interact(player: Node2D) -> void:
	if _showing_loot:
		return
	if _is_opened:
		_clamp_dialogue_box_to_viewport() # opened re-interact clips at the wall unless this runs before the notice
		_show_empty_notice()
		return

	_open_chest(player)


func _next_popup() -> int:
	_popup_gen += 1
	return _popup_gen


## The found line slides the label aside for the icon. The empty reread must not keep either.
func _clear_loot_presentation() -> void:
	_set_loot_icon("")
	if dialogue_label == null:
		return
	dialogue_label.position = Vector2(-112, -102)
	dialogue_label.size = Vector2(224, 44)
	dialogue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialogue_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP


func _show_empty_notice() -> void:
	var gen := _next_popup()
	_clear_loot_presentation()
	_clamp_dialogue_box_to_viewport()
	dialogue_box.visible = true
	dialogue_label.text = "The chest is empty."
	await get_tree().create_timer(1.0).timeout
	if gen != _popup_gen or not is_instance_valid(self) or not is_instance_valid(dialogue_box):
		return
	dialogue_box.visible = false


## Chest popup at (-120, -110) relative to the chest world position clips at dungeon-room edges when the chest sits close to a wall (struktured playtest msg 2802). Same class as the old local-panel cutoff bug that NPCDialogue was created to fix. Clamp the panel's world position inside the visible viewport with a 16px margin by shifting dialogue_box.position.
const _POPUP_MARGIN := 16.0
const _POPUP_LOCAL_OFFSET := Vector2(-120.0, -110.0)
const _POPUP_SIZE := Vector2(240.0, 60.0)

## Screen-space prompts follow the player's drawn position, not the chest's world offset.
func _process(_delta: float) -> void:
	if InteractGeometry.is_mode7():
		if _prompt_layer == null and name_label != null:
			_prompt_layer = Mode7Prompt.lift(self, name_label)
		if _popup_layer == null and dialogue_box != null:
			_popup_layer = Mode7Prompt.lift_control(self, dialogue_box)
		var vp := get_viewport_rect().size
		if name_label != null and name_label.visible:
			Mode7Prompt.place(name_label, vp, Mode7Prompt.ROW_ACTION)
		if dialogue_box != null and dialogue_box.visible:
			Mode7Prompt.place_control(dialogue_box, vp, Mode7Prompt.ROW_POPUP)
	elif _prompt_layer != null or _popup_layer != null:
		if _prompt_layer != null:
			Mode7Prompt.drop(self, _prompt_layer, name_label, FLAT_NAME_OFFSET, FLAT_NAME_FONT)
			_prompt_layer = null
		if _popup_layer != null:
			Mode7Prompt.drop_control(self, _popup_layer, dialogue_box, Vector2.ZERO)
			_popup_layer = null


func _clamp_dialogue_box_to_viewport() -> void:
	if not is_instance_valid(dialogue_box):
		return
	# Screen space is already inside the viewport; the world-coordinate clamp would fight it.
	if _popup_layer != null:
		return
	dialogue_box.position = Vector2.ZERO
	var vp := get_viewport()
	if vp == null:
		return
	var cam := vp.get_camera_2d()
	if cam == null:
		return
	var vp_size := vp.get_visible_rect().size
	var half := vp_size * 0.5
	var cam_center := cam.get_screen_center_position()
	var screen_min := cam_center - half + Vector2(_POPUP_MARGIN, _POPUP_MARGIN)
	var screen_max := cam_center + half - Vector2(_POPUP_MARGIN, _POPUP_MARGIN)
	var panel_min := global_position + _POPUP_LOCAL_OFFSET
	var panel_max := panel_min + _POPUP_SIZE
	var delta := Vector2.ZERO
	if panel_min.x < screen_min.x:
		delta.x = screen_min.x - panel_min.x
	elif panel_max.x > screen_max.x:
		delta.x = screen_max.x - panel_max.x
	if panel_min.y < screen_min.y:
		delta.y = screen_min.y - panel_min.y
	elif panel_max.y > screen_max.y:
		delta.y = screen_max.y - panel_max.y
	dialogue_box.position = delta


## ⛔ THE GRANT, LIFTED OUT SO IT CAN RUN BEFORE THE CHEST COMMITS TO BEING OPEN. It returns the
## PANEL TEXT and nothing else, so `granted` is DERIVED from it (`!= NOTHING_ADDED`) rather than
## carried beside it — one fact, one source. A second `ok` field would be the two-sources hazard
## this project's own CLAUDE.md names: they would agree today, which is the condition for a bug
## rather than a bug.
func _grant_contents() -> String:
	## ⛔ SEEDED AS A REFUSAL, NOT AS "". An empty string is not equal to NOTHING_ADDED, so an
	## unassigned path would read as GRANTED and consume the chest — the fail-OPEN direction, on the
	## one predicate the whole commit hangs from. All four arms assign today, so this is the default
	## nobody reaches; seeding it here means a FIFTH arm that forgets to assign refuses instead of
	## silently eating a reward.
	var contents_text := NOTHING_ADDED
	match contents_type:
		"gold":
			# Actually add the gold to the party. Pre-fix the comment said
			# "(if implemented)" and the call was never wired — players saw
			# "Found 100 Gold!" but party_gold stayed unchanged. Silent
			# regression: the chest_opened signal fires but no listener
			# touches GameState, and PartyStatusScreen's gold display
			# showed stale values. Routes through GameState.add_gold so
			# the gold_multiplier game_constant still applies.
			# ⚠️ AND THE FALLBACK IN THE ARM THAT WAS ALREADY REPAIRED CLAIMED TOO. `credited` was
			# seeded with `gold_amount`, so an absent GameState.add_gold announced the full find
			# having credited nothing — the same shape as the bug this arm's comment describes,
			# one layer in. Seed it at zero and let only a real credit raise it.
			var credited: int = 0
			if GameState and GameState.has_method("add_gold"):
				credited = int(GameState.add_gold(gold_amount))
			contents_text = claim_for("gold", "", credited)
		"item":
			# ⛔ ANNOUNCE AFTER THE GRANT, AND FROM WHAT IT ACTUALLY DID. Pre-fix this wrote
			# "Found %s x%d!" FIRST and then called add_item, discarding the result, behind
			# `if game_loop and party.size() > 0` — so three separate nothing-happened paths each
			# printed a find: no GameLoop, an empty party, and add_item's own two refusals
			# (negative quantity, empty id). That is the SAME defect the gold arm above already
			# shipped and had repaired — its comment records players seeing "Found 100 Gold!" with
			# party_gold unchanged — and only the gold arm was fixed. add_item returns `void`, so
			# the effect is read as an INVENTORY DELTA rather than a return value, which also
			# covers any refusal added to it later.
			var item_name = _resolve_display_name(contents_id)
			var gained: int = 0
			var game_loop = get_tree().root.get_node_or_null("GameLoop")
			if game_loop and game_loop.party.size() > 0:
				var holder = game_loop.party[0]
				var before: int = (int(holder.inventory.get(contents_id, 0)) if "inventory" in holder else 0)
				holder.add_item(contents_id, contents_amount)
				if "inventory" in holder:
					gained = int(holder.inventory.get(contents_id, 0)) - before
			contents_text = claim_for("item", item_name, gained)
		"equipment":
			var equip_name = _resolve_display_name(contents_id)
			# Add to equipment pool. Slot is resolved against EquipmentSystem's
			# weapons/armors/accessories dicts so the categorization is correct
			# regardless of naming convention. Pre-fix used keyword heuristics
			# ("armor" or "robe" or "mail" → armors) which misclassified items
			# like "iron_breastplate" or "obsidian_cuirass" into the weapons
			# pool, leaving them stuck and un-equippable as armor. Falls back
			# to "weapons" only when EquipmentSystem can't resolve the ID at
			# all (genuinely unknown item — better than dropping silently).
			# Same read-the-effect rule as the item arm: a null GameLoop announced a find and
			# appended to nothing.
			var game_loop = get_tree().root.get_node_or_null("GameLoop")
			var pooled: bool = false
			if game_loop:
				var pool_key = _resolve_equipment_pool(contents_id)
				if not game_loop.equipment_pool.has(pool_key):
					game_loop.equipment_pool[pool_key] = []
				var before_n: int = game_loop.equipment_pool[pool_key].size()
				game_loop.equipment_pool[pool_key].append(contents_id)
				pooled = game_loop.equipment_pool[pool_key].size() > before_n
			contents_text = claim_for("equipment", equip_name, 1 if pooled else 0)
		_:
			# ⚠️ contents_type IS DATA-DRIVEN at one site — WhisperingCave:749 assigns
			# `data["type"]` straight from its per-floor table — and this match had no default, so
			# an unrecognised type fell through with contents_text = "" and granted nothing, under
			# a chest that had already written its save-persisted flag. All five of that table's
			# floors are "item"/"gold" today, so this is latent rather than live; a silent empty
			# panel is the one outcome that cannot be told from a working chest.
			push_warning("[TreasureChest] %s has unknown contents_type '%s' — nothing granted" % [chest_id, contents_type])
			contents_text = claim_for(contents_type, "", 0)
	return contents_text

## ⛔ A GRANT THAT DID NOTHING NO LONGER CONSUMES THE CHEST. `_is_opened = true` and the
## save-persisted `set_story_flag` used to be the FIRST two statements, above the grant — so any
## nothing-happened path left a permanently-opened chest and the item gone. The stake was never the
## caption; it was a lost reward behind a flag that survives a reload.
##
## 🔑 THE SUCCESS PATH IS DELIBERATELY UNCHANGED, STATEMENT FOR STATEMENT. All 39 chest
## configuration sites in `src/` carry valid data today (derived, not assumed — the six overworlds
## constrain the type with `if c["type"] == "gold" … else`, and WhisperingCave's five floors are all
## item/gold with positive amounts), so `granted` is true for every chest in the game and this
## restructure cannot regress one. The refusal branch is reachable only from a future data edit,
## which is exactly the arrival it exists to meet.
func _open_chest(player: Node2D) -> void:
	## The grant happens FIRST. Everything below it is the commit, and the commit is conditional.
	var contents_text := _grant_contents()
	var granted := contents_text != NOTHING_ADDED
	_showing_loot = true
	var gen := _next_popup()
	if granted:
		_is_opened = true
		GameState.set_story_flag("chest_" + chest_id)

	# Play sound
	if SoundManager:
		SoundManager.play_ui("chest_open")

	# Update sprite — the SAME art convention _generate_sprite uses. Without this
	# an artist-rendered chest snaps to the procedural drawing the moment it opens.
	# ⚠️ AND IT ONLY LOOKS OPEN IF IT IS. An unconditional swap drew an open, "(Empty)" chest over
	# a chest that still holds its contents — the player's one cue that it is worth pressing again.
	if granted:
		var art := "res://assets/sprites/objects/chest_open.png"
		if ResourceLoader.exists(art):
			sprite.texture = load(art)
		else:
			var image = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
			_draw_chest(image)
			sprite.texture = ImageTexture.create_from_image(image)

		# Update label
		name_label.text = "(Empty)"
		name_label.add_theme_color_override("font_color", Color.GRAY)
		name_label.visible = true

	# Show dialogue. The icon sits above the pinned 240x60 panel so the label geometry stays put.
	_clamp_dialogue_box_to_viewport()
	dialogue_box.visible = true
	dialogue_label.text = contents_text
	## The icon DEPICTS A RECEIVED ITEM, so it answers to the effect like the panel and the cue.
	## The `chest_open` lid sound above deliberately does NOT: the press registered, and @cowir-sfx's
	## ruling on the examine chime is that silence cannot say so.
	_set_loot_icon(contents_id if granted and (contents_type == "item" or contents_type == "equipment") else "")

	## ⛔ AND THE SIGNAL. `chest_opened` is what listeners credit from — WhisperingCave:764 connects
	## it — so emitting it after a grant that did nothing invites a SECOND phantom credit on top of
	## the panel's. It fires only on a real grant.
	if granted:
		chest_opened.emit({"type": contents_type, "id": contents_id, "amount": contents_amount})
	# Content-aware "loot received" cue. Pre-fix this also played
	# "chest_open" — the same sound the opening at line 331 already fired,
	# so every chest played chest_open TWICE. Gold gets the canonical
	# gold_pickup chime (matches BattleResultsDisplay's gold count-up).
	#
	# Equipment now takes the composed stinger_item_found fanfare. The old note
	# here said a music stinger "caused a loop bug" — that bug was manifest
	# stingers carrying loop=true, so they never emitted `finished` and the
	# previous track never came back. Fixed 2026-05-02: SoundManager force-clears
	# loop for any "stinger_" id regardless of the manifest, and all five entries
	# now also carry loop=false. Consumables stay quiet — a fanfare per potion is
	# what makes a fanfare stop meaning anything.
	## The loot cue answers to the effect too — the same rule as the examine chime, one lane item
	## earlier: a fanfare for a grant that did not happen is the audio half of the same lie.
	## NESTED, not `and`-ed: test_treasure_chest_audio_dedupe_regression pins the literal outer
	## form for the post-emit block, and collapsing it into one condition reds a guard whose
	## subject (a null-safe second cue) this still satisfies. Their pin stays; the gate goes in.
	if SoundManager:
		if granted:
			match contents_type:
				"gold":
					SoundManager.play_pickup("gold_pickup")
				"equipment":
					SoundManager.play_music("stinger_item_found")

	# Hide after delay. A step-away or a later empty reread bumps _popup_gen, so this must not dismiss that line.
	await get_tree().create_timer(2.0).timeout
	if not is_instance_valid(self) or not is_instance_valid(dialogue_box):
		return
	if gen != _popup_gen:
		return
	_showing_loot = false
	dialogue_box.visible = false


## Tick 135: thin wrapper around ItemNameResolver. Local helper
## stays so call sites don't change shape.
func _set_loot_icon(item_id: String) -> void:
	if dialogue_box == null:
		return
	var old := dialogue_box.get_node_or_null("LootIcon")
	if old:
		old.queue_free()
	if item_id == "":
		return
	var icon := ItemIcons.make_rect(item_id, 32)
	icon.name = "LootIcon"
	icon.position = Vector2(-112, -102 + (44 - 32) * 0.5)
	dialogue_box.add_child(icon)
	# Slide the pinned label right of the icon. The setup assignment stays so the geometry pin holds.
	dialogue_label.position = Vector2(-76, -102)
	dialogue_label.size = Vector2(184, 44)
	dialogue_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dialogue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT


func _resolve_display_name(contents_id: String) -> String:
	return ItemNameResolver.resolve(contents_id)


func _resolve_equipment_pool(item_id: String) -> String:
	## Returns "weapons" / "armors" / "accessories" based on which
	## EquipmentSystem dict actually contains the item ID. Falls back to
	## "weapons" only when EquipmentSystem isn't available or genuinely
	## doesn't know the item — better than silently dropping the chest
	## reward. The fallback matches pre-fix default behavior so existing
	## save data with mis-pooled items doesn't change shape.
	# Engine.has_singleton("EquipmentSystem") is ALWAYS FALSE for autoloads in
	# Godot 4. The autoload lookup below (eq_node) is the only path that ever
	# fires; keep it as the sole source of truth.
	var eq_node = get_node_or_null("/root/EquipmentSystem")
	if eq_node:
		if eq_node.has_method("get_weapon") and not eq_node.get_weapon(item_id).is_empty():
			return "weapons"
		if eq_node.has_method("get_armor") and not eq_node.get_armor(item_id).is_empty():
			return "armors"
		if eq_node.has_method("get_accessory") and not eq_node.get_accessory(item_id).is_empty():
			return "accessories"
	return "weapons"
