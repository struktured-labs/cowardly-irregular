extends GutTest

## A LEDGER, not an allowlist, and the difference is the direction it can move.
##
## ui_up/ui_down bind the left stick's Y axis and ui_left/ui_right its X axis, alongside the d-pad.
## An axis carries no echo flag, so a stick push emits one event per value change and every one
## reads as pressed — measured, 5 cursor steps on one nudge. `MenuNav.step()` latches it; a menu
## reading `is_action_pressed("ui_up")` raw still over-steps.
##
## Twenty-six surfaces still read raw. Converting them is mechanical but not free — several own two
## lists or a mode switch — so they are DECLARED here rather than left invisible. What this file
## defends is the DIRECTION:
##   · a NEW surface may not silently join the unconverted set
##   · a CONVERTED surface may not stay on the list, so the list cannot outlive its fact
##   · a surface may not be HALF converted — routed and still reading raw beside it
##
## @cowir-cutscenes has claimed DialogueChoiceMenu + CutsceneGallery, @cowir-music the JukeboxMenu.
## DialogueChoiceMenu is the severe one: four options, a five-row cursor, and it refuses cancel, so
## an overshoot cannot be backed out of — only confirmed.

const RAW_UP := 'is_action_pressed("ui_up")'
const RAW_DOWN := 'is_action_pressed("ui_down")'

## Measured 2026-09-16. Shrinks only.
const KNOWN_UNCONVERTED := [
	"res://src/cutscene/CutsceneDialogue.gd",
	"res://src/llm/DialogueChoiceMenu.gd",
	"res://src/ui/AbilitiesMenu.gd",
	"res://src/ui/BossSelectorMenu.gd",
	"res://src/ui/CharacterCreationScreen.gd",
	"res://src/ui/ControlsMenu.gd",
	"res://src/ui/CutsceneGallery.gd",
	"res://src/ui/FormationsMenu.gd",
	"res://src/ui/GameOverScreen.gd",
	"res://src/ui/HowToPlayOverlay.gd",
	"res://src/ui/ItemsMenu.gd",
	"res://src/ui/JobMenu.gd",
	"res://src/ui/JukeboxMenu.gd",
	"res://src/ui/LensMenu.gd",
	"res://src/ui/OverworldMenu.gd",
	"res://src/ui/PartyChatMenu.gd",
	"res://src/ui/QuestLog.gd",
	"res://src/ui/RadialPicker.gd",
	"res://src/ui/RebalanceReviewPanel.gd",
	"res://src/ui/SaveScreen.gd",
	"res://src/ui/TitleScreen.gd",
	"res://src/ui/Win98Menu.gd",
	"res://src/ui/WorldMapMenu.gd",
	"res://src/ui/autobattle/AutobattleGridEditor.gd",
	"res://src/ui/autogrind/AutogrindGridEditor.gd",
	"res://src/ui/autogrind/AutogrindUI.gd",
]


func _gd_files(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			out.append_array(_gd_files(full))
		elif name.ends_with(".gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	return out


## The helper itself names the actions in its DIRECTIONS const; it is the owner, not a consumer.
func _scan() -> Dictionary:
	var GdSource = load("res://test/unit/helpers/gd_source.gd")
	var raw: Array = []
	var converted: Array = []
	var scanned := 0
	for path in _gd_files("res://src"):
		if path.ends_with("MenuNav.gd"):
			continue
		var code: String = GdSource.code_of(path)
		if code == "":
			continue
		scanned += 1
		if code.contains(RAW_UP) or code.contains(RAW_DOWN):
			raw.append(path)
		if code.contains("MenuNav.step("):
			converted.append(path)
	return {"raw": raw, "converted": converted, "scanned": scanned}


func test_no_new_surface_joins_the_unconverted_set() -> void:
	var scan := _scan()
	assert_gt(scan["scanned"], 200, "the scan must read the src tree; a short corpus passes vacuously")
	var newcomers: Array = []
	for path in scan["raw"]:
		if not KNOWN_UNCONVERTED.has(path):
			newcomers.append(path)
	assert_eq(newcomers, [],
		"these read ui_up/ui_down raw and are not on the ledger — a stick push will over-step "
		+ "them by ~5 rows. Route them through MenuNav.step(): %s" % [newcomers])


func test_the_ledger_does_not_outlive_its_fact() -> void:
	var scan := _scan()
	var stale: Array = []
	for path in KNOWN_UNCONVERTED:
		if not scan["raw"].has(path):
			stale.append(path)
	assert_eq(stale, [],
		"these no longer read raw — delete them from KNOWN_UNCONVERTED rather than leaving a "
		+ "declaration that describes nothing: %s" % [stale])


## A surface routed through MenuNav must not keep a raw read beside it: the latch would gate one
## path while the other still bursts, which is worse than either alone because it looks converted.
func test_no_surface_is_half_converted() -> void:
	var scan := _scan()
	var half: Array = []
	for path in scan["converted"]:
		if scan["raw"].has(path):
			half.append(path)
	assert_eq(half, [],
		"these route through MenuNav AND still read raw — one path is latched and one is not: %s"
			% [half])


## ANTI-VACUITY, both directions: the scan must actually find both populations, or all three arms
## above pass over nothing.
func test_the_scan_finds_both_populations() -> void:
	var scan := _scan()
	assert_gt(scan["raw"].size(), 0, "the unconverted set must be non-empty while the migration runs")
	assert_gt(scan["converted"].size(), 0, "the converted set must be non-empty, or nothing uses the helper")
	assert_true(scan["converted"].has("res://src/ui/EquipmentMenu.gd"),
		"a known converted surface must be found, or the MenuNav probe is wrong")
	assert_true(scan["raw"].has("res://src/ui/ItemsMenu.gd"),
		"a known unconverted surface must be found, or the raw probe is wrong")
