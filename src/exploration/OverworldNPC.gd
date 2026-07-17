extends Area2D
class_name OverworldNPC

## OverworldNPC - Simple NPC for villages and overworld
## Can be interacted with to show dialogue

signal dialogue_started(npc_name: String)
signal dialogue_ended(npc_name: String)

## NPC properties
@export var npc_name: String = "Villager"
@export var npc_type: String = "villager"  # villager, elder, shopkeeper, guard
@export var dialogue_lines: Array = ["Hello, traveler!"]
@export var facing_direction: int = 0  # 0=down, 1=up, 2=left, 3=right
## Quest-system identity; "" derives snake_case from npc_name ("Phil the Lost" → phil_the_lost).
@export var npc_id: String = ""

## Quest "!" marker over givers with live quest business
const QUEST_MARKER_BASE_Y: float = -46.0
var _quest_marker: Label = null
var _quest_marker_y: float = QUEST_MARKER_BASE_Y
var _quest_bob_t: float = 0.0
## Sprite archetype override. If empty, auto-derived from npc_type.
## Available: old_man, old_woman, young_man, young_woman, child, guard, merchant, scholar.
@export var sprite_archetype: String = ""

## LLM dynamic dialogue opt-in (per docs/llm-integration-design.md:157).
## Only NPCs with `dynamic = true` AND a non-empty `persona` participate
## in the LLM-driven DynamicConversation path. All other NPCs continue
## using the static dialogue_lines pipeline.
## Default OFF — design doc explicitly says do NOT retrofit every NPC.
## Showcase set is the 3 W1 NPCs flagged in scene/spawn code.
##
## R5 fix (2026-06-14): `dynamic` and `persona` use setters that re-run the
## persona overlay (_setup_persona_data) when assigned AFTER _ready. Before
## this, _setup_persona_data was ONLY called from _ready() gated on `dynamic`
## at that instant — so any code path that flips dynamic=true post-construction
## (a village factory that add_child's BEFORE setting the flag, or a future
## save-restore that re-applies NPC state) silently dropped the persona +
## opening lines. The showcase NPCs (Theron/Milo/Boris) reverted to scene
## defaults on save→load→re-spawn. The setters make BOTH orderings correct
## and idempotent. (CLAUDE.md principle #7 — silent failures > crashes.)
@export var dynamic: bool = false:
	set(value):
		dynamic = value
		# Only re-hydrate once the node has entered the tree (post-_ready).
		# In-_ready ordering is handled by the explicit _setup_persona_data()
		# call in _ready(); guarding on _ready_done prevents a redundant
		# double-load while still covering every post-construction assignment.
		if _ready_done and dynamic:
			_setup_persona_data()
@export_multiline var persona: String = "":
	set(value):
		persona = value
		# A non-empty persona implies the NPC is meant to be dynamic-capable;
		# re-running setup after _ready captures fallback/opening overlays even
		# if persona is assigned on its own (e.g. inline designer override that
		# lands after the node is already in the tree).
		if _ready_done and dynamic:
			_setup_persona_data()

## Mapping from npc_type → preferred archetype. "" = picked by name hash
## from a pair (defined in _resolve_archetype). All 20 archetype sheets
## are now available: old_man, old_woman, young_man, young_woman, child,
## guard, merchant, scholar, blacksmith, farmer, fisherman, innkeeper,
## king, monk, noble, noblewoman, priestess, queen, soldier, traveler.
const NPC_TYPE_TO_ARCHETYPE: Dictionary = {
	"elder": "",        # picked by name hash → old_man / old_woman
	"villager": "",     # picked by name hash → young_man / young_woman
	"noble_pair": "",   # picked by name hash → noble / noblewoman
	"shopkeeper": "merchant",
	"guard": "guard",
	"scholar": "scholar",
	"child": "child",
	"blacksmith": "blacksmith",
	"farmer": "farmer",
	"fisherman": "fisherman",
	"innkeeper": "innkeeper",
	"king": "king",
	"queen": "queen",
	"monk": "monk",
	"priestess": "priestess",
	"soldier": "soldier",
	"traveler": "traveler",
	"noble": "noble",
	"noblewoman": "noblewoman",
	# ShopInterior + tavern + role-specific customer types — map onto
	# existing archetype sheets so they stop falling to the generic
	# villager procedural render (playtest 2026-07-15: cowir-main msg 2551,
	# "tall red humanoid" was herbalist/pilgrim/apprentice sharing the
	# proc-gen chibi shape).
	"herbalist": "priestess",     # robed, gentle, gathers-things silhouette
	"hooded_mage": "scholar",     # hooded scholarly figure (deep-navy scholar reads as arcane)
	"nervous": "young_woman",     # generic customer, gendered by name-hash if empty preferred
	"pilgrim": "monk",            # hooded traveling holy figure
	"apprentice": "young_man",    # blacksmith journeyman, plain workwear
	"knight": "soldier",          # armored infantry — closest existing sheet
	"mysterious": "traveler",     # hooded stranger — traveler sheet has the cloak silhouette
	"bartender": "innkeeper",     # apron behind counter, same silhouette family
	"maid": "young_woman",        # apron-and-dress silhouette
	"adventurer": "traveler",     # cloaked wanderer
	"bard": "traveler",           # NPC bards in cutscenes — cloak+lute reads as traveler
	"rogue": "traveler",          # NPC rogues — hooded generic
	"scholarly": "scholar",       # alias (a few files use "scholarly" instead of "scholar")
	# "dancer" stays procedural — it has its own animation system
}

## Visual
var sprite: Sprite2D
var name_label: Label
# Legacy local dialogue UI (kept as fallback only — production path uses
# NPCDialogue/CutsceneDialogue, which is CanvasLayer-anchored and avoids
# the screen-edge cut-off bug the old Node2D-relative panel caused).
# (User feedback 2026-05-20: "dialogue boxes get cut off near edges of
# the screen in the village".)
var dialogue_box: Control
var dialogue_label: Label
var _npc_dialogue: Node = null  # NPCDialogue instance, lazy-init
var _dynamic_conv: DynamicConversation = null  # LLM-driven conversation, lazy-init
## Wave F R3 fix — authored opening lines from npc_showcase_personas.json,
## passed to DynamicConversation.setup() so the LLM-off path uses richer
## per-character voice for the opening turn (the rest of the conversation
## continues to draw from `dialogue_lines`).
var _persona_openings: Array = []
## Milo v2 (msg 2600): quest-state bucketed idle lines, populated from
## npc_showcase_personas.json's optional quest_state_lines block. Buckets
## are keyed pre_task_1 / in_progress / post_quest (matching the 3-state
## quest lifecycle). Empty when the persona has no quest_state_lines.
var _persona_quest_state_lines: Dictionary = {}
## Weight-boost pointer per bucket — first visit to a fresh bucket shows
## this line. Defaults to 0 when the JSON omits the *_money_pick_index sibling.
var _persona_quest_state_money_picks: Dictionary = {}
## Per-bucket visit counter so rotation restarts from money-pick when the
## quest transitions to a new state (avoids "landed on line 3 of the new
## bucket because the global visit counter was there").
var _quest_state_bucket_visits: Dictionary = {}

