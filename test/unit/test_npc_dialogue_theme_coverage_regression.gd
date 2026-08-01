extends GutTest

## Regression 2026-08-01: 24 of 156 placed NPCs spoke through the NARRATOR box.
##
## OverworldNPC passes `"theme": npc_type` into the dialogue entry, and the lookup was
## CHARACTER_THEMES.get(theme_name, CHARACTER_THEMES["narrator"]) — a silent fallback
## with no error and no log line. 16 of the 25 placed npc_types had no palette, so a
## blacksmith, a knight and four children all got the cold blue-grey narrator styling
## instead of a character box. Nothing failed; it just looked wrong.
##
## Two things are pinned here, and the SECOND is the one that nearly shipped:
##   1. every placed npc_type must resolve to something other than the narrator fallback
##   2. every THEME_ALIASES target must itself be a real CHARACTER_THEMES key
##
## (2) exists because the first proposed alias set had `knight -> soldier` and
## `bartender -> innkeeper`, and `soldier` was itself one of the missing 16 while
## `innkeeper` is not a theme at all — it is a SPRITE archetype. Aliasing into the hole
## is invisible at the call site: it returns the same grey box the fix was removing, so
## the fix reads as complete while 8 NPCs stay broken. Two lanes endorsed that set.
##
## Read via get_script_constant_map(), never a regex — a source-text scan of this table
## counts each theme's inner "bg"/"border" keys as theme names (measured: 32 vs 27).

const DIALOGUE := "res://src/cutscene/CutsceneDialogue.gd"
const SRC_DIR := "res://src"


func _consts() -> Dictionary:
	var script := load(DIALOGUE)
	assert_not_null(script, "CutsceneDialogue must load — it owns CHARACTER_THEMES")
	return script.get_script_constant_map()


func _themes() -> Dictionary:
	return _consts().get("CHARACTER_THEMES", {})


func _aliases() -> Dictionary:
	return _consts().get("THEME_ALIASES", {})


## Every npc_type passed to _create_npc anywhere under src/, with one placement name each.
func _placed_types() -> Dictionary:
	var out: Dictionary = {}
	var rx := RegEx.new()
	rx.compile('_create_npc\\(\\s*"([^"]+)"\\s*,\\s*"([a-z_0-9]+)"')
	for path in _gd_files(SRC_DIR):
		for m in rx.search_all(FileAccess.get_file_as_string(path)):
			if not out.has(m.get_string(2)):
				out[m.get_string(2)] = "%s (%s)" % [m.get_string(1), path.get_file()]
	return out


