extends RefCounted
class_name HybridSpriteLoader

## Hybrid sprite loader that checks for external artist sprite sheets first,
## then falls back to procedural SnesPartySprites generation.

const _SnesPartySprites = preload("res://src/battle/sprites/SnesPartySprites.gd")

static var _manifest: Dictionary = {}
static var _monster_manifest: Dictionary = {}
static var _battle_effects: Dictionary = {}
static var _manifest_loaded: bool = false


## Per-world job asset resolution (struktured 2026-08-06: "your characters are supposed to
## xform as they shift overworlds"). PURE: the suffix arrives as an argument, so this cannot
## inherit audio-state staleness. Medieval is the BASE — the unsuffixed file IS the medieval
## art, so "medieval" and "" both skip the variant probe (the monster loader's convention).
## `exists` is injectable so the medieval-skips-the-probe arm is falsifiable BEFORE any
## variant art ships — with the default probe, skip-and-miss return identical paths and a
## mutation deleting the medieval guard survives every test (measured, M1, 2026-08-06).
static func job_asset_path(job_id: String, base_name: String, world_suffix: String,
		exists: Callable = Callable()) -> String:
	if world_suffix != "" and world_suffix != "medieval":
		var variant := "res://assets/sprites/jobs/%s/%s_%s.png" % [job_id, base_name, world_suffix]
		var found: bool = exists.call(variant) if exists.is_valid() else ResourceLoader.exists(variant)
		if found:
			return variant
	return "res://assets/sprites/jobs/%s/%s.png" % [job_id, base_name]


## The ONE fetch site for the current suffix, so four consumers stay identical and the swap
## to SoundManager's public accessor (unfolded branch) is a single edit here, not four.
static func current_world_suffix() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return ""
	var sm := tree.root.get_node_or_null("SoundManager")
	if sm == null or not sm.has_method("_get_current_world_suffix"):
		return ""
	return str(sm._get_current_world_suffix())

static func _load_manifest() -> void:
	if _manifest_loaded:
		return
	# Always set the loaded flag at the END so a failure mid-load
	# doesn't poison the cache — but mark it loaded BEFORE any
	# early-return on failure so we don't re-warn every lookup.
	var file_path = "res://data/sprite_manifest.json"
	if not FileAccess.file_exists(file_path):
		push_warning("[SPRITES] sprite_manifest.json not found at %s — all jobs/monsters will use procedural fallbacks (artist sheets invisible)" % file_path)
		_manifest_loaded = true
		return
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_warning("[SPRITES] sprite_manifest.json exists but FileAccess.open failed — artist sheets invisible")
		_manifest_loaded = true
		return
	var raw := file.get_as_text()
	file.close()
	var json = JSON.new()
	var parse_result := json.parse(raw)
	if parse_result != OK:
		push_warning("[SPRITES] sprite_manifest.json parse error: %s — artist sheets invisible" % json.get_error_message())
		_manifest_loaded = true
		return
	if not (json.data is Dictionary):
		push_warning("[SPRITES] sprite_manifest.json parsed but root is not a Dictionary — artist sheets invisible")
		_manifest_loaded = true
		return
	_manifest = json.data.get("sheets", {})
	_monster_manifest = json.data.get("monster_sheets", {})
	_battle_effects = json.data.get("battle_effects", {})
	print("[SPRITES] Loaded sprite manifest: %d sheets, %d monster sheets, %d battle effects" % [_manifest.size(), _monster_manifest.size(), _battle_effects.size()])
	_manifest_loaded = true


static func load_battle_effect_texture(key: String) -> Texture2D:
	_load_manifest()
	if not _battle_effects.has(key):
		return null
	var entry: Dictionary = _battle_effects[key]
	var path: String = str(entry.get("path", ""))
	if path == "" or not ResourceLoader.exists(path):
		push_warning("[SPRITES] battle_effect '%s' path missing or unloadable: %s" % [key, path])
		return null
	var tex: Resource = load(path)
	return tex if tex is Texture2D else null


static func has_artist_sheet(job_id: String) -> bool:
	"""Check if a job has an artist sprite sheet in the manifest."""
	_load_manifest()
	return _manifest.has(job_id)


