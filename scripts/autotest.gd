extends Node
# Collaudo automatico: non viene mai eseguito dentro il gioco normale.
var main; var t := 0.0; var phase := 0; var shots := {}
var start_p := Vector3.ZERO; var start_yaw := 0.0; var ammo0 := 0; var results := []
var mode := ""; var outdir := ""; var ap_path := PackedVector3Array(); var ap_i := 0; var ap_t := 0.0; var last_print := 0.0
var maxz := 0

func _ready() -> void:
	mode = main.test_mode
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): outdir = a.substr(6)
	process_mode = Node.PROCESS_MODE_ALWAYS
	if mode.begins_with("sim"):
		main.difficulty = int(mode.substr(3, 1))
		main.start_match()
		if mode.ends_with("idle"): pass
	print("TEST start ", mode)

func _touch(i: int, p: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new(); e.index = i; e.position = p; e.pressed = pressed; Input.parse_input_event(e)
func _drag(i: int, p: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new(); e.index = i; e.position = p; e.relative = rel; Input.parse_input_event(e)
func _shot(n: String) -> void:
	if outdir == "": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [outdir, n])
	print("SHOT ", n, " fps=", Engine.get_frames_per_second(), " draw=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " prim=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
func _ok(n: String, c: bool, info := "") -> void:
	results.append([n, c]); print(("PASS " if c else "FAIL "), n, " ", info)

func _process(dt: float) -> void:
	t += dt
	if mode == "visual": _visual()
	elif mode == "touch": _touch_test()
	elif mode.begins_with("sim"): _sim(dt)
	elif mode == "aim": _aim_test()
	elif mode == "drop": _drop_test()
	elif mode == "look": _look()

var aim_b = null; var aim_case := 0; var aim_shots := 0
func _aim_test() -> void:
	# Bersaglio fermo davanti al giocatore: misura se i colpi arrivano davvero.
	if phase == 0:
		phase = 1; main.start_match(); var pl = main.player; pl.give("ak"); pl.reserve.ak = 900; pl.select("ak")
		for b in main.bots: b.set_physics_process(false); b.global_position = Vector3(300, 0, 200)
		aim_b = main.bots[0]; t = 0.0
		# Sceglie un punto con la linea di tiro libera: gli ostacoli sparsi cambiano con la mappa.
		var pp := Vector3.ZERO
		for k in 400:
			pp = Vector3(randf_range(-300, 300), 0, randf_range(-200, 200))
			if main.world.is_free(pp) and main.world.is_free(pp + Vector3(0, 0, -25)) and main.ray(pp + Vector3(0.9, 1.9, 4), pp + Vector3(0, 1.2, -25), 1).is_empty() and main.ray(pp + Vector3.UP, pp + Vector3(0, 1, -25), 1).is_empty(): break
		pl.global_position = pp; pl.yaw = 0.0; pl.pitch = 0.0
		aim_b.global_position = pp + Vector3(0, 0, -25)
		return
	var pl = main.player
	if phase <= 2:
		# Il giocatore centra il mirino sul nemico, come farebbe con il dito.
		var av: Vector3 = aim_b.global_position + Vector3(0, 1.2, 0) - pl.cam.global_position
		pl.yaw = atan2(-av.x, -av.z); pl.pitch = atan2(av.y, Vector2(av.x, av.z).length())
	if phase == 1 and t > 0.5:
		phase = 2; print("bot a ", aim_b.global_position, " cam ", pl.cam.global_position, " forward ", -pl.cam.global_transform.basis.z, " on_target ", pl.on_target)
		aim_shots = pl.shots_fired; main.hud.fire_held = true; t = 0.0
	elif phase == 2 and t > 0.6:
		main.hud.fire_held = false
		print("25m senza mirare: colpi=", pl.shots_fired - aim_shots, " hp bot=", aim_b.hp, " dead=", aim_b.dead, " vivi=", main.alive)
		_ok("Il mirino centrato colpisce un nemico fermo a 25 m", aim_b.hp < 100.0 or aim_b.dead)
		get_tree().quit(0)

# Primo piano dei soldati per controllare modello, divise e armi.
func _look() -> void:
	if phase == 0:
		phase = 1; main.start_match(); var pl = main.player
		for b in main.bots: b.set_physics_process(false); b.global_position = Vector3(300, 0, 200)
		pl.global_position = Vector3(-60, 0, 30); pl.yaw = 0.0; pl.give("ak"); pl.select("ak"); pl.set_physics_process(false)
		var cam := Camera3D.new(); add_child(cam); cam.fov = 30; cam.global_position = Vector3(-96, 4.0, 74); cam.look_at(Vector3(-110, 1.0, 62)); cam.make_current()
		main.hud.visible = false
		var i := 0
		for b in main.bots.slice(0, 4):
			b.global_position = Vector3(-62.4 + i * 1.6, 0, 30); b.model.rotation.y = [0.0, PI * 0.5, 0.3, PI][i]; b.model.animate(0.2, [0.0, 3.0, 0.0, 6.0][i], i == 2); i += 1
		var m = main.bots[0].model
		for mi in m.inst.find_children("*", "MeshInstance3D", true, false):
			print(mi.get_parent().name, " aabb ", mi.get_aabb(), " y=", mi.global_position.y)
		for n in [m.head, m.torso, m.arm_r, m.leg_l]: print(n.name, " pos ", n.position, " g ", n.global_position)
		pl.global_position = Vector3(-59, 0, 33); pl.model.rotation.y = 0.0 - 0.5; pl.model.animate(0.1, 0.0, false)
		main.bots[3].global_position = Vector3(-57.5, 0, 28); main.bots[3].model.rotation.y = 0.5; main.bots[3].model.die(); main.bots[3].model.animate(1.5, 0, false)
		t = 0.0
	elif phase == 1 and t > 1.2:
		phase = 2; await _shot("10_soldati"); get_tree().quit(0)

var drop_n := 0; var res0 := 0
func _drop_test() -> void:
	# Elimina un nemico sparandogli davvero, poi ci cammina sopra.
	if phase == 0:
		phase = 1; main.start_match(); var pl = main.player
		for b in main.bots: b.set_physics_process(false); b.global_position = Vector3(300, 0, 200)
		aim_b = main.bots[0]; aim_b.gun = "svd"; aim_b.model.set_gun("svd"); t = 0.0
		for l in main.loot: l.n.queue_free()
		main.loot.clear()
		pl.global_position = Vector3(-60, 0, 100); pl.yaw = 0.0
		aim_b.global_position = pl.global_position + Vector3(0, 0, -10)
		return
	var pl = main.player
	if phase <= 2 and not aim_b.dead:
		var v: Vector3 = aim_b.global_position + Vector3(0, 1.2, 0) - pl.cam.global_position
		pl.yaw = atan2(-v.x, -v.z); pl.pitch = atan2(v.y, Vector2(v.x, v.z).length())
	if phase == 2 and t > 15.0:
		_ok("Il nemico muore sotto i colpi", false); get_tree().quit(1)
	if phase == 1 and t > 0.5:
		phase = 2; main.hud.fire_held = true; t = 0.0
	elif phase == 2 and aim_b.dead:
		phase = 3; main.hud.fire_held = false; t = 0.0
		var types := []
		for l in main.loot: types.append(l.type)
		print("oggetti a terra: ", types)
		_ok("Il nemico lascia la sua arma", types.has("svd"))
		_ok("Il nemico lascia i proiettili della sua arma", types.has("ammo_svd"))
		res0 = pl.reserve.svd
		pl.global_position = aim_b.global_position
	elif phase == 3 and t > 0.5:
		phase = 4
		_ok("Passandoci sopra si prende l'arma", pl.owned.has("svd"), str(pl.owned))
		_ok("Passandoci sopra si prendono i proiettili", pl.reserve.svd > res0, "%d -> %d" % [res0, pl.reserve.svd])
		var fails := 0
		for r in results:
			if not r[1]: fails += 1
		get_tree().quit(fails)

func _visual() -> void:
	if phase == 0 and t > 2.0:
		phase = 1; await _shot("01_menu")
	elif phase == 1 and t > 3.0:
		phase = 2; main.difficulty = 1; main.start_match(); var pl = main.player
		pl.global_position = Vector3(-46, 0, 34); pl.yaw = 0.15; pl.pitch = 0.0
		for b in main.bots: b.set_physics_process(false)
		var i := 0
		for b in main.bots.slice(0, 4):
			b.global_position = pl.global_position + Vector3(-6 + i * 3.5, 0, -8 - i * 3); b.rotation.y = 0.5 * i; b.model.rotation.y = PI * 0.6 * (i + 1); b.model.animate(0.25, 3.0 + i, i == 1); i += 1
		main.bots[3].take_damage(500.0)
	elif phase == 2 and t > 6.0:
		var q = main.player; print("MODEL vis=", q.model.is_visible_in_tree(), " pos=", q.model.global_position, " torso=", q.model.torso.global_position, " cam=", q.cam.global_position, " len=", q.arm.spring_length, " children=", q.model.get_child_count())
		phase = 3; await _shot("02_gioco_piazzale"); main.player.give("ak"); main.player.give("svd")
		main.player.global_position = Vector3(2, 0, -44); main.player.yaw = 0.0; main.player.select("ak")
	elif phase == 3 and t > 8.0:
		phase = 4; await _shot("03_hangar_mriya")
		main.player.global_position = Vector3(55, 0, -135); main.player.yaw = 1.2; main.player.pitch = 0.06
	elif phase == 4 and t > 10.0:
		phase = 5; await _shot("04_dentro_hangar")
		main.player.global_position = Vector3(-140, 0, 120); main.player.yaw = -1.0; main.z_radius = 120.0; main.z_center = Vector2(-140, 40); main.z_from_r = 120.0; main.z_from_c = main.z_center; main.z_t = 60
	elif phase == 5 and t > 12.0:
		phase = 6; await _shot("05_pista_zona")
		main.player.global_position = Vector3(-46, 0, 34); main.player.yaw = 0.15; main.hud.add_hit(main.player.global_position + Vector3(10, 0, 0)); main.player.hp = 42; main.player.armor = 40; main.player.medkits = 2; main.hud.fire_held = true
	elif phase == 6 and t > 12.4:
		phase = 7; await _shot("06_spara_danno"); main.hud.fire_held = false; main.player.select("svd"); main.player.aiming = true
	elif phase == 7 and t > 14.0:
		phase = 8; await _shot("07_mirino_svd"); main.player.aiming = false
		main.mode = main.PLAY; main._end(true)
	elif phase == 8 and t > 15.0:
		phase = 9; await _shot("08_vittoria")
	elif phase == 9 and t > 16.0:
		print("TEST visual done"); get_tree().quit(0)

func _vp() -> Vector2:
	return get_viewport().get_visible_rect().size

func _touch_test() -> void:
	# Le coordinate iniettate sono quelle reali dello schermo (2400x1080), come su un S21.
	var scale_k: float = DisplayServer.window_get_size().y / 720.0
	var S := func(p: Vector2) -> Vector2: return p * scale_k
	var hud = main.hud
	if phase == 0 and t > 1.0:
		phase = 1
		var b: Button = hud.menu_box.find_children("*", "Button", true, false)[2]
		var c := b.get_global_rect().get_center() * scale_k
		_touch(0, c, true); print("tap su COMBATTI ", c)
	elif phase == 1 and t > 1.2:
		phase = 2; var b: Button = hud.menu_box.find_children("*", "Button", true, false)[2]
		_touch(0, b.get_global_rect().get_center() * scale_k, false)
	elif phase == 2 and t > 1.7:
		phase = 3; _ok("Tap su COMBATTI avvia la partita", main.mode == main.PLAY)
		for b in main.bots: b.set_physics_process(false)
		var pl = main.player; start_p = pl.global_position; start_yaw = pl.yaw
		_touch(1, S.call(Vector2(180, 560)), true)
	elif phase == 3 and t > 1.8:
		phase = 4; _drag(1, S.call(Vector2(180, 520)), S.call(Vector2(0, -40)))
	elif phase == 4 and t > 2.8:
		phase = 5; var d: float = main.player.global_position.distance_to(start_p)
		_ok("Il joystick muove il giocatore", d > 1.0, "spostamento %.2f m" % d)
		start_p = main.player.global_position
		_drag(1, S.call(Vector2(180, 460)), S.call(Vector2(0, -60)))
	elif phase == 5 and t > 3.8:
		phase = 6; var d: float = main.player.global_position.distance_to(start_p)
		_ok("Stick in fondo = corsa", main.player.was_sprint or d > 4.5, "%.2f m/s" % d)
		_touch(1, S.call(Vector2(180, 460)), false)
		_touch(2, S.call(Vector2(1000, 300)), true); start_yaw = main.player.yaw
	elif phase == 6 and t > 3.9:
		phase = 7; _drag(2, S.call(Vector2(1120, 300)), S.call(Vector2(120, 0)))
	elif phase == 7 and t > 4.1:
		phase = 8; var dy: float = main.player.yaw - start_yaw
		_ok("Trascinare a destra gira la visuale a destra", dy < -0.05, "%.3f rad" % dy)
		_touch(2, S.call(Vector2(1120, 300)), false)
		ammo0 = main.player.mag.pistol
		hud._layout(); _touch(3, hud.buttons.fire.p * scale_k, true)
		start_yaw = main.player.yaw
	elif phase == 8 and t > 4.2:
		phase = 9; _drag(3, (hud.buttons.fire.p + Vector2(-30, 0)) * scale_k, S.call(Vector2(-30, 0)))
		_touch(4, S.call(Vector2(180, 560)), true)
		_drag(4, S.call(Vector2(220, 560)), S.call(Vector2(40, 0)))
	elif phase == 9 and t > 4.8:
		phase = 10; _ok("SPARA spara", main.player.mag.pistol < ammo0, "%d->%d" % [ammo0, main.player.mag.pistol])
		_ok("Multitouch: si spara, si mira trascinando e ci si muove insieme", main.player.yaw != start_yaw and absf(hud.move_vec.x) > 0.3)
		_touch(3, hud.buttons.fire.p * scale_k, false); _touch(4, S.call(Vector2(220, 560)), false)
		var mg: int = main.player.mag.pistol
		_touch(5, hud.buttons.reload.p * scale_k, true); _touch(5, hud.buttons.reload.p * scale_k, false)
		ammo0 = mg
	elif phase == 10 and t > 7.0:
		phase = 11; _ok("RICARICA riempie il caricatore", main.player.mag.pistol == 12, str(main.player.mag.pistol))
		_touch(5, hud.buttons.crouch.p * scale_k, true); _touch(5, hud.buttons.crouch.p * scale_k, false)
		_touch(5, hud.buttons.aim.p * scale_k, true); _touch(5, hud.buttons.aim.p * scale_k, false)
	elif phase == 11 and t > 7.2:
		phase = 12; _ok("GIÙ e MIRA rispondono", main.player.crouching and main.player.aiming)
		main.player.give("ak"); hud._layout()
		_touch(5, hud.buttons.w_pistol.p * scale_k, true); _touch(5, hud.buttons.w_pistol.p * scale_k, false)
	elif phase == 12 and t > 7.4:
		phase = 13; _ok("Si cambia arma toccando lo slot", main.player.cur == "pistol", main.player.cur)
		main.player.hp = 50; _touch(5, hud.buttons.heal.p * scale_k, true); _touch(5, hud.buttons.heal.p * scale_k, false)
	elif phase == 13 and t > 10.7:
		phase = 14; _ok("CURA usa un kit medico", main.player.hp > 90 and main.player.medkits == 0, "hp %.0f" % main.player.hp)
		_touch(5, hud.buttons.pause.p * scale_k, true); _touch(5, hud.buttons.pause.p * scale_k, false)
	elif phase == 14 and t > 11.0:
		phase = 15; _ok("Pausa", get_tree().paused and hud.pause_box.visible)
		var b: Button = hud.pause_box.find_children("*", "Button", true, false)[0]
		var c := b.get_global_rect().get_center() * scale_k; _touch(6, c, true); _touch(6, c, false)
	elif phase == 15 and t > 11.4:
		phase = 16; _ok("Riprendi dalla pausa", not get_tree().paused)
		var fails := 0
		for r in results:
			if not r[1]: fails += 1
		print("TEST touch done, falliti: ", fails); get_tree().quit(fails)

func _sim(dt: float) -> void:
	var pl = main.player
	if main.mode == main.END:
		if phase == 0:
			phase = 1
			print("RESULT win=", not pl.dead, " kills=", main.kills, "/", main.total, " alive=", main.alive, " time=%.0f" % main.match_t, " hp=%.0f" % pl.hp, " shots=", pl.shots_fired, " zone_phase=", main.z_phase, " owned=", pl.owned)
			get_tree().quit(0)
		return
	if main.match_t - last_print > 60.0:
		last_print = main.match_t
		var moving := 0; var eng := 0; var zoneout := 0
		for b in main.bots:
			if b.dead: continue
			if b.speed_now > 0.3: moving += 1
			if b.state == 1: eng += 1
			if not main.in_zone(b.global_position): zoneout += 1
		print("t=%.0f alive=%d hp=%.0f r=%.0f moving=%d engaging=%d outzone=%d" % [main.match_t, main.alive, pl.hp, main.z_radius, moving, eng, zoneout])
	if mode.ends_with("idle"): return
	# pilota automatico: cura, entra in zona, cerca armi vicine, attacca chi vede
	if pl.hp < 55 and pl.medkits > 0: pl.heal()
	var near = null; var nd := 1e9; var vis := false
	for b in main.bots:
		if b.dead: continue
		var d: float = b.global_position.distance_to(pl.global_position)
		var s: bool = d < 200.0 and main.ray(pl.global_position + Vector3.UP * 1.5, b.global_position + Vector3.UP * 1.2, 1).is_empty()
		if s and (not vis or d < nd): near = b; nd = d; vis = true
		elif not vis and d < nd: near = b; nd = d
	var goal: Vector3 = near.global_position if near else pl.global_position
	if not main.in_zone(pl.global_position) or (main.z_shrinking and Vector2(pl.global_position.x, pl.global_position.z).distance_to(main.z_to_c) > main.z_to_r - 5.0):
		goal = Vector3(main.z_to_c.x, 0, main.z_to_c.y)
		vis = vis and nd < 40.0
	elif not pl.owned.has("ak") or pl.medkits == 0 or pl.reserve.ak < 30:
		var ld := 90.0
		for l in main.loot:
			var d: float = l.n.global_position.distance_to(pl.global_position)
			if d < ld: ld = d; goal = l.n.global_position
	if vis and near != null:
		var v: Vector3 = near.global_position + Vector3(0, 1.2, 0) - pl.cam.global_position
		pl.yaw = atan2(-v.x, -v.z) + randf_range(-0.02, 0.02)
		pl.pitch = atan2(v.y, Vector2(v.x, v.z).length())
		main.hud.fire_held = nd < float(pl.w().range) * 0.85
		if pl.owned.has("ak") and pl.reserve.ak + pl.mag.ak > 0: pl.select("ak")
	else:
		main.hud.fire_held = false
	ap_t -= dt
	if ap_t <= 0.0 or ap_i >= ap_path.size():
		ap_t = 1.0; ap_path = main.world.find_path(pl.global_position, goal); ap_i = 1
	if ap_i < ap_path.size():
		var w: Vector3 = ap_path[ap_i]
		if w.distance_to(pl.global_position) < 1.5: ap_i += 1
		var g: Vector3 = w - pl.global_position; g.y = 0
		if vis and nd < 45: g = Vector3.ZERO
		if g.length() > 0.1:
			var dirw: Vector3 = g.normalized()
			var fwd := Vector3(-sin(pl.yaw), 0, -cos(pl.yaw)); var right := Vector3(cos(pl.yaw), 0, -sin(pl.yaw))
			main.hud.move_vec = Vector2(dirw.dot(right), -dirw.dot(fwd))
		else: main.hud.move_vec = Vector2.ZERO
