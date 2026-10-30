extends Node
## Native application shell; all economic mutations go through Simulation.

const Simulation = preload("res://scripts/economy/simulation.gd")
const SaveStore = preload("res://scripts/save_system/save_store.gd")
const ThemeFactory = preload("res://scripts/ui/theme_factory.gd")
const Panels = preload("res://scripts/ui/panels.gd")
const Feed = preload("res://scripts/data_sync/economic_feed.gd")
const CityScene = preload("res://scenes/city/city.tscn")

var sim = Simulation.new()
var store = SaveStore.new()
var settings: Dictionary = {"theme":"sunrise","dark":false,"rounded":true,"accent":"","tutorial":true}
var brand: Dictionary
var city
var feed
var panels
var ui: Control
var layer: CanvasLayer
var panel_host: PanelContainer
var panel_body: VBoxContainer
var top: HBoxContainer
var navigation: HBoxContainer
var toast_label: Label
var tutorial_card: PanelContainer
var current_panel: String = ""
var selected_company: String = ""
var selected_country: String = "RU"
var selected_plot: int = 8
var running: bool = false
var busy: bool = false
var cash_label: Label
var date_text: Label
var status_label: Label
var palette: Dictionary
var _panel_tween: Tween
var toast_timer: Timer

func _ready() -> void:
	get_tree().auto_accept_quit = false
	brand = JSON.parse_string(FileAccess.get_file_as_string("res://data/brand.json"))
	var loaded_settings = store.read_record("settings")
	if loaded_settings.ok:
		settings.merge(loaded_settings.data, true)
	sim.new_game("RU")
	store.game_validator = Callable(sim,"validate_state")
	city = CityScene.instantiate()
	add_child(city)
	city.plot_selected.connect(open_plot)
	feed = Feed.new()
	add_child(feed)
	feed.load_cache()
	feed.sync_finished.connect(func(_ok: bool, message: String):
		toast(message)
		if current_panel == "news":
			show_panel("news")
	)
	layer = CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	toast_timer = Timer.new()
	toast_timer.one_shot = true
	toast_timer.wait_time = 4.0
	add_child(toast_timer)
	toast_timer.timeout.connect(func():
		if is_instance_valid(toast_label):
			toast_label.queue_free()
	)
	panels = Panels.new(self)
	apply_theme(false)
	city.sync_state(sim.state.companies, sim.state.get("properties", []))
	show_menu()
	var splash = ColorRect.new()
	splash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	splash.color = palette.background
	ui.add_child(splash)
	var title = Label.new()
	title.text = brand.name + "\nГОРОД ВОЗМОЖНОСТЕЙ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	splash.add_child(title)
	var tween = create_tween()
	tween.tween_interval(0.25)
	tween.tween_property(splash, "modulate:a", 0.0, 0.4)
	tween.tween_callback(splash.queue_free)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if running:
			autosave()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		if running:
			autosave()
		get_tree().quit()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		go_back()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		go_back()
		get_viewport().set_input_as_handled()

func go_back() -> void:
	if not running:
		show_menu()
	elif not current_panel.is_empty():
		close_panel()
	else:
		show_panel("pause")

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _clear_screen() -> void:
	if _panel_tween:
		_panel_tween.kill()
	_clear_children(ui)
	panel_host = null
	panel_body = null
	top = null
	toast_label = null
	tutorial_card = null
	cash_label = null
	date_text = null
	current_panel = ""

func text(parent: Node, content: String, size: int = 21, muted: bool = false) -> Label:
	var label = Label.new()
	label.text = content
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",palette.muted if muted else palette.ink)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func button(parent: Node, title: String, action: Callable, node_name: String = "", accent: bool = false) -> Button:
	var b = Button.new()
	b.text = title
	if not node_name.is_empty():
		b.name = node_name
	b.custom_minimum_size.y = 52
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.focus_mode = Control.FOCUS_ALL
	if accent:
		b.add_theme_stylebox_override("normal",ThemeFactory.box(palette.accent,16))
		b.add_theme_color_override("font_color",Color("243b34"))
		b.add_theme_color_override("font_hover_color",Color("243b34"))
		b.add_theme_color_override("font_pressed_color",Color("243b34"))
	b.pressed.connect(action)
	parent.add_child(b)
	return b

func card(parent: Node) -> VBoxContainer:
	var p = PanelContainer.new()
	p.add_theme_stylebox_override("panel",ThemeFactory.box(palette.background,14))
	parent.add_child(p)
	var v = VBoxContainer.new()
	p.add_child(v)
	return v

func row(parent: Node) -> HBoxContainer:
	var h = HBoxContainer.new()
	parent.add_child(h)
	return h

func section(parent: Node, title: String, description: String = "") -> void:
	text(parent,title,25)
	if not description.is_empty():
		text(parent,description,18,true)