## Does this sheet need flipping so the monster faces the party (screen right)?
##
## Frame size is only a PROXY here, and conflating the two cost us twice in one day:
##   cave_rat_king  256px sheet authored facing LEFT -> rendered backwards in battle (2026-07-25)
##   chancellor_mordaine  re-exported 256px -> 128px for the scale bump, which silently
##                        flipped her facing too; correct only because she happens to be
##                        drawn facing left (caught at fold review, 2026-07-26)
##
## The second one is the dangerous shape: a resolution change is a SIZING decision, and it
## must not be able to reverse a monster's facing as a side effect. So facing is declared,
## not inferred — "flip_h" in sprite_manifest wins whenever present, and the frame-size
## convention is only the fallback for sheets that have not declared.
static func monster_faces_party(monster_id: String, convention_default: bool) -> bool:
	_load_manifest()
	var entry = _monster_manifest.get(monster_id, {})
	if entry is Dictionary and entry.has("flip_h"):
		return bool(entry["flip_h"])
	return convention_default


## Sizing decision ONLY — small artist drops get the scale bump so they don't read tiny
## next to 256px proc-gen monsters. Deliberately separate from facing: see monster_faces_party.
static func monster_needs_scale_bump(frame_height: int, threshold: int) -> bool:
	return frame_height > 0 and frame_height <= threshold


static func load_sprite_frames(customization, primary_job_id: String, secondary_job_id: String = "", weapon_id: String = "", armor_id: String = "", accessory_id: String = "") -> SpriteFrames:
	_load_manifest()

	# Check manifest for external sprite sheet
	if _manifest.has(primary_job_id):
		var sheet_data = _manifest[primary_job_id]
		var frames = _load_external_sheet(sheet_data, primary_job_id)
		if frames:
			print("[SPRITES] Using artist sheet for '%s'" % primary_job_id)
			return frames
		else:
			print("[SPRITES] Artist sheet for '%s' failed to load, using procedural" % primary_job_id)
	else:
		print("[SPRITES] No manifest entry for '%s', using procedural" % primary_job_id)

	# Fall back to procedural generation
	return _SnesPartySprites.create_sprite_frames(customization, primary_job_id, secondary_job_id, weapon_id, armor_id, accessory_id)


## Load monster sprite frames from manifest. Returns null if no entry exists,
## allowing the caller to fall back to procedural generation.
## Monster sheet schema (in manifest under "monster_sheets"):
##   monster_id: {
##     "path": "res://assets/sprites/monsters/monster_id.png",
##     "frame_width": 256, "frame_height": 256, "fps": 8,
##     "animations": {
##       "idle":   {"start": 0, "end": 1},
##       "attack": {"start": 2, "end": 3},
##       ...
##     }
##   }
## Sheets are horizontal strips: frame_width * num_frames wide, frame_height tall.
static func load_monster_sprite_frames(monster_id: String) -> SpriteFrames:
	_load_manifest()

	if not _monster_manifest.has(monster_id):
		return null

	var sheet_data = _monster_manifest[monster_id]
	var sheet_path = sheet_data.get("path", "res://assets/sprites/monsters/%s.png" % monster_id)
	if not ResourceLoader.exists(sheet_path):
		push_warning("[SPRITES] Monster sheet not found: %s" % sheet_path)
		return null

	var texture = load(sheet_path) as Texture2D
	if not texture:
		push_warning("[SPRITES] Failed to load monster texture: %s" % sheet_path)
		return null

	var frame_width: int = sheet_data.get("frame_width", 256)
	var frame_height: int = sheet_data.get("frame_height", 256)
	var fps: float = sheet_data.get("fps", 8)
	var animations = sheet_data.get("animations", {})

	var sprite_frames = SpriteFrames.new()
	var cols_per_row: int = texture.get_width() / frame_width

	for anim_name in animations:
		var anim_data = animations[anim_name]
		var start_frame: int = anim_data.get("start", 0)
		var end_frame: int = anim_data.get("end", start_frame)

		sprite_frames.add_animation(anim_name)
		sprite_frames.set_animation_speed(anim_name, fps)
		sprite_frames.set_animation_loop(anim_name, anim_name == "idle")

		for frame_idx in range(start_frame, end_frame + 1):
			var col: int = frame_idx % cols_per_row
			var row: int = frame_idx / cols_per_row
			var atlas = AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(col * frame_width, row * frame_height, frame_width, frame_height)
			sprite_frames.add_frame(anim_name, atlas)

	if sprite_frames.get_animation_names().size() == 0:
		return null

	print("[SPRITES] Loaded monster sheet for '%s' (%d animations)" % [monster_id, sprite_frames.get_animation_names().size()])
	return sprite_frames


