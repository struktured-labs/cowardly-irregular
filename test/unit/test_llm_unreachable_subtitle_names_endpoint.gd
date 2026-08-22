extends GutTest

## "UNREACHABLE (llama3)" told the player WHAT was unreachable and never WHERE.
##
## With BYOK the endpoint is user-configurable (`base_url` persists in settings.json), so
## the same message covers two very different failures: a stopped Ollama on the default
## localhost:11434, and a perfectly healthy server behind a mistyped URL. The player can
## act on the first and cannot even see the second.
##
## BEHAVIOURAL, deliberately. The first version of this file pinned the SOURCE TEXT
## ("does the body contain `probe_url`") and a mutation proved it blind: keeping the
## token, computing `where`, and never rendering it left all three tests GREEN while the
## player saw no endpoint. A pin proves a token survives; only the string proves the
## player is told. Both arms are red now.

const SettingsMenuScript := preload("res://src/ui/SettingsMenu.gd")

const URL := "http://192.0.2.77:11434"


func _render(overrides: Dictionary) -> String:
	var info: Dictionary = {
		"llm_enabled": true, "probed": true, "available": false,
		"model": "llama3", "probe_url": URL, "probe_interval_sec": 30,
	}
	for k in overrides:
		info[k] = overrides[k]
	var menu: Node = SettingsMenuScript.new()
	var out: String = menu._render_llm_status(info)
	menu.free()
	return out


func test_unreachable_readout_shows_the_endpoint_to_the_player() -> void:
	var out := _render({})
	assert_true(out.contains(URL),
		("the UNREACHABLE readout must RENDER the endpoint, not merely consult it — with "
		+ "BYOK a mistyped base_url and a stopped server are the same message otherwise. "
		+ "Got: " + out))


func test_unreachable_readout_states_the_retry_interval() -> void:
	var out := _render({})
	assert_true(out.contains("30"),
		"the readout must tell the player it retries on its own. Got: " + out)


func test_a_blank_probe_url_falls_back_without_an_empty_at_clause() -> void:
	var out := _render({"probe_url": ""})
	assert_true(out.contains("UNREACHABLE"), "fallback must still say UNREACHABLE")
	assert_false(out.contains(" at "),
		"with no URL known the readout must not render a dangling 'at'. Got: " + out)


func test_control_the_renderer_discriminates() -> void:
	var unreachable := _render({})
	var connected := _render({"available": true})
	assert_true(connected.contains("Connected"), "the available branch must differ")
	assert_false(connected.contains("UNREACHABLE"), "available must not say UNREACHABLE")
	assert_ne(unreachable, connected, "the two branches must render differently")
	assert_false(unreachable.contains("Zzznotanendpoint"), "fabricated token found")
