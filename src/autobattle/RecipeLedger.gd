extends RefCounted
class_name RecipeLedger

## Per-character progress toward autobattle recipes. Counts MANUAL choices only: an autobattle or
## autogrind turn earning a card would let the script teach itself. Unwired until the spec lands;
## the seam is `ledger.record(actor_id, matcher.match(choice), is_manual)`.

signal recipe_earned(actor_id: String, recipe_id: String)

## actor_id -> {recipe_id: count}. A count stops at its recipe's threshold.
var _counts: Dictionary = {}
## actor_id -> recipe ids in the order they were earned.
var _earned: Dictionary = {}


## Counts each known recipe once for this choice. Returns the ids this call EARNED, in order.
## `is_manual` has no default on purpose: a caller that forgets it must not count.
func record(actor_id: String, recipe_ids: Array, is_manual: bool) -> Array[String]:
	var newly: Array[String] = []
	if not is_manual or actor_id == "":
		return newly
	var seen: Dictionary = {}
	for raw in recipe_ids:
		var rid := str(raw)
		if seen.has(rid):
			continue
		seen[rid] = true
		var need := RecipeCatalog.threshold(rid)
		if need <= 0 or is_earned(actor_id, rid):
			continue
		var counts: Dictionary = _counts.get(actor_id, {})
		counts[rid] = mini(int(counts.get(rid, 0)) + 1, need)
		_counts[actor_id] = counts
		if counts[rid] >= need:
			_mark_earned(actor_id, rid)
			newly.append(rid)
	for rid in newly:
		recipe_earned.emit(actor_id, rid)
	return newly


func count(actor_id: String, recipe_id: String) -> int:
	return int(_counts.get(actor_id, {}).get(recipe_id, 0))


func is_earned(actor_id: String, recipe_id: String) -> bool:
	return (_earned.get(actor_id, []) as Array).has(recipe_id)


func earned(actor_id: String) -> Array[String]:
	var out: Array[String] = []
	for rid in _earned.get(actor_id, []):
		out.append(str(rid))
	return out


## The dict RecipeReveal.show takes (cutscenes 27029): text from the catalog, progress from here.
func reveal_dict(actor_id: String, recipe_id: String) -> Dictionary:
	var r := RecipeCatalog.find(recipe_id)
	if r.is_empty():
		return {}
	return {
		"name": str(r.get("name", recipe_id)),
		"line": str(r.get("line", "")),
		"flavour": str(r.get("flavour", "")),
		"rarity": str(r.get("rarity", RecipeCatalog.DEFAULT_RARITY)),
		"icon_key": "icon_" + recipe_id,
		"progress": count(actor_id, recipe_id),
		"threshold": int(r["threshold"]),
	}


## New Game: no character keeps a card from the last run.
func reset() -> void:
	_counts.clear()
	_earned.clear()


func to_dict() -> Dictionary:
	return {"counts": _counts.duplicate(true), "earned": _earned.duplicate(true)}


## JSON-safe load: ints arrive as floats and arrays untyped, so every value is coerced.
## Ids the catalog no longer has are dropped; a count at or past a LOWERED threshold earns on load.
func from_dict(data: Dictionary) -> void:
	reset()
	var raw_counts = data.get("counts", {})
	if raw_counts is Dictionary:
		for actor in raw_counts:
			var per = raw_counts[actor]
			if not (per is Dictionary):
				continue
			for rid in per:
				var need := RecipeCatalog.threshold(str(rid))
				if need <= 0:
					continue
				var c := mini(int(per[rid]), need)
				if c <= 0:
					continue
				var counts: Dictionary = _counts.get(str(actor), {})
				counts[str(rid)] = c
				_counts[str(actor)] = counts
				if c >= need:
					_mark_earned(str(actor), str(rid))
	var raw_earned = data.get("earned", {})
	if raw_earned is Dictionary:
		for actor in raw_earned:
			var list = raw_earned[actor]
			if not (list is Array):
				continue
			for rid in list:
				if RecipeCatalog.threshold(str(rid)) > 0:
					_mark_earned(str(actor), str(rid))


func _mark_earned(actor_id: String, recipe_id: String) -> void:
	var list: Array = _earned.get(actor_id, [])
	if not list.has(recipe_id):
		list.append(recipe_id)
	_earned[actor_id] = list
	## An earned card always reads full, so a save whose counts were lost cannot show "3/10" on it.
	var counts: Dictionary = _counts.get(actor_id, {})
	counts[recipe_id] = RecipeCatalog.threshold(recipe_id)
	_counts[actor_id] = counts