func field(parent: Node, title: String, value: float, minimum: float, maximum: float, step: float = 1.0) -> SpinBox:
	text(parent,title,18,true)
	var input = SpinBox.new()
	input.min_value = minimum
	input.max_value = maximum
	input.step = step
	input.value = value
	input.custom_minimum_size.y = 52
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(input)
	return input

func money(amount) -> String:
	var units: int = int(round(float(amount) / 100.0))
	var digits = str(absi(units))
	var grouped = ""
	for i in range(digits.length()):
		if i > 0 and (digits.length() - i) % 3 == 0:
			grouped += " "
		grouped += digits[i]
	return ("−" if units < 0 else "") + grouped + " " + str(sim.country.get("symbol", "₽"))

func player_companies() -> Array:
	return sim.state.get("companies", []).filter(func(b): return b.get("owner", "") == "player" and b.get("status", "active") != "closed")

func company() -> Dictionary:
	var found: Dictionary = sim.get_company(selected_company)
	if not found.is_empty() and found.get("owner", "") == "player" and found.get("status", "active") != "closed":
		return found
	var owned = player_companies()
	if not owned.is_empty():
		selected_company = str(owned[0].id)
		return owned[0]
	return {}

func plot_info(id: int) -> Dictionary:
	for plot in sim.city.get("plots", []):
		if int(plot.id) == id:
			return plot
	return {}

func apply_theme(rebuild: bool = true) -> void:
	palette = ThemeFactory.colors(settings)
	ui.theme = ThemeFactory.build(settings)
	store.write_record("settings",settings)
	if rebuild:
		var previous = current_panel
		if running:
			build_hud()
			if not previous.is_empty():
				show_panel(previous)
		else:
			show_menu()

func show_menu() -> void:
	running = false
	_clear_screen()
	city.set_input_enabled(true)
	var plate = PanelContainer.new()
	plate.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	plate.offset_left = 32
	plate.offset_top = 32
	plate.offset_right = 512
	plate.offset_bottom = -32
	ui.add_child(plate)
	var scroll = ScrollContainer.new()
	plate.add_child(scroll)
	var v = VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	var icon = TextureRect.new()
	icon.texture = load(brand.icon)
	icon.custom_minimum_size = Vector2(76,76)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	v.add_child(icon)
	text(v,"БИЗНЕС · СТРАТЕГИЯ · ГОРОД",15,true)
	text(v,brand.name,44)
	text(v,brand.tagline,25)
	text(v,"Начните с небольшой компании. Найдите клиентов, управляйте расходами и постройте свою империю.",20,true)
	button(v,"Новая игра",show_countries,"NewGame",true)
	var saved = store.load_game("auto")
	var continue_button = button(v,"Продолжить",func(): load_slot("auto"),"Continue")
	continue_button.disabled = not saved.ok
	if saved.ok:
		text(v,"Сохранение · день %d" % int(saved.state.day),17,true)
	button(v,"Сохранения",func(): show_menu_saves(),"MenuSaves")
	button(v,"Настройки",func(): show_menu_settings(),"MenuSettings")
	button(v,"Выйти",func(): get_tree().quit(),"Quit")
	text(v,"v%s · Нативная офлайн-игра\nИгровая экономическая модель. Развитие продолжается." % brand.version,15,true)

func _menu_page(title: String) -> VBoxContainer:
	_clear_screen()
	var plate = PanelContainer.new()
	plate.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	plate.offset_left = 32
	plate.offset_top = 32
	plate.offset_right = 560
	plate.offset_bottom = -32
	ui.add_child(plate)
	var scroll = ScrollContainer.new()
	plate.add_child(scroll)
	var v = VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	text(v,title,34)
	button(v,"‹ Главное меню",show_menu)
	return v

func show_countries() -> void:
	var v = _menu_page("Новая история")
	text(v,"01 / 02 · Выберите страну",21,true)
	text(v,"Страна задаёт валюту, стоимость труда, налоги и кредитные условия. Профили описывают игровую модель.",20)
	button(v,"Россия · ₽",func(): choose_country("RU"),"CountryRU",true)
	text(v,"Екатеринбург · Основной игровой профиль",18,true)
	button(v,"США · $ · экспериментальный",func(): choose_country("US"),"CountryUS")
	text(v,"Rivergate · Вымышленный город, упрощённые правила США",18,true)
	text(v,"Новая игра заменит автосохранение после выбора города. Ручное сохранение остаётся доступным.",17,true)

