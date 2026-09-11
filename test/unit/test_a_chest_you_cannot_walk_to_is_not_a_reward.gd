extends GutTest

## Harmonia's legend has declared `e = hedge (impassable decorative border)` since the village was
## written. TileGenerator carries the whole tile — palette, `_draw_village_hedge`, atlas slot 34, and
## an entry in `_get_impassable_types()` — and a comment stating it "is used in HarmoniaVillage's
## border". It was painted NOWHERE. A finished tile, shipped and never once on screen.
##
## It is now the formal border ringing Harmonia's verge, and a gap in the north run leads to a hedge
## nook holding `harmonia_chest_hedge_nook`.
##
## ⛔ THE GAP THAT MAKES THIS FILE NECESSARY. `test_village_global_reachability` floods the village
## with the real `_can_step` and proves every interactable is walkable-to — but `_interactables()`
## collects from `buildings`, `transitions`, `props` and `npcs`. **`treasures` is not in that list.**
## So a chest sealed behind geometry passes every test in the suite: the grid agrees with physics,
## the props block nothing, the flood is healthy, and the reward is unreachable forever. That is
## exactly the failure a secret nook invites, and nothing was watching for it.
##
## 🔑 Scope: this file owns CHESTS specifically, village-wide, plus the one-way-in property of the
## nook. It does not re-check what global_reachability already covers.

const TILE := 32.0
const PLAYER_HALF := 12.0
const INTERACT_REACH := 40.0  # OverworldController's flat-village press probe
const VGS := preload("res://test/unit/helpers/village_grid_source.gd")

## ScripturaPlaza's only chest is QUEST-GATED — _place_book_pickup() runs from _setup_npcs() solely
## while this flag is set and the quest is unfinished. A default instance has no chest at all, so
## the one chest in the corpus most likely to be sealed unnoticed is the one a plain sweep never
## sees. Armed here so it IS measured.
const GATED_CHEST_FLAG := "quest_world1_thirty_seven_favor_asked"

const HARMONIA := "res://src/maps/villages/HarmoniaVillage.gd"
const NOOK_CHEST := "harmonia_chest_hedge_nook"
const NOOK_THROAT := Vector2i(18, 2)  # the single gap in the row-2 hedge screen

const VILLAGE_SCRIPTS := [
	"res://src/maps/villages/HarmoniaVillage.gd",
	"res://src/maps/villages/SandriftVillage.gd",
	"res://src/maps/villages/EldertreeVillage.gd",
	"res://src/maps/villages/GrimhollowVillage.gd",
	"res://src/maps/villages/IronhavenVillage.gd",
	"res://src/maps/villages/FrostholdVillage.gd",
	"res://src/maps/villages/MapleHeightsVillage.gd",
	"res://src/maps/villages/MapleStripMall.gd",
	"res://src/maps/villages/BrasstonVillage.gd",
	"res://src/maps/villages/ScripturaPlaza.gd",
	"res://src/maps/villages/RivetRowVillage.gd",
	"res://src/maps/villages/NodePrimeVillage.gd",
	"res://src/maps/villages/VertexVillage.gd",
]


func _cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / TILE)), int(floor(pos.y / TILE)))


## Reachable set under the village's OWN `_can_step`, with `blocked` treated as solid.
func _flood(village, start: Vector2i, blocked: Dictionary) -> Dictionary:
	var seen := {start: true}
	var queue: Array = [start]
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + step
			if seen.has(n) or blocked.has(n):
				continue
			if village._can_step(cur, n):
				seen[n] = true
				queue.append(n)
	return seen


func _spawn_cell(v) -> Vector2i:
	var spawn: Vector2 = v.spawn_points.get("default", Vector2.ZERO) if "spawn_points" in v else Vector2.ZERO
	if spawn == Vector2.ZERO and v.has_method("_get_player_spawn_fallback"):
		spawn = v._get_player_spawn_fallback()
	return _cell_of(spawn)