## State
var _current_line: int = 0
var _is_talking: bool = false
var _player_nearby: bool = false
## Rotates the starting index of dialogue_lines on each interaction so
## the player doesn't hear the same opener every time they re-talk to
## a static NPC. Preserves relative order (still cycles through the
## scripted set) — just shifts the entry point.
var _dialogue_visit_count: int = 0
## True once _ready() has finished. Gates the dynamic/persona setters so they
## only trigger a re-hydrate for POST-construction assignments (the in-_ready
## path is handled by the explicit _setup_persona_data() call). R5 fix.
var _ready_done: bool = false

## Animation
var _is_dancing: bool = false
var _dance_frame: int = 0
var _dance_timer: float = 0.0
const DANCE_SPEED: float = 0.2  # Seconds per frame
const DANCE_FRAMES: int = 4
var _sprite_cache: Dictionary = {}  # frame -> texture

const TILE_SIZE: int = 32

## Persona JSON cache — parsed once per process, shared across all NPC
## instances. Per CLAUDE.md/plan-risk-4: file read at _ready() per NPC
## would be wasteful; this static dictionary makes it free after the first
## opt-in NPC spawns. Map: npc_name → { persona, openings[], fallbacks[] }.
const PERSONA_DATA_PATH: String = "res://data/cutscenes/npc_showcase_personas.json"
static var _persona_cache: Dictionary = {}
static var _persona_cache_loaded: bool = false


func _ready() -> void:
	# Wave D: hydrate persona & fallback lines from data/cutscenes/
	# npc_showcase_personas.json for dynamic-opt-in showcase NPCs (design
	# doc :157). Must run BEFORE sprite generation so the resolved persona
	# is visible to any other _ready-time consumer; ordering chosen to
	# match the existing static dialogue_lines workflow.
	if dynamic:
		_setup_persona_data()

	_generate_sprite()
	_setup_collision()
	_setup_name_label()
	_setup_quest_marker()
	_setup_dialogue_box()

	# Pre-generate animation frames for dancer
	if npc_type == "dancer":
		_generate_dance_frames()

	# Add to interactables group for reliable interaction detection
	add_to_group("interactables")

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Mark ready LAST so the dynamic/persona setters now re-hydrate on any
	# post-construction assignment (save-restore re-spawn, late factory flag).
	# R5 fix — see the @export blocks above.
	_ready_done = true


## Public: force a re-hydrate of persona/opening/fallback overlay from
## npc_showcase_personas.json. Safe to call any time after construction;
## no-ops if this NPC isn't dynamic. Idempotent. Provided so a village/
## save-restore path can deterministically re-apply the overlay after
## flipping `dynamic`/`persona` (rather than relying on setter side effects).
func refresh_persona() -> void:
	if dynamic:
		_setup_persona_data()


## Load and apply persona + fallback dialogue for showcase NPCs.
## Called from _ready() ONLY when @export dynamic is true. The persona
## text is resolved by `npc_name` lookup; if the name isn't in the JSON
## the NPC silently falls through to whatever `persona` / `dialogue_lines`
## were already set on the scene node (so a designer can author one
## inline without breaking the JSON-driven path for the rest).
func _setup_persona_data() -> void:
	if not _persona_cache_loaded:
		_load_persona_cache()
	if not _persona_cache.has(npc_name):
		return  # No JSON entry — keep whatever the scene set inline.
	var entry: Dictionary = _persona_cache[npc_name]
	# Persona takes precedence from JSON unless the scene already set
	# a non-empty one (allowing per-instance overrides for testing).
	if persona == "" and entry.has("persona"):
		persona = str(entry["persona"])
	# Fallback dialogue lines: replace the scene's static list with the
	# JSON-authored set. These are also what DynamicConversation hands
	# to LLMService as the deterministic fallback when the null backend
	# is in use (web build / LLM disabled), so they need to read as
	# in-character first-line dialogue, not stage directions.
	if entry.has("fallbacks"):
		var fb_raw: Variant = entry["fallbacks"]
		if fb_raw is Array:
			var typed_lines: Array = []
			for line in (fb_raw as Array):
				typed_lines.append(str(line))
			if typed_lines.size() > 0:
				dialogue_lines = typed_lines
	# Wave F R3 fix — capture authored openings; passed to DynamicConversation
	# via setup() so the LLM-off opening turn uses richer per-character voice.
	if entry.has("openings"):
		var op_raw: Variant = entry["openings"]
		if op_raw is Array:
			var typed_openings: Array = []
			for line in (op_raw as Array):
				typed_openings.append(str(line))
			_persona_openings = typed_openings
	# Milo v2: capture optional quest_state_lines block (buckets + money-pick indices).
	if entry.has("quest_state_lines"):
		var qsl_raw: Variant = entry["quest_state_lines"]
		if qsl_raw is Dictionary:
			for k in (qsl_raw as Dictionary).keys():
				var key_str: String = str(k)
				if key_str.begins_with("_"):
					continue
				var v: Variant = (qsl_raw as Dictionary)[k]
				if v is Array:
					var typed_bucket: Array = []
					for line in (v as Array):
						typed_bucket.append(str(line))
					_persona_quest_state_lines[key_str] = typed_bucket
				elif (v is int or v is float) and key_str.ends_with("_money_pick_index"):
					var bucket_name: String = key_str.substr(0, key_str.length() - "_money_pick_index".length())
					_persona_quest_state_money_picks[bucket_name] = int(v)


static func _load_persona_cache() -> void:
	# Tick 282: split parse-error and non-Dict-root paths so devs can
	# tell apart "JSON is malformed" from "JSON parses but root isn't
	# a Dictionary" (matches the canonical loud-fail pattern from
	# tick 274/275/276). Pre-fix both fell under one generic warning.
	_persona_cache_loaded = true  # Set first so a malformed file doesn't retry every NPC.
	if not FileAccess.file_exists(PERSONA_DATA_PATH):
		push_warning("[OverworldNPC] persona data missing at %s — dynamic NPC dialogue scoped-personas will be empty" % PERSONA_DATA_PATH)
		return
	var f := FileAccess.open(PERSONA_DATA_PATH, FileAccess.READ)
	if f == null:
		push_warning("[OverworldNPC] %s exists but FileAccess.open failed — persona cache empty" % PERSONA_DATA_PATH)
		return
	var text: String = f.get_as_text()
	f.close()
	var json := JSON.new()
	var parse_result := json.parse(text)
	if parse_result != OK:
		push_warning("[OverworldNPC] %s parse error: %s — persona cache empty" % [PERSONA_DATA_PATH, json.get_error_message()])
		return
	if not (json.data is Dictionary):
		push_warning("[OverworldNPC] %s parsed but root is not a Dictionary — persona cache empty" % PERSONA_DATA_PATH)
		return
	# Only keep keys that look like NPC entries (have a "persona" subkey).
	for key in (json.data as Dictionary).keys():
		var v: Variant = (json.data as Dictionary)[key]
		if v is Dictionary and (v as Dictionary).has("persona"):
			_persona_cache[str(key)] = v


