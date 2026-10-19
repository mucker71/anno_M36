class_name DepositMap
extends RefCounted
## Finite resource deposits. Each cluster is a blob of tiles sharing one yield
## pool; mines draw it down until it is exhausted (a pressure source).

class Cluster:
	var id: int
	var item: StringName
	var cells: Array[Vector2i] = []
	var initial: int
	var remaining: int

	func fraction_left() -> float:
		return float(remaining) / float(maxi(initial, 1))


var clusters: Array[Cluster] = []
var _cell_to_cluster: Dictionary = {}   # Vector2i -> int


func add_cluster(item: StringName, cells: Array[Vector2i], yield_amount: int) -> Cluster:
	var cl := Cluster.new()
	cl.id = clusters.size()
	cl.item = item
	cl.cells = cells
	cl.initial = yield_amount
	cl.remaining = yield_amount
	clusters.append(cl)
	for c in cells:
		_cell_to_cluster[c] = cl.id
	return cl


func cluster_at(c: Vector2i) -> Cluster:
	var i: int = _cell_to_cluster.get(c, -1)
	return clusters[i] if i >= 0 else null


func has_deposit(c: Vector2i) -> bool:
	return _cell_to_cluster.has(c)


func get_cluster(id: int) -> Cluster:
	return clusters[id] if id >= 0 and id < clusters.size() else null


## Takes up to amount units from a cluster. Returns what was actually taken.
func draw(id: int, amount: int) -> int:
	var cl := get_cluster(id)
	if cl == null:
		return 0
	var taken := mini(amount, cl.remaining)
	cl.remaining -= taken
	return taken
