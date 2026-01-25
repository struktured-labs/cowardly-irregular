extends Node2D
class_name TavernInterior

## TavernInterior - "The Dancing Tonberry" bar interior
## Separate scene like the cave, with NPCs and the iconic dancing girl

signal transition_triggered(target_map: String, target_spawn: String)
signal area_transition(target_map: String, target_spawn: String)
signal battle_triggered(enemies: Array)

## Constants
const TILE_SIZE: int = 32
const MAP_WIDTH: int = 16
const MAP_HEIGHT: int = 12

## Scene components
var tilemap: TileMapLayer
var player: Node2D
var camera: Camera2D
var npcs: Node2D
var transitions: Node2D
var decorations: Node2D
var controller: Node

## Dancing girl animation
var dancer_sprite: Sprite2D
var _dancer_frames: Array[ImageTexture] = []
var _anim_frame: int = 0
var _anim_timer: float = 0.0
const ANIM_SPEED: float = 0.15

## Spawn points
var spawn_points: Dictionary = {
	"entrance": Vector2(8, 10),
	"stage": Vector2(12, 4),
	"bar": Vector2(4, 4)
}

## Floor layout
## . = floor, W = wall, B = bar counter, S = stage, T = table, D = door
const TAVERN_LAYOUT = [
	"WWWWWWWWWWWWWWWW",
	"W..............W",
	"W.BBB....SSSSS.W",
	"W.BBB....SSSSS.W",
	"W.BBB....SSSSS.W",
	"W..............W",
	"W..TT....TT....W",
	"W..TT....TT....W",
	"W..............W",
	"W..TT....TT....W",
	"W..............W",
	"WWWWWWWDDDWWWWWW"
]


func _ready() -> void:
	_setup_tilemap()
	_setup_decorations()
	_setup_dancer()
	_setup_npcs()
	_setup_transitions()
	_setup_player()
	_setup_camera()
	_setup_controller()

	# Play tavern music
	if SoundManager:
		SoundManager.play_area_music("village")  # Reuse village music for now


func _process(delta: float) -> void:
	_animate_dancer(delta)


func _setup_tilemap() -> void:
	tilemap = TileMapLayer.new()
	tilemap.name = "TileMapLayer"
	add_child(tilemap)

	# Create tileset
	var tileset = TileSet.new()
	tileset.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# Floor source
	var floor_source = TileSetAtlasSource.new()
	var floor_img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	_draw_floor_tile(floor_img)
	floor_source.texture = ImageTexture.create_from_image(floor_img)
	floor_source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	floor_source.create_tile(Vector2i(0, 0))
	tileset.add_source(floor_source, 0)

	# Wall source
	var wall_source = TileSetAtlasSource.new()
	var wall_img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	_draw_wall_tile(wall_img)
	wall_source.texture = ImageTexture.create_from_image(wall_img)
	wall_source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	wall_source.create_tile(Vector2i(0, 0))
	tileset.add_source(wall_source, 1)

	tilemap.tile_set = tileset
	_generate_floor()


func _draw_floor_tile(image: Image) -> void:
	var wood = Color(0.45, 0.30, 0.18)
	var wood_dark = Color(0.38, 0.24, 0.12)

	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			# Wood plank pattern
			var plank = (x / 8) % 2
			var grain = (y + x / 4) % 4 == 0
			var c = wood_dark if plank == 0 or grain else wood
			image.set_pixel(x, y, c)


func _draw_wall_tile(image: Image) -> void:
	var brick = Color(0.55, 0.35, 0.25)
	var brick_dark = Color(0.42, 0.26, 0.16)
	var mortar = Color(0.65, 0.55, 0.45)

	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var row = y / 8
			var offset = 8 if row % 2 == 0 else 0
			var in_mortar_h = y % 8 == 0
			var in_mortar_v = (x + offset) % 16 == 0

			if in_mortar_h or in_mortar_v:
				image.set_pixel(x, y, mortar)
			else:
				var c = brick if (x + y) % 7 != 0 else brick_dark
				image.set_pixel(x, y, c)


func _generate_floor() -> void:
	for y in range(MAP_HEIGHT):
		for x in range(MAP_WIDTH):
			var char = TAVERN_LAYOUT[y][x]
			match char:
				"W":
					tilemap.set_cell(Vector2i(x, y), 1, Vector2i(0, 0))
				_:
					tilemap.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))


