extends SceneTree

## The six screens of the font collage (main 24148): battle menu, a dialogue box, Settings, the overworld
## menu, a shop, the title; plus the quest log for long read text. xvfb + opengl3 via tools/uifont_shots.sh.
##   -- --out=res://tmp/uifont/after_default [--text-scale=1.0]
## The face is chosen by the environment, before the engine starts (UiFont.install reads it):
##   COWIR_UIFONT=off             the old face           COWIR_UIFONT_READ=pixel|default   the read tier

func _init() -> void:
	var out_dir := "res://tmp/uifont/shots"
	var text_scale := 1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.get_slice("=", 1)
		if a.begins_with("--text-scale="):
			text_scale = float(a.get_slice("=", 1))
	DirAccess.make_dir_recursive_absolute(out_dir)
	await process_frame
	await process_frame
	var gs = root.get_node_or_null("GameState")
	if gs != null:
		gs.text_size_scale = text_scale
	var uf = load("res://src/ui/UiFont.gd")
	var probe := Label.new()
	root.add_child(probe)
	var rt := RichTextLabel.new()
	root.add_child(rt)
	print("[UIFONT-SHOTS] installed=%s read_tier=%s text_scale=%.2f label_font=%s rich_font=%s h10=%.1f h12=%.1f h14=%.1f h16=%.1f h24=%.1f w(Attack)@12=%.1f" % [
		uf.is_installed(), uf.read_tier, text_scale, probe.get_theme_font("font").get_font_name(),
		rt.get_theme_font("normal_font").get_font_name(),
		probe.get_theme_font("font").get_height(10), probe.get_theme_font("font").get_height(12),
		probe.get_theme_font("font").get_height(14), probe.get_theme_font("font").get_height(16),
		probe.get_theme_font("font").get_height(24),
		probe.get_theme_font("font").get_string_size("Attack", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x])
	probe.queue_free()
	rt.queue_free()

	var pc = load("res://src/battle/Combatant.gd").new()
	pc.combatant_name = "Bram"
	pc.equipped_weapon = "returned_sword"
	root.add_child(pc)
	var js = root.get_node_or_null("JobSystem")
	if js != null and js.has_method("assign_job"):
		js.call("assign_job", pc, "fighter")
	await process_frame

	await _shoot(out_dir, "1_battle_menu", func():
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

	var dialogue := func():
		var d = load("res://src/cutscene/CutsceneDialogue.gd").new()
		root.add_child(d)
		d.show_dialogue([{"speaker": "Cleric", "theme": "cleric", "portrait": "cleric",
			"text": "The well was sealed before any of us were born. If the Chancellor wants it opened, ask what he thinks is still down there... and why he sent four strangers instead of his own guard."}])
		if d.has_method("_finish_typing"):
			d._finish_typing()
		return d
	await _shoot(out_dir, "2_dialogue", dialogue, 40)

	await _shoot(out_dir, "3_settings", func():
		var m = load("res://src/ui/SettingsMenu.gd").new()
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(m)
		return m)

	await _shoot(out_dir, "4_overworld_menu", func():
		var m = load("res://src/ui/OverworldMenu.gd").new()
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(m)
		m.setup([pc])
		return m)

	await _shoot(out_dir, "5_shop", func():
		var shop = load("res://src/exploration/ShopScene.gd").new()
		root.add_child(shop)
		var shelf: Array = load("res://src/exploration/VillageShop.gd").ITEM_INVENTORY.duplicate()
		shop.setup(0, "General Store", shelf)
		shop._open_buy_menu()
		return shop)

	await _shoot(out_dir, "6_title", func():
		var m = load("res://src/ui/TitleScreen.gd").new()
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(m)
		return m)

	await _shoot(out_dir, "7_quest_log", func():
		var m = load("res://src/ui/QuestLog.gd").new()
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(m)
		m.setup()
		return m)
	quit()


func _shoot(out_dir: String, name: String, build: Callable, frames: int = 12) -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.04, 0.05, 0.09)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)
	var node = build.call()
	for _i in frames:
		await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	if img == null:
		push_error("no viewport image for %s" % name)
	else:
		var path := out_dir + "/" + name + ".png"
		print("SCREEN saved %s (%dx%d) err=%d" % [path, img.get_width(), img.get_height(), img.save_png(path)])
	if node != null and is_instance_valid(node):
		node.queue_free()
	backdrop.queue_free()
	await process_frame