func _process(delta: float) -> void:
	if _is_dancing and npc_type == "dancer":
		_dance_timer += delta
		if _dance_timer >= DANCE_SPEED:
			_dance_timer -= DANCE_SPEED
			_dance_frame = (_dance_frame + 1) % DANCE_FRAMES
			_update_dance_sprite()
	if _quest_marker != null and _quest_marker.visible:
		_quest_bob_t += delta * 3.0
		_quest_marker.position.y = _quest_marker_y + sin(_quest_bob_t) * 3.0


## Returns the sprite scale for our current scene context — same logic as
## WanderingNPC._get_context_scale. Open overworlds need 3x for Mode 7
## visibility; villages/dungeons use 1x to match the rest of the room.
## (User feedback 2026-05-03: 653eae1 brought all NPCs down to 1x to fix
## an in-village size bug, but that broke the open-overworld visibility.)
func _get_context_scale() -> Vector2:
	var p = get_parent()
	if p:
		var pname = p.name.to_lower()
		if "overworld" in pname:
			return Vector2(3.0, 3.0)
		# Walk up one extra level — some overworlds parent NPCs to a
		# dedicated `NPCs` Node2D below the scene root.
		var gp = p.get_parent()
		if gp and "overworld" in gp.name.to_lower():
			return Vector2(3.0, 3.0)
	return Vector2.ONE


func _generate_sprite() -> void:
	sprite = Sprite2D.new()
	sprite.name = "Sprite"
	sprite.centered = true
	sprite.scale = _get_context_scale()
	add_child(sprite)

	# Try archetype sheet first (artist-style 4-row × 4-col 32x32 grid).
	# Falls back to procedural drawing if no archetype matches.
	var archetype = _resolve_archetype()
	if archetype != "" and _try_load_archetype_sprite(archetype):
		return

	var image = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	_draw_npc(image)
	sprite.texture = ImageTexture.create_from_image(image)


## Resolve which archetype this NPC should use, falling back to "" if procedural.
func _resolve_archetype() -> String:
	# Explicit override wins.
	if sprite_archetype != "":
		return sprite_archetype
	# npc_type → archetype mapping (some types defer to name-hash variants).
	if npc_type in NPC_TYPE_TO_ARCHETYPE:
		var mapped = NPC_TYPE_TO_ARCHETYPE[npc_type]
		if mapped != "":
			return mapped
		# Hash-pair fallbacks for gendered villager/elder/noble.
		var pair: Array = ["young_man", "young_woman"]
		if npc_type == "elder":
			pair = ["old_man", "old_woman"]
		elif npc_type == "noble_pair":
			pair = ["noble", "noblewoman"]
		return pair[hash(npc_name) % 2]
	return ""


## Load the archetype overworld sheet and slice the (facing_direction, frame 0)
## frame as a static portrait. Returns true on success, false on missing/bad asset.
func _try_load_archetype_sprite(archetype: String) -> bool:
	var path = "res://assets/sprites/npcs/%s/overworld.png" % archetype
	if not ResourceLoader.exists(path):
		return false
	var tex = load(path) as Texture2D
	if not tex:
		return false
	var img = tex.get_image()
	if not img or img.get_width() < 128 or img.get_height() < 128:
		return false
	# 4×4 grid, 32x32 frames. Row mapping: 0=down, 1=left, 2=right, 3=up.
	# OverworldNPC.facing_direction uses: 0=down, 1=up, 2=left, 3=right.
	# Translate.
	var sheet_row := 0
	match facing_direction:
		0: sheet_row = 0  # down
		1: sheet_row = 3  # up
		2: sheet_row = 1  # left
		3: sheet_row = 2  # right
	var frame_w := 32
	var frame_h := 32
	var col := 0  # frame 0 (idle pose) for static NPCs
	var region = Rect2i(col * frame_w, sheet_row * frame_h, frame_w, frame_h)
	var frame_img = img.get_region(region)
	sprite.texture = ImageTexture.create_from_image(frame_img)
	# Note: scale is set in _generate_sprite() via _get_context_scale()
	# (3x for open overworld / Mode 7, 1x for village/dungeon).
	# Don't override here — would clobber the context-aware scale.
	return true


