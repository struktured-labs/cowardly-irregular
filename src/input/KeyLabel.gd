class_name KeyLabel
extends RefCounted

## An action's keyboard keys, read off InputMap with no autoload, so a fallback can ask it. Five hand-written fallback
## letters still named the pre-2026-09-29 layout ("X" for cancel, "Z" for confirm; it is X = Confirm, Z = Back since).


## Every key bound to `action`, joined " / ", or "—" when it has none.
static func all_keys(action: String) -> String:
	if not InputMap.has_action(action):
		return "—"
	var labels: Array[String] = []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var ke := ev as InputEventKey
			# keycode (the printed key) over physical_keycode, so a player reads "L", not an OS code.
			var kc: Key = ke.keycode if ke.keycode != 0 else ke.physical_keycode
			if kc == 0:
				continue
			var name := OS.get_keycode_string(kc)
			if name != "":
				labels.append(name)
	return " / ".join(labels) if labels.size() > 0 else "—"


## The first key bound to `action`; `meaning` (e.g. "Back") when no key is, never a guessed letter.
static func first_key(action: String, meaning: String) -> String:
	var all := all_keys(action)
	return meaning if all == "—" else all.split(" / ")[0]
