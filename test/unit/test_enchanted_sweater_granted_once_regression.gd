extends GutTest

## After the suburban Warden, world2_chapter3 plays on any map and hands the
## Cleric the Enchanted Sweater. Entering Maple Heights then plays
## world2_chapter4_garage, a second Oak Street sale that gives the same
## sweater again. The items menu showed Enchanted Sweater x2. It is a key
## item (category META). A second cutscene grant must not add another copy.
## A consumable granted the same way still stacks.

const STUB := "res://test/unit/_test_game_loop_stub.gd"
const SWEATER := "enchanted_sweater"
const CHAPTER3 := "res://data/cutscenes/world2_chapter3.json"
const GARAGE := "res://data/cutscenes/world2_chapter4_garage.json"

var _director: Node = null
var _stub: Node = null
var _host: Node = null
var _leader: Combatant = null
var _ally: Combatant = null
var _borrowed_leader: bool = false
var _prev_counts: Dictionary = {}


func before_each() -> void:
	_director = CutsceneDirector.new()
	add_child_autofree(_director)
	_director._replay = false
	_mount_party()


func after_each() -> void:
	_strip_extras()
	if _host != null and is_instance_valid(_host) and "party" in _host:
		if _ally != null and is_instance_valid(_ally):
			_host.party.erase(_ally)
			_ally.free()
		if not _borrowed_leader and _leader != null and is_instance_valid(_leader):
			_host.party.erase(_leader)
			_leader.free()
	if _stub != null and is_instance_valid(_stub):
		_stub.free()
	_director = null
	_stub = null
	_host = null
	_leader = null
	_ally = null
	_borrowed_leader = false
	_prev_counts = {}


func _mount_party() -> void:
	var existing := get_tree().root.get_node_or_null("GameLoop")
	var host: Node = existing
	if host == null:
		host = load(STUB).new()
		host.name = "GameLoop"
		get_tree().root.add_child(host)
		_stub = host
	_host = host
	if "party" in host and host.party.size() > 0:
		_leader = host.party[0]
		_borrowed_leader = true
	else:
		_leader = Combatant.new()
		_leader.combatant_name = "Sweater Probe"
		host.add_child(_leader)
		host.party.append(_leader)
	_ally = Combatant.new()
	_ally.combatant_name = "Sweater Ally"
	host.add_child(_ally)
	host.party.append(_ally)
	for item_id in [SWEATER, "potion"]:
		_prev_counts[item_id] = ItemSystem.party_item_count(host.party, item_id)


func _strip_extras() -> void:
	if _host == null or not is_instance_valid(_host) or not ("party" in _host):
		return
	for item_id in _prev_counts:
		var extra: int = ItemSystem.party_item_count(_host.party, item_id) - int(_prev_counts[item_id])
		while extra > 0:
			if not ItemSystem.take_party_item(_leader, _host.party, item_id):
				break
			extra -= 1


func _gained(item_id: String) -> int:
	if _host == null or not is_instance_valid(_host):
		return -1
	return ItemSystem.party_item_count(_host.party, item_id) - int(_prev_counts.get(item_id, 0))


func _read_steps(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	var steps = parsed.get("steps", [])
	return steps if steps is Array else []


func _collect_sweater_grants(steps: Array, out: Array) -> void:
	for step in steps:
		if typeof(step) != TYPE_DICTIONARY:
			continue
		var kind := str(step.get("type", ""))
		if (kind == "give_item" or kind == "grant_item") and str(step.get("item", "")) == SWEATER:
			out.append(step)
		if step.get("steps") is Array:
			_collect_sweater_grants(step["steps"], out)
		var cases = step.get("cases", null)
		if cases is Dictionary:
			for key in cases.keys():
				if cases[key] is Array:
					_collect_sweater_grants(cases[key], out)
		var options = step.get("options", null)
		if options is Array:
			for opt in options:
				if opt is Dictionary and opt.get("steps") is Array:
					_collect_sweater_grants(opt["steps"], out)


func _sweater_grants() -> Array:
	var out: Array = []
	_collect_sweater_grants(_read_steps(CHAPTER3), out)
	_collect_sweater_grants(_read_steps(GARAGE), out)
	return out


## Applies the steps and returns how many of item_id the party gained. An abort returns 0.
func _landed(steps: Array, item_id: String) -> int:
	for step in steps:
		if typeof(step) != TYPE_DICTIONARY:
			return -1
		if str(step.get("type", "")) == "give_item":
			_director._step_give_item(step)
		else:
			_director._add_item_to_party_leader(str(step.get("item", "")), int(step.get("quantity", 1)))
	return _gained(item_id)


func test_both_oak_street_scenes_leave_one_sweater() -> void:
	var grants := _sweater_grants()
	assert_eq(grants.size(), 2,
		"chapter 3 and the Maple Heights garage sale both still hand over the Enchanted Sweater — the bag is what must stay at one")
	assert_eq(_landed(grants, SWEATER), 1,
		"playing both Oak Street scenes must leave one Enchanted Sweater, not two")


func test_a_second_potion_still_stacks() -> void:
	assert_eq(_landed([
		{"type": "give_item", "item": "potion", "quantity": 1},
		{"type": "give_item", "item": "potion", "quantity": 1},
	], "potion"), 2, "a consumable granted twice still stacks — the once-only rule is for key items")


## Moves the first sweater onto the ally, then grants again. Returns the party total gained.
func _sweater_held_off_the_leader() -> int:
	_director._step_give_item({"type": "give_item", "item": SWEATER, "quantity": 1})
	if _leader == null or not _leader.remove_item(SWEATER, 1):
		return -1
	_ally.add_item(SWEATER, 1)
	_director._step_give_item({"type": "give_item", "item": SWEATER, "quantity": 1})
	return _gained(SWEATER)


func test_a_sweater_held_off_the_leader_is_still_one() -> void:
	assert_eq(_sweater_held_off_the_leader(), 1,
		"the garage sale must not add a second sweater when someone other than the leader already carries it")