func _safe_pixel(image: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and x < TILE_SIZE and y >= 0 and y < TILE_SIZE:
		image.set_pixel(x, y, color)


func _draw_npc(image: Image) -> void:
	# SNES-quality NPC with proper shading and detail
	var skin_color = Color(0.95, 0.80, 0.65)
	var skin_dark = Color(0.78, 0.62, 0.48)
	var skin_light = Color(1.0, 0.88, 0.75)
	var hair_color = _get_npc_hair_color()
	var hair_dark = hair_color.darkened(0.25)
	var hair_light = hair_color.lightened(0.20)
	var clothes_color = _get_clothes_color()
	var clothes_dark = clothes_color.darkened(0.25)
	var clothes_light = clothes_color.lightened(0.18)
	var outline_color = Color(0.08, 0.08, 0.12)
	var eye_white = Color(0.92, 0.92, 0.95)
	var eye_color = Color(0.15, 0.15, 0.25)
	var boot_color = Color(0.25, 0.18, 0.12)
	var boot_dark = Color(0.18, 0.12, 0.08)

	# Clear
	image.fill(Color.TRANSPARENT)

	# Shadow beneath character
	for x in range(11, 22):
		var shadow_alpha = 0.18 - abs(x - 16) * 0.015
		_safe_pixel(image, x, 30, Color(0, 0, 0, shadow_alpha))
		_safe_pixel(image, x, 31, Color(0, 0, 0, shadow_alpha * 0.5))

	# ---- HEAD (elliptical for SNES look) ----
	var head_cx = 16
	var head_cy = 6
	var head_rx = 5
	var head_ry = 5
	# Outline
	for y in range(-head_ry - 1, head_ry + 2):
		for x in range(-head_rx - 1, head_rx + 2):
			var dist = sqrt(pow(float(x) / (head_rx + 1), 2) + pow(float(y) / (head_ry + 1), 2))
			if dist >= 0.85 and dist < 1.0:
				_safe_pixel(image, head_cx + x, head_cy + y, outline_color)
	# Fill with shading
	for y in range(-head_ry, head_ry + 1):
		for x in range(-head_rx, head_rx + 1):
			var dist = sqrt(pow(float(x) / head_rx, 2) + pow(float(y) / head_ry, 2))
			if dist < 1.0:
				var c = skin_color
				if y < -head_ry * 0.3:
					c = skin_light
				elif x > head_rx * 0.4:
					c = skin_dark
				elif y > head_ry * 0.3:
					c = skin_dark
				_safe_pixel(image, head_cx + x, head_cy + y, c)

	# ---- HAIR ----
	for y in range(head_cy - head_ry - 1, head_cy - 1):
		for x in range(head_cx - head_rx, head_cx + head_rx + 1):
			var dist = sqrt(pow(float(x - head_cx) / (head_rx + 1), 2) + pow(float(y - head_cy + head_ry) / (head_ry * 0.5), 2))
			if dist < 1.2:
				var c = hair_color
				if y < head_cy - head_ry:
					c = hair_light
				elif x > head_cx + 2:
					c = hair_dark
				_safe_pixel(image, x, y, c)
	# Hair shine
	_safe_pixel(image, head_cx - 2, head_cy - head_ry, hair_light)
	_safe_pixel(image, head_cx - 1, head_cy - head_ry, hair_light)

	# ---- EYES with detail ----
	# Eye whites
	_safe_pixel(image, 13, 6, eye_white)
	_safe_pixel(image, 14, 6, eye_white)
	_safe_pixel(image, 18, 6, eye_white)
	_safe_pixel(image, 19, 6, eye_white)
	# Pupils
	_safe_pixel(image, 14, 6, eye_color)
	_safe_pixel(image, 18, 6, eye_color)
	# Catchlights
	_safe_pixel(image, 13, 5, Color(1, 1, 1, 0.7))
	_safe_pixel(image, 17, 5, Color(1, 1, 1, 0.7))
	# Eyebrows
	_safe_pixel(image, 13, 4, hair_dark)
	_safe_pixel(image, 14, 4, hair_dark)
	_safe_pixel(image, 18, 4, hair_dark)
	_safe_pixel(image, 19, 4, hair_dark)
	# Mouth
	_safe_pixel(image, 15, 9, Color(0.65, 0.40, 0.38))
	_safe_pixel(image, 16, 9, Color(0.65, 0.40, 0.38))
	_safe_pixel(image, 17, 9, Color(0.55, 0.32, 0.32))

	# ---- NECK ----
	_safe_pixel(image, 15, 11, skin_color)
	_safe_pixel(image, 16, 11, skin_color)
	_safe_pixel(image, 17, 11, skin_dark)

	# ---- BODY with 3-tone shading ----
	for y in range(12, 24):
		var body_half = 5 if y < 15 else 4
		for x in range(head_cx - body_half, head_cx + body_half + 1):
			var c = clothes_color
			if x < head_cx - body_half + 2:
				c = clothes_dark
			elif x > head_cx + body_half - 2:
				c = clothes_light
			# Collar detail
			if y == 12 and abs(x - head_cx) < 3:
				c = clothes_light
			_safe_pixel(image, x, y, c)
		# Outline edges
		_safe_pixel(image, head_cx - body_half - 1, y, outline_color)
		_safe_pixel(image, head_cx + body_half + 1, y, outline_color)

	# Belt/sash detail
	for x in range(11, 22):
		_safe_pixel(image, x, 20, clothes_dark)

	# ---- ARMS with shading ----
	for y in range(13, 21):
		# Left arm
		_safe_pixel(image, 9, y, clothes_dark)
		_safe_pixel(image, 10, y, clothes_color)
		# Right arm
		_safe_pixel(image, 22, y, clothes_color)
		_safe_pixel(image, 23, y, clothes_light)
	# Hands
	_safe_pixel(image, 9, 21, skin_color)
	_safe_pixel(image, 10, 21, skin_color)
	_safe_pixel(image, 22, 21, skin_color)
	_safe_pixel(image, 23, 21, skin_dark)

	# ---- LEGS with proper shading ----
	for y in range(24, 29):
		# Left leg
		_safe_pixel(image, 13, y, clothes_dark)
		_safe_pixel(image, 14, y, clothes_color)
		_safe_pixel(image, 15, y, clothes_color)
		# Right leg
		_safe_pixel(image, 17, y, clothes_color)
		_safe_pixel(image, 18, y, clothes_color)
		_safe_pixel(image, 19, y, clothes_light)

	# ---- BOOTS with highlight ----
	for x in range(12, 16):
		_safe_pixel(image, x, 29, boot_color)
		_safe_pixel(image, x, 30, boot_dark)
	for x in range(17, 21):
		_safe_pixel(image, x, 29, boot_color)
		_safe_pixel(image, x, 30, boot_dark)
	# Boot highlights
	_safe_pixel(image, 12, 29, boot_color.lightened(0.15))
	_safe_pixel(image, 17, 29, boot_color.lightened(0.15))

	# ---- NPC TYPE ACCESSORIES ----
	_draw_npc_accessory(image, head_cx, head_cy, clothes_color, clothes_dark, clothes_light)


func _draw_npc_accessory(image: Image, cx: int, cy: int, clothes: Color, clothes_dark: Color, clothes_light: Color) -> void:
	"""Draw type-specific accessories for NPC distinction"""
	match npc_type:
		"elder":
			# Long white beard
			for y in range(9, 16):
				var w = 3 - (y - 9) / 3
				for dx in range(-w, w + 1):
					_safe_pixel(image, cx + dx, y, Color(0.85, 0.85, 0.90))
			# Walking staff
			for y in range(8, 29):
				_safe_pixel(image, 24, y, Color(0.45, 0.30, 0.18))
			_safe_pixel(image, 24, 7, Color(0.6, 0.5, 0.3))
		"shopkeeper":
			# Apron highlight
			for y in range(16, 23):
				_safe_pixel(image, cx - 2, y, clothes_light)
				_safe_pixel(image, cx + 2, y, clothes_light)
		"guard":
			# Helmet/visor
			for x in range(cx - 5, cx + 6):
				_safe_pixel(image, x, 1, Color(0.55, 0.55, 0.65))
				_safe_pixel(image, x, 2, Color(0.45, 0.45, 0.55))
			# Spear
			for y in range(3, 30):
				_safe_pixel(image, 25, y, Color(0.45, 0.40, 0.35))
			_safe_pixel(image, 24, 3, Color(0.6, 0.6, 0.7))
			_safe_pixel(image, 25, 2, Color(0.7, 0.7, 0.8))
			_safe_pixel(image, 26, 3, Color(0.6, 0.6, 0.7))
		"knight":
			# Armor shoulder pads
			for side in [-1, 1]:
				for dy in range(3):
					_safe_pixel(image, cx + side * 7, 13 + dy, Color(0.6, 0.6, 0.7))
					_safe_pixel(image, cx + side * 8, 13 + dy, Color(0.5, 0.5, 0.6))
		"mysterious":
			# Hood shadow over face
			for y in range(1, 5):
				for x in range(cx - 5, cx + 6):
					_safe_pixel(image, x, y, clothes_dark)
			# Glowing eyes under hood
			_safe_pixel(image, 14, 6, Color(0.5, 0.8, 0.5))
			_safe_pixel(image, 18, 6, Color(0.5, 0.8, 0.5))


func _get_npc_hair_color() -> Color:
	"""Get varied hair color based on NPC name hash"""
	var hair_colors = [
		Color(0.15, 0.12, 0.10),  # Black
		Color(0.45, 0.30, 0.18),  # Brown
		Color(0.65, 0.50, 0.30),  # Light brown
		Color(0.85, 0.65, 0.35),  # Blonde
		Color(0.55, 0.55, 0.60),  # Gray
		Color(0.65, 0.25, 0.15),  # Red
	]
	match npc_type:
		"elder": return Color(0.75, 0.75, 0.80)  # White/silver
		"mysterious": return Color(0.15, 0.12, 0.20)  # Very dark
		_: return hair_colors[hash(npc_name) % hair_colors.size()]


func _generate_dance_frames() -> void:
	"""Generate all dance animation frames for dancer NPC"""
	for frame in range(DANCE_FRAMES):
		var image = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
		_draw_dancer_frame(image, frame)
		var texture = ImageTexture.create_from_image(image)
		_sprite_cache[frame] = texture


func _draw_dancer_frame(image: Image, frame: int) -> void:
	"""Draw dancer with different poses for each frame"""
	var skin_color = Color(0.95, 0.80, 0.65)
	var hair_color = Color(0.2, 0.15, 0.1)
	var dress_color = Color(0.9, 0.3, 0.4)  # Red dress
	var dress_accent = Color(0.95, 0.5, 0.3)  # Orange/gold trim
	var outline_color = Color(0.1, 0.1, 0.1)

	image.fill(Color.TRANSPARENT)

	# Dance pose parameters based on frame
	# Frame 0: Arms down, feet together
	# Frame 1: Left arm up, right foot out
	# Frame 2: Both arms up, on tiptoes
	# Frame 3: Right arm up, left foot out
	var left_arm_up = frame == 1 or frame == 2
	var right_arm_up = frame == 2 or frame == 3
	var body_offset = -2 if frame == 2 else 0  # Jump up on frame 2
	var skirt_swirl = frame % 2  # Alternate skirt direction
	var head_tilt = 1 if frame == 1 else (-1 if frame == 3 else 0)

	# Head (slightly tilted based on pose)
	var head_x = 16 + head_tilt
	for y in range(2 + body_offset, 10 + body_offset):
		for x in range(head_x - 4, head_x + 4):
			if x >= 0 and x < TILE_SIZE and y >= 0 and y < TILE_SIZE:
				if y == 2 + body_offset or y == 9 + body_offset or x == head_x - 4 or x == head_x + 3:
					image.set_pixel(x, y, outline_color)
				else:
					image.set_pixel(x, y, skin_color)

	# Hair (long, flowing)
	for y in range(2 + body_offset, 6 + body_offset):
		for x in range(head_x - 3, head_x + 3):
			if x >= 0 and x < TILE_SIZE and y >= 0 and y < TILE_SIZE:
				image.set_pixel(x, y, hair_color)
	# Hair flowing down back
	for y in range(6 + body_offset, 14 + body_offset):
		var hair_x = head_x + 3 - (skirt_swirl * 2)
		if hair_x >= 0 and hair_x < TILE_SIZE and y >= 0 and y < TILE_SIZE:
			image.set_pixel(hair_x, y, hair_color)
			if hair_x + 1 < TILE_SIZE:
				image.set_pixel(hair_x + 1, y, hair_color)

	# Eyes
	if head_x - 2 >= 0 and head_x + 1 < TILE_SIZE:
		image.set_pixel(head_x - 2, 6 + body_offset, outline_color)
		image.set_pixel(head_x + 1, 6 + body_offset, outline_color)

	# Smile
	if head_x - 1 >= 0 and head_x + 1 < TILE_SIZE and 8 + body_offset < TILE_SIZE:
		image.set_pixel(head_x - 1, 8 + body_offset, Color(0.8, 0.5, 0.5))
		image.set_pixel(head_x, 8 + body_offset, Color(0.8, 0.5, 0.5))

	# Body/dress top
	for y in range(10 + body_offset, 18 + body_offset):
		for x in range(12, 20):
			if x >= 0 and x < TILE_SIZE and y >= 0 and y < TILE_SIZE:
				if y == 10 + body_offset or x == 12 or x == 19:
					image.set_pixel(x, y, outline_color)
				else:
					image.set_pixel(x, y, dress_color)

	# Dress skirt (flowing, swirling)
	var skirt_center = 16 + (skirt_swirl * 2 - 1) * 2
	for y in range(18 + body_offset, 28 + body_offset):
		var progress = float(y - (18 + body_offset)) / 10.0
		var skirt_width = int(6 + progress * 6)  # Gets wider at bottom
		var swirl_offset = int(sin(progress * 3.14) * 3 * (skirt_swirl * 2 - 1))
		for x in range(skirt_center - skirt_width + swirl_offset, skirt_center + skirt_width + swirl_offset):
			if x >= 0 and x < TILE_SIZE and y >= 0 and y < TILE_SIZE:
				# Dress pattern - alternating stripes
				var stripe = (x + y) % 4 < 2
				var color = dress_color if stripe else dress_accent
				image.set_pixel(x, y, color)

	# Left arm
	var left_arm_y_start = 12 + body_offset + (-6 if left_arm_up else 0)
	var left_arm_y_end = 20 + body_offset + (-6 if left_arm_up else 0)
	var left_arm_x = 10 + (-2 if left_arm_up else 0)
	for y in range(max(0, left_arm_y_start), min(TILE_SIZE, left_arm_y_end)):
		if left_arm_x >= 0 and left_arm_x < TILE_SIZE:
			image.set_pixel(left_arm_x, y, skin_color)
			if left_arm_x + 1 < TILE_SIZE:
				image.set_pixel(left_arm_x + 1, y, skin_color)

	# Right arm
	var right_arm_y_start = 12 + body_offset + (-6 if right_arm_up else 0)
	var right_arm_y_end = 20 + body_offset + (-6 if right_arm_up else 0)
	var right_arm_x = 21 + (2 if right_arm_up else 0)
	for y in range(max(0, right_arm_y_start), min(TILE_SIZE, right_arm_y_end)):
		if right_arm_x >= 0 and right_arm_x < TILE_SIZE:
			image.set_pixel(right_arm_x, y, skin_color)
			if right_arm_x - 1 >= 0:
				image.set_pixel(right_arm_x - 1, y, skin_color)

	# Legs peeking from skirt
	var leg_y = 26 + body_offset
	if leg_y >= 0 and leg_y < TILE_SIZE - 3:
		# Left leg
		var left_leg_x = 14 + (-2 if frame == 3 else 0)
		for y in range(leg_y, min(TILE_SIZE, leg_y + 4)):
			if left_leg_x >= 0 and left_leg_x < TILE_SIZE:
				image.set_pixel(left_leg_x, y, skin_color)
		# Right leg
		var right_leg_x = 18 + (2 if frame == 1 else 0)
		for y in range(leg_y, min(TILE_SIZE, leg_y + 4)):
			if right_leg_x >= 0 and right_leg_x < TILE_SIZE:
				image.set_pixel(right_leg_x, y, skin_color)

	# Feet/shoes
	var shoe_color = Color(0.8, 0.2, 0.3)  # Red shoes
	var foot_y = 30 + body_offset
	if foot_y >= 0 and foot_y < TILE_SIZE:
		for dx in [-1, 0, 1]:
			var lx = 14 + (-2 if frame == 3 else 0) + dx
			var rx = 18 + (2 if frame == 1 else 0) + dx
			if lx >= 0 and lx < TILE_SIZE:
				image.set_pixel(lx, foot_y, shoe_color)
			if rx >= 0 and rx < TILE_SIZE:
				image.set_pixel(rx, foot_y, shoe_color)


func _update_dance_sprite() -> void:
	"""Update sprite to current dance frame"""
	if _sprite_cache.has(_dance_frame):
		sprite.texture = _sprite_cache[_dance_frame]


func start_dancing() -> void:
	"""Start the dance animation"""
	if npc_type != "dancer":
		return
	_is_dancing = true
	_dance_frame = 0
	_dance_timer = 0.0
	_update_dance_sprite()


func stop_dancing() -> void:
	"""Stop the dance animation and return to normal pose"""
	_is_dancing = false
	_dance_frame = 0
	# Regenerate normal sprite
	var image = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	_draw_npc(image)
	var texture = ImageTexture.create_from_image(image)
	sprite.texture = texture


func _get_clothes_color() -> Color:
	match npc_type:
		"elder":
			return Color(0.6, 0.5, 0.7)  # Purple robes
		"shopkeeper":
			return Color(0.2, 0.5, 0.3)  # Green apron
		"guard":
			return Color(0.4, 0.4, 0.5)  # Gray armor
		"innkeeper":
			return Color(0.7, 0.5, 0.3)  # Brown
		"bartender":
			return Color(0.5, 0.35, 0.2)  # Dark brown apron
		"dancer":
			return Color(0.9, 0.3, 0.4)  # Red dress
		"knight":
			return Color(0.55, 0.55, 0.65)  # Silver armor
		"mysterious":
			return Color(0.25, 0.2, 0.35)  # Dark purple cloak
		"bard":
			return Color(0.7, 0.55, 0.3)  # Gold/tan tunic
		"scholar":
			# tick 69: docstring listed scholar as valid but
			# _get_clothes_color had no arm — fell through to random
			# villager. Sister Concord / Cantor Vell / Greenleaf /
			# Mire / Clavis / Vetch / SUDO-1 / The Witness all carry
			# this type. Deep teal-grey reads as 'studious quiet'.
			return Color(0.30, 0.40, 0.45)
		"merchant":
			# tick 69: same gap — Senga / Crusher Pete carry merchant.
			# Earthy mustard distinguishes from innkeeper's brown
			# (0.7/0.5/0.3) and bard's gold/tan (0.7/0.55/0.3).
			return Color(0.60, 0.45, 0.20)
		_:
			# Random villager colors
			var colors = [
				Color(0.3, 0.4, 0.7),  # Blue
				Color(0.7, 0.3, 0.3),  # Red
				Color(0.3, 0.6, 0.4),  # Green
				Color(0.6, 0.6, 0.3),  # Yellow
			]
			return colors[hash(npc_name) % colors.size()]


func _setup_collision() -> void:
	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 40.0  # Default for villages/interiors
	collision.shape = shape
	collision.position = Vector2(0, 0)
	add_child(collision)
	# Enlarge for Mode 7 overworld after scene tree is ready
	call_deferred("_adjust_collision_for_mode7", shape)


func _adjust_collision_for_mode7(shape: CircleShape2D) -> void:
	# Tick 349: collision layer/mask setup moved BEFORE the Mode 7 check
	# so it runs for ALL NPCs, not just non-Mode-7 ones. Pre-fix the
	# early `return` inside the Mode 7 branch skipped lines 794-797 —
	# Mode 7 overworld NPCs never got collision_layer = 4, so
	# OverworldController._on_interaction_requested's primary physics
	# intersect_point query (mask=4) couldn't find them. The fallback
	# group/distance loop (line ~201) still worked, but every Mode 7
	# NPC interaction routed through the slower path. Same NPC, two
	# different code paths depending on world type.
	#
	# Layer 4 = interactables (NPCs, signs, etc.) - detected by controller queries
	# Mask 2 = player layer - for detecting when player enters NPC zone
	collision_layer = 4  # So controller can find us via physics query
	collision_mask = 2   # To detect player entering our zone
	monitoring = true
	monitorable = true

	# Check if we're on a Mode 7 overworld by looking for Mode7Overlay in ancestors
	var parent = get_parent()
	while parent:
		if parent.get("mode7_overlay") != null or parent.name.ends_with("Overworld"):
			shape.radius = 128.0
			# Y-stretch: matches Mode 7 billboard Y:X ratio (0.3:0.5)
			var col = shape.get_meta("owner_node", null)
			if not col:
				for child in get_children():
					if child is CollisionShape2D and child.shape == shape:
						child.scale = Vector2(1.0, 1.67)
						break
			return
		parent = parent.get_parent()


func _setup_name_label() -> void:
	name_label = Label.new()
	name_label.text = npc_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(-40, -24)
	name_label.size = Vector2(80, 20)
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	name_label.add_theme_constant_override("shadow_offset_x", 1)
	name_label.add_theme_constant_override("shadow_offset_y", 1)
	name_label.visible = false
	add_child(name_label)


## Gold "!" over NPCs with quest business (offerable or mid-quest
## dialogue). Without a marker the W1 givers are only discoverable by
## talking to every NPC in the village. Always visible (unlike the
## proximity-gated name label) — that's the point of the affordance.
func _setup_quest_marker() -> void:
	# Only the SPRITE gets context scale (3x on open overworld) — a
	# fixed marker height sat on the scaled sprite's face there. Clear
	# the sprite's actual scaled top instead; villages (1x) keep the
	# original height.
	_quest_marker_y = QUEST_MARKER_BASE_Y
	if sprite and is_instance_valid(sprite) and sprite.texture:
		var scaled_half: float = sprite.texture.get_height() * 0.5 * sprite.scale.y
		_quest_marker_y = minf(QUEST_MARKER_BASE_Y, -scaled_half - 14.0)
	_quest_marker = Label.new()
	_quest_marker.text = "!"
	_quest_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quest_marker.position = Vector2(-40, _quest_marker_y)
	_quest_marker.size = Vector2(80, 22)
	_quest_marker.add_theme_font_size_override("font_size", 18)
	_quest_marker.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_quest_marker.add_theme_color_override("font_shadow_color", Color.BLACK)
	_quest_marker.add_theme_constant_override("shadow_offset_x", 1)
	_quest_marker.add_theme_constant_override("shadow_offset_y", 1)
	_quest_marker.visible = false
	add_child(_quest_marker)
	var qs = get_node_or_null("/root/QuestSystem")
	if qs != null:
		# Method callables (not lambdas) so Godot auto-disconnects when
		# this NPC frees — village unloads must not leave dead listeners
		# on the autoload's signals.
		qs.quest_state_changed.connect(_on_quest_progress_changed)
		qs.objective_advanced.connect(_on_quest_progress_changed)
	_refresh_quest_marker()


func _on_quest_progress_changed(_a = null, _b = null) -> void:
	_refresh_quest_marker()


func _refresh_quest_marker() -> void:
	if _quest_marker == null or not is_instance_valid(_quest_marker):
		return
	var qs = get_node_or_null("/root/QuestSystem")
	var kind: String = qs.giver_business_kind(get_npc_id()) if qs != null else ""
	match kind:
		"offer":
			_quest_marker.text = "!"
			_quest_marker.visible = true
		"talk":
			_quest_marker.text = "?"
			_quest_marker.visible = true
		_:
			_quest_marker.visible = false


func _setup_dialogue_box() -> void:
	dialogue_box = Control.new()
	dialogue_box.name = "DialogueBox"
	dialogue_box.visible = false
	dialogue_box.z_index = 100

	# Background panel
	var panel = Panel.new()
	panel.position = Vector2(-100, -80)
	panel.size = Vector2(200, 60)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.2, 0.95)
	style.border_color = Color(0.8, 0.8, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	dialogue_box.add_child(panel)

	# Dialogue text
	dialogue_label = Label.new()
	dialogue_label.position = Vector2(-92, -72)
	dialogue_label.size = Vector2(184, 44)
	dialogue_label.add_theme_font_size_override("font_size", 11)
	dialogue_label.add_theme_color_override("font_color", Color.WHITE)
	dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_box.add_child(dialogue_label)

	add_child(dialogue_box)


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("set_can_move"):  # It's the player
		_player_nearby = true
		name_label.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.has_method("set_can_move"):
		_player_nearby = false
		name_label.visible = false
		if _is_talking:
			_end_dialogue()


func _input(event: InputEvent) -> void:
	if not _player_nearby:
		return
	# Zone-listener lock gate: this handler grabs ui_accept directly — mid-cutscene presses opened phantom dialogue over the scene (struktured 2026-07-11, SavePoint-class leak).
	var ilm_gate = get_tree().root.get_node_or_null("InputLockManager") if is_inside_tree() else null
	if ilm_gate and ilm_gate.is_locked():
		return
	# 2026-07-12: also gate on tutorial hints — a hint dismiss press near an NPC would fire dialogue.
	if TutorialHint.is_any_active():
		return

	# Only intercept ui_accept to OPEN dialogue. Once open, CutsceneDialogue
	# (via NPCDialogue) handles ui_accept itself for advance/close.
	# Defer to the next frame to avoid awaiting inside _input.
	if event.is_action_pressed("ui_accept") and not _is_talking:
		get_viewport().set_input_as_handled()
		call_deferred("_start_dialogue")


func _start_dialogue() -> void:
	if dialogue_lines.is_empty() or _is_talking:
		return

	_is_talking = true
	_current_line = 0
	dialogue_started.emit(npc_name)
	if SoundManager:
		SoundManager.play_ui("menu_open")

	# Set story flags for key NPC interactions and trigger pending cutscenes
	if npc_name == "Bram Smith" and GameState:
		GameState.game_constants["talked_to_bram_smith"] = true
		dialogue_ended.connect(func(_name):
			var game_loop_b = get_node_or_null("/root/GameLoop")
			if game_loop_b and game_loop_b.has_method("check_pending_cutscene"):
				game_loop_b.check_pending_cutscene()
		, CONNECT_ONE_SHOT)

	if npc_name == "Elder Theron" and GameState:
		GameState.game_constants["talked_to_theron"] = true
		# Notify GameLoop to check for pending cutscenes after dialogue finishes
		dialogue_ended.connect(func(_name):
			var game_loop = get_node_or_null("/root/GameLoop")
			if game_loop and game_loop.has_method("check_pending_cutscene"):
				game_loop.check_pending_cutscene()
		, CONNECT_ONE_SHOT)

	# Dancer starts dancing when talked to
	if npc_type == "dancer":
		start_dancing()

	# ── Quest path — quest business outranks dynamic chat + scripted lines
	# (routing chain settled in huddle msgs 2124/2126: quest > dynamic > static).
	# notify_talk always fires first: it silently progresses talk objectives
	# TARGETING this NPC (their own lines still play — e.g. Phil mid-quest),
	# and returns a quest_id when this talk completed the FINAL step so the
	# completion beat plays with this NPC as presenter (thirty_seven's
	# scholar turn-in). Giver business (offer/turn-in/in-progress) replaces
	# the NPC's normal dialogue entirely for that interaction.
	var quest_sys = get_node_or_null("/root/QuestSystem")
	if quest_sys:
		var qplayer := _get_nearby_player()
		if qplayer and qplayer.has_method("set_can_move"):
			qplayer.set_can_move(false)
		var has_giver: bool = quest_sys.has_giver_business(get_npc_id())
		var yield_to_llm: bool = _quest_should_yield_to_llm(quest_sys, has_giver)
		var was_giver: bool = false
		if has_giver and not yield_to_llm:
			await quest_sys.run_giver_dialogue(get_npc_id(), self)
			was_giver = true
		elif not has_giver:
			var done_qid: String = quest_sys.notify_talk(get_npc_id())
			if done_qid != "":
				await quest_sys.run_completion_dialogue(done_qid, self)
				was_giver = true
		if qplayer and is_instance_valid(qplayer) and qplayer.has_method("set_can_move"):
			qplayer.set_can_move(true)
		if was_giver:
			_end_dialogue()
			return

	# ── LLM-driven path: use DynamicConversation when LLMService is available
	# AND this NPC is opt-in for dynamic dialogue. Per design doc :157, only
	# the showcase W1 NPCs (dynamic = true with authored persona) take this
	# branch; every other NPC continues through the static dialogue_lines
	# pipeline below.
	# Story beats outrank freeform chat: Theron's first talk arms the
	# chapter1 cutscene, and the LLM prompt hijacked it (struktured
	# 2026-07-11). With a story cutscene pending, fall through to static
	# lines so dialogue_ended → check_pending_cutscene plays the beat.
	var gl_story = get_node_or_null("/root/GameLoop")
	var story_pending: bool = gl_story != null \
		and gl_story.has_method("_get_pending_story_cutscene") \
		and str(gl_story._get_pending_story_cutscene()) != ""
	if dynamic and persona != "" and not story_pending and _llm_conversation_available():
		var player := _get_nearby_player()
		await _run_dynamic_conversation(player)
		_end_dialogue()
		return

	# ── Static path (NPCDialogue, CanvasLayer-anchored). ──
	# Resolves both the screen-edge cut-off bug AND the gamepad-input
	# bug (ui_accept now reaches CutsceneDialogue's _input handler
	# without competing with NPCDialogue's nearby-NPC consumer).
	# (User feedback 2026-05-20: "dialogue boxes get cut off near edges
	# of the screen in the village", "gamepad doesn't advance cutscene".)
	if not _npc_dialogue or not is_instance_valid(_npc_dialogue):
		var NPCDialogueClass = load("res://src/cutscene/NPCDialogue.gd")
		_npc_dialogue = NPCDialogueClass.new()
		add_child(_npc_dialogue)

	# Freeze player while talking (matching WanderingNPC behavior)
	var player := _get_nearby_player()
	if player and player.has_method("set_can_move"):
		player.set_can_move(false)

	var lines: Array = []
	var _quest_sys_for_lines = get_node_or_null("/root/QuestSystem")
	var _quest_bucket: String = _quest_state_bucket_for_npc(_quest_sys_for_lines)
	var source_lines: Array = _quest_state_bucket_rotation(_quest_bucket)
	if source_lines.is_empty():
		var n: int = dialogue_lines.size()
		var offset: int = (_dialogue_visit_count % n) if n > 0 else 0
		for i in range(n):
			var line_text = dialogue_lines[(i + offset) % n]
			lines.append({
				"speaker": npc_name,
				"text": line_text,
				"theme": npc_type,
				"portrait": npc_type,
			})
		_dialogue_visit_count += 1
	else:
		for line_text in source_lines:
			lines.append({
				"speaker": npc_name,
				"text": str(line_text),
				"theme": npc_type,
				"portrait": npc_type,
			})
		_quest_state_bucket_visits[_quest_bucket] = int(_quest_state_bucket_visits.get(_quest_bucket, 0)) + 1
	await _npc_dialogue.say_lines(lines)

	if player and is_instance_valid(player) and player.has_method("set_can_move"):
		player.set_can_move(true)

	_end_dialogue()


func _advance_dialogue() -> void:
	# Retained for backward compatibility with any direct callers / tests.
	# Production path uses NPCDialogue/CutsceneDialogue which advances
	# internally on ui_accept.
	_current_line += 1
	if _current_line >= dialogue_lines.size():
		_end_dialogue()
	else:
		if dialogue_label and is_instance_valid(dialogue_label):
			dialogue_label.text = dialogue_lines[_current_line]
		if SoundManager:
			SoundManager.play_ui("menu_select")


## Quest identity: explicit npc_id export, else snake_case of npc_name.
func get_npc_id() -> String:
	if npc_id != "":
		return npc_id
	return npc_name.to_lower().replace(" ", "_").replace("'", "").replace("-", "_")


func _get_nearby_player() -> Node:
	"""Find the player node currently inside our trigger Area2D."""
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0]
	return null


