extends SceneTree

var failures: int = 0
var checks: int = 0
var app

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func tap(button_name: String) -> void:
	var button = app.ui.find_child(button_name, true, false)
	check(button is Button, "Visible action exists: " + button_name)
	if button is Button:
		button.pressed.emit()
		await process_frame
		await process_frame

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene = load("res://scenes/main_menu/main.tscn")
	check(scene != null, "Native main scene must load")
	if scene == null:
		quit(1)
		return
	app = scene.instantiate()
	root.add_child(app)
	await create_timer(0.9).timeout
	await tap("NewGame")
	await tap("CountryRU")
	await tap("CityStart")
	check(app.running and app.sim.state.country_id == "RU", "Country selection starts native game")
	app.city.plot_selected.emit(8)
	await process_frame
	await tap("Open_shop")
	check(app.player_companies().size() == 1, "Open a business through the property panel")
	await tap("HireStaff")
	check(app.player_companies()[0].staff.size() >= 1, "Hire through UI")
	await tap("OrderStock")
	var price = app.ui.find_child("BusinessPrice",true,false)
	price.value = 245.50
	await tap("PriceApply")
	check(app.player_companies()[0].price == 24550, "Price applies in integer minor units")
	await tap("EndDay")
	check(app.sim.state.day == 2, "End day advances once")
	app.show_panel("finance")
	await process_frame
	check(app.ui.find_child("FinanceReport",true,false) != null, "Financial report renders")
	check(app.sim.state.tutorial_step == 6, "Interactive tutorial follows actual player actions")
	app.open_plot(0)
	app.show_panel("business")
	check(app.company().get("owner","") == "player", "Own business remains selectable after inspecting a competitor")
	app.show_panel("aira")
	await process_frame
	check(app.ui.find_child("AiraAdvice",true,false) != null, "AIRA renders from real state")
	app.show_panel("settings")
	await process_frame
	await tap("Theme_sage")
	check(app.settings.theme == "sage", "Theme applied and stored")
	app.show_panel("saves")
	await process_frame
	await tap("ManualSave")
	check(app.store.load_game("manual").ok, "Manual save from UI")
	var state_before: String = JSON.stringify(app.sim.state)
	await tap("ManualLoad")
	var before = JSON.parse_string(state_before)
	if before != app.sim.state:
		for key in before:
			if before[key] != app.sim.state.get(key):
				print("SAVE DIFF ", key, " before=",JSON.stringify(before[key])," after=",JSON.stringify(app.sim.state.get(key)))
	check(before == app.sim.state, "Manual load preserves simulation")
	for page in ["business","staff","suppliers","warehouse","banks","property","news","achievements","profile","settings"]:
		app.show_panel(page)
		await process_frame
		check(app.current_panel == page, "Panel opens: " + page)
	var day_before = int(app.sim.state.day)
	app.complete_day()
	app.complete_day()
	await process_frame
	await process_frame
	check(int(app.sim.state.day) == day_before+1,"Repeated taps within a frame cannot skip several days")
	app._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(int(app.store.load_game("auto").state.day) == int(app.sim.state.day),"Pausing saves the current game day")
	print("UI TESTS: %d checks, %d failures" % [checks,failures])
	app.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
