extends RefCounted
class_name HybridSpriteLoader

## Hybrid sprite loader that checks for external artist sprite sheets first,
## then falls back to procedural SnesPartySprites generation.

const _SnesPartySprites = preload("res://src/battle/sprites/SnesPartySprites.gd")

static var _manifest: Dictionary = {}
static var _monster_manifest: Dictionary = {}
static var _battle_effects: Dictionary = {}
static var _overworld_player_sheets: Dictionary = {}
static var _overworld_monster_sheets: Dictionary = {}
static var _overworld_npc_sheets: Dictionary = {}
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
## RESOLVER UNIFICATION (cowir-sprites' fold slot, as agreed): delegates to world_suffix()
## instead of reading SoundManager's private method, so the codebase has ONE visual world
## source. Four consumers keep calling this name; only the body moved.
##
## Why GameState and not audio, now that both are correct: audio's suffix is written at ONE
## site behind an early return for interiors with no resolved track, by an audio function,
## and play_music CLEARS _current_area for battle — which is where sprites resolve.
## current_world is written in _set_current_map_id(), the setter for every map change.
##
## The interior hole that made audio look better is CLOSED on this tree: GameLoop:144 derives
## a shared interior's world from _village_origin_id, so current_world no longer zeroes to W1
## in a Brasston inn. That fix landing is what makes this a correct unification rather than a
## trade — before it, each source was right only where the other was wrong.
static func current_world_suffix() -> String:
	return world_suffix()


## NPC twin of job_asset_path: <archetype>/overworld_<world>.png when it exists, else the base.
## ⛔ THE PATH IS THE ROUTE; the manifest entry is the LEDGER. 145 overworld_npc_sheets entries
## exist and the art is live — an archetype renders because its PNG sits at the conventional path,
## not because it is registered. The section was declared "an audit ledger, not a route" in
## _section_provenance until 2026-09-16, when overworld_walk_rows() gave it a real reader for the
## walk-row order and that declaration expired. The durable half is this: registering art here
## attributes it; putting the file at this path is what makes it appear.
static func npc_overworld_path(archetype: String) -> String:
	var suffix := world_suffix()
	if suffix != "" and suffix != "medieval":
		var variant := "res://assets/sprites/npcs/%s_%s/overworld.png" % [archetype, suffix]
		if ResourceLoader.exists(variant):
			return variant
	return "res://assets/sprites/npcs/%s/overworld.png" % archetype

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
	_overworld_player_sheets = json.data.get("overworld_player_sheets", {})
	_overworld_monster_sheets = json.data.get("overworld_monster_sheets", {})
	_overworld_npc_sheets = json.data.get("overworld_npc_sheets", {})
	print("[SPRITES] Loaded sprite manifest: %d sheets, %d monster sheets, %d battle effects" % [_manifest.size(), _monster_manifest.size(), _battle_effects.size()])
	_manifest_loaded = true


## The overworld walk sheet's frame size, DECLARED per job in overworld_player_sheets.
##
## OverworldPlayer cut every sheet at a hardcoded 32 and only checked the image was BIG ENOUGH
## (>= 128x128), so a sheet authored at any other frame size passed and was sliced into 32px
## squares — the player character rendered as a quarter of a figure, with nothing erroring.
## All 14 sheets are 32px today, which is exactly why it held; cowir-cutscenes hit the identical
## shape in CutsceneActor the same afternoon, on sheets that were 159-for-159 uniform.
##
## Wiring it also gives overworld_player_sheets its first runtime reader. It was one of six
## manifest sections nothing read — and a section whose FIELDS are all read elsewhere is invisible
## to a field-level census, which is the gap this closes rather than declares.
static func overworld_frame_size(job_id: String) -> Vector2i:
	_load_manifest()
	var entry = _overworld_player_sheets.get(job_id, {})
	if not (entry is Dictionary):
		return Vector2i(32, 32)
	return Vector2i(int(entry.get("frame_width", 32)), int(entry.get("frame_height", 32)))


## The roaming-monster walk sheet's geometry, DECLARED per monster in overworld_monster_sheets:
## frame size, columns per row, and WHICH ROW IS WHICH FACING.
##
## RoamingMonster hardcoded all three — FRAME_W/FRAME_H 32, SHEET_COLS 4, and rows 0=down 1=left
## 2=right 3=up written into _update_row_from_move_dir — while the manifest declared each of them
## and nothing read the section. A sheet that ordered its rows differently would walk facing the
## wrong way; one at another frame size would be mis-sliced. All 10 are 128x128 / 32px / that row
## order today, which is the uniformity that hides it, same as the player's sheet one hour ago.
##
## Returns convention defaults for an unregistered monster — the section is an audit ledger for
## art the runtime also reaches by path convention, so absence must not refuse a sheet.
## The walk-row order DECLARED per job, falling back to the documented convention.
##
## OverworldPlayer hardcoded [DOWN, LEFT, RIGHT, UP] while RoamingMonster reads its rows from the
## manifest. Every shipped sheet agrees with that order today — 53 of 53, pinned by
## test_a_walk_sheet_declares_the_facing_its_pixels_show — so this is LATENT. The asymmetry is the
## defect: one consumer deriving and one guessing is worse than both guessing, because the two
## disagree only for the sheet that would have needed the fix.
##
## ⛔ FALLS BACK WHOLESALE, not per key. A declaration that maps two directions onto one row is
## incoherent rather than partially useful, and half-applying it would face the player two ways at
## once — worse than the convention it replaced.
static func overworld_player_rows(job_id: String) -> Dictionary:
	return overworld_walk_rows("overworld_player_sheets", job_id)


