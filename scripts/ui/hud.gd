class_name Hud
extends CanvasLayer
## Prototype HUD, built in code so it is easy to change while the design moves.
## Covers: build menu, stockpile, inspection, tithe/objective bar, population
## and morale, and a message log. Production statistics, the in-game wiki and
## settings menus from the design doc are still to do.

const CATEGORY_TABS := [
	[&"extraction", "Extract"],
	[&"industry", "Industry"],
	[&"civic", "Civic"],
	[&"housing", "Housing"],
	[&"service", "Services"],
	[&"logistics", "Logistics"],
]
const TEXT := Color(0.86, 0.80, 0.66)
const TEXT_DIM := Color(0.55, 0.51, 0.44)
const BRASS := Color(0.62, 0.47, 0.20)
const GOOD := Color(0.55, 0.85, 0.45)
const BAD := Color(0.95, 0.45, 0.35)

var world: World

var _top_tithe: Label
var _top_status: Label
var _stock_labels: Dictionary = {}   # item id -> Label
var _inspect_panel: PanelContainer
var _inspect_title: Label
var _inspect_body: Label
var _recipe_select: OptionButton
var _upgrade_button: Button
var _demolish_button: Button
var _hint: Label
var _log: VBoxContainer
var _selected: BuildingInstance


func setup(p_world: World) -> void:
	world = p_world
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)
	_build_top_bar(root)
	_build_build_menu(root)
	_build_stockpile(root)
	_build_inspector(root)
	_build_hint_and_log(root)
	world.placement.selection_changed.connect(_on_selection_changed)
	world.placement.build_mode_changed.connect(func(_def): refresh())
	world.message_posted.connect(post_message)


func refresh() -> void:
	if world == null:
		return
	_refresh_top()
	_refresh_stockpile()
	_refresh_inspector()
	_refresh_hint()


func post_message(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.add_child(label)
	while _log.get_child_count() > 6:
		_log.get_child(0).queue_free()
		_log.remove_child(_log.get_child(0))
	var tween := label.create_tween()
	tween.tween_interval(10.0)
	tween.tween_property(label, "modulate:a", 0.0, 2.0)
	tween.tween_callback(label.queue_free)


# --- Layout -------------------------------------------------------------------

func _build_top_bar(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	root.add_child(panel)
	var row := VBoxContainer.new()
	panel.add_child(row)
	_top_tithe = Label.new()
	_top_tithe.add_theme_color_override("font_color", BRASS.lightened(0.3))
	row.add_child(_top_tithe)
	_top_status = Label.new()
	row.add_child(_top_status)


func _build_build_menu(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(8, 64)
	panel.custom_minimum_size = Vector2(250, 420)
	root.add_child(panel)
	var tabs := TabContainer.new()
	panel.add_child(tabs)
	var by_cat := {}
	for def in Database.sorted_buildings():
		by_cat.get_or_add(def.category, []).append(def)
	for tab in CATEGORY_TABS:
		var scroll := ScrollContainer.new()
		scroll.name = tab[1]
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tabs.add_child(scroll)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(list)
		for def in by_cat.get(tab[0], []):
			# Upgrades are reached from the inspector, not built directly.
			if _is_upgrade_target(def):
				continue
			var b := Button.new()
			b.text = def.display_name
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.tooltip_text = _building_tooltip(def)
			b.pressed.connect(world.placement.begin_build.bind(def))
			list.add_child(b)


func _build_stockpile(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -250
	panel.offset_right = -8
	panel.offset_top = 64
	panel.offset_bottom = 560
	root.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "Hive Stockpile"
	title.add_theme_color_override("font_color", BRASS.lightened(0.3))
	box.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 14)
	scroll.add_child(margin)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(grid)
	var last_tier := -1
	for def in Database.sorted_items():
		if def.tier != last_tier:
			last_tier = def.tier
			var head := Label.new()
			head.text = ["Raw", "Refined", "Components", "Finished"][def.tier]
			head.add_theme_color_override("font_color", BRASS)
			grid.add_child(head)
			grid.add_child(Control.new())
		var name_label := Label.new()
		name_label.text = def.display_name
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.tooltip_text = def.description
		name_label.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(name_label)
		var count := Label.new()
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(count)
		_stock_labels[def.id] = count


func _build_inspector(root: Control) -> void:
	_inspect_panel = PanelContainer.new()
	_inspect_panel.anchor_top = 1.0
	_inspect_panel.anchor_bottom = 1.0
	_inspect_panel.offset_left = 8
	_inspect_panel.offset_right = 380
	_inspect_panel.offset_top = -300
	_inspect_panel.offset_bottom = -8
	_inspect_panel.visible = false
	root.add_child(_inspect_panel)
	var box := VBoxContainer.new()
	_inspect_panel.add_child(box)
	_inspect_title = Label.new()
	_inspect_title.add_theme_color_override("font_color", BRASS.lightened(0.3))
	box.add_child(_inspect_title)
	_recipe_select = OptionButton.new()
	_recipe_select.item_selected.connect(_on_recipe_selected)
	box.add_child(_recipe_select)
	_inspect_body = Label.new()
	_inspect_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inspect_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_inspect_body)
	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	_upgrade_button = Button.new()
	_upgrade_button.text = "Upgrade (U)"
	_upgrade_button.pressed.connect(_on_upgrade_pressed)
	buttons.add_child(_upgrade_button)
	_demolish_button = Button.new()
	_demolish_button.text = "Demolish (Del)"
	_demolish_button.pressed.connect(_on_demolish_pressed)
	buttons.add_child(_demolish_button)


func _build_hint_and_log(root: Control) -> void:
	_hint = Label.new()
	_hint.anchor_left = 0.5
	_hint.anchor_right = 0.5
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = -300
	_hint.offset_right = 300
	_hint.offset_top = -34
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hint)
	_log = VBoxContainer.new()
	_log.anchor_left = 1.0
	_log.anchor_right = 1.0
	_log.anchor_top = 1.0
	_log.anchor_bottom = 1.0
	_log.offset_left = -420
	_log.offset_right = -8
	_log.offset_top = -240
	_log.offset_bottom = -44
	_log.alignment = BoxContainer.ALIGNMENT_END
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_log)


