extends GutTest

## cowir-main 28523 / adhoc 28522 (2026-11-27): a `say` bubble hides on frame delta, so a load hitch can end it unread.
## No scene authors one yet; the cap is parked on lane/a-speech-bubble-outlasts-a-hitch. This reds the first `say` until it ships.

const DIR := "res://data/cutscenes"
const PARKED := "lane/a-speech-bubble-outlasts-a-hitch"


func _walk(node, file: String, out: Array, counts: Dictionary) -> void:
	if node is Dictionary:
		if node.has("type"):
			counts["steps"] += 1
			if str(node["type"]) == "say":
				out.append(file)
		for v in node.values():
			_walk(v, file, out, counts)
	elif node is Array:
		for v in node:
			_walk(v, file, out, counts)


func _say_files(counts: Dictionary) -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(DIR):
		if not f.ends_with(".json"):
			continue
		counts["files"] += 1
		_walk(JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [DIR, f])), f, out, counts)
	return out


func _cap_shipped() -> bool:
	var d := CutsceneDirector.new()
	autofree(d)
	return d.has_method("beat_step")


func test_no_say_step_is_authored_before_its_cap_ships() -> void:
	var counts := {"files": 0, "steps": 0}
	var says := _say_files(counts)
	assert_gt(counts["files"], 100, "CONTROL: the walk read the cutscene corpus, got %d files" % counts["files"])
	assert_gt(counts["steps"], 1000, "CONTROL: the walk reached nested steps, got %d" % counts["steps"])
	if _cap_shipped():
		pass_test("beat_step is on main, so a say step is safe to author")
		return
	assert_eq(says, [], "a say step is authored in %s, but its bubble can vanish unread after a load hitch: ship %s (cowir-cutscenes) in this fold" % [str(says), PARKED])


func test_the_walk_sees_a_say_where_one_is_planted() -> void:
	var out: Array = []
	var counts := {"files": 0, "steps": 0}
	_walk({"steps": [{"type": "wait"}, {"type": "branch", "then": [{"type": "say", "id": "milo"}]}]}, "planted.json", out, counts)
	assert_eq(out, ["planted.json"], "a say nested inside a branch is found")
	assert_eq(counts["steps"], 3, "every step is counted")
