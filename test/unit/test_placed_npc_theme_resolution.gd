extends GutTest

## Every NPC standing in the world must have a dialogue palette of their own.
##
## `CutsceneDialogue.resolve_theme()` is total by construction — direct hit, then
## THEME_ALIASES, then `CHARACTER_THEMES["narrator"]`. Nothing ever fails, so a
## theme name nobody gave a palette to does not error: it renders in the
## NARRATOR's colours, which look deliberate. A merchant who speaks in the
## narrator's palette is indistinguishable from a merchant whose palette is grey.
##
## cowir-cutscenes already guards the alias table on its own terms (dangling
## targets, aliases shadowed by a real palette). What nothing checked is the other
## end — whether the names actually PLACED IN THE WORLD reach a palette. That
## corpus is src/maps and src/exploration, which is this lane's.
##
## THREE placement surfaces, and the second and third are the interesting ones:
##   OverworldNPC.npc_type          BaseVillage._create_npc
##   WanderingNPC.dialogue_theme    BaseVillage._create_wandering_npc
##   WanderingNPC.dialogue_theme    OverworldScene:683 — assigned from the SPRITE
##                                  ARCHETYPE, a different vocabulary entirely
##
## That third one is the reason this guard is worth its runtime. Its own comment
## says "CutsceneDialogue safely falls back if the theme key doesn't exist" — the
## author knowingly routed one vocabulary into another across a silent fallback.
## It works today only because "traveler" happens to have an alias; the next
## archetype someone adds gets the narrator palette and no error anywhere.
##
## Assert RESOLUTION, never MEMBERSHIP. `resolve_theme` deliberately accepts
## aliased names that will never be CHARACTER_THEMES keys — "soldier", "pilgrim",
## "traveler", "dancer" all resolve and none is a key. A membership check would go
## red on 14 correct roles and hand its inheritor a suppression list.
##
## DRIVEN, not parsed: names are read off constructed scenes, so a placement made
## by a constructor argument, a loop, or a table is caught the same as one written
## `npc_type = "..."`. A source scan for the literal assignment finds 8 types and
## misses every wanderer in the overworld table.

var _dialogue: Node = null


func before_all() -> void:
	_dialogue = load("res://src/cutscene/CutsceneDialogue.gd").new()


func after_all() -> void:
	if _dialogue != null:
		_dialogue.free()
		_dialogue = null


func _isolated_viewport() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	add_child_autofree(vp)
	return vp


## Derived by CONTENT: anything that calls a placement helper or constructs an NPC
## directly. A new map is covered on arrival; the NPC class files themselves are
## definitions, not placements, so they are excluded by name.
func _placement_scripts() -> Array:
	const MARKERS := ["_create_npc(", "_create_wandering_npc(", "WanderingNPC.new()",
		"WanderingNPCScript.new()", "OverworldNPCScript.new()", "OverworldNPC.new()"]
	const NOT_PLACEMENTS := ["OverworldNPC.gd", "WanderingNPC.gd", "BaseVillage.gd"]
	var out: Array = []
	var stack: Array = ["res://src/exploration", "res://src/maps"]
	while not stack.is_empty():
		var d: String = stack.pop_back()
		var dir := DirAccess.open(d)
		if dir == null:
			continue
		for sub in dir.get_directories():
			stack.append(d + "/" + sub)
		for f in dir.get_files():
			if not f.ends_with(".gd") or f in NOT_PLACEMENTS:
				continue
			var src: String = FileAccess.get_file_as_string(d + "/" + f)
			for m in MARKERS:
				if src.contains(m):
					out.append(d + "/" + f)
					break
	out.sort()
	return out


func _collect(root: Node, into: Array) -> void:
	for child in root.get_children():
		if child is OverworldNPC or child is WanderingNPC:
			into.append(child)
		_collect(child, into)


## The control: prove the narrator fallback is both reachable and distinguishable.
## Without it, "nothing fell back" is equally consistent with a resolver that
## cannot fall back, or one that returns narrator for everything.
func test_the_narrator_fallback_is_reachable_and_detectable() -> void:
	assert_not_null(_dialogue, "CutsceneDialogue instantiated")
	var narrator: Dictionary = _dialogue.resolve_theme("narrator")
	assert_gt(narrator.size(), 0,
		"the narrator theme is non-empty — an empty one would make every comparison below trivially equal")
	assert_eq(_dialogue.resolve_theme("zzz_not_a_real_theme"), narrator,
		"a fabricated name must land on narrator — if it did not, the sweep below could never detect an unthemed NPC")
	assert_ne(_dialogue.resolve_theme("merchant"), narrator,
		"a known-themed name must NOT equal narrator — without this half, a resolver returning narrator for everything still passes the line above")


## Aliased roles resolve without being keys. Pinned so nobody 'simplifies' this
## file into a membership check later.
func test_resolution_accepts_aliases_that_are_not_keys() -> void:
	var narrator: Dictionary = _dialogue.resolve_theme("narrator")
	var checked := 0
	for alias in ["soldier", "pilgrim", "traveler", "dancer"]:
		assert_ne(_dialogue.resolve_theme(alias), narrator,
			"'%s' is an aliased role with no palette of its own and must still resolve — this is why the sweep asserts resolution, not membership" % alias)
		checked += 1
	assert_eq(checked, 4, "drove every alias probe — a short count means the loop died partway")


func test_every_placed_npc_resolves_to_a_real_palette() -> void:
	var files := _placement_scripts()
	assert_gt(files.size(), 0, "found scripts that place NPCs — zero would pass this file for free")
	var narrator: Dictionary = _dialogue.resolve_theme("narrator")

	var seen := 0
	var files_yielding := 0
	var names := {}
	var offenders: Array = []

	for path in files:
		var script = load(path)
		if script == null:
			continue
		var node = script.new()
		if node == null or not (node is Node):
			if node is Node:
				node.free()
			continue
		_isolated_viewport().add_child(node)
		await get_tree().process_frame

		var found: Array = []
		_collect(node, found)
		if not found.is_empty():
			files_yielding += 1
		for npc in found:
			# Two surfaces, one contract: whatever string reaches say() must resolve.
			var theme: String = str(npc.npc_type) if npc is OverworldNPC else str(npc.dialogue_theme)
			if theme == "":
				continue
			seen += 1
			names[theme] = int(names.get(theme, 0)) + 1
			if theme == "narrator":
				continue
			if _dialogue.resolve_theme(theme) == narrator:
				offenders.append("%s: an NPC placed with theme '%s' has no palette and no alias — it speaks in the NARRATOR's colours, which reads as deliberate" % [path.get_file(), theme])

	assert_gt(seen, 0,
		"built %d placement scripts and found ZERO NPC nodes — the placement pattern changed and this sweep is now blind" % files.size())
	assert_gt(files_yielding, 1,
		"only %d script yielded NPCs — too few for this to be a sweep" % files_yielding)
	assert_gt(names.size(), 1,
		"saw only %d distinct theme name across %d NPCs — a single-name corpus cannot exercise the resolver" % [names.size(), seen])
	assert_true(offenders.is_empty(),
		"%d of %d placed NPC(s) fall through to the narrator palette:\n  %s" % [
			offenders.size(), seen, "\n  ".join(offenders)])
