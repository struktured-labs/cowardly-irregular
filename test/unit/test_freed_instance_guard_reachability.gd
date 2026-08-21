extends GutTest

## GDScript type-checks an argument BEFORE entering the function, so a freed instance passed to
## an Object-derived typed param aborts the CALLER's remaining statements and the
## is_instance_valid guard inside never runs. Measured 2026-08-21: Node2D and Object both abort;
## Variant and untyped reach the guard. _spawn_cast_anticipation is the site with a PROVEN
## unguarded caller (BattleScene:3254) and the only one of its shape ever observed aborting in a
## full suite run. The same shape exists elsewhere in src/battle unfixed — deliberately, see
## test_scope_bound below; blanket-untyping it broke 16 signature-pinning tests for no evidenced gain.

const SCENE_PATH := "res://src/battle/BattleScene.gd"
const SKIP_TYPES := ["Variant", "int", "float", "bool", "String", "Array", "Dictionary",
	"Vector2", "Vector2i", "Callable", "StringName", "Color", "Rect2", "NodePath"]


func _unreachable_guards(source: String) -> Array:
	var out: Array = []
	var lines := source.split("\n")
	for i in lines.size():
		var line: String = lines[i]
		if not line.begins_with("func ") or not "(" in line or not ")" in line:
			continue
		var params: String = line.substr(line.find("(") + 1, line.rfind(")") - line.find("(") - 1)
		var body := ""
		for j in range(i + 1, lines.size()):
			if lines[j].begins_with("func "):
				break
			body += lines[j] + "\n"
		for raw in params.split(","):
			var p: String = raw.strip_edges()
			if not ":" in p:
				continue
			var pname: String = p.split(":")[0].strip_edges()
			var ptype: String = p.split(":")[1].split("=")[0].strip_edges()
			if ptype in SKIP_TYPES or ptype.begins_with("Array["):
				continue
			if "is_instance_valid(" + pname + ")" in body:
				out.append(line.substr(5, line.find("(") - 5) + "|" + pname + ": " + ptype)
	return out


func test_detector_fires_on_a_known_positive() -> void:
	## ARM+: without this, any zero below could mean "none" or "broken scan".
	var synthetic := "func _f(sprite: Node2D, other: int) -> void:\n\tif not is_instance_valid(sprite):\n\t\treturn\n"
	assert_eq(_unreachable_guards(synthetic).size(), 1, "ARM+: detector fires on a typed guarded param")


func test_detector_ignores_a_variant_param() -> void:
	## ARM-: the fixed shape must not be reported, or the assert below can never pass.
	var fixed := "func _f(sprite: Variant, other: int) -> void:\n\tif not is_instance_valid(sprite):\n\t\treturn\n"
	assert_eq(_unreachable_guards(fixed).size(), 0, "ARM-: a Variant param reaches its guard")


func test_the_proven_site_keeps_a_reachable_guard() -> void:
	var src := FileAccess.get_file_as_string(SCENE_PATH)
	assert_gt(src.length(), 1000, "CONTROL: read a real file")
	for hit in _unreachable_guards(src):
		assert_false(hit.begins_with("_spawn_cast_anticipation|"),
			"_spawn_cast_anticipation must not re-acquire a typed param — its caller at :3254 is unguarded: " + hit)


func test_a_freed_instance_reaches_the_guard_for_real() -> void:
	## Behavioural arm — the source scan cannot prove the runtime property.
	var scene: Node = load(SCENE_PATH).new()
	add_child_autofree(scene)
	var doomed := Node2D.new()
	add_child(doomed)
	doomed.free()
	var survived := 0
	scene._spawn_cast_anticipation(doomed, {"id": "fire"})
	survived += 1
	assert_eq(survived, 1, "the call returned via its guard instead of aborting this test")


func test_scope_bound_is_stated_not_silently_narrowed() -> void:
	## The rest of the lane still has this shape. Recording the number so it is a known
	## quantity rather than an unmeasured one — NOT asserted as a baseline, which would go
	## red on a correct fix and green on a wrong one.
	var src := FileAccess.get_file_as_string(SCENE_PATH)
	assert_gt(src.length(), 1000, "CONTROL: the count below came from a real read, not an empty string")
	gut.p("BattleScene.gd still has %d typed-param guards of this shape (unfixed by design)" % _unreachable_guards(src).size())