## The same question for any overworld section — players, npcs, monsters all declare walk rows.
##
## ⛔ ONE OWNER, NOT ONE PER SECTION. A third near-identical copy is how this fleet ended up
## measuring 18 redundant private comment-strippers in a day; the sections differ by KEY, not by
## rule.
## The loaded store for an overworld section, or {} for a name nothing loads.
##
## Explicit rather than reflective: a `get(section)` over the raw manifest would silently accept
## any string and return {} for a typo, which reads exactly like a section with no entries.
static func _manifest_section(section: String) -> Dictionary:
	match section:
		"overworld_player_sheets":
			return _overworld_player_sheets
		"overworld_monster_sheets":
			return _overworld_monster_sheets
		"overworld_npc_sheets":
			return _overworld_npc_sheets
	push_warning("[SPRITES] no loaded store for manifest section '%s'" % section)
	return {}


static func overworld_walk_rows(section: String, id: String) -> Dictionary:
	_load_manifest()
	var convention := {"walk_down": 0, "walk_left": 1, "walk_right": 2, "walk_up": 3}
	var store: Dictionary = _manifest_section(section)
	var entry = store.get(id, {})
	if not (entry is Dictionary):
		return convention
	var anims = (entry as Dictionary).get("animations", {})
	if not (anims is Dictionary):
		return convention
	var out := {}
	var seen := {}
	for name in convention:
		var a = (anims as Dictionary).get(name, {})
		if not (a is Dictionary) or not (a as Dictionary).has("row"):
			return convention
		var row := int((a as Dictionary)["row"])
		if row < 0 or seen.has(row):
			return convention
		seen[row] = true
		out[name] = row
	return out


static func overworld_monster_geometry(monster_id: String) -> Dictionary:
	_load_manifest()
	var out := {"frame": Vector2i(32, 32), "cols": 4, "rows": {"walk_down": 0, "walk_left": 1, "walk_right": 2, "walk_up": 3}}
	var entry = _overworld_monster_sheets.get(monster_id, {})
	if not (entry is Dictionary) or entry.is_empty():
		return out
	out["frame"] = Vector2i(int(entry.get("frame_width", 32)), int(entry.get("frame_height", 32)))
	var anims = entry.get("animations", {})
	if anims is Dictionary and not anims.is_empty():
		var rows := {}
		var cols := 0
		for name in anims:
			var a = anims[name]
			if a is Dictionary and a.has("row"):
				rows[str(name)] = int(a["row"])
				cols = maxi(cols, int(a.get("frames", 0)))
		if not rows.is_empty():
			out["rows"] = rows
		if cols > 0:
			out["cols"] = cols
	return out


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


## Where the FIGURE sits inside frame 0, not where the frame is. Job sheets place their
## figures very differently — measured 2026-09-16, the Fighter fills 0.38 of its 256px frame
## with its head at y=66, the Cleric's head at y=10 — so any geometry cut from the FRAME is
## framing empty space for some jobs and the character for others.
static var _figure_rect_cache: Dictionary = {}

## TWIN, deliberately not shared: AdvanceAura.figure_rect_of(tex) answers the same question from a
## LIVE TEXTURE and falls back to the WHOLE frame. This one takes a path, so an absent or unreadable
## sheet returns EMPTY — a caller with no sheet must not be handed a plausible rect. Same retirement
## condition as the twin: collapse only when one caller needs both inputs.
static func figure_rect(sheet_path: String) -> Rect2i:
	if _figure_rect_cache.has(sheet_path):
		return _figure_rect_cache[sheet_path]
	var empty := Rect2i(0, 0, 0, 0)
	if not ResourceLoader.exists(sheet_path):
		_figure_rect_cache[sheet_path] = empty
		return empty
	var tex := load(sheet_path) as Texture2D
	if tex == null:
		_figure_rect_cache[sheet_path] = empty
		return empty
	var img: Image = tex.get_image()
	if img == null:
		_figure_rect_cache[sheet_path] = empty
		return empty
	var frame: int = img.get_height()
	if frame <= 0 or img.get_width() < frame:
		_figure_rect_cache[sheet_path] = empty
		return empty
	var used: Rect2i = img.get_region(Rect2i(0, 0, frame, frame)).get_used_rect()
	_figure_rect_cache[sheet_path] = used
	return used


