extends SceneTree
## Run with a real display; captures the actual native renderer, not a mockup.

var app

func _initialize() -> void:
	call_deferred("run")

func capture(name: String) -> void:
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image()
	var path = "res://artifacts/screenshots/" + name + ".png"
	var error = image.save_png(path)
	if error != OK:
		push_error("Failed screenshot: " + path)
		quit(1)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/screenshots"))
	app = load("res://scenes/main_menu/main.tscn").instantiate()
	root.add_child(app)
	await create_timer(0.8).timeout
	await capture("01-main-menu")
	app.start_campaign("RU")
	app.settings.tutorial = false
	app.build_hud()
	var opened = app.sim.open_business("shop",8)
	if not opened.ok:
		quit(1)
		return
	app.selected_company = opened.company_id
	app.sim.hire(app.selected_company)
	app.sim.order_stock(app.selected_company,400,"standard")
	app.sim.set_price(app.selected_company,23000)
	for i in range(4): app.sim.end_day()
	app.city.sync_state(app.sim.state.companies,app.sim.state.properties)
	app.build_hud()
	app.close_panel()
	await capture("02-native-city")
	app.city.focus_plot(8)
	app.show_panel("business")
	await capture("03-company")
	app.show_panel("finance")
	await capture("04-finance")
	app.show_panel("aira")
	await capture("05-aira")
	app.settings.theme = "sage"
	app.settings.dark = true
	app.apply_theme()
	await capture("06-dark-theme")
	print("Native screenshots saved to artifacts/screenshots/")
	app.queue_free()
	await process_frame
	quit()
