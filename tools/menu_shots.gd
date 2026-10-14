extends SceneTree

## Shots of the menus NOTHING else renders. xvfb + opengl3, not --headless.
##
## Before this, three menus had any automated render at all — ItemsMenu, ShopScene and
## EquipmentMenu, all by tools/item_icon_screenshot.gd, which itself had no .sh wrapper and no
## invocation anywhere in the repo. Ten more had none, and the item flavour overflow fixed in
## 384b863fd was sitting in one of the three that did: a Label whose assigned width is lost when
## it enters a Control parent, so the text renders at content width and runs off the screen.
## That class is invisible to source review and to every headless guard; it needs a frame.
##
## Autoloads register after this script parses, so every menu is load()'d after two frames.
##
## `--text-scale=2.0` renders the whole set at a Text Size preset, because ten lanes shipped Text
## Size items in one day and the one defect no guard caught — an escalating effect whose level n+1
## trough beat level n's peak — was found by looking at pixels. The scale is verified against
## GameState after being set, and it goes in the filename.
##
## Covers sixteen screens. Still uncovered and worth adding when someone needs them: MenuScene (see
## below), ShopScene and EquipmentMenu (tools/item_icon_screenshot.gd has those), StatusMenu,
## and anything that needs a live battle.

## The scale every shot is taken at. 1.0 keeps the filenames and the pixels exactly as they were.
var _text_scale := 1.0