## Sheet suffix per world, indexed by GameState.current_world (1-6).
## World 1 is the artist's BASE art and is deliberately never suffixed, so the
## costume vocabulary is 5 suffixes and not 6. Order pinned to WorldMapMenu.WORLD_DATA.
const WORLD_SUFFIXES := ["", "suburban", "steampunk", "industrial", "digital", "abstract"]


## Resolve the current world's sheet suffix; pass `world` explicitly to override.
##
## Reads GameState.current_world and DELIBERATELY does not call
## SoundManager.get_current_world_suffix(), which was added for this consumer. An earlier
## version deferred to it; cowir-sfx flagged the hazard and the source confirms it:
##
##   GameState.current_world     written in _set_current_map_id(), the setter for EVERY map
##                               change, derived from the map id (GameLoop:141)
##   audio's cached suffix       written at ONE site, behind an early `return` for interiors
##                               with no resolved track — and by an AUDIO function, so it
##                               tracks music state, not player location
##
## Audio's is right for audio: during a battle _current_area is cleared on purpose so the
## cached value keeps battle music world-aware. But sprites resolve DURING battle, on that
## exact cleared-area path, so deferring would have made costumes inherit whatever the last
## music transition happened to leave behind.
##
## The two are not duplicates. Audio maps AREA -> world; this maps WORLD INDEX -> suffix.
## The logic that must not be duplicated is area -> world, and GameLoop already owns it.
##
## Left as a plain read with no accessor probe, so folding sfx-world-suffix-public cannot
## silently change what the player sees.
static func world_suffix(world: int = -1) -> String:
	var w: int = world
	if w < 0:
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		var root: Node = tree.root if tree != null else null
		var gs: Object = root.get_node_or_null("GameState") if root != null else null
		w = int(gs.get("current_world")) if gs != null and "current_world" in gs else 1
	if w < 1 or w > WORLD_SUFFIXES.size():
		return ""
	return WORLD_SUFFIXES[w - 1]


## Audio's vocabulary is not the sheet vocabulary: it says "medieval" where the sheets say
## "" (world 1 IS the artist's base art). Anything unrecognised also lands on base art.
static func _normalize_suffix(audio_suffix: String) -> String:
	return audio_suffix if audio_suffix in WORLD_SUFFIXES else ""


static func _load_external_sheet(sheet_data: Dictionary, job_id: String) -> SpriteFrames:
	var base_path = sheet_data.get("path", "res://assets/sprites/jobs/%s" % job_id)
	var frame_width = sheet_data.get("frame_width", 32)
	var frame_height = sheet_data.get("frame_height", 32)
	var animations = sheet_data.get("animations", ["idle", "walk", "attack", "cast", "hit", "dead"])

	var sprite_frames = SpriteFrames.new()
	var loaded_any = false
	var suffix: String = world_suffix()

	for anim_name in animations:
		var sheet_path = "%s/%s.png" % [base_path, anim_name]
		# A world-dressed sheet wins ONLY when it exists; absence falls back to artist base.
		if suffix != "":
			var dressed: String = "%s/%s_%s.png" % [base_path, anim_name, suffix]
			if ResourceLoader.exists(dressed):
				sheet_path = dressed
		if not ResourceLoader.exists(sheet_path):
			continue

		var texture = load(sheet_path) as Texture2D
		if not texture:
			continue

		sprite_frames.add_animation(anim_name)
		sprite_frames.set_animation_speed(anim_name, sheet_data.get("fps", 8))
		# Only idle and victory loop; all others play once so animation_finished fires
		sprite_frames.set_animation_loop(anim_name, anim_name in ["idle", "victory"])

		var frame_count = texture.get_width() / frame_width
		for i in range(frame_count):
			var atlas = AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(i * frame_width, 0, frame_width, frame_height)
			sprite_frames.add_frame(anim_name, atlas)

		loaded_any = true

	return sprite_frames if loaded_any else null