func _llm_conversation_available() -> bool:
	"""Returns true when LLMService is present and reporting availability."""
	# Engine.has_singleton("LLMService") is ALWAYS FALSE for autoloads in
	# Godot 4 — look up the autoload via the scene tree root.
	var svc: Node = get_node_or_null("/root/LLMService")
	return svc != null and svc.is_available()


## For LLM-opt-in NPCs (dynamic + persona), mid-quest in_progress giver-flavor yields to dynamic chat; offer/talk-completion still preempts (msg 2164, huddle 2124/2126).
func _quest_should_yield_to_llm(quest_sys: Node, has_giver: bool) -> bool:
	if not has_giver or not (dynamic and persona != ""):
		return false
	if not quest_sys.has_method("giver_business_kind"):
		return false
	var kind: String = str(quest_sys.giver_business_kind(get_npc_id()))
	return kind != "offer" and kind != "talk"


## Milo v2 (msg 2600): map QuestSystem state for the quest THIS NPC gives → persona bucket ("" if no override applies).
func _quest_state_bucket_for_npc(quest_sys: Node) -> String:
	if quest_sys == null or not quest_sys.has_method("get_all_ids") or not quest_sys.has_method("get_quest") or not quest_sys.has_method("get_state"):
		return ""
	var npc: String = get_npc_id()
	for qid in quest_sys.get_all_ids():
		var q: Dictionary = quest_sys.get_quest(qid)
		if str(q.get("giver", {}).get("npc_id", "")) != npc:
			continue
		var state: String = str(quest_sys.get_state(qid))
		if state == "active":
			return "in_progress"
		if state == "completed" or state == "turned_in":
			return "post_quest"
		if state == "":
			return "pre_task_1"
		return ""
	return ""