func _init() -> void:
	var out_dir := "res://tmp/menu_shots"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.get_slice("=", 1)
		elif a.begins_with("--text-scale="):
			_text_scale = float(a.get_slice("=", 1))
	DirAccess.make_dir_recursive_absolute(out_dir)
	await process_frame
	await process_frame

	## ⛔ A FLAG THAT SILENTLY DOES NOTHING IS WORSE THAN NO FLAG, because the shot it produces
	## looks fine and gets FILED as the scale you asked for. `TextScale.scaled()` resolves GameState
	## through the scene-tree root, so if the autoload is not up — or the field is not there — every
	## menu below would render at 1.0 and the PNG would carry a 2.0x name. Set it, READ IT BACK, and
	## refuse to save anything if the two disagree.
	if not is_equal_approx(_text_scale, 1.0):
		var gs := root.get_node_or_null("GameState")
		if gs == null or not ("text_size_scale" in gs):
			push_error("--text-scale=%s requested but GameState/text_size_scale is unreachable; "
				% _text_scale + "refusing to save shots that would be mislabelled")
			quit(1)
			return
		gs.text_size_scale = _text_scale
		var got: float = float(gs.text_size_scale)
		if not is_equal_approx(got, _text_scale):
			push_error("--text-scale=%s did not take (GameState reports %s) — it is clamped or "
				% [_text_scale, got] + "rejected; refusing to save mislabelled shots")
			quit(1)
			return
		print("SCREEN text_size_scale applied and verified: %s" % got)

	var pc = load("res://src/battle/Combatant.gd").new()
	pc.combatant_name = "Bram"
	pc.equipped_weapon = "returned_sword"
	root.add_child(pc)
	var js = root.get_node_or_null("JobSystem")
	if js != null and js.has_method("assign_job"):
		js.call("assign_job", pc, "fighter")
	await process_frame

	await _shoot(out_dir, "abilities_menu", func():
		var m = load("res://src/ui/AbilitiesMenu.gd").new()
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(m)
		m.setup(pc)
		return m)

	await _shoot(out_dir, "party_status", func():
		var m = load("res://src/ui/PartyStatusScreen.gd").new()
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(m)
		m.setup([pc])
		return m)

	## The autogrind and autobattle editors, the quest log and the bestiary. Added after the first
	## six found two defects: these four were rendered ad-hoc to check them, came back clean, and
	## then were covered by nothing {E} so a regression in them would be found by a player.
	await _shoot(out_dir, "autogrind_ui", func():
		var m = load("res://src/ui/autogrind/AutogrindUI.gd").new()
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(m)
		m.setup([pc], "Harmonia Fields")
		return m)

	await _shoot(out_dir, "autobattle_grid_editor", func():
		var m = load("res://src/ui/autobattle/AutobattleGridEditor.gd").new()
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(m)
		m.setup("bram", "Bram", pc, [pc])
		return m)

	await _shoot(out_dir, "quest_log", func():
		var m = load("res://src/ui/QuestLog.gd").new()
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(m)
		m.setup()
		return m)

	await _shoot(out_dir, "bestiary", func():
		var m = load("res://src/ui/BestiaryMenu.gd").new()
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(m)
		return m)

	## ⚠ MenuScene is NOT shot here. It reaches for @onready paths from its .tscn
	## ("BattlesLabel", "PartyPanel/MarginContainer/VBoxContainer/PartyList"), so a bare .new()
	## leaves them null and the script errors before anything renders. Shooting it needs the
	## packed scene; left out rather than left erroring, because a tool that prints SCRIPT ERROR
	## on every run teaches its reader to skip the errors.
	await _shoot(out_dir, "save_screen", func():
		var m = load("res://src/ui/SaveScreen.gd").new()
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(m)
		m.setup(0, [pc])
		return m)

	await _shoot(out_dir, "lens_menu", func():
		var m = load("res://src/ui/LensMenu.gd").new()
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		if "party" in m:
			m.party = [pc]
		root.add_child(m)
		return m)

	await _shoot(out_dir, "settings_menu", func():
		var m = load("res://src/ui/SettingsMenu.gd").new()
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(m)
		return m)

	## The longest authored item description, in the popup that shows one.
	await _shoot(out_dir, "key_item_popup", func():
		var host := Control.new()
		host.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(host)
		var longest := ""
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
		if parsed is Dictionary:
			var items: Variant = (parsed as Dictionary).get("items", parsed)
			if items is Dictionary:
				for k in (items as Dictionary):
					var v = (items as Dictionary)[k]
					if v is Dictionary:
						var d := str((v as Dictionary).get("description", ""))
						if d.length() > longest.length():
							longest = d
		load("res://src/ui/KeyItemPopup.gd").show_item(host, {
			"id": "probe", "name": "Probe Relic", "description": longest})
		return host)

	## The six screens still rendered by nothing. The first two are the first two screens a player
	## ever sees, and neither had any automated render until now.
	await _shoot(out_dir, "title_screen", func():
		var m = load("res://src/ui/TitleScreen.gd").new()
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(m)
		return m)

	await _shoot(out_dir, "character_creation", func():
		var m = load("res://src/ui/CharacterCreationScreen.gd").new()
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(m)
		return m)

	await _shoot(out_dir, "controls_menu", func():
		var m = load("res://src/ui/ControlsMenu.gd").new()
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(m)
		return m)

	await _shoot(out_dir, "job_menu", func():
		var m = load("res://src/ui/JobMenu.gd").new()
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(m)
		m.setup(pc)
		return m)

	## The rename flow, at its cap: a 20-char name is what AutogrindGridEditor allows.
	await _shoot(out_dir, "virtual_keyboard", func():
		var m = load("res://src/ui/VirtualKeyboard.gd").new()
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(m)
		m.setup("Rename Autogrind Profile", "Scriptweaver Profile", 20)
		return m)

	## Win98Menu is the BATTLE COMMAND MENU and the SHOP MENU — `BattleCommandMenu:136` and
	## `ShopScene:479` both instantiate it. An earlier version of this file claimed it was
	## unreachable and skipped it; that was wrong, and the cause is worth keeping: the grep behind
	## the claim was piped through `head -4`, which cut the results off at MenuScene (the one caller
	## that IS dead). A bounded search answered "none below my cutoff" and was read as "none".
	##
	## Items are Dictionaries, the shape ShopScene builds: {"id": ..., "label": ...}.
	await _shoot(out_dir, "win98_menu", func():
		var host := Control.new()
		host.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(host)
		var m = load("res://src/ui/Win98Menu.gd").new()
		m.battle_mode = true
		m.is_root_menu = true
		host.add_child(m)
		m.setup("Bram", [
			{"id": "attack", "label": "Attack"},
			{"id": "abilities", "label": "Abilities"},
			{"id": "items", "label": "Items"},
			{"id": "defend", "label": "Defend"},
			{"id": "run", "label": "Run"},
		], Vector2(80, 120), "fighter")
		return host)

	quit(0)


func _shoot(out_dir: String, name: String, build: Callable) -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.04, 0.05, 0.09)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)
	var node = build.call()
	for _i in 10:
		await process_frame
	## The scale goes in the FILENAME, so a 2.0x sweep cannot overwrite the 1.0x baseline and a
	## shot can never be confused for one taken at another size. 1.0 keeps the original names.
	var suffix := "" if is_equal_approx(_text_scale, 1.0) else "@%sx" % str(_text_scale)
	await _save(out_dir + "/" + name + suffix + ".png")
	if node != null and is_instance_valid(node):
		node.queue_free()
	backdrop.queue_free()
	await process_frame


func _save(path: String) -> void:
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	if img == null:
		push_error("no viewport image for %s" % path)
		return
	var err := img.save_png(path)
	print("SCREEN saved %s (%dx%d) err=%d" % [path, img.get_width(), img.get_height(), err])
