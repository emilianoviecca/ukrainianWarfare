extends Control
const W := preload("res://scripts/weapons.gd")
const PLAY_MODE := 1
var main
var font: Font; var bold: Font
var move_vec := Vector2.ZERO; var fire_held := false; var look_acc := Vector2.ZERO
var joy_touch := -1; var joy_origin := Vector2.ZERO; var joy_pos := Vector2.ZERO
var look_touch := -1; var fire_touch := -1; var fire2_touch := -1
var active := false
var msg := ""; var msg_t := 0.0; var msg2 := ""; var msg2_t := 0.0
var hits := []; var pings := []; var hitmark_t := 0.0; var hitmark_head := false; var dmg_flash := 0.0; var kill_t := 0.0
var map_tex: Texture2D
var buttons := {}
var menu_box: Control; var end_box: Control; var pause_box: Control
var btn_diff: Button; var btn_sens: Button
const FG := Color(0.97, 0.97, 0.93)
const DIM := Color(0, 0, 0, 0.42)
const YEL := Color(1.0, 0.82, 0.12)
const BLU := Color(0.15, 0.48, 0.92)
const RED := Color(0.95, 0.20, 0.17)

func build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font
	var fv := FontVariation.new(); fv.base_font = font; fv.variation_embolden = 0.7; bold = fv
	var img := Image.new(); img.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/minimap.dat")); map_tex = ImageTexture.create_from_image(img)
	_build_menu()

func _style(col: Color, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new(); s.bg_color = col; s.border_color = border; s.set_border_width_all(2 if border.a > 0 else 0); s.set_corner_radius_all(10)
	s.content_margin_left = 22; s.content_margin_right = 22; s.content_margin_top = 12; s.content_margin_bottom = 12
	return s

func _button(text: String, cb: Callable, primary := false) -> Button:
	var b := Button.new(); b.text = text; b.custom_minimum_size = Vector2(0, 66)
	b.add_theme_font_size_override("font_size", 25)
	b.add_theme_font_override("font", bold if primary else font)
	var col := YEL if primary else Color(1, 1, 1, 0.13)
	var fg := Color(0.06, 0.08, 0.14) if primary else FG
	b.add_theme_color_override("font_color", fg); b.add_theme_color_override("font_hover_color", fg); b.add_theme_color_override("font_pressed_color", fg); b.add_theme_color_override("font_focus_color", fg)
	for st in ["normal", "hover", "focus"]:
		b.add_theme_stylebox_override(st, _style(col, Color(1, 1, 1, 0.32) if not primary else Color(0, 0, 0, 0)))
	b.add_theme_stylebox_override("pressed", _style(col.darkened(0.2)))
	b.pressed.connect(cb)
	return b

func _label(text: String, size_f: int, col := FG, is_bold := false) -> Label:
	var l := Label.new(); l.text = text; l.add_theme_font_size_override("font_size", size_f); l.add_theme_color_override("font_color", col)
	if is_bold: l.add_theme_font_override("font", bold)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _panel_host(left_align: bool) -> VBoxContainer:
	var host := PanelContainer.new()
	var st := _style(Color(0.035, 0.05, 0.075, 0.9)); st.set_corner_radius_all(0); st.content_margin_left = 62; st.content_margin_right = 52; st.content_margin_top = 26; st.content_margin_bottom = 26
	host.add_theme_stylebox_override("panel", st)
	add_child(host)
	if left_align:
		host.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE); host.offset_right = 640
	else:
		host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 9); host.add_child(v)
	if not left_align: v.alignment = BoxContainer.ALIGNMENT_CENTER
	return v

func _flag_bar() -> Control:
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 0)
	for c in [BLU, YEL]:
		var r := ColorRect.new(); r.color = c; r.custom_minimum_size = Vector2(52, 7); h.add_child(r)
	return h

func _build_menu() -> void:
	var v := _panel_host(true); menu_box = v.get_parent()
	v.add_child(_flag_bar())
	v.add_child(_label("UKRAINIAN WARFARE", 44, FG, true))
	v.add_child(_label("Hostomel, 24 febbraio 2022 · Aeroporto Antonov", 20, YEL))
	var desc := _label("Le truppe aviotrasportate russe assaltano l'aeroporto. Sei un difensore ucraino: raccogli armi, resta nella zona sicura ed elimina ogni nemico.", 20)
	desc.custom_minimum_size = Vector2(520, 0); v.add_child(desc)
	var gap := Control.new(); gap.size_flags_vertical = Control.SIZE_EXPAND_FILL; v.add_child(gap)
	btn_diff = _button("", _cycle_diff); v.add_child(btn_diff)
	btn_sens = _button("", _cycle_sens); v.add_child(btn_sens)
	v.add_child(_button("COMBATTI", func(): main.start_match(), true))
	_refresh_menu()