## Press-A reach from a reachable cell — the semantics the probe actually uses. A chest is opened
## by pressing at it from an adjacent tile, never by standing on it.
func _probe_reaches(chest: Node2D, reachable: Dictionary) -> bool:
	var center: Vector2 = chest.global_position
	for cell in reachable:
		var stand := Vector2((cell.x + 0.5) * TILE, (cell.y + 0.5) * TILE)
		for facing in [Vector2(0, INTERACT_REACH), Vector2(0, -INTERACT_REACH), Vector2(INTERACT_REACH, 0), Vector2(-INTERACT_REACH, 0)]:
			if (stand + facing).distance_to(center) <= TILE:
				return true
	return false


func _chests(v) -> Array:
	var out: Array = []
	if not ("treasures" in v) or v.get("treasures") == null:
		return out
	for kid in v.get("treasures").get_children():
		if kid is Node2D and "chest_id" in kid:
			out.append(kid)
	return out


## THE TILE IS ON SCREEN. Source-level, because a runtime check cannot tell "drawn" from "declared".
func test_the_hedge_is_painted_not_merely_declared() -> void:
	var src := FileAccess.get_file_as_string(HARMONIA)
	assert_gt(src.length(), 1000, "PRECONDITION: HarmoniaVillage must be readable")
	var rows: Array = VGS.rows(src)
	assert_gt(rows.size(), 20, "PRECONDITION: the map_data parser must return real rows")
	var hedge := 0
	for r in rows:
		hedge += str(r).count("e")
	assert_gt(hedge, 80,
		"Harmonia paints %d hedge cells; the border ring alone is >80. The tile was finished and " % hedge +
		"painted nowhere for months — if this drops back toward zero it has gone dead again.")
	# CONTROL: the counter must be able to report a char ABSENT, or the arm above proves nothing.
	var absent := 0
	for r in rows:
		absent += str(r).count("Q")
	assert_eq(absent, 0, "CONTROL: an unused legend char must count zero")


## AND IT BLOCKS. Derived from the generator's own _get_impassable_types(), never a hand-list —
## the legend's word "impassable" is only true while VILLAGE_HEDGE stays in that return.
func test_the_hedge_blocks_by_the_generators_own_rule() -> void:
	var src := FileAccess.get_file_as_string(HARMONIA)
	var blocked: Dictionary = VGS.blocked_chars(src, [])
	assert_true(blocked.has("e"),
		"'e' must be a blocking char. The legend calls the hedge an impassable border and the nook " +
		"is only secret while it is one; drop VILLAGE_HEDGE from _get_impassable_types() and the " +
		"whole border becomes decorative grass with nothing red.")
	assert_true(blocked.has("W"), "CONTROL present: the stone wall must block")
	assert_false(blocked.has("g"), "CONTROL absent: village grass must NOT block")


