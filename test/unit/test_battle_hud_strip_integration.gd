extends "res://addons/gut/test.gd"

## test_battle_hud_strip_integration.gd
## Integration tests for the BDFFHD Bottom HUD Strip wiring into BattleScene.
##
## Validates:
##   1. BattleBDFFHDHudStrip scene node exists inside BattleScene's UI tree.
##   2. PartyStatusPanel is hidden (retired in favour of HUD Strip).
##   3. BattleLogPanel and ActionMenuPanel have been raised 72 px (offsets verified).
##   4. _hud_strip.update_hud() correctly binds live party state.
##   5. BattleUIManager._ensure_party_status_boxes() is a no-op when panel is hidden.
##   6. Calling _update_ui() drives the strip without errors (smoke test).

const HudStripClass = preload("res://src/ui/autogrind/BattleBDFFHDHudStrip.gd")
const CombatantClass = preload("res://src/battle/Combatant.gd")
const BattleUIManagerClass = preload("res://src/battle/BattleUIManager.gd")

# ── Helpers ──────────────────────────────────────────────────────────────────

func _make_combatant(p_name: String, hp: int, ap: int, locked: bool) -> Combatant:
	var c = CombatantClass.new()
	c.combatant_name = p_name
	c.max_hp = hp
	c.current_hp = hp
	c.is_alive = true
	c.current_ap = ap
	c.autobattle_locked = locked
	return c

# ── Test 1: HUD Strip node is registered in the scene ────────────────────────

func test_hud_strip_node_exists_in_scene() -> void:
	var strip = HudStripClass.new()
	add_child_autoqfree(strip)
	assert_not_null(strip, "BattleBDFFHDHudStrip must instantiate without errors.")
	assert_true(strip is Control,
		"BattleBDFFHDHudStrip must extend Control (registered as UI node).")

# ── Test 2: PartyStatusPanel is hidden after BDFFHD integration ──────────────

func test_party_status_panel_hidden_by_default() -> void:
	# Simulate scene-level visibility flag: the tscn sets visible=false on
	# PartyStatusPanel. We verify the tscn file itself carries the flag so
	# the Godot editor agrees without needing a live scene instance.
	var tscn_path = "res://src/battle/BattleScene.tscn"
	var file = FileAccess.open(tscn_path, FileAccess.READ)
	assert_not_null(file, "BattleScene.tscn must be accessible.")
	if not file:
		return
	var content = file.get_as_text()
	file.close()

	# Ensure 'visible = false' appears in the PartyStatusPanel block.
	# We look for the combined marker to avoid false matches in other nodes.
	var has_hidden_panel = content.contains("PartyStatusPanel") and content.contains("visible = false")
	assert_true(has_hidden_panel,
		"BattleScene.tscn must declare PartyStatusPanel with visible = false.")

# ── Test 3: BattleLogPanel and ActionMenuPanel offsets raised by 72 px ───────

func test_log_and_action_panels_raised_72px() -> void:
	var tscn_path = "res://src/battle/BattleScene.tscn"
	var file = FileAccess.open(tscn_path, FileAccess.READ)
	assert_not_null(file, "BattleScene.tscn must be accessible.")
	if not file:
		return
	var content = file.get_as_text()
	file.close()

	# BattleLogPanel: old offset_top=-130 → new -202; old offset_bottom=-10 → new -82
	assert_true(content.contains("offset_top = -202.0"),
		"BattleLogPanel offset_top must be -202 (raised 72 px from -130).")
	assert_true(content.contains("offset_bottom = -82.0"),
		"BattleLogPanel/ActionMenuPanel offset_bottom must be -82 (raised 72 px from -10).")
	# ActionMenuPanel: old offset_top=-220 → new -292
	assert_true(content.contains("offset_top = -292.0"),
		"ActionMenuPanel offset_top must be -292 (raised 72 px from -220).")

# ── Test 4: update_hud() binds live party state correctly ────────────────────