func _setup_decorations() -> void:
	decorations = Node2D.new()
	decorations.name = "Decorations"
	add_child(decorations)

	# Bar counter
	_create_bar_counter()

	# Stage
	_create_stage()

	# Tables
	_create_tables()

	# Ambient lighting (warm tavern glow)
	var light = PointLight2D.new()
	light.position = Vector2(8 * TILE_SIZE, 5 * TILE_SIZE)
	light.color = Color(1.0, 0.9, 0.7, 0.3)
	light.energy = 0.5
	light.texture = _create_light_texture()
	decorations.add_child(light)


func _create_light_texture() -> ImageTexture:
	var size = 256
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center = size / 2

	for y in range(size):
		for x in range(size):
			var dist = Vector2(x - center, y - center).length()
			var alpha = clampf(1.0 - (dist / center), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, alpha * alpha))

	return ImageTexture.create_from_image(img)


func _create_bar_counter() -> void:
	var counter = Node2D.new()
	counter.name = "BarCounter"

	# Draw bar counter sprite
	var sprite = Sprite2D.new()
	var img = Image.create(TILE_SIZE * 3, TILE_SIZE * 3, false, Image.FORMAT_RGBA8)

	var wood = Color(0.35, 0.22, 0.12)
	var wood_top = Color(0.55, 0.38, 0.22)

	for y in range(TILE_SIZE * 3):
		for x in range(TILE_SIZE * 3):
			if y < 8:
				img.set_pixel(x, y, wood_top)  # Counter top
			else:
				var panel = (x / 16) % 2
				var c = wood if panel == 0 else Color(0.30, 0.18, 0.10)
				img.set_pixel(x, y, c)

	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(2.5 * TILE_SIZE, 3.5 * TILE_SIZE)
	counter.add_child(sprite)

	# Bottles on shelf
	_add_bottles(counter)

	decorations.add_child(counter)