func _refresh_menu() -> void:
	var d: Dictionary = main.DIFF[main.difficulty]
	btn_diff.text = "Difficoltà: %s · %d nemici" % [d.name, d.bots]
	btn_sens.text = "Sensibilità visuale: %s" % ["bassa", "media", "alta"][main.sensitivity]

func _cycle_diff() -> void:
	main.difficulty = (main.difficulty + 1) % 3; main.save_settings(); _refresh_menu()

func _cycle_sens() -> void:
	main.sensitivity = (main.sensitivity + 1) % 3; main.save_settings(); _refresh_menu()

func set_mode(_m: int) -> void:
	menu_box.visible = false; active = true; mouse_filter = Control.MOUSE_FILTER_IGNORE

func show_pause(p: bool) -> void:
	if pause_box == null:
		var v := _panel_host(false); pause_box = v.get_parent()
		var st: StyleBoxFlat = pause_box.get_theme_stylebox("panel").duplicate(); st.bg_color = Color(0.03, 0.04, 0.06, 0.78); st.content_margin_left = 360; st.content_margin_right = 360; pause_box.add_theme_stylebox_override("panel", st)
		var t := _label("PAUSA", 44, FG, true); t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(t)
		v.add_child(_button("RIPRENDI", func(): main.toggle_pause(false), true))
		v.add_child(_button("Ricomincia", func(): main.restart()))
		v.add_child(_button("Menu principale", func(): main.to_menu()))
	pause_box.visible = p; active = not p
	_reset_touches()

func _reset_touches() -> void:
	joy_touch = -1; look_touch = -1; fire_touch = -1; fire2_touch = -1; move_vec = Vector2.ZERO; fire_held = false

func show_end(win: bool, kills: int, total: int, place: int, t: float) -> void:
	active = false; _reset_touches()
	var v := _panel_host(false); end_box = v.get_parent()
	var st: StyleBoxFlat = end_box.get_theme_stylebox("panel").duplicate(); st.bg_color = Color(0.02, 0.03, 0.05, 0.72); st.content_margin_left = 300; st.content_margin_right = 300; end_box.add_theme_stylebox_override("panel", st)
	var flag := CenterContainer.new(); flag.add_child(_flag_bar()); v.add_child(flag)
	var title := _label("AEROPORTO DIFESO" if win else "SEI CADUTO", 56, YEL if win else FG, true); title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(title)
	var sub := "Ultimo in piedi: tutti i nemici sono stati eliminati." if win else "Hai resistito fino al %d° posto su %d." % [place, total + 1]
	var s := _label(sub, 23); s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(s)
	var st2 := _label("Eliminazioni: %d   ·   Tempo: %d:%02d" % [kills, int(t) / 60, int(t) % 60], 23, FG); st2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(st2)
	var g := Control.new(); g.custom_minimum_size = Vector2(0, 14); v.add_child(g)
	v.add_child(_button("RIGIOCA", func(): main.restart(), true))
	v.add_child(_button("Menu principale", func(): main.to_menu()))

func message(t: String, secs: float) -> void:
	msg = t; msg_t = secs
func message2(t: String, secs: float) -> void:
	msg2 = t; msg2_t = secs
func add_hit(from: Vector3) -> void:
	hits.append({"p": from, "t": 1.3}); dmg_flash = min(dmg_flash + 0.45, 1.0)
func flash_damage(a: float) -> void:
	dmg_flash = min(dmg_flash + a, 0.8)
func add_ping(p: Vector3) -> void:
	for e in pings:
		if e.p.distance_squared_to(p) < 16.0:
			e.t = 2.0; return
	if pings.size() < 8: pings.append({"p": p, "t": 2.0})
func show_hitmarker(head: bool) -> void:
	hitmark_t = 0.22; hitmark_head = head
func kill_note() -> void:
	kill_t = 1.6
func take_look() -> Vector2:
	var v := look_acc; look_acc = Vector2.ZERO; return v

