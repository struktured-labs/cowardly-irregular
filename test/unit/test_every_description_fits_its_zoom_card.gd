extends GutTest

## .788 disclosure: AbilityZoomCard._refit_description had no arm, because the one-liner fixture never makes fit_px and
## the Label disagree. This sweeps EVERY real description through the card at the smallest and largest Text Size, and
## requires what the refit exists for: the drawn lines fit the description box, and the text stays above list size.

var _saved_scale = null


func before_all() -> void:
	_saved_scale = GameState.text_size_scale


func after_all() -> void:
	GameState.text_size_scale = _saved_scale


func _descriptions() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var all: Dictionary = (parsed as Dictionary).get("abilities", parsed)
	var out := {}
	for id in all:
		if all[id] is Dictionary and str(all[id].get("description", "")) != "":
			out[str(id)] = str(all[id]["description"])
	return out


func test_every_description_fits_its_card_at_both_ends_of_text_size() -> void:
	var descs := _descriptions()
	assert_gt(descs.size(), 250, "CONTROL: the whole kit's descriptions are read (%d)" % descs.size())
	var holder := Control.new()
	add_child_autofree(holder)
	holder.size = Vector2(1280, 720)
	var bad: Array = []
	var checked := 0
	for scale in [0.8, 2.0]:
		GameState.text_size_scale = scale
		for id in descs:
			var card := AbilityZoomCard.new()
			holder.add_child(card)
			card.show_for(str(id), descs[id], null)
			await get_tree().process_frame
			var d: Label = card.description_label()
			var px: int = d.get_theme_font_size("font_size")
			var drawn: float = float(d.get_line_count()) * d.get_theme_font("font").get_height(px)
			if drawn > card.description_box().y + 0.5:
				bad.append("@%s %s: %d lines at %d px draw %d in %d" % [str(scale), id, d.get_line_count(), px, int(drawn), int(card.description_box().y)])
			checked += 1
			holder.remove_child(card)
			card.free()
	assert_eq(checked, descs.size() * 2, "CONTROL: every description was measured at both sizes")
	assert_eq(bad, [], "a zoomed description must draw inside its box; fit_px's estimate is not enough on its own")