# --- Refresh ------------------------------------------------------------------

func _refresh_top() -> void:
	var t := world.tithe
	var parts := []
	for item in t.quota:
		parts.append("%s %d/%d" % [Database.item_name(item), world.economy.amount(item), int(t.quota[item])])
	_top_tithe.text = "Imperial Tithe %d  ·  due in %s  ·  %s  ·  Favour %d" % [
		t.cycle, _clock(t.time_left), ",  ".join(parts), int(t.favour)]

	var e := world.economy
	var pops := []
	for caste in Database.sorted_castes():
		var pop := int(e.population.get(caste.id, 0))
		var wanted := int(e.jobs.get(caste.id, 0))
		if pop > 0 or wanted > 0:
			pops.append("%s %d/%d jobs (%d%%)" % [caste.display_name, pop, wanted,
				int(float(e.staffing.get(caste.id, 0.0)) * 100.0)])
	var speed_text := "PAUSED" if world.speed == 0.0 else "x%d" % int(world.speed)
	_top_status.text = "%s  ·  Morale %d%%  ·  Fervour %d  ·  Order %d  ·  Logistics %d/s (%d%% used)  ·  %s" % [
		"  ".join(pops) if not pops.is_empty() else "No citizens housed",
		int(e.morale * 100.0), e.fervour_coverage, e.order_coverage,
		int(e.logistics_capacity), int(e.logistics_load * 100.0), speed_text]


func _refresh_stockpile() -> void:
	for id in _stock_labels:
		var n := world.economy.amount(id)
		var label: Label = _stock_labels[id]
		label.text = str(n)
		label.add_theme_color_override("font_color", TEXT if n > 0 else TEXT_DIM)


func _refresh_inspector() -> void:
	if _selected == null or not world.grid.buildings.has(_selected):
		_inspect_panel.visible = false
		_selected = null
		return
	_inspect_panel.visible = true
	var b := _selected
	var d := b.def
	_inspect_title.text = d.display_name
	var lines := []
	lines.append(b.status_text())
	if d.is_housing():
		var caste := Database.caste(d.housing_caste)
		lines.append("Houses %d %s" % [d.housing_capacity, caste.display_name if caste else ""])
		lines.append("Basic needs met %d%%, comforts %d%%" % [
			int(float(world.economy.basic_satisfaction.get(d.housing_caste, 0.0)) * 100.0),
			int(float(world.economy.comfort_satisfaction.get(d.housing_caste, 0.0)) * 100.0)])
		if d.upgrade_to != &"":
			var up := Database.building(d.upgrade_to)
			lines.append("Upgrade to %s (%d): %s" % [up.display_name, up.housing_capacity, _cost_text(d.upgrade_cost)])
	if b.recipe:
		var r := b.recipe
		lines.append("Speed %d%%  ·  Condition %d%%  ·  Cycle %d%%" % [
			int(b.last_speed * 100.0), int(b.condition), int(b.progress * 100.0)])
		lines.append("%s  →  %s  (%.1fs)" % [_amounts_text(r.inputs, "nothing"),
			_amounts_text(r.outputs, "service"), r.duration])
		if not b.input_buffer.is_empty():
			lines.append("In: " + _amounts_text(b.input_buffer, "-"))
		if not b.output_buffer.is_empty():
			lines.append("Out: " + _amounts_text(b.output_buffer, "-"))
		if not b.links_out.is_empty():
			var names := []
			for l in b.links_out:
				names.append(l.def.display_name)
			lines.append("Direct link to: " + ", ".join(names))
	if b.deposit_cluster >= 0:
		var cl := world.deposits.get_cluster(b.deposit_cluster)
		if cl:
			lines.append("Deposit: %d %s left (%d%% coverage)" % [cl.remaining,
				Database.item_name(cl.item), int(b.deposit_coverage * 100.0)])
	if not d.workers.is_empty():
		lines.append("Workers: " + _castes_text(d.workers))
	if d.service_kind != &"":
		lines.append("%s for %d citizens" % [String(d.service_kind).capitalize(), d.service_capacity])
	_inspect_body.text = "\n".join(lines)
	_upgrade_button.visible = d.upgrade_to != &""
	_demolish_button.disabled = d.category == &"core"


