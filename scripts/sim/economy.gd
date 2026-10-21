class_name Economy
extends RefCounted
## Stockpile-based economic simulation, stepped at a fixed rate.
##
## Goods live in district stockpiles (held at depots) and in building buffers.
##  * Inside a district, buildings trade with the depot over ROADS, spending the
##    district's haulage (depots add capacity). No road, no trade.
##  * Directly linked ports hand goods across for free, road or not.
##  * Between districts, Freight moves goods by rail or road.
##  * Citizens shop at their district depot on foot (walkways or roads).
##  * Workers commute to jobs they can walk to (Labour), across district lines.
##
## Construction draws on every district's stock (its own first): build crews
## are not simulated. The tithe is collected from the Bastion district only.

const STEP := 0.25                 ## seconds of game time per simulation step
const MAX_STEPS_PER_FRAME := 40
const LABOUR_INTERVAL := 3.0       ## seconds between workforce reallocations
const REPAIR_THRESHOLD := 75.0     ## TUNE: condition below which a repair is ordered
const REPAIR_AMOUNT := 25.0        ## TUNE: condition restored per machine part
const CONDITION_KNEE := 60.0       ## TUNE: above this, condition has no penalty
const NEED_SMOOTHING := 0.05       ## TUNE: how fast satisfaction reacts (per step)

var grid: BuildGrid
var deposits: DepositMap
var labour: Labour
var freight: Freight
var districts: DistrictMap
var bastion_district: int = 0
## Current tithe quota, so the Bastion district stocks up for it.
var tithe_quota: Dictionary = {}
var time: float = 0.0

## Hive-wide aggregates for the HUD.
var population: Dictionary = {}    # caste -> housed
var jobs: Dictionary = {}          # caste -> wanted
var employed: Dictionary = {}      # caste -> filled
var morale: float = 0.5
var haul_capacity: float = 0.0
var haul_load: float = 0.0

var produced_total: Dictionary = {}
var consumed_total: Dictionary = {}

var _accum: float = 0.0
var _rr_offset: int = 0
var _topology_seen := -1
var _labour_timer := 0.0


func _init(p_grid: BuildGrid, p_deposits: DepositMap) -> void:
	grid = p_grid
	deposits = p_deposits
	districts = grid.districts
	labour = Labour.new(grid)
	freight = Freight.new(grid)


# --- Stockpiles -----------------------------------------------------------------

func district(id: int) -> DistrictMap.District:
	return districts.get_district(id)


func bastion() -> DistrictMap.District:
	return districts.get_district(bastion_district)


## Total of an item across every district.
func amount(item: StringName) -> int:
	var t := 0
	for d in districts.districts:
		t += d.amount(item)
	return t


func district_amount(id: int, item: StringName) -> int:
	var d := district(id)
	return d.amount(item) if d else 0


func add(item: StringName, n: int, district_id: int = -1) -> void:
	var d := district(district_id if district_id >= 0 else bastion_district)
	if d:
		d.add(item, n)


## Takes from one district first, then the others. Returns what was taken.
func take_hive(item: StringName, n: int, preferred: int = -1) -> int:
	var got := 0
	var first := district(preferred)
	if first:
		got += first.take(item, n)
	for d in districts.districts:
		if got >= n:
			break
		if d != first:
			got += d.take(item, n - got)
	return got


func can_afford(cost: Dictionary) -> bool:
	for item in cost:
		if amount(item) < int(cost[item]):
			return false
	return true


func pay(cost: Dictionary, preferred: int = -1) -> bool:
	if not can_afford(cost):
		return false
	for item in cost:
		take_hive(item, int(cost[item]), preferred)
	return true


func refund(cost: Dictionary, fraction: float, district_id: int = -1) -> void:
	for item in cost:
		add(item, int(floor(int(cost[item]) * fraction)), district_id)


func return_buffers(inst: BuildingInstance) -> void:
	for item in inst.input_buffer:
		add(item, int(inst.input_buffer[item]), inst.district_id)
	for item in inst.output_buffer:
		add(item, int(inst.output_buffer[item]), inst.district_id)
	inst.input_buffer.clear()
	inst.output_buffer.clear()


## The tithe is collected from the Bastion district's stockpile.
func tithe_take(item: StringName, n: int) -> int:
	var d := bastion()
	return d.take(item, n) if d else 0


# --- Simulation -------------------------------------------------------------------

func advance(delta: float) -> void:
	_accum += delta
	var steps := 0
	while _accum >= STEP and steps < MAX_STEPS_PER_FRAME:
		step(STEP)
		_accum -= STEP
		steps += 1
	if steps == MAX_STEPS_PER_FRAME:
		_accum = 0.0