func choose_country(id: String) -> void:
	selected_country = id
	var v = _menu_page("Место для старта")
	text(v,"02 / 02 · Выберите город",21,true)
	text(v,"Екатеринбург" if id == "RU" else "Rivergate",32)
	text(v,"Четыре района, 16 коммерческих участков, действующие конкуренты. Земля и покупательский спрос ограничены.",21)
	text(v,"Центр · Торговый · Жилой · Промышленный",18,true)
	text(v,"Стартовый капитал: 500 000 ₽" if id == "RU" else "Стартовый капитал: 50 000 $",24)
	button(v,"Начать в этом городе",func(): start_campaign(selected_country),"CityStart",true)
	button(v,"‹ Выбрать другую страну",show_countries)

func start_campaign(country_id: String) -> void:
	sim.new_game(country_id)
	sim.state["tutorial_step"] = 0
	selected_company = ""
	running = true
	city.sync_state(sim.state.companies,sim.state.get("properties",[]))
	build_hud()
	autosave()
	toast("Добро пожаловать. Выберите свободный участок на карте.")

func build_hud() -> void:
	_clear_screen()
	city.set_input_enabled(true)
	top = HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 22
	top.offset_right = -22
	top.offset_top = 18
	top.offset_bottom = 88
	ui.add_child(top)
	var logo_card = PanelContainer.new()
	logo_card.custom_minimum_size.x = 285
	top.add_child(logo_card)
	var logo_v = VBoxContainer.new()
	logo_v.add_theme_constant_override("separation",0)
	logo_card.add_child(logo_v)
	text(logo_v,brand.name,25)
	text(logo_v,str(sim.city.name) + " · " + str(sim.country.get("name","Россия")),15,true)
	var data_card = PanelContainer.new()
	data_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(data_card)
	var data_row = row(data_card)
	cash_label = text(data_row,money(sim.player_cash()),27)
	date_text = text(data_row,sim.date_label(),20,true)
	var end_button = button(top,"Завершить день  ›",complete_day,"EndDay",true)
	end_button.custom_minimum_size.x = 258
	end_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	end_button.disabled = sim.state.get("bankrupt",false)
	navigation = HBoxContainer.new()
	navigation.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	navigation.offset_left = 22
	navigation.offset_right = -22
	navigation.offset_top = -82
	navigation.offset_bottom = -18
	ui.add_child(navigation)
	for tab in [["city","Город"],["business","Компании"],["finance","Финансы"],["market","Рынок"],["banks","Банк"],["aira","AIRA"],["more","Ещё"]]:
		var id: String = tab[0]
		button(navigation,tab[1],func():
			if id == "city": close_panel()
			else: show_panel(id)
		,"Nav_" + id)
	build_camera_controls()
	build_tutorial()
	if sim.state.get("bankrupt",false):
		show_panel("bankruptcy")

func build_camera_controls() -> void:
	var controls = VBoxContainer.new()
	controls.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	controls.offset_left = 22
	controls.offset_right = 78
	controls.offset_top = -130
	controls.offset_bottom = 130
	ui.add_child(controls)
	for spec in [["+","zoom_in"],["−","zoom_out"],["↶","rotate_left"],["↷","rotate_right"],["⌂","reset"]]:
		var action: String = spec[1]
		button(controls,spec[0],func(): city.set_camera_action(action),"Camera_" + action)

func build_tutorial() -> void:
	if is_instance_valid(tutorial_card):
		ui.remove_child(tutorial_card)
		tutorial_card.queue_free()
	if not settings.get("tutorial",true) or int(sim.state.get("tutorial_step",0)) >= 6:
		return
	var messages = ["Выберите свободный участок и откройте магазин, кафе или студию.","Наймите сотрудника: без команды продажи ограничены.","Закажите первую поставку. Доставка занимает игровые дни.","Установите цену. Высокая наценка может сократить спрос.","Завершите день: продажи, расходы и конкуренты начнут действовать.","Откройте финансовый отчёт и сравните прибыль с денежным потоком."]
	var step = clampi(int(sim.state.get("tutorial_step",0)),0,5)
	tutorial_card = PanelContainer.new()
	tutorial_card.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	tutorial_card.offset_left = 22
	tutorial_card.offset_right = 416
	tutorial_card.offset_top = -239
	tutorial_card.offset_bottom = -102
	ui.add_child(tutorial_card)
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation",5)
	tutorial_card.add_child(v)
	text(v,"ПЕРВЫЕ ШАГИ   %d / 6" % (step+1),15,true)
	text(v,messages[step],19)
	button(v,"Показать",func():
		if step == 0:
			city.focus_plot(8)
			open_plot(8)
		elif step == 5: show_panel("finance")
		else: show_panel("business")
	,"GuideNext")

func tutorial_event(action: String) -> void:
	var actions = ["open","hire","stock","price","day","finance"]
	var step = int(sim.state.get("tutorial_step",0))
	if step < 6 and actions[step] == action:
		sim.state.tutorial_step = step + 1
		if action == "hire" and not company().is_empty() and sim.catalog[company().type].get("service",false):
			sim.state.tutorial_step = 3
		build_tutorial()

