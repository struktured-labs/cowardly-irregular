extends RefCounted
## Where a node sorts as BUILT, not where it sits: a node under a y-sorted parent sorts by its own y (nested y-sorted
## containers merge into one sort), and a node under an unsorted parent draws with that parent, at the parent's key.
## Unsorted, every door in a village's Buildings sorted at y=0 and drew under every facade and prop. Comparing raw
## positions cannot see that -- they never change when the container's y_sort is switched off.


static func sort_key(n: Node) -> float:
	var p: Node = n.get_parent()
	if not (p is CanvasItem):
		return 0.0
	if (p as CanvasItem).y_sort_enabled:
		return (n as Node2D).global_position.y if n is Node2D else 0.0
	return sort_key(p)


## True when `top` draws over `under` in their shared y-sort. A tie is NOT counted: it falls back to tree order.
static func draws_over(top: Node, under: Node) -> bool:
	return sort_key(top) > sort_key(under)
