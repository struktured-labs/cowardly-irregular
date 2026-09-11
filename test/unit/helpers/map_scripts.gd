extends RefCounted
## Which scripts in a map directory are MAPS, derived from their shape rather than from a skip list.
##
## Every sweep over src/maps/* has to answer this, and three of them answered it with a hand-kept
## array of filenames. Those lists were true when written and stay true only by someone rechecking:
## on 2026-09-11 a contact-sheet render of src/maps/dungeons showed BossTrigger.gd — an Area2D
## component — being instantiated as a dungeon and counted by a sweep's own CONTROL. The fleet had
## already audited that exact list out of test_every_dungeon_is_lit two days earlier.
##
## 🔑 The failure is silent in the direction that matters: a component dropped into a map directory
## gets BUILT and reported, and a new base gets SKIPPED forever. Both are invisible to a reader of
## the list, because a skip list cannot say which of its entries have stopped being true.
##
## THE RULE: a file is a map if its extends-chain roots at Node2D and no sibling extends it.
## Components root elsewhere (Area2D, RefCounted); bases are named as the parent of a sibling.
##
## test_every_dungeon_is_lit carries an equivalent derivation inline. Left alone deliberately — it is
## another lane's file and a working copy, and folding it into this helper is churn, not a fix.


## Absolute res:// paths of the map scripts in `dir`, sorted. Empty if the directory cannot be read.
static func maps_in(dir_path: String) -> Array:
	var files: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return files
	for f in dir.get_files():
		if f.ends_with(".gd"):
			files.append(f)

	var base_of := {}
	var extended := {}
	var rx := RegEx.new()
	rx.compile("(?m)^extends\\s+(\\w+)")
	for name in files:
		var m := rx.search(FileAccess.get_file_as_string("%s/%s" % [dir_path, name]))
		base_of[name] = (m.get_string(1) if m != null else "")
		for other in files:
			if other != name and base_of[name] == other.get_basename():
				extended[other] = true

	var out: Array = []
	for name in files:
		if extended.has(name):
			continue
		var cur: String = name
		var root: String = base_of.get(cur, "")
		var hops := 0
		while hops < 8:
			var parent_file: String = root + ".gd"
			if not (parent_file in files):
				break
			cur = parent_file
			root = base_of.get(cur, "")
			hops += 1
		if root == "Node2D":
			out.append("%s/%s" % [dir_path, name])
	out.sort()
	return out


## Convenience for sweeps that cover several map directories at once.
static func maps_in_all(dir_paths: Array) -> Array:
	var out: Array = []
	for d in dir_paths:
		out.append_array(maps_in(str(d)))
	out.sort()
	return out