# --- layout comandi (coordinate del viewport) ---
func _layout() -> void:
	var s := get_viewport_rect().size
	buttons = {
		"fire": {"p": Vector2(s.x - 142, s.y - 150), "r": 82.0},
		"fire2": {"p": Vector2(92, s.y - 322), "r": 50.0},
		"aim": {"p": Vector2(s.x - 298, s.y - 92), "r": 52.0},
		"reload": {"p": Vector2(s.x - 298, s.y - 218), "r": 48.0},
		"crouch": {"p": Vector2(s.x - 76, s.y - 320), "r": 48.0},
		"heal": {"p": Vector2(s.x - 188, s.y - 342), "r": 48.0},
		"pause": {"p": Vector2(s.x - 50, 124), "r": 30.0},
	}
	var owned: Array = main.player.owned if main.player else ["pistol"]
	var total_w := 164.0 * owned.size(); var x0 := s.x / 2 - total_w / 2 + 82
	for i in owned.size():
		buttons["w_" + owned[i]] = {"p": Vector2(x0 + i * 164.0, s.y - 48), "r": 46.0, "wide": 78.0}

func _hit_button(p: Vector2) -> String:
	for k in buttons:
		var b = buttons[k]
		if b.has("wide"):
			if absf(p.x - b.p.x) < b.wide and absf(p.y - b.p.y) < 40.0: return k
		elif p.distance_to(b.p) < b.r + 12.0:
			return k
	return ""

func _input(event: InputEvent) -> void:
	if not active or main.mode != main.PLAY: return
	if event is InputEventScreenTouch:
		_touch(event.index, event.position, event.pressed); get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_drag(event.index, event.position, event.relative); get_viewport().set_input_as_handled()

func _touch(i: int, p: Vector2, pressed: bool) -> void:
	if pressed:
		_layout()
		var k := _hit_button(p)
		match k:
			"fire": fire_touch = i; fire_held = true; return
			"fire2": fire2_touch = i; fire_held = true; return
			"aim": main.player.toggle_aim(); return
			"reload": main.player.reload(); return
			"crouch": main.player.toggle_crouch(); return
			"heal": main.player.heal(); return
			"pause": main.toggle_pause(true); return
		if k.begins_with("w_"):
			main.player.select(k.substr(2)); return
		if p.x < get_viewport_rect().size.x * 0.42 and joy_touch < 0:
			joy_touch = i; joy_origin = p; joy_pos = p; move_vec = Vector2.ZERO
		elif look_touch < 0:
			look_touch = i
	else:
		if i == joy_touch: joy_touch = -1; move_vec = Vector2.ZERO
		if i == look_touch: look_touch = -1
		if i == fire_touch: fire_touch = -1
		if i == fire2_touch: fire2_touch = -1
		fire_held = fire_touch >= 0 or fire2_touch >= 0

func _drag(i: int, p: Vector2, rel: Vector2) -> void:
	if i == joy_touch:
		joy_pos = p
		var d := p - joy_origin
		move_vec = (d / 74.0).limit_length(1.0)
		if d.length() > 94.0: joy_origin = p - d.normalized() * 94.0
	elif i == look_touch or i == fire_touch or i == fire2_touch:
		look_acc += rel

func _process(dt: float) -> void:
	msg_t -= dt; msg2_t -= dt; hitmark_t -= dt; kill_t -= dt
	dmg_flash = max(dmg_flash - dt * 1.1, 0.0)
	for arr in [hits, pings]:
		for j in range(arr.size() - 1, -1, -1):
			arr[j].t -= dt
			if arr[j].t <= 0.0: arr.remove_at(j)
	queue_redraw()

func _txt(p: Vector2, t: String, s: int, c := FG, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0, f: Font = null) -> void:
	var ff: Font = f if f != null else bold
	draw_string_outline(ff, p, t, align, w, s, 5, Color(0, 0, 0, 0.75))
	draw_string(ff, p, t, align, w, s, c)

func _ctr(p: Vector2, t: String, s: int, c := FG) -> void:
	_txt(p - Vector2(600, -s * 0.34), t, s, c, HORIZONTAL_ALIGNMENT_CENTER, 1200.0)

func _btn(k: String, label: String, on := false, col := FG) -> void:
	var b = buttons[k]
	draw_circle(b.p, b.r, Color(YEL.r, YEL.g, YEL.b, 0.55) if on else DIM)
	draw_arc(b.p, b.r, 0, TAU, 40, Color(1, 1, 1, 0.55), 2.5, true)
	_ctr(b.p, label, 19 if b.r < 70 else 24, col)