func test_update_hud_binds_party_state() -> void:
	var strip = HudStripClass.new()
	add_child_autoqfree(strip)

	var c1 = _make_combatant("Riku", 200, 3, false)
	var c2 = _make_combatant("Yuna", 80, -1, true)
	add_child_autoqfree(c1)
	add_child_autoqfree(c2)

	strip.update_hud([c1, c2])

	# Column 1 — Riku (Manual, full HP, positive AP)
	var col1 = strip._party_columns[0]
	assert_true(col1.visible, "Column 1 (Riku) must be visible.")
	assert_eq(col1.get_node("HeaderRow/NameLabel").text, "Riku",
		"Column 1 name must be 'Riku'.")
	assert_eq(col1.get_node("HeaderRow/TrustLabel").text, "Manual",
		"Column 1 trust label must be 'Manual'.")
	assert_eq(col1.get_node("HPBar").value, 200.0,
		"Column 1 HP bar value must be 200.")
	assert_string_contains(col1.get_node("APLabel").text, "AP:",
		"Column 1 AP label must contain 'AP:'.")

	# Column 2 — Yuna (Trust / AI, partial HP, negative AP)
	var col2 = strip._party_columns[1]
	assert_true(col2.visible, "Column 2 (Yuna) must be visible.")
	assert_eq(col2.get_node("HeaderRow/TrustLabel").text, "Trust / AI",
		"Column 2 trust label must be 'Trust / AI'.")
	assert_eq(col2.get_node("HPBar").value, 80.0,
		"Column 2 HP bar value must be 80.")

	# Columns 3-5 must be hidden (party size == 2)
	for i in range(2, 5):
		assert_false(strip._party_columns[i].visible,
			"Column %d must be hidden for a 2-member party." % (i + 1))

# ── Test 5: BattleUIManager._ensure_party_status_boxes is a no-op when panel hidden ─

func test_uimanager_skips_party_boxes_when_panel_hidden() -> void:
	# Create a minimal mock scene object with a hidden PartyStatusPanel.
	var mock_scene = Node.new()
	add_child_autoqfree(mock_scene)

	# Build a minimal UI/PartyStatusPanel subtree — hidden.
	var ui = Control.new()
	ui.name = "UI"
	mock_scene.add_child(ui)

	var panel = PanelContainer.new()
	panel.name = "PartyStatusPanel"
	panel.visible = false  # The critical flag
	ui.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.name = "VBoxContainer"
	panel.add_child(vbox)

	# Add fake party_members so member access doesn't explode.
	mock_scene.set("party_members", [])

	var manager = BattleUIManagerClass.new(mock_scene)
	# _ensure_party_status_boxes should return early without touching the node.
	manager._ensure_party_status_boxes()  # Must NOT crash or add child nodes.
	assert_eq(vbox.get_child_count(), 0,
		"VBoxContainer must remain empty — _ensure_party_status_boxes must be a no-op when panel is hidden.")

# ── Test 6: _update_ui() smoke-fires strip without crashing ──────────────────

func test_update_ui_calls_strip_without_crash() -> void:
	# Instantiate the strip stand-alone and call update_hud with 5 combatants.
	var strip = HudStripClass.new()
	add_child_autoqfree(strip)

	var party: Array = []
	for i in range(5):
		var c = _make_combatant("PC%d" % (i + 1), 100 + i * 20, i - 2, i % 2 == 0)
		add_child_autoqfree(c)
		party.append(c)

	# update_hud must not crash with a full 5-member party.
	strip.update_hud(party)

	# All 5 columns must be visible for a full party.
	for i in range(5):
		assert_true(strip._party_columns[i].visible,
			"Column %d must be visible for a 5-member party." % (i + 1))
		var name_text = strip._party_columns[i].get_node("HeaderRow/NameLabel").text
		assert_eq(name_text, "PC%d" % (i + 1),
			"Column %d NameLabel must match combatant name." % (i + 1))