## Milo v2: return the bucket lines rotated so a fresh bucket-visit lands on money_pick_index; [] means no override, keep dialogue_lines.
func _quest_state_bucket_rotation(bucket: String) -> Array:
	if bucket == "" or _persona_quest_state_lines.is_empty() or not _persona_quest_state_lines.has(bucket):
		return []
	var bucket_lines: Array = _persona_quest_state_lines[bucket]
	if bucket_lines.is_empty():
		return []
	var money_pick: int = int(_persona_quest_state_money_picks.get(bucket, 0))
	var count: int = int(_quest_state_bucket_visits.get(bucket, 0))
	var start: int = (money_pick + count) % bucket_lines.size()
	var rotated: Array = []
	for i in range(bucket_lines.size()):
		rotated.append(str(bucket_lines[(i + start) % bucket_lines.size()]))
	return rotated


func _run_dynamic_conversation(player: Node) -> void:
	"""Spin up (or reuse) a DynamicConversation and run a full LLM-driven exchange.

	The caller (`interact()`) must gate on `dynamic and persona != ""` so this
	path is only taken by opt-in showcase NPCs (design doc :157). The persona
	is the authored @export string — there is no longer a npc_type → fake
	persona table.
	"""
	if not _dynamic_conv or not is_instance_valid(_dynamic_conv):
		_dynamic_conv = DynamicConversation.new()
		_dynamic_conv.name = "DynamicConversation"
		add_child(_dynamic_conv)

	# Resolve EventLog from the GameState autoload (engine has_singleton check
	# is ALWAYS FALSE for autoloads in Godot 4 — use scene tree root).
	var event_log: EventLog = null
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and "event_log" in gs:
		event_log = gs.event_log

	# Resolve location name from parent scene.
	var location: String = _resolve_location_name()

	var quest_sys_for_llm = get_node_or_null("/root/QuestSystem")
	var llm_bucket: String = _quest_state_bucket_for_npc(quest_sys_for_llm)
	var llm_quest_lines: Array = _persona_quest_state_lines.get(llm_bucket, []) if llm_bucket != "" else []
	_dynamic_conv.setup(npc_name, persona, location, event_log, dialogue_lines, _persona_openings, llm_quest_lines)
	await _dynamic_conv.run(player)


func _resolve_location_name() -> String:
	var p = get_parent()
	if p:
		var n: String = p.name
		if n != "" and n != "Node":
			return n
		var gp = p.get_parent()
		if gp:
			var gn: String = gp.name
			if gn != "" and gn != "Node":
				return gn
	return "Unknown Land"


func _end_dialogue() -> void:
	_is_talking = false
	if dialogue_box and is_instance_valid(dialogue_box):
		dialogue_box.visible = false
	_current_line = 0
	dialogue_ended.emit(npc_name)
	if SoundManager:
		SoundManager.play_ui("menu_close")

	# Dancer stops dancing when dialogue ends
	if npc_type == "dancer" and _is_dancing:
		stop_dancing()


## Called by interaction system
func interact(player: Node2D) -> void:
	if _is_talking:
		_advance_dialogue()
	else:
		_start_dialogue()