func _refresh_hint() -> void:
	var p := world.placement
	if p.build_def == null:
		_hint.text = "WASD pan · wheel zoom · Q/E rotate view · Space pause · 1/2/3 speed"
		_hint.add_theme_color_override("font_color", TEXT_DIM)
		return
	var text := "%s  ·  %s  ·  R rotate · right-click cancel" % [p.build_def.display_name, _cost_text(p.build_def.build_cost)]
	var ok := true
	if not p.hover_check.is_empty() and not p.hover_check["ok"]:
		text = "%s  ·  %s" % [p.hover_check["reason"], text]
		ok = false
	elif not world.economy.can_afford(p.build_def.build_cost):
		text = "Cannot afford  ·  " + text
		ok = false
	elif p.hover_check.get("cluster", -1) >= 0:
		text = "Covers %d%% of deposit  ·  %s" % [int(p.hover_check["coverage"] * 100.0), text]
	_hint.text = text
	_hint.add_theme_color_override("font_color", GOOD if ok else BAD)


func _on_selection_changed(inst: BuildingInstance) -> void:
	_selected = inst
	_recipe_select.clear()
	_recipe_select.visible = false
	if inst and inst.def.recipes.size() > 1 and not inst.def.needs_deposit:
		_recipe_select.visible = true
		for i in inst.def.recipes.size():
			var r := Database.recipe(inst.def.recipes[i])
			_recipe_select.add_item(r.display_name, i)
			if r == inst.recipe:
				_recipe_select.select(i)
	refresh()


func _on_upgrade_pressed() -> void:
	if _selected:
		world.upgrade(_selected)


func _on_demolish_pressed() -> void:
	if _selected:
		world.demolish(_selected)


func _on_recipe_selected(index: int) -> void:
	if _selected:
		world.set_recipe(_selected, _selected.def.recipes[index])


# --- Text helpers -------------------------------------------------------------

func _building_tooltip(def: BuildingDef) -> String:
	var lines := [def.display_name]
	if def.description != "":
		lines.append(def.description)
	lines.append("Cost: " + _cost_text(def.build_cost))
	if not def.workers.is_empty():
		lines.append("Workers: " + _castes_text(def.workers))
	if def.is_housing():
		lines.append("Houses %d %s" % [def.housing_capacity, Database.caste(def.housing_caste).display_name])
	for rid in def.recipes:
		var r := Database.recipe(rid)
		lines.append("%s: %s → %s" % [r.display_name, _amounts_text(r.inputs, "nothing"),
			_amounts_text(r.outputs, "service")])
	return "\n".join(lines)


func _is_upgrade_target(def: BuildingDef) -> bool:
	for other in Database.buildings.values():
		if other.upgrade_to == def.id:
			return true
	return false


func _amounts_text(d: Dictionary, empty: String) -> String:
	if d.is_empty():
		return empty
	var parts := []
	for item in d:
		parts.append("%d %s" % [int(d[item]), Database.item_name(item)])
	return ", ".join(parts)


func _cost_text(d: Dictionary) -> String:
	return _amounts_text(d, "free")


func _castes_text(d: Dictionary) -> String:
	var parts := []
	for c in d:
		var caste := Database.caste(c)
		parts.append("%d %s" % [int(d[c]), caste.display_name if caste else String(c)])
	return ", ".join(parts)


func _clock(seconds: float) -> String:
	var s := maxi(0, int(seconds))
	return "%d:%02d" % [s / 60, s % 60]


func _make_theme() -> Theme:
	var theme := Theme.new()
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.07, 0.06, 0.05, 0.9)
	panel.border_color = BRASS.darkened(0.3)
	panel.set_border_width_all(1)
	panel.set_content_margin_all(8)
	panel.set_corner_radius_all(2)
	theme.set_stylebox("panel", "PanelContainer", panel)
	var button := StyleBoxFlat.new()
	button.bg_color = Color(0.14, 0.12, 0.10)
	button.border_color = BRASS.darkened(0.5)
	button.set_border_width_all(1)
	button.set_content_margin_all(5)
	var hover := button.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.22, 0.18, 0.12)
	hover.border_color = BRASS
	theme.set_stylebox("normal", "Button", button)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", hover)
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", BRASS.lightened(0.4))
	theme.set_default_font_size(14)
	return theme
