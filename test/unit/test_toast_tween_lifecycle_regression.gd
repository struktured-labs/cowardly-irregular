extends GutTest

## Toast tweens must be owned by the local CanvasLayer, not the parent caller,
## so a scene swap on the parent doesn't kill the tween before the toast
## finishes fading + frees its layer.

const TOAST_PATH := "res://src/ui/Toast.gd"


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


func test_tween_is_created_on_local_layer_not_parent() -> void:
	var text := _read(TOAST_PATH)
	var idx := text.find("func show(parent: Node")
	assert_gt(idx, -1, "Toast.show must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nstatic func ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("layer.create_tween()"),
		"Toast.show's tween must be created on the local layer so it survives the parent's scene swap")
	assert_false(body.contains("parent.create_tween()"),
		"Toast.show must NOT create the tween on the parent — tween dies with the parent's tree exit and the layer leaks")


func test_dead_has_method_check_is_gone() -> void:
	var text := _read(TOAST_PATH)
	# every Node has create_tween — the runtime check was always true.
	assert_false(text.contains("has_method(\"create_tween\")"),
		"has_method(\"create_tween\") is always true on Node — dead defensive code")
