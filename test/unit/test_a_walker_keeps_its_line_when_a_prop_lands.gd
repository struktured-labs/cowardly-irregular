extends GutTest

const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const MapScripts := preload("res://test/unit/helpers/map_scripts.gd")

## deploy's .805 store recheck: Grimhollow's child walker left the shot and Frosthold showed a different villager,
## from props and examines that touched neither of them. Walkers were dealt runs by LIST INDEX, so one new blocked
## cell re-sorted the list and re-dealt the whole cast. cowir-main ruled it a defect (2026-11-15).

const VILLAGE_DIR := "res://src/maps/villages"

var _built: Array = []


func _ensure_built() -> void:
	if not _built.is_empty():
		return
	for path in MapScripts.maps_in(VILLAGE_DIR):
		var vp := SubViewport.new()
		vp.size = Vector2i(64, 64)
		vp.world_2d = World2D.new()
		add_child(vp)
		var village = load(path).new()
		vp.add_child(village)
		_built.append({"path": path, "village": village, "vp": vp})
	await get_tree().physics_frame


func after_all() -> void:
	for b in _built:
		(b["vp"] as Node).queue_free()
	_built.clear()
	SoundState.restore()


func _mid(run: Array) -> Vector2i:
	return (run[0] + run[1]) / 2


## Runs as their recorded lines, in roster order, so the derivation is judged against what the village built.
func _as_lines(v: Node, runs: Array) -> Array:
	var out: Array = []
	for r in runs:
		out.append([v._cell_centre(r[0]), v._cell_centre(r[1])])
	return out


func _recorded(v: Node) -> Array:
	var out: Array = []
	for spec in v._get_ambient_walkers():
		out.append(Array(v.ambient_walker_lines.get("Walker_%s" % str(spec["name"]).validate_node_name(), [])))
	return out


## Block one cell as a prop footprint would, derive with `derive`, then put the village back.
func _with_prop(v: Node, cell: Vector2i, derive: Callable) -> Array:
	var saved: Dictionary = v._prop_blocked
	v._prop_blocked = saved.duplicate()
	v._prop_blocked[cell] = true
	var out: Array = derive.call()
	v._prop_blocked = saved
	return out


func test_a_prop_on_one_walkers_line_moves_only_that_walker() -> void:
	await _ensure_built()
	var judged: int = 0
	for b in _built:
		var v = b["village"]
		var n: int = v._get_ambient_walkers().size()
		if n < 2:
			continue
		var vname: String = b["path"].get_file()
		var before: Array = v._stable_walker_runs(n)
		assert_eq(_as_lines(v, before), _recorded(v), "%s: the village built its walkers from this derivation" % vname)
		for k in before.size():
			var after: Array = _with_prop(v, _mid(before[k]), func(): return v._stable_walker_runs(n))
			assert_eq(after.size(), n, "%s: a prop on walker %d's line dropped a walker" % [vname, k])
			assert_ne(after[k] if k < after.size() else null, before[k], "CONTROL: %s: the prop at %s lands on walker %d's line" % [vname, str(_mid(before[k])), k])
			for j in mini(after.size(), before.size()):
				if j != k:
					assert_eq(after[j], before[j], "%s: a prop on walker %d's line moved walker %d" % [vname, k, j])
			judged += 1
	assert_gt(judged, 15, "CONTROL: walkers were judged (%d)" % judged)


func test_control_the_index_deal_re_dealt_the_cast() -> void:
	await _ensure_built()
	## The same prop under the old deal must move a bystander somewhere, or this file cannot see the defect it guards.
	var redealt: int = 0
	for b in _built:
		var v = b["village"]
		var n: int = v._get_ambient_walkers().size()
		if n < 2:
			continue
		var before: Array = v._walker_runs(n)
		for k in mini(n, before.size()):
			var after: Array = _with_prop(v, _mid(before[k]), func(): return v._walker_runs(n))
			for j in mini(n, before.size()):
				if j != k and (j >= after.size() or after[j] != before[j]):
					redealt += 1
					break
	assert_gt(redealt, 0, "the index deal re-dealt no bystander, so this file reproduces nothing")
