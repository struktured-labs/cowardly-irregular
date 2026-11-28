extends GutTest
## .846 gate: test_llm_backend_selfhealing_probe logged 9 "/root" absolute-path errors from an off-tree HTTPBackend.
## dialogue_enabled() now reads LLMService through the SceneTree root, so a detached backend reports the real toggle.

var _svc: Node
var _was: bool


func before_each() -> void:
	_svc = get_node_or_null("/root/LLMService")
	_was = bool(_svc.llm_enabled) if _svc != null and "llm_enabled" in _svc else false


func after_each() -> void:
	if _svc != null and "llm_enabled" in _svc:
		_svc.llm_enabled = _was


func test_the_service_exists() -> void:
	assert_not_null(_svc, "CONTROL: LLMService autoload must exist or every arm below is vacuous")
	assert_true(_svc != null and "llm_enabled" in _svc, "CONTROL: the toggle must exist on the service")


func test_a_detached_backend_reads_the_toggle_on() -> void:
	var be := HTTPBackend.new()
	autofree(be)
	assert_false(be.is_inside_tree(), "CONTROL: the backend is off the tree")
	_svc.llm_enabled = true
	assert_true(be.dialogue_enabled(), "an off-tree backend must read an enabled toggle as enabled")


func test_a_detached_backend_reads_the_toggle_off() -> void:
	var be := HTTPBackend.new()
	autofree(be)
	_svc.llm_enabled = false
	assert_false(be.dialogue_enabled(), "an off-tree backend must read a disabled toggle as disabled")


func test_no_absolute_root_lookup_remains() -> void:
	var src := FileAccess.get_file_as_string("res://src/llm/HTTPBackend.gd")
	assert_gt(src.length(), 0, "CONTROL: the source was read")
	assert_eq(src.count("get_node_or_null(\"/root/"), 0,
		"HTTPBackend must not look up a service by an absolute /root path: an off-tree backend logs an engine error for it")