## THE GAP. Every chest in every village, probe-reachable from the spawn under the real _can_step.
func test_every_chest_in_every_village_can_be_walked_to() -> void:
	var villages := 0
	var chests := 0
	var problems: Array = []
	var gs = get_node_or_null("/root/GameState")
	var had_flag: bool = gs.is_story_flag_set(GATED_CHEST_FLAG) if gs != null else false
	if gs != null:
		gs.set_story_flag(GATED_CHEST_FLAG, true)
	for path in VILLAGE_SCRIPTS:
		if not ResourceLoader.exists(path):
			continue
		var v = load(path).new()
		add_child(v)
		await get_tree().process_frame
		await get_tree().process_frame

		var vid: String = v._get_area_id() if v.has_method("_get_area_id") else path.get_file()
		var start := _spawn_cell(v)
		var mine := _chests(v)
		if mine.is_empty():
			v.queue_free()
			await get_tree().process_frame
			continue
		if not v._is_cell_walkable(start):
			problems.append("%s: SPAWN cell %s is not walkable" % [vid, str(start)])
			v.queue_free()
			await get_tree().process_frame
			continue

		var reachable := _flood(v, start, {})
		if reachable.size() < 30:
			problems.append("%s: flood reached only %d cells — the probe is broken, not the map" % [vid, reachable.size()])
			v.queue_free()
			await get_tree().process_frame
			continue

		villages += 1
		for c in mine:
			chests += 1
			if not _probe_reaches(c, reachable):
				problems.append("%s: chest '%s' at %s is sealed off — %d cells reachable from spawn, none of them adjacent" % [
					vid, str(c.get("chest_id")), str(_cell_of(c.global_position)), reachable.size()])
		v.queue_free()
		await get_tree().process_frame

	# Pinned to the MEASURED corpus (13 villages / 31 chests on b4d0bba9), not to a floor low enough
	# to survive a drain. gte, so adding a village or a chest is free and losing one is not.
	if gs != null:
		gs.set_story_flag(GATED_CHEST_FLAG, had_flag)
	# Pinned to the MEASURED corpus (13 villages / 31 chests on b4d0bba9) rather than to a floor low
	# enough to survive a drain. gte, so adding a village or a chest is free and losing one is not.
	# Without the flag armed above this reads 12 / 30 — which is how the gated chest stayed invisible.
	assert_gte(villages, 13, "only %d of 13 villages carried chests — the collector has gone blind, " % villages +
		"and a sweep that sees nothing reports nothing unreachable")
	assert_gte(chests, 31, "only %d chests were measured; 31 are authored. A drained corpus looks " % chests +
		"exactly like a clean sweep from the outside.")
	assert_eq(problems, [], "unreachable chests:\n  %s" % "\n  ".join(problems))


## THE NOOK IS A NOOK. One gap, and the reward is behind it. The negative arm is the whole point:
## a positive-only version passes just as happily if the north border is deleted entirely.
func test_the_hedge_nook_has_exactly_one_way_in() -> void:
	var v = load(HARMONIA).new()
	add_child(v)
	await get_tree().process_frame
	await get_tree().process_frame

	var chest: Node2D = null
	for c in _chests(v):
		if str(c.get("chest_id")) == NOOK_CHEST:
			chest = c
	assert_not_null(chest, "PRECONDITION: %s must exist, or every arm below is vacuous" % NOOK_CHEST)
	if chest == null:
		v.queue_free()
		return

	var start := _spawn_cell(v)
	var open := _flood(v, start, {})
	assert_true(_probe_reaches(chest, open),
		"POSITIVE: the nook chest must be reachable from the entrance — an easter egg nobody can " +
		"open is not content")

	var sealed := _flood(v, start, {NOOK_THROAT: true})
	assert_gt(sealed.size(), 30, "CONTROL: sealing one cell must not collapse the flood")
	assert_false(_probe_reaches(chest, sealed),
		"NEGATIVE: blocking %s alone must cut the nook off. If the chest is still reachable, the " % str(NOOK_THROAT) +
		"north hedge has another way in and the nook is a corridor, not a secret.")
	v.queue_free()


## THE HINT. The gap is a few pixels of grass in a hedge run; Flora is how a player learns it is
## there. Scoped to her four dialogue variants — a whole-file scan would pass on the map comment.
func test_flora_still_points_at_the_gap() -> void:
	var src := FileAccess.get_file_as_string(HARMONIA)
	var at := src.find("var _flora_pre :=")
	assert_gt(at, -1, "PRECONDITION: Flora's dialogue block must exist")
	var stop := src.find("var _flora_lines", at)
	assert_gt(stop, at, "PRECONDITION: the block must be bounded")
	var block := src.substr(at, stop - at)
	assert_eq(block.count("hedge"), 4,
		"each of Flora's four variants (pre/post x day/night) must name the hedge; she is the only " +
		"pointer to the gap, and a variant that drops it strands a player in that state: %d found" % block.count("hedge"))
	# CONTROL: the slice must really be her lines and not the whole file.
	assert_true(block.contains("La la la~"), "CONTROL: the slice must contain Flora's opening line")
	assert_false(block.contains("Dr. Temporal"), "CONTROL: the slice must stop before the next NPC")
