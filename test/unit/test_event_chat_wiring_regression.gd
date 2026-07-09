extends GutTest

## Event-chat wiring guard (2026-07-09, +3 chats: tent_rules / share_code /
## fool_marks_three). Generalizes the unfireable-content class the Orrery
## chain had: every REGISTRY event chat must have (a) its cutscene JSON on
## disk with trigger == id, and (b) for event_flag_* unlocks, a LIVE
## fire_event_flag emitter somewhere in src/ — a chat nobody can unlock is
## authored-but-dead content.

const SCAN_DIRS := ["res://src"]


func _all_gd_sources() -> String:
	var out := ""
	var stack: Array = SCAN_DIRS.duplicate()
	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			var full := dir_path + "/" + f
			if dir.current_is_dir() and not f.begins_with("."):
				stack.append(full)
			elif f.ends_with(".gd"):
				out += FileAccess.get_file_as_string(full)
			f = dir.get_next()
	return out


func test_every_event_chat_is_reachable() -> void:
	var src := _all_gd_sources()
	var checked_files := 0
	var checked_flags := 0
	# 2026-07-09 extension: EVERY registry id (chapter + world chats too, not
	# just event_chat_*) must have its cutscene file — verified all 37+ hold.
	for id in PartyChatSystem.REGISTRY.keys():
		var path := "res://data/cutscenes/%s.json" % id
		assert_true(FileAccess.file_exists(path), "%s registered but %s missing — dead menu entry" % [id, path])
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		assert_eq(typeof(data), TYPE_DICTIONARY, "%s must parse" % path)
		# trigger==id is the convention for event/pc chats; legacy chapter
		# chats carry breadcrumb triggers (runtime-inert, cutscenes-lane ruling)
		if str(id).begins_with("event_chat_") or "_pc_" in str(id):
			assert_eq(str(data.get("trigger", "")), str(id), "%s trigger must equal its id" % id)
		checked_files += 1
		for flag in PartyChatSystem.REGISTRY[id].get("unlock", []):
			if not str(flag).begins_with("event_flag_"):
				continue  # cutscene_flag_* unlocks come from the completion machinery
			checked_flags += 1
			assert_true(("fire_event_flag(\"%s\"" % flag) in src,
				"chat %s unlocks on %s but NO fire_event_flag emitter exists in src/ — the chat can never unlock" % [id, flag])
	assert_gt(checked_files, 35, "sanity: the FULL chat roster was scanned (37 pre-W2 + 3 W2)")
	assert_gt(checked_flags, 5, "sanity: event_flag unlocks were emitter-checked")


func test_new_chats_registered() -> void:
	for id in ["event_chat_tent_rules", "event_chat_share_code", "event_chat_fool_marks_three"]:
		assert_true(PartyChatSystem.REGISTRY.has(id), "%s in REGISTRY" % id)
