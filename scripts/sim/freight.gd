class_name Freight
extends RefCounted
## Moves goods between district stockpiles.
##
## Each district wants a stock of what its buildings and citizens use in the
## next minute (its targets). The Bastion district also wants the current
## tithe quota. Surplus flows to districts in deficit, and any leftover surplus
## flows to the Bastion district, which acts as the hive's central store.
##
## Links between districts:
##  * Rail: both districts have a road-connected cargo station on the same rail
##    line. Capacity is the smaller side's total station capacity.
##  * Road: both districts' depots share a road network. Slow (ROAD_CAPACITY)
##    and it spends both districts' haulage, so it congests local deliveries.

const ROAD_CAPACITY := 3.0        ## TUNE: units per second for road freight
const TARGET_SECONDS := 60.0      ## TUNE: how much local consumption to keep on hand
const BUFFER_UNITS := 10          ## minimum stock kept before calling anything surplus

class Link:
	var a: int
	var b: int
	var rail: bool
	var capacity: float
	var path: Array[Vector2i] = []     # for train / truck visuals
	var flow_recent: float = 0.0       # units moved, decaying
	var _budget: float = 0.0

var grid: BuildGrid
var links: Array[Link] = []
var _version := -1


func _init(p_grid: BuildGrid) -> void:
	grid = p_grid


func link_between(a: int, b: int) -> Link:
	for l in links:
		if (l.a == a and l.b == b) or (l.a == b and l.b == a):
			return l
	return null


## Rebuilds links and stock targets after a topology change.
func rebuild(force: bool = false) -> void:
	if not force and _version == grid.topology_version:
		return
	_version = grid.topology_version
	var old_flows := {}
	for l in links:
		old_flows["%d-%d" % [l.a, l.b]] = l.flow_recent
	links.clear()
	var ds := grid.districts.districts
	for i in ds.size():
		for j in range(i + 1, ds.size()):
			var l := _make_link(ds[i], ds[j])
			if l:
				l.flow_recent = float(old_flows.get("%d-%d" % [l.a, l.b], 0.0))
				links.append(l)


func _make_link(a: DistrictMap.District, b: DistrictMap.District) -> Link:
	var t := grid.transport
	# Rail: total station capacity per rail line on each side.
	var cap_a := _station_capacity_by_line(a)
	var cap_b := _station_capacity_by_line(b)
	var best_line := -1
	var best_cap := 0.0
	for line in cap_a:
		if cap_b.has(line):
			var cap := minf(cap_a[line], cap_b[line])
			if cap > best_cap:
				best_cap = cap
				best_line = line
	if best_line >= 0:
		var l := Link.new()
		l.a = a.id
		l.b = b.id
		l.rail = true
		l.capacity = best_cap
		l.path = _path_between(a.stations, b.stations, TransportGrid.Graph.RAIL)
		return l
	# Road: any depot in a shares a road network with any depot in b.
	var roads_a := {}
	for d in a.depots:
		roads_a.merge(t.components_touching(d.cells, TransportGrid.Graph.ROAD))
	for d in b.depots:
		for comp in t.components_touching(d.cells, TransportGrid.Graph.ROAD):
			if roads_a.has(comp):
				var l := Link.new()
				l.a = a.id
				l.b = b.id
				l.rail = false
				l.capacity = ROAD_CAPACITY
				l.path = _path_between(a.depots, b.depots, TransportGrid.Graph.ROAD)
				return l
	return null


func _station_capacity_by_line(d: DistrictMap.District) -> Dictionary:
	var out := {}
	for s in d.stations:
		if not s.road_access:
			continue
		for line in grid.transport.components_touching(s.cells, TransportGrid.Graph.RAIL):
			out[line] = float(out.get(line, 0.0)) + s.def.station_capacity * s.staffing
	return out


func _path_between(from_b: Array, to_b: Array, graph: int) -> Array[Vector2i]:
	var starts: Array[Vector2i] = []
	var goals: Array[Vector2i] = []
	for b in from_b:
		starts.append_array(grid.transport.touching(b.cells, graph))
	for b in to_b:
		goals.append_array(grid.transport.touching(b.cells, graph))
	return grid.transport.find_path(graph, starts, goals)