func _draw() -> void:
	if main == null or main.mode == main.MENU or main.player == null: return
	var s := get_viewport_rect().size
	_layout()
	var pl = main.player
	if pl.scoped() and pl.cam.fov < 25.0: _scope(s)
	if main.mode == main.PLAY:
		_crosshair(s, pl)
		_controls(s, pl)
	_status(s, pl)
	_minimap(s, pl)
	_compass(s, pl)
	if dmg_flash > 0.0: _vignette(s, Color(0.7, 0.03, 0.02, dmg_flash * 0.45))
	for h in hits: _hit_arc(s, pl, h)
	if msg_t > 0.0:
		_ctr(Vector2(s.x / 2, 150), msg, 25, Color(FG.r, FG.g, FG.b, clampf(msg_t * 2.0, 0, 1)))
	if msg2_t > 0.0:
		_ctr(Vector2(s.x / 2, 186), msg2, 20, Color(FG.r, FG.g, FG.b, clampf(msg2_t * 2.0, 0, 1)))
	if kill_t > 0.0:
		_ctr(Vector2(s.x / 2, s.y * 0.36), "NEMICO ELIMINATO", 26, Color(YEL.r, YEL.g, YEL.b, clampf(kill_t * 2.0, 0, 1)))

func _scope(s: Vector2) -> void:
	var c := s / 2; var r := s.y * 0.46
	draw_rect(Rect2(0, 0, c.x - r, s.y), Color.BLACK); draw_rect(Rect2(c.x + r, 0, c.x - r + 2, s.y), Color.BLACK)
	draw_arc(c, r + 90, 0, TAU, 72, Color.BLACK, 182, false)
	draw_arc(c, r, 0, TAU, 72, Color(0.2, 0.2, 0.2), 3, true)

func _crosshair(s: Vector2, pl) -> void:
	var c := s / 2
	var col := RED if pl.on_target else Color(1, 1, 1, 0.92)
	if pl.scoped() and pl.cam.fov < 25.0:
		draw_line(c - Vector2(s.y * 0.46, 0), c - Vector2(7, 0), Color(0, 0, 0, 0.9), 1.5); draw_line(c + Vector2(7, 0), c + Vector2(s.y * 0.46, 0), Color(0, 0, 0, 0.9), 1.5)
		draw_line(c + Vector2(0, 7), c + Vector2(0, s.y * 0.46), Color(0, 0, 0, 0.9), 1.5); draw_circle(c, 1.6, col)
	else:
		var gap := 7.0 if pl.aiming else 12.0 + clampf(pl.speed_now, 0, 6) * 1.5
		for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_line(c + d * gap, c + d * (gap + 11), Color(0, 0, 0, 0.5), 4.0); draw_line(c + d * gap, c + d * (gap + 11), col, 2.0)
		draw_circle(c, 1.7, col)
	if hitmark_t > 0.0:
		var hc := RED if hitmark_head else FG
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + d * 11, c + d * 22, hc, 3.0)

func _controls(s: Vector2, pl) -> void:
	# stick sinistro
	var o: Vector2 = joy_origin if joy_touch >= 0 else Vector2(180, s.y - 160)
	draw_circle(o, 92, Color(0, 0, 0, 0.22)); draw_arc(o, 92, 0, TAU, 48, Color(1, 1, 1, 0.4), 2.5, true)
	var k: Vector2 = joy_pos if joy_touch >= 0 else o
	k = o + (k - o).limit_length(74.0)
	draw_circle(k, 38, Color(1, 1, 1, 0.42))
	if pl.was_sprint: draw_arc(o, 92, -PI * 0.75, -PI * 0.25, 18, YEL, 6.0, true)
	if joy_touch < 0: _txt(o + Vector2(-90, 124), "muoviti", 17, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_CENTER, 180.0)
	_btn("fire", "SPARA", fire_held, FG)
	_btn("fire2", "SPARA", fire_held, FG)
	_btn("aim", "MIRA", pl.aiming, FG)
	_btn("reload", "RICARICA" if false else "RICAR.", pl.reload_t > 0.0)
	_btn("crouch", "GIÙ", pl.crouching)
	_btn("heal", "CURA %d" % pl.medkits, pl.heal_t > 0.0, FG if pl.medkits > 0 else Color(1, 1, 1, 0.4))
	_btn("pause", "II")
	for kk in pl.owned:
		var b = buttons["w_" + kk]; var sel: bool = kk == pl.cur
		var r := Rect2(b.p - Vector2(78, 38), Vector2(156, 76))
		draw_rect(r, Color(YEL.r, YEL.g, YEL.b, 0.92) if sel else Color(0, 0, 0, 0.5))
		if not sel: draw_rect(r, Color(1, 1, 1, 0.42), false, 2.0)
		var tc: Color = Color(0.05, 0.06, 0.1) if sel else FG
		draw_string(bold, r.position + Vector2(0, 28), W.DATA[kk].name, HORIZONTAL_ALIGNMENT_CENTER, 156, 20, tc)
		draw_string(bold, r.position + Vector2(0, 61), "%d / %d" % [pl.mag[kk], pl.reserve[kk]], HORIZONTAL_ALIGNMENT_CENTER, 156, 23, tc)