func step(dt: float) -> void:
	time += dt
	if _topology_seen != grid.topology_version:
		refresh_topology()
	_labour_timer -= dt
	if _labour_timer <= 0.0:
		_labour_timer = LABOUR_INTERVAL
		_reallocate()

	var budget := {}
	for d in districts.districts:
		budget[d.id] = d.haul_capacity * dt
	var start := budget.duplicate()

	for d in districts.districts:
		_supply_needs(d, dt)
	_update_services_and_morale()
	freight.step(dt, budget, bastion_district)

	var list := grid.buildings
	var n := list.size()
	if n > 0:
		_rr_offset = (_rr_offset + 1) % n
	for i in n:
		var b: BuildingInstance = list[(i + _rr_offset) % n]
		b.hauled_recent = maxf(0.0, b.hauled_recent - b.hauled_recent * dt / 8.0)
		if b.def.is_module():
			_step_module(b, dt)
		elif not b.def.is_housing() and b.recipe != null:
			_step_building(b, dt, budget)

	var used_total := 0.0
	var cap_total := 0.0
	for d in districts.districts:
		var s: float = start[d.id]
		var used := 0.0 if s <= 0.0 else clampf(1.0 - float(budget[d.id]) / s, 0.0, 1.0)
		d.haul_load = lerpf(d.haul_load, used, 0.1)
		used_total += d.haul_load * d.haul_capacity
		cap_total += d.haul_capacity
	haul_capacity = cap_total
	haul_load = 0.0 if cap_total <= 0.0 else used_total / cap_total


## Recomputes depots, access, links and jobs after anything is built or removed.
func refresh_topology() -> void:
	_topology_seen = grid.topology_version
	var t := grid.transport
	var road_comps := {}     # district -> {comp: true}
	var people_comps := {}
	var depot_cells := {}    # district -> {cell: true} cells next to a depot
	for d in districts.districts:
		d.depots.clear()
		d.stations.clear()
		d.haul_capacity = 0.0
		road_comps[d.id] = {}
		people_comps[d.id] = {}
		depot_cells[d.id] = {}
	for b in grid.buildings:
		var d := district(b.district_id)
		if d == null:
			continue
		if b.def.is_station():
			d.stations.append(b)
		if not b.def.is_depot:
			continue
		d.depots.append(b)
		d.haul_capacity += b.def.logistics_capacity
		road_comps[d.id].merge(t.components_touching(b.cells, TransportGrid.Graph.ROAD))
		people_comps[d.id].merge(t.components_touching(b.cells, TransportGrid.Graph.PEOPLE))
		for nb in grid.neighbours_of(b.cells):
			depot_cells[d.id][nb.uid] = true
	for b in grid.buildings:
		if b.district_id < 0:
			continue
		var next_to_depot: bool = depot_cells[b.district_id].has(b.uid)
		if b.def.is_depot:
			b.road_access = true
			b.market_access = true
			continue
		b.road_access = next_to_depot or _shares(t.components_touching(b.cells, TransportGrid.Graph.ROAD), road_comps[b.district_id])
		b.market_access = next_to_depot or _shares(t.components_touching(b.cells, TransportGrid.Graph.PEOPLE), people_comps[b.district_id])
		if b.def.is_housing():
			b.status = BuildingInstance.Status.HOUSING if b.market_access else BuildingInstance.Status.NO_MARKET
	_reallocate()


func _reallocate() -> void:
	labour.allocate(_basic_sat)
	freight.rebuild(true)
	freight.compute_targets(tithe_quota, bastion_district)
	for c in Database.castes:
		population[c] = 0
		jobs[c] = 0
		employed[c] = 0
	for d in districts.districts:
		d.population.clear()
		d.jobs.clear()
		d.employed.clear()
	for b in grid.buildings:
		var d := district(b.district_id)
		if d == null:
			continue
		if b.def.is_housing():
			var c := b.def.housing_caste
			d.population[c] = int(d.population.get(c, 0)) + b.def.housing_capacity
			population[c] = int(population.get(c, 0)) + b.def.housing_capacity
			d.employed[c] = int(d.employed.get(c, 0)) + int(b.workers_assigned.get(c, 0))
		else:
			var req := Labour.job_requirements(b)
			for c in req:
				d.jobs[c] = int(d.jobs.get(c, 0)) + int(req[c])
				jobs[c] = int(jobs.get(c, 0)) + int(req[c])
				employed[c] = int(employed.get(c, 0)) + int(b.workers_assigned.get(c, 0))


func total_population() -> int:
	var t := 0
	for c in population:
		t += int(population[c])
	return t


func _basic_sat(district_id: int, caste: StringName) -> float:
	var d := district(district_id)
	return float(d.basic_satisfaction.get(caste, 1.0)) if d else 0.0


static func _shares(a: Dictionary, b: Dictionary) -> bool:
	for k in a:
		if b.has(k):
			return true
	return false