## Stock each district wants on hand, from nominal local consumption.
func compute_targets(quota: Dictionary, bastion_id: int) -> void:
	for d in grid.districts.districts:
		d.targets.clear()
	for b in grid.buildings:
		var d := grid.districts.get_district(b.district_id)
		if d == null:
			continue
		if b.recipe and not b.def.is_housing():
			var per_sec := 1.0 / maxf(b.recipe.duration, 0.1)
			for item in b.recipe.inputs:
				var want := int(ceil(int(b.recipe.inputs[item]) * per_sec * TARGET_SECONDS))
				d.targets[item] = int(d.targets.get(item, 0)) + want
		if b.def.is_housing():
			var caste := Database.caste(b.def.housing_caste)
			if caste:
				for needs in [caste.basic_needs, caste.comfort_needs]:
					for item in needs:
						var want := int(ceil(float(needs[item]) * b.def.housing_capacity / 100.0 * TARGET_SECONDS / 60.0 * 2.0))
						d.targets[item] = int(d.targets.get(item, 0)) + want
		if b.def.is_module() and b.host:
			for item in b.def.module_upkeep:
				d.targets[item] = int(d.targets.get(item, 0)) + int(ceil(float(b.def.module_upkeep[item]) * 2.0))
		# Machine parts for repairs.
		if b.def.decay_per_minute > 0.0 and b.recipe:
			d.targets[&"machine_parts"] = int(d.targets.get(&"machine_parts", 0)) + 1
	var bastion := grid.districts.get_district(bastion_id)
	if bastion:
		for item in quota:
			bastion.targets[item] = int(bastion.targets.get(item, 0)) + int(quota[item])


## Moves goods along links for one step. Road links spend haulage budgets.
## haul_budget: district id -> remaining units this step (modified in place).
func step(dt: float, haul_budget: Dictionary, bastion_id: int) -> void:
	if links.is_empty():
		return
	var ds := grid.districts.districts
	for l in links:
		# Carry up to one unit between steps so slow links still move goods.
		l._budget = minf(l._budget, 1.0) + l.capacity * dt
		l.flow_recent = maxf(0.0, l.flow_recent - l.flow_recent * dt / 10.0)
	var items := {}
	for d in ds:
		for item in d.stockpile:
			if d.amount(item) > 0:
				items[item] = true

	for item in items:
		# 1. Deficits first.
		for need in ds:
			var deficit := int(need.targets.get(item, 0)) - need.amount(item)
			if deficit <= 0:
				continue
			for give in ds:
				if give == need or deficit <= 0:
					continue
				var surplus := _surplus(give, item)
				if surplus <= 0:
					continue
				deficit -= _move(give, need, item, mini(deficit, surplus), haul_budget)
		# 2. Leftover surplus drains to the Bastion district, the hive store.
		var bastion := grid.districts.get_district(bastion_id)
		if bastion == null:
			continue
		for give in ds:
			if give == bastion:
				continue
			var surplus := _surplus(give, item)
			if surplus > 0:
				_move(give, bastion, item, surplus, haul_budget)


func _surplus(d: DistrictMap.District, item: StringName) -> int:
	return d.amount(item) - maxi(int(d.targets.get(item, 0)), BUFFER_UNITS if d.targets.has(item) else 0)


func _move(from_d: DistrictMap.District, to_d: DistrictMap.District, item: StringName,
		want: int, haul_budget: Dictionary) -> int:
	var l := link_between(from_d.id, to_d.id)
	if l == null:
		return 0
	var n := mini(want, int(l._budget))
	if not l.rail:
		n = mini(n, int(minf(float(haul_budget.get(from_d.id, 0.0)), float(haul_budget.get(to_d.id, 0.0)))))
	if n <= 0:
		return 0
	n = from_d.take(item, n)
	to_d.add(item, n)
	l._budget -= n
	l.flow_recent += n
	if not l.rail:
		haul_budget[from_d.id] = float(haul_budget[from_d.id]) - n
		haul_budget[to_d.id] = float(haul_budget[to_d.id]) - n
	return n
