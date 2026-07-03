extends GutTest

## Permanent version of the tick-271/278/281 audits: a story flag that
## a gate READS but nothing ever WRITES is permanently-locked content
## (the QuestLog W2-W6 chapters and tracker objectives all shipped
## dead this way once). Scans quest prereqs/required_flags — the
## hand-authored, highest-churn reader surface — against every writer
## (cutscene set_flag steps, quest mirrors, src set_story_flag /
## fire_event_flag / completion-flag map).

const INTENTIONALLY_UNWRITTEN := [
	"quest_wiring_chicken_catch_ready",
	"quest_wiring_light_spell_ready",
]


func _collect_writers() -> Dictionary:
	var written: Dictionary = {}
	var dir := DirAccess.open("res://data/cutscenes")
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".json"):
			var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/cutscenes/" + f))
			if d is Dictionary:
				for s in d.get("steps", []):
					if s is Dictionary and str(s.get("type", "")) == "set_flag" and str(s.get("flag", "")) != "":
						written[str(s["flag"])] = true
		f = dir.get_next()
	var qdir := DirAccess.open("res://data/quests")
	qdir.list_dir_begin()
	f = qdir.get_next()
	while f != "":
		if f.ends_with(".json"):
			var q = JSON.parse_string(FileAccess.get_file_as_string("res://data/quests/" + f))
			if q is Dictionary:
				if str(q.get("flag_on_complete", "")) != "":
					written[str(q["flag_on_complete"])] = true
				for o in q.get("objectives", []):
					if o is Dictionary and str(o.get("flag_on_complete", "")) != "":
						written[str(o["flag_on_complete"])] = true
		f = qdir.get_next()
	var rx := RegEx.new()
	rx.compile("set_story_flag\\(\"([a-z0-9_]+)\"|fire_event_flag\\(\"([a-z0-9_]+)\"|game_constants\\[\"([a-z0-9_]+)\"\\]\\s*=|\"(cutscene_flag_[a-z0-9_]+)\"")
	for src_path in ["res://src/GameLoop.gd", "res://src/quests/QuestSystem.gd",
			"res://src/battle/BattleManager.gd", "res://src/exploration/OverworldPlayer.gd",
			"res://src/maps/dungeons/DragonCave.gd", "res://src/cutscene/PartyChatSystem.gd",
			"res://src/exploration/OverworldScene.gd", "res://src/exploration/SuburbanOverworld.gd",
			"res://src/exploration/SteampunkOverworld.gd", "res://src/exploration/IndustrialOverworld.gd",
			"res://src/exploration/FuturisticOverworld.gd", "res://src/exploration/AbstractOverworld.gd"]:
		var text := FileAccess.get_file_as_string(src_path)
		if text == "":
			continue
		for m in rx.search_all(text):
			for gi in range(1, 5):
				var g := m.get_string(gi)
				if g != "":
					written[g] = true
	return written


func _is_written(flag: String, written: Dictionary) -> bool:
	return written.has(flag) or written.has("cutscene_flag_" + flag) \
		or written.has(flag.trim_prefix("cutscene_flag_"))


func test_every_quest_gate_flag_has_a_writer() -> void:
	var written := _collect_writers()
	var dead: Dictionary = {}
	var qdir := DirAccess.open("res://data/quests")
	qdir.list_dir_begin()
	var f := qdir.get_next()
	while f != "":
		if f.ends_with(".json"):
			var q = JSON.parse_string(FileAccess.get_file_as_string("res://data/quests/" + f))
			if q is Dictionary:
				var qid: String = str(q.get("id", f))
				var prereq: String = str(q.get("prereq_flag", ""))
				if prereq != "" and prereq not in INTENTIONALLY_UNWRITTEN and not _is_written(prereq, written):
					dead[prereq] = qid
				for o in q.get("objectives", []):
					if not (o is Dictionary):
						continue
					var req: String = str(o.get("required_flag", ""))
					if req != "" and req not in INTENTIONALLY_UNWRITTEN and not _is_written(req, written):
						dead[req] = qid
		f = qdir.get_next()
	assert_eq(dead.size(), 0,
		"quest gate flags with NO writer anywhere (flag → quest): %s — that content is permanently locked" % str(dead))
