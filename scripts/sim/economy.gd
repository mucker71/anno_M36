class_name Economy
extends RefCounted
## Stockpile-based economic simulation, stepped at a fixed rate.
##
## Goods live in three places: the hive stockpile, building input buffers and
## building output buffers. Moving goods between a building and the stockpile
## spends logistics capacity (a stand-in for the road and rail networks).
## Goods passed through linked ports go straight to the next building for free,
## which is what makes compact, directly-chained layouts worth the space.
##
## Placeholder systems, marked TUNE or TODO, are there to be argued over:
## global (not per-district) workforce, morale and needs, and simple repair.

const STEP := 0.25                 ## seconds of game time per simulation step
const MAX_STEPS_PER_FRAME := 40
const REPAIR_THRESHOLD := 75.0     ## TUNE: condition below which a repair is ordered
const REPAIR_AMOUNT := 25.0        ## TUNE: condition restored per machine part
const CONDITION_KNEE := 60.0       ## TUNE: above this, condition has no penalty
const NEED_SMOOTHING := 0.05       ## TUNE: how fast satisfaction reacts (per step)

var grid: BuildGrid
var deposits: DepositMap
var stockpile: Dictionary = {}           # item -> int
var time: float = 0.0

var logistics_capacity: float = 0.0      # units per second
var logistics_load: float = 0.0          # smoothed fraction of capacity used, 0..1

var population: Dictionary = {}          # caste -> citizens housed
var jobs: Dictionary = {}                # caste -> workers wanted
var staffing: Dictionary = {}            # caste -> 0..1 share of jobs filled
var basic_satisfaction: Dictionary = {}  # caste -> 0..1
var comfort_satisfaction: Dictionary = {}
var fervour_coverage: int = 0
var order_coverage: int = 0
var morale: float = 0.5
var productivity: float = 1.0

## Running produced/consumed totals per item, for the statistics panel.
var produced_total: Dictionary = {}
var consumed_total: Dictionary = {}

var _accum: float = 0.0
var _rr_offset: int = 0
var _need_owed: Dictionary = {}          # "caste|item" -> float units owed
var _need_met: Dictionary = {}           # "caste|item" -> smoothed 0..1


func _init(p_grid: BuildGrid, p_deposits: DepositMap) -> void:
	grid = p_grid
	deposits = p_deposits
	for c in Database.castes:
		basic_satisfaction[c] = 1.0
		comfort_satisfaction[c] = 0.0
		staffing[c] = 1.0


# --- Stockpile ----------------------------------------------------------------

func amount(item: StringName) -> int:
	return int(stockpile.get(item, 0))


func add(item: StringName, n: int) -> void:
	if n == 0:
		return
	stockpile[item] = amount(item) + n


func take(item: StringName, n: int) -> int:
	var got := mini(n, amount(item))
	if got > 0:
		stockpile[item] = amount(item) - got
	return got


func can_afford(cost: Dictionary) -> bool:
	for item in cost:
		if amount(item) < int(cost[item]):
			return false
	return true