func open_plot(id: int) -> void:
	if not running:
		return
	selected_plot = id
	for b in sim.state.companies:
		if int(b.plot_id) == id and b.get("status","active") != "closed":
			selected_company = str(b.id)
			show_panel("business" if b.owner == "player" else "competitor")
			return
	show_panel("plot")

func _make_panel(title: String) -> VBoxContainer:
	if is_instance_valid(panel_host):
		ui.remove_child(panel_host)
		panel_host.queue_free()
	if _panel_tween:
		_panel_tween.kill()
	panel_host = PanelContainer.new()
	panel_host.name = "GamePanel"
	panel_host.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel_host.offset_left = -492
	panel_host.offset_right = -22
	panel_host.offset_top = 108
	panel_host.offset_bottom = -100
	ui.add_child(panel_host)
	var frame = VBoxContainer.new()
	panel_host.add_child(frame)
	var heading = row(frame)
	text(heading,title,28)
	var close = button(heading,"×",close_panel,"ClosePanel")
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.custom_minimum_size.x = 52
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	frame.add_child(scroll)
	panel_body = VBoxContainer.new()
	panel_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel_body)
	panel_host.modulate.a = 0
	_panel_tween = create_tween()
	_panel_tween.tween_property(panel_host,"modulate:a",1.0,0.16)
	return panel_body

func show_panel(id: String) -> void:
	if not running:
		return
	current_panel = id
	panels.show(id)
	if id == "finance":
		tutorial_event("finance")
		autosave()

func close_panel() -> void:
	if is_instance_valid(panel_host):
		ui.remove_child(panel_host)
		panel_host.queue_free()
	panel_host = null
	panel_body = null
	current_panel = ""
	city.set_input_enabled(true)

func act(result: Dictionary, next_panel: String = "business", action: String = "") -> void:
	if result.get("ok",false):
		if not action.is_empty():
			tutorial_event(action)
		autosave()
		city.sync_state(sim.state.companies,sim.state.get("properties",[]))
		if is_instance_valid(cash_label):
			cash_label.text = money(sim.player_cash())
		if not next_panel.is_empty():
			show_panel(next_panel)
	toast(str(result.get("message","Готово.")))

func complete_day() -> void:
	if busy or not running or sim.state.get("bankrupt",false):
		return
	busy = true
	var result: Dictionary = sim.end_day()
	tutorial_event("day")
	autosave()
	city.sync_state(sim.state.companies,sim.state.get("properties",[]))
	var previous = current_panel
	build_hud()
	if not sim.state.get("bankrupt",false):
		show_panel(previous if previous in ["business","finance","staff","suppliers","warehouse","banks","market","aira"] else "day_report")
	toast(str(result.get("message","День завершён. Откройте отчёт, чтобы увидеть результат.")))
	# Repeated taps cannot advance several days within one frame.
	await get_tree().process_frame
	busy = false

func autosave() -> void:
	if not running:
		return
	var result = store.save_game(sim.state,"auto")
	if not result.ok:
		toast(result.message)

func load_slot(slot: String) -> void:
	var result = store.load_game(slot)
	if not result.ok:
		toast(result.message)
		return
	var error: String = sim.validate_state(result.state)
	if not error.is_empty():
		toast("Сохранение не загружено: " + error)
		return
	# Re-load the chosen configuration before assigning the serialized state.
	sim.new_game(str(result.state.country_id))
	sim.state = result.state
	selected_company = ""
	running = true
	city.sync_state(sim.state.companies,sim.state.get("properties",[]))
	build_hud()
	toast(result.message)

func show_menu_settings() -> void:
	var v = _menu_page("Настройки")
	panels.settings_page(v)

func show_menu_saves() -> void:
	var v = _menu_page("Сохранения")
	for slot in ["auto","manual"]:
		var key: String = slot
		var saved = store.load_game(key)
		var title = "Автосохранение" if key == "auto" else "Ручное сохранение"
		text(v,title,24)
		text(v,("День %d" % int(saved.state.day)) if saved.ok else "Пусто или повреждено",18,true)
		var load_button = button(v,"Загрузить",func(): load_slot(key))
		load_button.disabled = not saved.ok

func toast(message: String) -> void:
	if not is_instance_valid(ui):
		return
	if is_instance_valid(toast_label):
		toast_label.queue_free()
	toast_label = Label.new()
	toast_label.text = message
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	toast_label.offset_left = 360
	toast_label.offset_right = -50
	toast_label.offset_top = 90
	toast_label.offset_bottom = 145
	toast_label.add_theme_font_size_override("font_size",19)
	toast_label.add_theme_stylebox_override("normal",ThemeFactory.box(palette.surface,14,palette.accent))
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(toast_label)
	toast_timer.start()