func _add_bottles(parent: Node2D) -> void:
	var bottles = Sprite2D.new()
	var img = Image.create(TILE_SIZE * 2, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	var colors = [
		Color(0.8, 0.3, 0.3),  # Red wine
		Color(0.9, 0.8, 0.4),  # Mead
		Color(0.4, 0.6, 0.3),  # Absinthe
		Color(0.6, 0.4, 0.2),  # Whiskey
	]

	for i in range(4):
		var bx = 8 + i * 14
		for y in range(8, 28):
			for x in range(bx, bx + 8):
				if x < TILE_SIZE * 2:
					img.set_pixel(x, y, colors[i])
		# Bottle neck
		for y in range(4, 8):
			for x in range(bx + 2, bx + 6):
				if x < TILE_SIZE * 2:
					img.set_pixel(x, y, colors[i].darkened(0.2))

	bottles.texture = ImageTexture.create_from_image(img)
	bottles.position = Vector2(2 * TILE_SIZE, 1.5 * TILE_SIZE)
	parent.add_child(bottles)


func _create_stage() -> void:
	var stage = Node2D.new()
	stage.name = "Stage"

	var sprite = Sprite2D.new()
	var img = Image.create(TILE_SIZE * 5, TILE_SIZE * 3, false, Image.FORMAT_RGBA8)

	var stage_wood = Color(0.5, 0.35, 0.2)
	var stage_light = Color(0.6, 0.45, 0.28)
	var curtain = Color(0.7, 0.15, 0.2)
	var curtain_dark = Color(0.5, 0.1, 0.15)

	for y in range(TILE_SIZE * 3):
		for x in range(TILE_SIZE * 5):
			if y < TILE_SIZE:
				# Curtain backdrop
				var fold = (x / 12) % 2
				var c = curtain if fold == 0 else curtain_dark
				img.set_pixel(x, y, c)
			else:
				# Stage floor (raised platform)
				var plank = (x / 10) % 2
				var c = stage_wood if plank == 0 else stage_light
				img.set_pixel(x, y, c)

	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(12.5 * TILE_SIZE, 3.5 * TILE_SIZE)
	stage.add_child(sprite)

	decorations.add_child(stage)


func _create_tables() -> void:
	var table_positions = [
		Vector2(3, 6.5), Vector2(3, 9.5),
		Vector2(9, 6.5), Vector2(9, 9.5)
	]

	for pos in table_positions:
		var table = Sprite2D.new()
		var img = Image.create(TILE_SIZE * 2, TILE_SIZE * 2, false, Image.FORMAT_RGBA8)

		var wood = Color(0.45, 0.28, 0.15)
		var wood_dark = Color(0.35, 0.20, 0.10)

		# Table top
		for y in range(8, 24):
			for x in range(8, 56):
				var c = wood if (x + y) % 5 != 0 else wood_dark
				img.set_pixel(x, y, c)

		# Mugs on table
		for mug_x in [16, 40]:
			for y in range(12, 22):
				for x in range(mug_x, mug_x + 8):
					img.set_pixel(x, y, Color(0.6, 0.5, 0.3))

		table.texture = ImageTexture.create_from_image(img)
		table.position = pos * TILE_SIZE
		decorations.add_child(table)


func _setup_dancer() -> void:
	dancer_sprite = Sprite2D.new()
	dancer_sprite.name = "DancingGirl"
	dancer_sprite.position = Vector2(12.5 * TILE_SIZE, 3.5 * TILE_SIZE)
	dancer_sprite.z_index = 10
	add_child(dancer_sprite)

	_generate_dancer_sprites()


func _generate_dancer_sprites() -> void:
	_dancer_frames.clear()

	for frame in range(4):
		var image = Image.create(32, 48, false, Image.FORMAT_RGBA8)
		_draw_dancer(image, frame)
		var texture = ImageTexture.create_from_image(image)
		_dancer_frames.append(texture)

	if _dancer_frames.size() > 0:
		dancer_sprite.texture = _dancer_frames[0]


func _draw_dancer(image: Image, frame: int) -> void:
	image.fill(Color.TRANSPARENT)

	var skin = Color(0.95, 0.80, 0.70)
	var hair = Color(0.85, 0.65, 0.25)  # Blonde
	var dress = Color(0.85, 0.25, 0.35)  # Red dress
	var dress_light = Color(0.95, 0.45, 0.55)
	var dress_sparkle = Color(1.0, 0.9, 0.5)  # Gold sparkles

	# Animation offsets - more dramatic for larger sprite
	var arm_angle = sin(frame * PI / 2) * 6
	var leg_angle = cos(frame * PI / 2) * 4
	var body_sway = sin(frame * PI / 2) * 3
	var hair_flow = sin(frame * PI / 2 + 0.5) * 4

	var cx = 16 + int(body_sway)

	# Head
	for y in range(4, 14):
		for x in range(cx - 5, cx + 5):
			if x >= 0 and x < 32:
				image.set_pixel(x, y, skin)

	# Hair (flowing dramatically)
	for y in range(0, 12):
		for x in range(cx - 6, cx + 6):
			if x >= 0 and x < 32 and y < 10:
				image.set_pixel(x, y, hair)

	# Side hair waves (longer, more dramatic)
	for y in range(6, 22):
		var hx = cx + 6 + int(hair_flow)
		if hx >= 0 and hx < 32:
			image.set_pixel(hx, y, hair)
		hx = cx - 7 - int(hair_flow)
		if hx >= 0 and hx < 32:
			image.set_pixel(hx, y, hair)

	# Dress body (larger, more flowing)
	for y in range(14, 40):
		var dress_width = 6 if y < 24 else 8 + (y - 24) / 3
		for x in range(cx - dress_width, cx + dress_width):
			if x >= 0 and x < 32:
				var c = dress if (x + y) % 3 != 0 else dress_light
				# Add sparkles
				if (x + y + frame * 5) % 11 == 0:
					c = dress_sparkle
				image.set_pixel(x, y, c)

	# Arms (gracefully raised)
	var left_arm_x = cx - 8 + int(arm_angle)
	var right_arm_x = cx + 7 - int(arm_angle)
	for y in range(16, 26):
		if left_arm_x >= 0 and left_arm_x < 32:
			image.set_pixel(left_arm_x, y, skin)
			if left_arm_x + 1 < 32:
				image.set_pixel(left_arm_x + 1, y, skin)
		if right_arm_x >= 0 and right_arm_x < 32:
			image.set_pixel(right_arm_x, y, skin)
			if right_arm_x - 1 >= 0:
				image.set_pixel(right_arm_x - 1, y, skin)

	# Legs (elegant dance pose)
	var left_leg_x = cx - 4 + int(leg_angle)
	var right_leg_x = cx + 3 - int(leg_angle)
	for y in range(40, 48):
		if left_leg_x >= 0 and left_leg_x < 32:
			image.set_pixel(left_leg_x, y, skin)
		if right_leg_x >= 0 and right_leg_x < 32:
			image.set_pixel(right_leg_x, y, skin)


func _animate_dancer(delta: float) -> void:
	_anim_timer += delta
	if _anim_timer >= ANIM_SPEED:
		_anim_timer -= ANIM_SPEED
		_anim_frame = (_anim_frame + 1) % _dancer_frames.size()
		if dancer_sprite and _dancer_frames.size() > 0:
			dancer_sprite.texture = _dancer_frames[_anim_frame]


func _setup_npcs() -> void:
	npcs = Node2D.new()
	npcs.name = "NPCs"
	add_child(npcs)

	# Bartender
	_create_npc("Grog", "bartender", Vector2(2.5, 3), [
		"Grog: Welcome to The Dancing Tonberry!",
		"Grog: What'll it be? Mead? Ale? Liquid courage?",
		"Grog: *polishes glass* Heard the cave's been... hungry lately.",
		"Grog: Some say the monsters are learning. Adapting.",
		"Grog: If you're smart, you'll automate. The cave respects efficiency.",
		"Grog: But push too hard... and it pushes back. *chuckles darkly*"
	])

	# Dancing girl (interactive, next to stage)
	_create_npc("Aria", "dancer", Vector2(11, 5), [
		"Aria: *graceful curtsy* Welcome, hero~",
		"Aria: I dance to lift spirits... and to forget.",
		"Aria: My brother went into the cave. He was a 'Scriptweaver.'",
		"Aria: He said he'd found a way to rewrite the rules...",
		"Aria: *twirls* But rules have a way of rewriting you.",
		"Aria: Be careful what you automate. Some things fight back.",
		"Aria: *wink* Come back alive, okay? I'll save you a dance~"
	])

	# Regular at bar
	_create_npc("Old Mack", "villager", Vector2(4, 4), [
		"Old Mack: *slurring* Hic... another one bites the cave...",
		"Old Mack: You know what's funny? I was an adventurer once.",
		"Old Mack: Spent WEEKS grinding those rats. Weeks!",
		"Old Mack: Then some kid shows up with a script...",
		"Old Mack: ...clears the place in an afternoon. AN AFTERNOON!",
		"Old Mack: *finishes drink* Progress, they call it. I call it cheating.",
		"Old Mack: But what do I know? I'm just a 'tutorial NPC' now."
	])

	# Mysterious patron in corner
	_create_npc("???", "mysterious", Vector2(13, 9), [
		"???: ...",
		"???: You can see me?",
		"???: Most walk right past. Too busy grinding.",
		"???: I've been watching this loop for... how long now?",
		"???: The cave. The village. The battles. The saves.",
		"???: Did you know there's a class that can SEE the code?",
		"???: The Scriptweaver. They say one went mad reading the source.",
		"???: Found comments in the margins. Developer notes.",
		"???: 'TODO: Add meaning to NPC lives' *laughs bitterly*",
		"???: We're all just waiting for someone to write us a purpose."
	])

	# Drunk adventurer at table
	_create_npc("Sir Reginald", "knight", Vector2(3, 7), [
		"Sir Reginald: *hiccup* Brave Sir Reginald, they called me!",
		"Sir Reginald: I once MANUALLY fought every battle. Every. One.",
		"Sir Reginald: No scripts! No automation! Pure skill!",
		"Sir Reginald: Took me three months to reach floor 3.",
		"Sir Reginald: Then the Rat King... *shudders*",
		"Sir Reginald: He said something before attacking...",
		"Sir Reginald: 'Your persistence is admirable. But I've EVOLVED.'",
		"Sir Reginald: *stares into mug* The cave learns, friend. It learns."
	])

	# Gossipping villagers at table
	_create_npc("Martha", "villager", Vector2(9, 7), [
		"Martha: Did you hear about the Time Mage?",
		"Martha: They say he can UNDO death itself!",
		"Martha: Rewinding saves, erasing mistakes...",
		"Martha: But there's a cost. There's always a cost.",
		"Martha: Every rewind leaves a scar on the timeline.",
		"Martha: Too many, and reality starts to... glitch.",
		"Martha: *whispers* I've seen adventurers flicker.",
		"Martha: Here one moment, gone the next. Like they never existed."
	])

	# Bard in corner
	_create_npc("Melody", "bard", Vector2(14, 6), [
		"Melody: *strumming lute* Care for a song, traveler?",
		"Melody: I compose ballads of brave autobattlers~",
		"Melody: 'The Hero Who Slept Through Victory'...",
		"Melody: 'A Thousand Rats, One Script'...",
		"Melody: 'The Recursion of Summoner Steve'...",
		"Melody: That last one goes forever. Literally.",
		"Melody: *laughs* He summoned himself summoning himself!",
		"Melody: They say he's still casting somewhere in memory."
	])


func _create_npc(npc_name: String, npc_type: String, grid_pos: Vector2, dialogue: Array) -> void:
	var OverworldNPCScript = load("res://src/exploration/OverworldNPC.gd")
	if OverworldNPCScript:
		var npc = OverworldNPCScript.new()
		npc.npc_name = npc_name
		npc.npc_type = npc_type
		npc.dialogue_lines = dialogue
		npc.position = grid_pos * TILE_SIZE
		npcs.add_child(npc)
	else:
		# Fallback: create simple NPC marker
		var marker = _create_simple_npc(npc_name, npc_type, grid_pos)
		npcs.add_child(marker)


func _create_simple_npc(npc_name: String, npc_type: String, grid_pos: Vector2) -> Node2D:
	var npc = Area2D.new()
	npc.position = grid_pos * TILE_SIZE

	# Simple colored square
	var sprite = Sprite2D.new()
	var img = Image.create(24, 32, false, Image.FORMAT_RGBA8)

	var color = Color(0.5, 0.5, 0.5)
	match npc_type:
		"bartender": color = Color(0.5, 0.35, 0.2)
		"dancer": color = Color(0.9, 0.4, 0.5)
		"knight": color = Color(0.6, 0.6, 0.7)
		"mysterious": color = Color(0.3, 0.2, 0.4)
		"bard": color = Color(0.7, 0.6, 0.3)

	for y in range(32):
		for x in range(24):
			img.set_pixel(x, y, color)

	sprite.texture = ImageTexture.create_from_image(img)
	npc.add_child(sprite)

	# Name label
	var label = Label.new()
	label.text = npc_name
	label.position = Vector2(-20, -40)
	label.add_theme_font_size_override("font_size", 10)
	npc.add_child(label)

	return npc


func _setup_transitions() -> void:
	transitions = Node2D.new()
	transitions.name = "Transitions"
	add_child(transitions)

	# Exit door
	var AreaTransitionScript = load("res://src/exploration/AreaTransition.gd")
	if AreaTransitionScript:
		var exit = AreaTransitionScript.new()
		exit.name = "Exit"
		exit.target_map = "harmonia_village"
		exit.target_spawn = "bar_exit"
		exit.require_interaction = false
		exit.position = Vector2(8 * TILE_SIZE, 11.5 * TILE_SIZE)

		# Setup collision
		var collision = CollisionShape2D.new()
		var shape = RectangleShape2D.new()
		shape.size = Vector2(TILE_SIZE * 3, TILE_SIZE)
		collision.shape = shape
		exit.add_child(collision)

		exit.collision_layer = 4
		exit.collision_mask = 2
		exit.monitoring = true

		exit.transition_triggered.connect(_on_exit_triggered)
		transitions.add_child(exit)


func _on_exit_triggered(target_map: String, target_spawn: String) -> void:
	transition_triggered.emit(target_map, target_spawn)
	area_transition.emit(target_map, target_spawn)


func _setup_player() -> void:
	var PlayerScript = load("res://src/exploration/OverworldPlayer.gd")
	if PlayerScript:
		player = PlayerScript.new()
		player.position = spawn_points["entrance"] * TILE_SIZE
		add_child(player)


func _setup_camera() -> void:
	camera = Camera2D.new()
	camera.name = "Camera2D"
	camera.zoom = Vector2(2.5, 2.5)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0

	# Limit camera to room
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = MAP_WIDTH * TILE_SIZE
	camera.limit_bottom = MAP_HEIGHT * TILE_SIZE

	if player:
		player.add_child(camera)
	else:
		add_child(camera)
		camera.position = Vector2(MAP_WIDTH * TILE_SIZE / 2, MAP_HEIGHT * TILE_SIZE / 2)


func spawn_player_at(spawn_name: String) -> void:
	if spawn_points.has(spawn_name) and player:
		player.position = spawn_points[spawn_name] * TILE_SIZE


func _setup_controller() -> void:
	var ControllerScript = load("res://src/exploration/OverworldController.gd")
	if ControllerScript and player:
		controller = ControllerScript.new()
		controller.player = player
		controller.encounter_enabled = false  # No random battles in tavern
		add_child(controller)
