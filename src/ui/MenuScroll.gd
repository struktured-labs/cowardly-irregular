class_name MenuScroll
extends RefCounted

## Shared scroll window for long menus that rebuild their rows from scratch.
##
## The four sites this replaces all computed `max(0, selected - visible + 1)`, which pins the cursor
## to the BOTTOM row for the whole back half of a list: past the first screenful the window moves on
## every single step, and nothing below the cursor is ever on screen. A window should move only when
## the selection would leave it — which needs the PREVIOUS offset, and a stateless one-liner has none.


## First visible row. `current` is the caller's own previous offset; it stores what this returns.
static func window_offset(selected: int, visible: int, total: int, current: int) -> int:
	if visible <= 0 or total <= 0:
		return 0
	var limit: int = maxi(0, total - visible)
	var offset: int = clampi(current, 0, limit)
	if selected < offset:
		offset = selected
	elif selected >= offset + visible:
		offset = selected - visible + 1
	return clampi(offset, 0, limit)