func _status(s: Vector2, pl) -> void:
	# vita e corazza sopra le armi, al centro
	var bw := 396.0; var x := s.x / 2 - bw / 2; var y := s.y - 121.0
	draw_rect(Rect2(x - 2, y - 2, bw + 4, 18), Color(0, 0, 0, 0.6))
	var hp_c := FG if pl.hp > 45 else (YEL if pl.hp > 22 else RED)
	draw_rect(Rect2(x, y, bw * pl.hp / 100.0, 14), hp_c)
	if pl.armor > 0.0:
		draw_rect(Rect2(x - 2, y - 11, bw + 4, 8), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(x, y - 9.5, bw * pl.armor / 100.0, 5), Color(0.35, 0.68, 1.0))
	var prog := -1.0; var ptxt := ""
	if pl.reload_t > 0.0: prog = 1.0 - pl.reload_t / float(pl.w().reload); ptxt = "Ricarica"
	elif pl.heal_t > 0.0: prog = 1.0 - pl.heal_t / 3.0; ptxt = "Medicazione"
	if prog >= 0.0:
		var c := s / 2 + Vector2(0, 66)
		draw_arc(c, 24, -PI / 2, -PI / 2 + TAU * prog, 40, YEL, 6.0, true)
		_ctr(c + Vector2(0, 46), ptxt, 19)
	# contatori
	_txt(Vector2(s.x - 322, 56), "Nemici %d" % main.alive, 30, FG, HORIZONTAL_ALIGNMENT_RIGHT, 250.0)
	_txt(Vector2(s.x - 322, 86), "Eliminati %d" % main.kills, 21, YEL, HORIZONTAL_ALIGNMENT_RIGHT, 250.0)
	# stato zona
	var z: Dictionary = main.zone_info()
	var ztext := ""
	if main.z_phase < main.PHASES.size():
		ztext = ("Zona in chiusura: %ds" if z.shrinking else "Prossima chiusura: %ds") % int(max(z.t, 0.0))
	var outside: bool = not main.in_zone(pl.global_position)
	var mp := Rect2(38, 20, 214, 153)
	_txt(mp.position + Vector2(0, mp.size.y + 25), ztext, 18, RED if outside or z.shrinking else FG, HORIZONTAL_ALIGNMENT_LEFT, 300.0)

func _w2m(p: Vector2, r: Rect2) -> Vector2:
	return r.position + Vector2((p.x + 350.0) / 700.0 * r.size.x, (p.y + 250.0) / 500.0 * r.size.y)

func _minimap(_s: Vector2, pl) -> void:
	var r := Rect2(38, 20, 214, 153)
	draw_texture_rect(map_tex, r, false, Color(0.82, 0.82, 0.82, 0.95))
	for m in main.world.mini_rects:
		var a := _w2m(m.position, r); var b := _w2m(m.end, r)
		draw_rect(Rect2(a, b - a), Color(0.12, 0.13, 0.15, 0.9))
	draw_rect(r, Color(1, 1, 1, 0.7), false, 2.0)
	var k := r.size.x / 700.0
	var zr: float = main.z_radius * k
	# Disegno del cerchio ritagliato: limitato alla mappa con punti calcolati a mano
	_clipped_circle(_w2m(main.z_center, r), zr, r, Color(0.2, 0.75, 1.0), 2.5)
	if main.z_phase < main.PHASES.size():
		_clipped_circle(_w2m(main.z_to_c, r), main.z_to_r * k, r, Color(1, 1, 1, 0.95), 1.6)
	for e in pings:
		var q := _w2m(Vector2(e.p.x, e.p.z), r)
		draw_circle(q, 3.2, Color(RED.r, RED.g, RED.b, clampf(e.t, 0, 1)))
	for l in main.loot:
		pass
	var pp := _w2m(Vector2(pl.global_position.x, pl.global_position.z), r)
	var d := Vector2(-sin(pl.yaw), -cos(pl.yaw)); var n := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([pp + d * 9, pp - d * 5 + n * 5.5, pp - d * 5 - n * 5.5]), YEL)
	draw_polyline(PackedVector2Array([pp + d * 9, pp - d * 5 + n * 5.5, pp - d * 5 - n * 5.5, pp + d * 9]), Color.BLACK, 1.2, true)

