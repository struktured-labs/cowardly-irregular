extends GutTest

## An inn built off the tree asked /root/GameLoop for its origin village, and a detached GameLoop's area transition asked
## /root/LLMService: each logged "Can't use get_node() with absolute paths" (9 per gate) and returned null anyway.

const INN := "res://src/maps/interiors/InnInterior.gd"
const GL := "res://src/GameLoop.gd"


func _src(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func test_the_inn_asks_for_gameloop_only_from_the_tree() -> void:
	var s := _src(INN)
	assert_eq(s.count('get_node_or_null("/root/GameLoop") if is_inside_tree() else null'), 1, "the origin lookup is gated on the tree")
	assert_eq(s.count('get_node_or_null("/root/GameLoop")\n'), 0, "no ungated GameLoop lookup is left in the inn")


func test_a_transition_asks_for_llmservice_only_from_the_tree() -> void:
	assert_eq(_src(GL).count('get_node_or_null("/root/LLMService") if is_inside_tree() else null'), 1, "the transition's LLM cancel is gated on the tree")


func test_a_detached_inn_still_answers_no_origin() -> void:
	var inn: Node = load(INN).new()
	assert_false(inn.is_inside_tree(), "CONTROL: the inn is off the tree")
	assert_eq(inn._origin_map_id(), "", "off the tree there is no origin village, as before")
	inn.free()


func test_an_inn_in_the_tree_still_reads_gameloop() -> void:
	var inn: Node = load(INN).new()
	add_child_autofree(inn)
	var gl: Node = get_tree().root.get_node_or_null("GameLoop")
	var expected := "" if gl == null or not gl.has_method("get_village_origin_id") else str(gl.get_village_origin_id())
	assert_eq(inn._origin_map_id(), expected, "in the tree the lookup reads whatever GameLoop reports")