## Citizens with market access draw their needs from the district stockpile.
func _supply_needs(d: DistrictMap.District, dt: float) -> void:
	var served := {}   # caste -> citizens who can reach the depot
	for b in grid.buildings:
		if b.def.is_housing() and b.district_id == d.id and b.market_access:
			served[b.def.housing_caste] = int(served.get(b.def.housing_caste, 0)) + b.def.housing_capacity
	for caste_id in Database.castes:
		var caste: CasteDef = Database.castes[caste_id]
		var pop: int = int(served.get(caste_id, 0))
		d.basic_satisfaction[caste_id] = _satisfy(d, caste_id, caste.basic_needs, pop, dt, true)
		d.comfort_satisfaction[caste_id] = _satisfy(d, caste_id, caste.comfort_needs, pop, dt, false)


## Minimum for basic needs (no water is not cancelled by plenty of food),
## mean for comforts.
func _satisfy(d: DistrictMap.District, caste_id: StringName, needs: Dictionary, pop: int,
		dt: float, use_min: bool) -> float:
	if needs.is_empty():
		return 1.0
	if pop <= 0:
		return 1.0 if use_min else 0.0
	var agg := 1.0 if use_min else 0.0
	for item in needs:
		var key := "%s|%s" % [caste_id, item]
		var owed: float = float(d.need_owed.get(key, 0.0)) + float(needs[item]) * pop / 100.0 * dt / 60.0
		var whole := int(floor(owed))
		var met_now := 1.0
		if whole > 0:
			var got := d.take(item, whole)
			consumed_total[item] = int(consumed_total.get(item, 0)) + got
			met_now = float(got) / float(whole)
			owed -= whole   # unmet demand is lost, not carried as debt
		d.need_owed[key] = owed
		var met: float = lerpf(float(d.need_met.get(key, 1.0 if use_min else 0.0)), met_now, NEED_SMOOTHING)
		d.need_met[key] = met
		if use_min:
			agg = minf(agg, met)
		else:
			agg += met / needs.size()
	return agg


## Comfort, Fervour and Order per district. TUNE: weights.
## TODO: zealotry and resentment side effects.
func _update_services_and_morale() -> void:
	for d in districts.districts:
		d.fervour_coverage = 0
		d.order_coverage = 0
	for b in grid.buildings:
		if b.def.service_kind == &"" or b.recipe == null:
			continue
		var d := district(b.district_id)
		if d == null or time - b.last_service_time > b.recipe.duration * 1.5:
			continue
		if b.def.service_kind == &"fervour":
			d.fervour_coverage += b.def.service_capacity
		elif b.def.service_kind == &"order":
			d.order_coverage += b.def.service_capacity
	var hive_pop := 0
	var hive_morale := 0.0
	for d in districts.districts:
		var pop := d.total_population()
		if pop <= 0:
			d.morale = 0.5
		else:
			var comfort := 0.0
			for c in d.population:
				comfort += float(d.comfort_satisfaction.get(c, 0.0)) * float(d.population[c]) / pop
			var fervour := minf(1.0, float(d.fervour_coverage) / pop)
			var order := minf(1.0, float(d.order_coverage) / pop)
			d.morale = clampf(0.6 * comfort + 0.25 * fervour + 0.25 * order, 0.0, 1.0)
			hive_pop += pop
			hive_morale += d.morale * pop
		d.productivity = 0.75 + 0.35 * d.morale
	morale = 0.5 if hive_pop == 0 else hive_morale / hive_pop


func _step_module(m: BuildingInstance, dt: float) -> void:
	if m.host == null:
		m.status = BuildingInstance.Status.NO_HOST
		m.module_active = false
		return
	var d := district(m.district_id)
	var paid := true
	for item in m.def.module_upkeep:
		var owed: float = float(m.upkeep_owed.get(item, 0.0)) + float(m.def.module_upkeep[item]) * dt / 60.0
		if owed >= 1.0:
			var whole := int(floor(owed))
			var got := d.take(item, whole) if d and m.host.road_access else 0
			consumed_total[item] = int(consumed_total.get(item, 0)) + got
			if got < whole:
				paid = false
				owed = minf(owed, 1.0)   # wait for one unit rather than run up a debt
			else:
				owed -= whole
		m.upkeep_owed[item] = owed
	m.module_active = paid
	m.status = BuildingInstance.Status.MODULE_ACTIVE if paid else BuildingInstance.Status.UPKEEP_UNPAID


