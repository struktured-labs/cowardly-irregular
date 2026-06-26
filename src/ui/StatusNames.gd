extends RefCounted
class_name StatusNames

## Shared status-effect display helpers — tick 215.
##
## Same insight as tick 211's StatNames extraction. Four sites
## independently rendered status names — StatusMenu, BattleManager
## (×2), AutobattleGridEditor — some via `status.capitalize()` and
## some via `status.replace("_", " ").capitalize()`. Godot 4's
## capitalize() handles word boundaries on underscores so both
## produce identical output ("cannot_act" → "Cannot Act"), but the
## inconsistency invites bugs if future statuses need overrides
## (e.g. "regen" → "Regenerating") and only some sites pick up
## the change.
##
## DISPLAY_OVERRIDES lets us name specific statuses explicitly when
## .capitalize() doesn't produce the right phrasing. Empty by default
## — extend as content needs.

const DISPLAY_OVERRIDES := {
	# Empty for now; add entries like:
	#   "cannot_act": "Stunned (no action)",
	# when content requires non-capitalize phrasing.
}


# Long-form display name. Status id (snake_case) → title-cased label, with explicit overrides taking precedence.
static func display(status_name: String) -> String:
	if status_name == "":
		return ""
	if DISPLAY_OVERRIDES.has(status_name):
		return DISPLAY_OVERRIDES[status_name]
	return status_name.capitalize()