func _gd_files(dir_path: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append("%s/%s" % [dir_path, f])
	for sub in d.get_directories():
		out.append_array(_gd_files("%s/%s" % [dir_path, sub]))
	return out


func test_every_placed_npc_type_resolves_to_its_own_theme() -> void:
	# THE regression. Narrator styling on a townsperson is the visible symptom.
	var dlg = load(DIALOGUE).new()
	add_child_autofree(dlg)
	var placed := _placed_types()
	assert_gt(placed.size(), 10,
		"POSITIVE CONTROL: the sweep must find placed npc_types — a small number makes everything below vacuous")
	var narrator: Dictionary = _themes().get("narrator", {})
	assert_false(narrator.is_empty(), "PRECONDITION: the narrator theme must exist to compare against")
	var greyed: Array = []
	for npc_type in placed:
		if npc_type == "narrator":
			continue
		if dlg.resolve_theme(npc_type) == narrator:
			greyed.append("%s -> %s" % [npc_type, placed[npc_type]])
	assert_eq(greyed.size(), 0,
		"these placed npc_types fall back to the NARRATOR box — give them a CHARACTER_THEMES palette or a THEME_ALIASES entry: %s" % str(greyed))


func test_every_alias_target_is_a_real_theme() -> void:
	# The defect that nearly shipped: an alias into another missing name is INVISIBLE,
	# because the call site returns the same narrator box either way.
	var themes := _themes()
	var aliases := _aliases()
	assert_gt(aliases.size(), 0,
		"POSITIVE CONTROL: THEME_ALIASES must be readable — if it was renamed this test proves nothing")
	var dangling: Array = []
	for src_type in aliases:
		if not themes.has(str(aliases[src_type])):
			dangling.append("%s -> %s" % [src_type, aliases[src_type]])
	assert_eq(dangling.size(), 0,
		"these aliases point at names that are NOT CHARACTER_THEMES keys, so they still render narrator-grey while looking fixed: %s" % str(dangling))


func test_an_alias_never_shadows_a_real_palette() -> void:
	# If a role gains its own palette later, the alias is dead weight that reads as
	# intent. The resolver prefers the real one; this makes the leftover visible.
	var themes := _themes()
	var redundant: Array = []
	for src_type in _aliases():
		if themes.has(str(src_type)):
			redundant.append(str(src_type))
	assert_eq(redundant.size(), 0,
		"these roles now have their OWN CHARACTER_THEMES palette, so their alias is stale — remove it: %s" % str(redundant))


func test_resolution_order_prefers_a_real_palette_over_an_alias() -> void:
	# Order-independence is the whole reason this merges cleanly with the sprite lane's
	# child/blacksmith palettes: whichever lands first, nobody renders grey.
	var dlg = load(DIALOGUE).new()
	add_child_autofree(dlg)
	var themes := _themes()
	assert_true(themes.has("guard"), "PRECONDITION: 'guard' must be a real theme for this test to mean anything")
	assert_eq(dlg.resolve_theme("guard"), themes["guard"],
		"a real palette must win directly, never route through an alias")
	assert_eq(dlg.resolve_theme("knight"), themes["guard"],
		"an aliased role must resolve to its target's palette")


func test_the_render_path_actually_uses_the_resolver() -> void:
	# BEHAVIOURAL, and the reason the rest of this file is not enough. Every other test
	# here calls resolve_theme() directly, so reverting the CALL SITE back to
	# CHARACTER_THEMES.get(theme_name, narrator) leaves them all green — measured: 5/5
	# passing with the bug fully restored. This drives _show_current_line() and reads the
	# colour that actually reaches the screen.
	var dlg = load(DIALOGUE).new()
	add_child_autofree(dlg)
	await get_tree().process_frame
	var themes := _themes()
	dlg._dialogue_queue = [{"text": "x", "speaker": "Sir Test", "theme": "knight"}]
	dlg._current_index = 0
	dlg._show_current_line()
	# _ready() paints a narrator box first, and _create_dialogue_visuals clears children
	# with queue_free() — which is DEFERRED, so the stale narrator ColorRect is still a
	# child here and reading the first one measures the previous line's theme.
	var painted := Color(0, 0, 0, 0)
	for child in dlg._dialogue_box.get_children():
		if child is ColorRect and not child.is_queued_for_deletion():
			painted = child.color
			break
	assert_ne(painted, Color(0, 0, 0, 0),
		"PRECONDITION: the render path must paint a background, or this test cannot tell the themes apart")
	assert_eq(painted, themes["guard"]["bg"],
		"a 'knight' entry must render the GUARD palette on screen — if this is the narrator colour the call site stopped using resolve_theme()")
	assert_ne(painted, themes["narrator"]["bg"],
		"the rendered box must not be narrator-grey — that is the exact regression, visible to the player")


func test_an_unknown_type_still_falls_back_rather_than_crashing() -> void:
	# NEGATIVE CONTROL. The fallback must survive — removing it would turn a cosmetic
	# bug into a crash, and an unmapped type must NOT silently equal a real palette.
	var dlg = load(DIALOGUE).new()
	add_child_autofree(dlg)
	var themes := _themes()
	assert_eq(dlg.resolve_theme("zzz_not_a_role"), themes["narrator"],
		"an unknown theme must still return the narrator styling rather than null")
	assert_ne(dlg.resolve_theme("zzz_not_a_role"), themes["villager"],
		"an unknown theme must not resolve to a real palette — that would make this whole audit unfalsifiable")
