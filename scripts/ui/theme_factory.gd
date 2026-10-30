extends RefCounted

const THEMES = {
	"sunrise":{"name":"Солнечный","accent":"edc766","background":"f7f4e9","ink":"263b36"},
	"sage":{"name":"Шалфей","accent":"94c4ab","background":"f0f5ef","ink":"294339"},
	"ocean":{"name":"Океан","accent":"8ab9d3","background":"eef4f7","ink":"243d50"},
	"terracotta":{"name":"Терракота","accent":"dba087","background":"f9f0e9","ink":"513d36"},
	"lavender":{"name":"Лаванда","accent":"b6a7d3","background":"f3eff8","ink":"3c354d"}
}

static func colors(settings: Dictionary) -> Dictionary:
	var spec: Dictionary = THEMES.get(settings.get("theme", "sunrise"), THEMES.sunrise)
	var dark: bool = settings.get("dark", false)
	var accent = Color(spec.accent)
	var custom: String = settings.get("accent", "")
	if Color.html_is_valid(custom):
		accent = Color(custom)
	return {"accent":accent,"background":Color("1f2c2a") if dark else Color(spec.background),"surface":Color("293a36") if dark else Color("fffdf6"),"ink":Color("f3f0e4") if dark else Color(spec.ink),"muted":Color("b0c5b9") if dark else Color("6e7f76"),"border":Color("43584e") if dark else Color("e0e5da"),"green":Color("8ed1a9") if dark else Color("277456"),"red":Color("efb0a1") if dark else Color("ad554c")}

static func box(color: Color, radius: int = 18, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(14)
	if border.a > 0:
		style.border_color = border
		style.set_border_width_all(1)
	return style

static func build(settings: Dictionary) -> Theme:
	var c = colors(settings)
	var theme = Theme.new()
	theme.default_font_size = 21
	var radius = 18 if settings.get("rounded", true) else 5
	for node in ["Label","Button","CheckButton","OptionButton","LineEdit","SpinBox"]:
		theme.set_color("font_color",node,c.ink)
	theme.set_color("font_hover_color","Button",c.ink)
	theme.set_color("font_pressed_color","Button",c.ink)
	theme.set_color("font_disabled_color","Button",c.muted)
	theme.set_stylebox("normal","Button",box(c.background,radius,c.border))
	theme.set_stylebox("hover","Button",box(c.accent.lightened(0.3),radius))
	theme.set_stylebox("pressed","Button",box(c.accent,radius))
	theme.set_stylebox("focus","Button",box(Color.TRANSPARENT,radius,c.accent))
	theme.set_stylebox("disabled","Button",box(c.background.darkened(0.03),radius))
	theme.set_stylebox("panel","PanelContainer",box(c.surface,radius,c.border))
	theme.set_stylebox("normal","LineEdit",box(c.background,radius,c.border))
	theme.set_stylebox("focus","LineEdit",box(c.background,radius,c.accent))
	theme.set_color("font_uneditable_color","LineEdit",c.muted)
	theme.set_stylebox("normal","OptionButton",box(c.background,radius,c.border))
	theme.set_stylebox("hover","OptionButton",box(c.accent.lightened(0.3),radius))
	theme.set_stylebox("panel","PopupMenu",box(c.surface,radius,c.border))
	theme.set_color("font_color","PopupMenu",c.ink)
	theme.set_color("font_hover_color","PopupMenu",c.ink)
	theme.set_stylebox("hover","PopupMenu",box(c.accent,radius))
	theme.set_constant("separation","VBoxContainer",12)
	theme.set_constant("separation","HBoxContainer",12)
	theme.set_constant("scroll_speed","ScrollContainer",800)
	theme.set_color("font_selected_color","LineEdit",c.ink)
	theme.set_color("selection_color","LineEdit",c.accent)
	return theme