func pay(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for item in cost:
		take(item, int(cost[item]))
	return true


func refund(cost: Dictionary, fraction: float) -> void:
	for item in cost:
		add(item, int(floor(int(cost[item]) * fraction)))


## Returns a building's buffered goods to the stockpile (on demolition).
func return_buffers(inst: BuildingInstance) -> void:
	for item in inst.input_buffer:
		add(item, int(inst.input_buffer[item]))
	for item in inst.output_buffer:
		add(item, int(inst.output_buffer[item]))
	inst.input_buffer.clear()
	inst.output_buffer.clear()


# --- Simulation ---------------------------------------------------------------

func advance(delta: float) -> void:
	_accum += delta
	var steps := 0
	while _accum >= STEP and steps < MAX_STEPS_PER_FRAME:
		step(STEP)
		_accum -= STEP
		steps += 1
	if steps == MAX_STEPS_PER_FRAME:
		_accum = 0.0   # fell behind; drop time rather than spiral


func step(dt: float) -> void:
	time += dt
	_count_population_and_jobs()
	var budget := logistics_capacity * dt
	var budget_start := budget
	budget = _supply_needs(dt, budget)
	_update_services()
	_update_morale_and_staffing()

	var list := grid.buildings
	var n := list.size()
	if n > 0:
		_rr_offset = (_rr_offset + 1) % n
	for i in n:
		var b: BuildingInstance = list[(i + _rr_offset) % n]
		budget = _step_building(b, dt, budget)

	var used := 0.0 if budget_start <= 0.0 else 1.0 - budget / budget_start
	logistics_load = lerpf(logistics_load, used, 0.1)


func _count_population_and_jobs() -> void:
	logistics_capacity = 0.0
	for c in Database.castes:
		population[c] = 0
		jobs[c] = 0
	for b in grid.buildings:
		logistics_capacity += b.def.logistics_capacity
		if b.def.is_housing():
			population[b.def.housing_caste] = int(population.get(b.def.housing_caste, 0)) + b.def.housing_capacity
		for caste in b.def.workers:
			jobs[caste] = int(jobs.get(caste, 0)) + int(b.def.workers[caste])


func total_population() -> int:
	var t := 0
	for c in population:
		t += int(population[c])
	return t


## Citizens draw their needs from the stockpile. Needs are served before any
## building and are not capped by logistics; whatever they use is taken out of
## the step's budget, so a hungry hive starves its factories of haulage.
## TODO: per-district stockpiles fed by the pedestrian and traffic networks.
func _supply_needs(dt: float, budget: float) -> float:
	_budget_spent = 0.0
	for caste_id in Database.castes:
		var caste: CasteDef = Database.castes[caste_id]
		var pop: int = int(population.get(caste_id, 0))
		basic_satisfaction[caste_id] = _satisfy(caste_id, caste.basic_needs, pop, dt, true)
		comfort_satisfaction[caste_id] = _satisfy(caste_id, caste.comfort_needs, pop, dt, false)
	return maxf(0.0, budget - _budget_spent)


var _budget_spent: float = 0.0


## Returns the satisfaction for a set of needs: the minimum for basic needs
## (no water is not cancelled out by plenty of food), the mean for comforts.
func _satisfy(caste_id: StringName, needs: Dictionary, pop: int, dt: float, use_min: bool) -> float:
	if needs.is_empty():
		return 1.0
	if pop <= 0:
		return 1.0 if use_min else 0.0
	var agg := 1.0 if use_min else 0.0
	for item in needs:
		var key := "%s|%s" % [caste_id, item]
		var owed: float = float(_need_owed.get(key, 0.0)) + float(needs[item]) * pop / 100.0 * dt / 60.0
		var whole := int(floor(owed))
		var met_now := 1.0
		if whole > 0:
			var got := take(item, whole)
			_budget_spent += got
			consumed_total[item] = int(consumed_total.get(item, 0)) + got
			met_now = float(got) / float(whole)
			owed -= whole   # unmet demand is lost, not carried as debt
		_need_owed[key] = owed
		var met: float = lerpf(float(_need_met.get(key, 1.0 if use_min else 0.0)), met_now, NEED_SMOOTHING)
		_need_met[key] = met
		if use_min:
			agg = minf(agg, met)
		else:
			agg += met / needs.size()
	return agg


func _update_services() -> void:
	fervour_coverage = 0
	order_coverage = 0
	for b in grid.buildings:
		if b.def.service_kind == &"" or b.recipe == null:
			continue
		var active := time - b.last_service_time <= b.recipe.duration * 1.5
		if not active:
			continue
		if b.def.service_kind == &"fervour":
			fervour_coverage += b.def.service_capacity
		elif b.def.service_kind == &"order":
			order_coverage += b.def.service_capacity


## The three levers from the design doc: Comfort, Fervour and Order.
## TUNE: weights. TODO: per district, plus zealotry and resentment side effects.
func _update_morale_and_staffing() -> void:
	var pop := total_population()
	if pop <= 0:
		morale = 0.5
	else:
		var comfort := 0.0
		for c in population:
			comfort += float(comfort_satisfaction.get(c, 0.0)) * float(population[c]) / pop
		var fervour := minf(1.0, float(fervour_coverage) / pop)
		var order := minf(1.0, float(order_coverage) / pop)
		morale = clampf(0.6 * comfort + 0.25 * fervour + 0.25 * order, 0.0, 1.0)
	productivity = 0.75 + 0.35 * morale

	for c in Database.castes:
		var wanted: int = int(jobs.get(c, 0))
		var effective: float = float(population.get(c, 0)) * (0.4 + 0.6 * float(basic_satisfaction.get(c, 1.0)))
		staffing[c] = 1.0 if wanted <= 0 else minf(1.0, effective / wanted)


func _step_building(b: BuildingInstance, dt: float, budget: float) -> float:
	if b.def.is_housing() or b.recipe == null:
		return budget
	var r := b.recipe

	# Decay and repair (the maintenance supply chain).
	b.condition = maxf(0.0, b.condition - b.def.decay_per_minute * dt / 60.0)
	if b.condition < REPAIR_THRESHOLD and budget >= 1.0 and take(&"machine_parts", 1) == 1:
		budget -= 1.0
		b.condition = minf(100.0, b.condition + REPAIR_AMOUNT)
		consumed_total[&"machine_parts"] = int(consumed_total.get(&"machine_parts", 0)) + 1

	# Speed multiplier.
	var staff := 1.0
	for caste in b.def.workers:
		staff = minf(staff, float(staffing.get(caste, 0.0)))
	var cond := 1.0 if b.condition >= CONDITION_KNEE else lerpf(0.3, 1.0, b.condition / CONDITION_KNEE)
	var speed := staff * cond * productivity
	if r.is_extraction():
		speed *= b.deposit_coverage
	b.last_speed = speed

	# Return goods left over from a previous recipe.
	for item in b.input_buffer.keys():
		if not r.inputs.has(item) and int(b.input_buffer[item]) > 0:
			var back := mini(int(b.input_buffer[item]), int(budget))
			b.input_buffer[item] = int(b.input_buffer[item]) - back
			add(item, back)
			budget -= back

	# Pull inputs from the stockpile.
	for item in r.inputs:
		var space := b.input_space(item)
		if space <= 0 or budget < 1.0:
			continue
		var got := take(item, mini(space, int(budget)))
		if got > 0:
			b.input_buffer[item] = int(b.input_buffer.get(item, 0)) + got
			budget -= got

	# Start a cycle.
	if not b.running:
		if speed <= 0.001 and not b.def.workers.is_empty():
			b.status = BuildingInstance.Status.NO_WORKERS
		elif r.is_extraction() and not _deposit_can_supply(b, r):
			b.status = BuildingInstance.Status.DEPOSIT_EXHAUSTED
		elif not b.has_inputs_for_cycle():
			b.status = BuildingInstance.Status.MISSING_INPUTS
		elif not r.is_service() and not b.output_has_room():
			b.status = BuildingInstance.Status.OUTPUT_BLOCKED
		else:
			b.consume_inputs()
			for item in r.inputs:
				consumed_total[item] = int(consumed_total.get(item, 0)) + int(r.inputs[item])
			b.running = true

	# Progress the cycle.
	if b.running:
		if speed <= 0.001:
			b.status = BuildingInstance.Status.NO_WORKERS
		else:
			b.status = BuildingInstance.Status.WORKING
			b.progress += dt * speed / maxf(r.duration, 0.01)
			if b.progress >= 1.0:
				_finish_cycle(b, r)

	return _push_outputs(b, budget)


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
	for item in r.outputs:
		var n := int(r.outputs[item])
		if r.is_extraction():
			n = deposits.draw(b.deposit_cluster, n)
		b.output_buffer[item] = int(b.output_buffer.get(item, 0)) + n
		produced_total[item] = int(produced_total.get(item, 0)) + n


## Linked buildings first (free), then the stockpile (costs logistics).
func _push_outputs(b: BuildingInstance, budget: float) -> float:
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
		if have > 0 and budget >= 1.0:
			var send := mini(have, int(budget))
			add(item, send)
			have -= send
			budget -= send
		b.output_buffer[item] = have
	return budget