func _clipped_circle(c: Vector2, rad: float, r: Rect2, col: Color, w: float) -> void:
	var prev := Vector2.ZERO; var prev_in := false
	for i in 73:
		var a := TAU * i / 72.0; var q := c + Vector2(cos(a), sin(a)) * rad
		var inn := r.has_point(q)
		if i > 0 and inn and prev_in: draw_line(prev, q, col, w, true)
		prev = q; prev_in = inn

func _compass(s: Vector2, pl) -> void:
	var cx := s.x / 2; var y := 48.0; var hw := 245.0
	draw_rect(Rect2(cx - hw, y - 30, hw * 2, 38), Color(0, 0, 0, 0.3))
	var head := fposmod(rad_to_deg(-pl.yaw), 360.0)
	var names := {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SO", 270: "O", 315: "NO"}
	for deg in range(0, 360, 15):
		var rel := fposmod(deg - head + 180.0, 360.0) - 180.0
		if absf(rel) > 60: continue
		var x: float = cx + rel / 60.0 * hw
		if names.has(deg):
			var big: bool = deg % 90 == 0
			draw_string(bold, Vector2(x - 40, y - 8), names[deg], HORIZONTAL_ALIGNMENT_CENTER, 80, 21 if big else 16, YEL if deg == 0 else FG)
		else:
			draw_line(Vector2(x, y - 2), Vector2(x, y + 5), Color(1, 1, 1, 0.7), 2.0)
	draw_colored_polygon(PackedVector2Array([Vector2(cx, y + 2), Vector2(cx - 7, y + 15), Vector2(cx + 7, y + 15)]), YEL)
	# direzione della zona sicura
	var zp: Vector2 = main.z_to_c
	var to := Vector2(zp.x - pl.global_position.x, zp.y - pl.global_position.z)
	if to.length() > main.z_to_r:
		var b := fposmod(rad_to_deg(atan2(to.x, -to.y)) - head + 180.0, 360.0) - 180.0
		var bx: float = cx + clampf(b, -60.0, 60.0) / 60.0 * hw
		draw_circle(Vector2(bx, y + 11), 5.0, Color(0.2, 0.75, 1.0))

func _vignette(s: Vector2, c: Color) -> void:
	var t := 90.0; var clear := Color(c.r, c.g, c.b, 0.0)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), Vector2(s.x, t), Vector2(0, t)]), PackedColorArray([c, c, clear, clear]))
	draw_polygon(PackedVector2Array([Vector2(0, s.y), Vector2(s.x, s.y), Vector2(s.x, s.y - t), Vector2(0, s.y - t)]), PackedColorArray([c, c, clear, clear]))
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(0, s.y), Vector2(t * 1.5, s.y), Vector2(t * 1.5, 0)]), PackedColorArray([c, c, clear, clear]))
	draw_polygon(PackedVector2Array([Vector2(s.x, 0), Vector2(s.x, s.y), Vector2(s.x - t * 1.5, s.y), Vector2(s.x - t * 1.5, 0)]), PackedColorArray([c, c, clear, clear]))

func _hit_arc(s: Vector2, pl, h) -> void:
	var to: Vector3 = h.p - pl.global_position
	var world_a := atan2(to.x, to.z)
	var rel: float = world_a - (pl.yaw + PI)
	var c := s / 2; var a: float = -PI / 2 + rel
	var col := Color(RED.r, RED.g, RED.b, clampf(h.t, 0.0, 0.9))
	draw_arc(c, 152, a - 0.33, a + 0.33, 20, col, 11.0, true)