func _step_building(b: BuildingInstance, dt: float, budget: Dictionary) -> void:
	var r := b.recipe
	var d := district(b.district_id)
	var trade := d != null and b.road_access

	# Decay and repair (the maintenance supply chain).
	b.condition = maxf(0.0, b.condition - b.def.decay_per_minute * b.effect("decay") * dt / 60.0)
	if b.condition < REPAIR_THRESHOLD and trade and float(budget[d.id]) >= 1.0 and d.take(&"machine_parts", 1) == 1:
		budget[d.id] = float(budget[d.id]) - 1.0
		b.condition = minf(100.0, b.condition + REPAIR_AMOUNT)
		consumed_total[&"machine_parts"] = int(consumed_total.get(&"machine_parts", 0)) + 1

	# No drive module, no work: the building waits, and employs nobody.
	var drive := b.drive()
	if drive <= 0.0:
		b.status = BuildingInstance.Status.NEEDS_MODULE
		b.last_speed = 0.0
		_push_outputs(b, d if trade else null, budget)
		return

	# Speed multiplier.
	var staff := 1.0 if Labour.job_requirements(b).is_empty() else b.staffing
	var cond := 1.0 if b.condition >= CONDITION_KNEE else lerpf(0.3, 1.0, b.condition / CONDITION_KNEE)
	var prod := d.productivity if d else 1.0
	var speed := staff * cond * prod * b.effect("speed") * drive
	if r.is_extraction():
		speed *= b.deposit_coverage
	b.last_speed = speed

	if trade:
		var room: float = budget[d.id]
		# Return goods left over from a previous recipe.
		for item in b.input_buffer.keys():
			if not r.inputs.has(item) and int(b.input_buffer[item]) > 0:
				var back := mini(int(b.input_buffer[item]), int(room))
				b.input_buffer[item] = int(b.input_buffer[item]) - back
				d.add(item, back)
				room -= back
		# Pull inputs from the depot.
		for item in r.inputs:
			var space := b.input_space(item)
			if space <= 0 or room < 1.0:
				continue
			var got := d.take(item, mini(space, int(room)))
			if got > 0:
				b.input_buffer[item] = int(b.input_buffer.get(item, 0)) + got
				room -= got
				b.hauled_recent += got
		budget[d.id] = room

	# Start a cycle.
	if not b.running:
		if speed <= 0.001 and not Labour.job_requirements(b).is_empty():
			b.status = BuildingInstance.Status.NO_WORKERS
		elif r.is_extraction() and not _deposit_can_supply(b, r):
			b.status = BuildingInstance.Status.DEPOSIT_EXHAUSTED
		elif not b.has_inputs_for_cycle():
			b.status = BuildingInstance.Status.MISSING_INPUTS if trade else BuildingInstance.Status.NO_ROAD
		elif not r.is_service() and not b.output_has_room():
			b.status = BuildingInstance.Status.OUTPUT_BLOCKED if trade else BuildingInstance.Status.NO_ROAD
		else:
			b.consume_inputs()
			for item in r.inputs:
				consumed_total[item] = int(consumed_total.get(item, 0)) + int(r.inputs[item])
			b.running = true

	if b.running:
		if speed <= 0.001:
			b.status = BuildingInstance.Status.NO_WORKERS
		else:
			b.status = BuildingInstance.Status.WORKING
			b.progress += dt * speed / maxf(r.duration, 0.01)
			if b.progress >= 1.0:
				_finish_cycle(b, r)

	_push_outputs(b, d if trade else null, budget)


func _deposit_can_supply(b: BuildingInstance, r: RecipeDef) -> bool:
	var cl := deposits.get_cluster(b.deposit_cluster)
	if cl == null:
		return false
	var need := 0
	for item in r.outputs:
		need += int(r.outputs[item])
	return cl.remaining >= need


func _finish_cycle(b: BuildingInstance, r: RecipeDef) -> void:
	b.progress = 0.0
	b.running = false
	if r.is_service():
		b.last_service_time = time
		return
	var mult := b.effect("output")
	for item in r.outputs:
		var exact: float = int(r.outputs[item]) * mult + float(b.output_carry.get(item, 0.0))
		var n := int(floor(exact))
		b.output_carry[item] = exact - n
		if r.is_extraction():
			n = deposits.draw(b.deposit_cluster, n)
		b.output_buffer[item] = int(b.output_buffer.get(item, 0)) + n
		produced_total[item] = int(produced_total.get(item, 0)) + n


## Linked buildings first (free), then the district depot (costs haulage).
func _push_outputs(b: BuildingInstance, d: DistrictMap.District, budget: Dictionary) -> void:
	for item in b.output_buffer.keys():
		var have := int(b.output_buffer[item])
		if have <= 0:
			continue
		for target in b.links_out:
			if have <= 0:
				break
			var space := target.input_space(item)
			if space > 0:
				var give := mini(space, have)
				target.input_buffer[item] = int(target.input_buffer.get(item, 0)) + give
				have -= give
		if have > 0 and d != null and float(budget[d.id]) >= 1.0:
			var send := mini(have, int(budget[d.id]))
			d.add(item, send)
			have -= send
			budget[d.id] = float(budget[d.id]) - send
			b.hauled_recent += send
		b.output_buffer[item] = have