## A head-and-shoulders box around the FIGURE, square so every job renders at one aspect.
## `ratio` is the fraction of the FIGURE's height the bust keeps (0.55 = head + torso).
## Falls back to the old frame-relative crop when the sheet has no opaque pixels to measure.
static func bust_region(sheet_path: String, frame: int, ratio: float) -> Rect2i:
	var fig := figure_rect(sheet_path)
	if fig.size.x <= 0 or fig.size.y <= 0:
		return Rect2i(0, 0, frame, int(float(frame) * ratio))
	var bust_h: int = maxi(8, int(round(float(fig.size.y) * ratio)))
	var side: int = clampi(maxi(fig.size.x, bust_h), 8, frame)
	var headroom: int = int(round(float(side) * 0.06))
	var x: int = clampi(fig.position.x + fig.size.x / 2 - side / 2, 0, frame - side)
	var y: int = clampi(fig.position.y - headroom, 0, frame - side)
	return Rect2i(x, y, side, side)


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
## One monster frame as a plain texture — for map markers that want the CREATURE, not a letter.
## struktured 2026-09-06: "I want bosses to not be labeld as a 'B' tile any longer lets get a sprite there".
## Returns the idle frame from the same monster_sheets ledger the battle sprite uses, so a boss can
## never show one face on the map and another in the fight. Null when the id has no sheet.
static func monster_frame_texture(monster_id: String, anim: String = "idle") -> AtlasTexture:
	_load_manifest()
	if not _monster_manifest.has(monster_id):
		return null
	var sheet_data: Dictionary = _monster_manifest[monster_id]
	var sheet_path: String = sheet_data.get("path", "res://assets/sprites/monsters/%s.png" % monster_id)
	if not ResourceLoader.exists(sheet_path):
		return null
	var texture := load(sheet_path) as Texture2D
	if texture == null:
		return null
	var frame_width: int = sheet_data.get("frame_width", 256)
	var frame_height: int = sheet_data.get("frame_height", 256)
	if frame_width <= 0 or frame_height <= 0:
		return null
	var animations: Dictionary = sheet_data.get("animations", {})
	var frame_idx: int = 0
	if animations.has(anim):
		frame_idx = int((animations[anim] as Dictionary).get("start", 0))
	var cols_per_row: int = maxi(1, texture.get_width() / frame_width)
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(float((frame_idx % cols_per_row) * frame_width), float((frame_idx / cols_per_row) * frame_height), float(frame_width), float(frame_height))
	return atlas


## base_id re-times a world costume against the base it dresses. Monster costumes are SEPARATE
## manifest entries resolved by the caller, so unlike the job path the loader cannot derive it.
static func load_monster_sprite_frames(monster_id: String, base_id: String = "") -> SpriteFrames:
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
	# Refuse a zero declaration as monster_frame_texture does — the division below raises before maxi() can clamp it.
	if frame_width <= 0 or frame_height <= 0:
		return null
	var fps: float = sheet_data.get("fps", 8)
	var animations = sheet_data.get("animations", {})
	var base_anims: Dictionary = {}
	if base_id != "" and base_id != monster_id and _monster_manifest.has(base_id):
		var base_entry = _monster_manifest[base_id]
		if base_entry is Dictionary:
			var ba = (base_entry as Dictionary).get("animations", {})
			if ba is Dictionary:
				base_anims = ba

	var sprite_frames = SpriteFrames.new()
	# maxi() floors a NARROW sheet at one column; a ZERO declaration is refused above, because this division runs first.
	var cols_per_row: int = maxi(1, texture.get_width() / frame_width)

	for anim_name in animations:
		var anim_data = animations[anim_name]
		var start_frame: int = anim_data.get("start", 0)
		var end_frame: int = anim_data.get("end", start_frame)

		sprite_frames.add_animation(anim_name)
		var anim_fps: float = fps
		if base_anims.has(anim_name):
			var b = base_anims[anim_name]
			if b is Dictionary:
				var b_start: int = (b as Dictionary).get("start", 0)
				var b_end: int = (b as Dictionary).get("end", b_start)
				anim_fps = retimed_fps(fps, end_frame - start_frame + 1, b_end - b_start + 1)
		sprite_frames.set_animation_speed(anim_name, anim_fps)
		sprite_frames.set_animation_loop(anim_name, anim_name == "idle")

		for frame_idx in range(start_frame, end_frame + 1):
			var col: int = frame_idx % cols_per_row
			var row: int = frame_idx / cols_per_row
			var atlas = AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(col * frame_width, row * frame_height, frame_width, frame_height)
			sprite_frames.add_frame(anim_name, atlas)

	if not has_usable_frames(sprite_frames):
		return null

	print("[SPRITES] Loaded monster sheet for '%s' (%d animations)" % [monster_id, usable_animation_count(sprite_frames)])
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


