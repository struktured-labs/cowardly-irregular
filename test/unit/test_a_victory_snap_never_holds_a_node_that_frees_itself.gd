extends GutTest

## VictoryOverlay records one "snap to the end state" lambda per animation, and complete_now()
## calls them all on the first accept press. The ring and the letterbox bars free themselves when
## their tween ends. Their snaps captured the node itself, so letting the animation finish and then
## pressing accept called a lambda whose capture was already freed. The engine logs
## "Lambda capture at index 0 was freed" before the body's is_instance_valid guard can run, and the
## shipped .481 build logged exactly that after every victory. A snap now holds a WeakRef.
## The self-freeing set is derived from the file's own tween_callback(X.queue_free) calls, so a
## new one is covered without editing this test.

const OVERLAY := "res://src/battle/VictoryOverlay.gd"


func _self_freeing(src: String) -> Array:
	var re := RegEx.new()
	re.compile("tween_callback\\((\\w+)\\.queue_free\\)")
	var out: Array = []
	for m in re.search_all(src):
		if not out.has(m.get_string(1)):
			out.append(m.get_string(1))
	return out


func test_control_the_derived_set_holds_the_nodes_that_shipped() -> void:
	var nodes := _self_freeing(FileAccess.get_file_as_string(OVERLAY))
	assert_true(nodes.has("ring"), "CONTROL: the ring frees itself — the derivation must find it")
	assert_true(nodes.has("bar"), "CONTROL: the letterbox bars free themselves — the derivation must find them")


func test_every_self_freeing_node_is_held_by_a_weakref() -> void:
	var src := FileAccess.get_file_as_string(OVERLAY)
	for n in _self_freeing(src):
		assert_true(src.contains("weakref(%s)" % n),
			"'%s' frees itself at its tween's end; a snap capturing it logs 'Lambda capture ... was freed'" % n)
		assert_false(src.contains("is_instance_valid(%s):\n\t\t\t%s.queue_free()" % [n, n]) or src.contains("is_instance_valid(%s):\n\t\t%s.queue_free()" % [n, n]),
			"a snap still captures '%s' itself" % n)