## The ONE place that knows a portrait's world rule — an avatar surface that builds the path
## itself serves medieval art in every world, which is how the menu shipped wrong
static func portrait_path(job_id: String, world: int = -1) -> String:
	var base: String = "res://assets/sprites/portraits/%s.png" % job_id
	var suffix: String = world_suffix(world)
	if suffix == "" or suffix == "medieval":
		return base
	var variant: String = "res://assets/sprites/portraits/%s_%s.png" % [job_id, suffix]
	return variant if ResourceLoader.exists(variant) else base


## Audio's vocabulary is not the sheet vocabulary: it says "medieval" where the sheets say
## "" (world 1 IS the artist's base art). Anything unrecognised also lands on base art.
static func _normalize_suffix(audio_suffix: String) -> String:
	return audio_suffix if audio_suffix in WORLD_SUFFIXES else ""


## A world costume is a RESKIN, not a re-timing. `fps` is authored per SHEET, so a dressed
## sheet with fewer frames than the artist's base runs the same animation in less time:
## measured 2026-09-16, the cleric's 7-frame idle breathes once every 0.875 s in world 1 and
## its 2-frame costume every 0.250 s in worlds 2-6 — the same character, 3.5x faster.
##
## It is not only cosmetic. Action sheets play once and BattleAnimator sequences combat on
## `animation_finished`, so a dressed attack with fewer frames would finish early and move the
## beat a fight lands on. Only idles are dressed today; this keeps the seam honest either way.
##
## Returns the base fps unchanged whenever there is nothing to match against — an undressed
## sheet, an equal frame count, or a base sheet that is not on disk.
## SpriteFrames.new() ships with a "default" animation, so a NAME count is always at least 1 and
## counts a pose nobody authored. Every caller wants animations that HAVE FRAMES; this is the owner.
static func usable_animation_count(sf: SpriteFrames) -> int:
	if sf == null:
		return 0
	var n: int = 0
	for anim_name in sf.get_animation_names():
		if sf.get_frame_count(anim_name) > 0:
			n += 1
	return n


static func has_usable_frames(sf: SpriteFrames) -> bool:
	return usable_animation_count(sf) > 0


## A costume with fewer frames than its base must take the SAME wall-clock time, not run fast.
static func retimed_fps(base_fps: float, frames: int, base_frames: int) -> float:
	if frames <= 0 or base_frames <= 0 or base_frames == frames:
		return base_fps
	return base_fps * float(frames) / float(base_frames)


static func dressed_fps(base_fps: float, sheet_path: String, base_sheet: String, frames: int, frame_width: int) -> float:
	if sheet_path == base_sheet or frames <= 0 or frame_width <= 0:
		return base_fps
	if not ResourceLoader.exists(base_sheet):
		return base_fps
	var base_tex := load(base_sheet) as Texture2D
	if base_tex == null:
		return base_fps
	return retimed_fps(base_fps, frames, base_tex.get_width() / frame_width)


static func _load_external_sheet(sheet_data: Dictionary, job_id: String) -> SpriteFrames:
	var base_path = sheet_data.get("path", "res://assets/sprites/jobs/%s" % job_id)
	var frame_width = sheet_data.get("frame_width", 32)
	var frame_height = sheet_data.get("frame_height", 32)
	# frame_count divides by this; dressed_fps already refuses it three lines on, and this site did not.
	if frame_width <= 0 or frame_height <= 0:
		return null
	var animations = sheet_data.get("animations", ["idle", "walk", "attack", "cast", "hit", "dead"])

	var sprite_frames = SpriteFrames.new()
	var loaded_any = false
	var suffix: String = world_suffix()

	for anim_name in animations:
		var base_sheet: String = "%s/%s.png" % [base_path, anim_name]
		var sheet_path: String = base_sheet
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

		var frame_count = texture.get_width() / frame_width

		sprite_frames.add_animation(anim_name)
		sprite_frames.set_animation_speed(anim_name,
			dressed_fps(float(sheet_data.get("fps", 8)), sheet_path, base_sheet, int(frame_count), int(frame_width)))
		# Rest poses loop (weak breathes like idle); action anims play once so animation_finished fires
		sprite_frames.set_animation_loop(anim_name, anim_name in ["idle", "victory", "weak"])

		for i in range(frame_count):
			var atlas = AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(i * frame_width, 0, frame_width, frame_height)
			sprite_frames.add_frame(anim_name, atlas)

		loaded_any = true

	return sprite_frames if loaded_any else null
