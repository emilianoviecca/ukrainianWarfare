extends Node3D
const World := preload("res://scripts/world.gd")
const Player := preload("res://scripts/player.gd")
const Bot := preload("res://scripts/bot.gd")
const Hud := preload("res://scripts/hud.gd")
const Fx := preload("res://scripts/fx.gd")
const Batch := preload("res://scripts/mesh_batch.gd")
const Humanoid := preload("res://scripts/humanoid.gd")
enum { MENU, PLAY, END }
const DIFF := [
	{"name": "Recluta", "bots": 14, "dmg": 0.6, "skill": 0.7, "tokens": 1, "vision": 75.0},
	{"name": "Soldato", "bots": 20, "dmg": 0.8, "skill": 0.85, "tokens": 2, "vision": 95.0},
	{"name": "Veterano", "bots": 26, "dmg": 1.05, "skill": 1.05, "tokens": 3, "vision": 125.0},
]
const PHASES := [[50.0, 45.0, 255.0, 1.5], [35.0, 40.0, 165.0, 3.0], [30.0, 35.0, 100.0, 5.0], [28.0, 28.0, 55.0, 8.0], [22.0, 22.0, 26.0, 13.0], [18.0, 20.0, 9.0, 22.0]]
var mode := MENU
var difficulty := 1; var sensitivity := 1
var world; var player; var hud; var fx
var menu_cam: Camera3D; var menu_a := 0.0
var bots := []; var alive := 0; var kills := 0; var total := 0
var loot := []
var match_t := 0.0; var enemy_damage := 1.0; var max_tokens := 3; var fire_tokens := 0; var path_budget := 2
var z_center := Vector2.ZERO; var z_radius := 450.0; var z_from_c := Vector2.ZERO; var z_from_r := 450.0; var z_to_c := Vector2.ZERO; var z_to_r := 450.0
var z_phase := -1; var z_t := 0.0; var z_shrinking := false; var z_dps := 0.0; var zone_tick := 0.0; var bomb_t := 3.0
var zone_mesh: MeshInstance3D
var helis := []; var rotor: AudioStreamPlayer3D
var fps_t := 0.0; var fps_frames := 0; var low_fps_n := 0; var quality := 2; var sun: DirectionalLight3D
var test_mode := ""

func _ready() -> void:
	randomize()
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_load_settings()
	_env()
	world = World.new(); add_child(world); world.build()
	fx = Fx.new(); fx.main = self; add_child(fx); fx.setup()
	_smokes()
	_zone_visual()
	hud = Hud.new(); hud.main = self
	var layer := CanvasLayer.new(); layer.process_mode = Node.PROCESS_MODE_ALWAYS; add_child(layer); layer.add_child(hud); hud.build()
	menu_cam = Camera3D.new(); menu_cam.far = 1500.0; menu_cam.fov = 58.0; add_child(menu_cam); menu_cam.make_current()
	get_viewport().scaling_3d_scale = 0.85
	Engine.max_fps = 60
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--test="): test_mode = a.substr(7)
	if test_mode != "":
		var t = load("res://scripts/autotest.gd").new(); t.main = self; add_child(t)
	elif Engine.has_meta("autostart"):
		Engine.remove_meta("autostart"); start_match()

func _load_settings() -> void:
	var c := ConfigFile.new()
	if c.load("user://settings.cfg") == OK:
		difficulty = int(c.get_value("g", "diff", 1)); sensitivity = int(c.get_value("g", "sens", 1))

func save_settings() -> void:
	var c := ConfigFile.new(); c.set_value("g", "diff", difficulty); c.set_value("g", "sens", sensitivity); c.save("user://settings.cfg")

func _env() -> void:
	var env := Environment.new()
	var sky := Sky.new(); var ps := ProceduralSkyMaterial.new()
	ps.sky_top_color = Color(0.40, 0.48, 0.58); ps.sky_horizon_color = Color(0.74, 0.74, 0.72); ps.ground_horizon_color = Color(0.56, 0.56, 0.52); ps.ground_bottom_color = Color(0.3, 0.3, 0.27); ps.sun_angle_max = 18.0; sky.sky_material = ps
	env.background_mode = Environment.BG_SKY; env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color(0.68, 0.72, 0.78); env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC; env.tonemap_white = 1.3
	env.fog_enabled = true; env.fog_light_color = Color(0.70, 0.72, 0.72); env.fog_density = 0.0014; env.fog_sky_affect = 0.35; env.fog_aerial_perspective = 0.0
	var we := WorldEnvironment.new(); we.environment = env; add_child(we)
	sun = DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-42, -38, 0); sun.light_energy = 0.9; sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = true; sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL; sun.directional_shadow_max_distance = 70.0; sun.shadow_opacity = 0.85; sun.shadow_blur = 1.2
	add_child(sun)

func _smokes() -> void:
	var mt := StandardMaterial3D.new(); mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; mt.albedo_texture = fx.tex_smoke; mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES; mt.vertex_color_use_as_albedo = true
	var qm := QuadMesh.new(); qm.material = mt
	var grad := Gradient.new(); grad.offsets = PackedFloat32Array([0.0, 0.2, 1.0]); grad.colors = PackedColorArray([Color(0.16, 0.15, 0.14, 0.0), Color(0.15, 0.14, 0.13, 0.55), Color(0.4, 0.4, 0.39, 0.0)])
	var cv := Curve.new(); cv.add_point(Vector2(0, 0.35)); cv.add_point(Vector2(1, 1))
	for s in world.smoke_spots:
		var p := CPUParticles3D.new(); p.mesh = qm; p.amount = 14; p.lifetime = 8.0; p.preprocess = 8.0; p.position = s; p.cast_shadow = 0
		p.direction = Vector3(0.22, 1, 0.1); p.spread = 9.0; p.gravity = Vector3(0.45, 0.25, 0.1); p.initial_velocity_min = 2.0; p.initial_velocity_max = 3.5
		p.scale_amount_min = 7.0; p.scale_amount_max = 11.0; p.scale_amount_curve = cv; p.color_ramp = grad; p.local_coords = false
		add_child(p)

func _zone_visual() -> void:
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
varying float h;
uniform vec3 col = vec3(1.0,0.38,0.12);
void vertex(){ h = VERTEX.y + 0.5; }
void fragment(){ ALBEDO = col; float s = 0.5+0.5*sin(h*42.0 + TIME*1.6); ALPHA = (0.05+0.09*s) * pow(1.0-h,2.2); }"""
	var m := ShaderMaterial.new(); m.shader = sh
	var cm := CylinderMesh.new(); cm.top_radius = 1.0; cm.bottom_radius = 1.0; cm.height = 1.0; cm.radial_segments = 72; cm.rings = 1; cm.cap_top = false; cm.cap_bottom = false
	zone_mesh = MeshInstance3D.new(); zone_mesh.mesh = cm; zone_mesh.material_override = m; zone_mesh.cast_shadow = 0; zone_mesh.visible = false; add_child(zone_mesh)

func start_match() -> void:
	var d: Dictionary = DIFF[difficulty]
	enemy_damage = d.dmg; max_tokens = d.tokens; total = d.bots; alive = total
	player = Player.new(); add_child(player); player.setup(self, hud)
	var spawns := [Vector3(-34, 0, 44), Vector3(-205, 0, 36), Vector3(165, 0, -28), Vector3(-248, 0, -25), Vector3(-6, 0, -48)]
	var sp: Vector3 = spawns[randi() % spawns.size()]
	player.global_position = world.pos_of(world.nearest_free(world.cell_of(sp)))
	player.yaw = randf() * TAU
	player.cam.make_current()
	for i in total:
		var b := Bot.new(); add_child(b); b.setup(self, d.skill, d.vision)
		var p := Vector3.ZERO
		for t in 40:
			p = Vector3(randf_range(-330, 330), 0, randf_range(-235, 235))
			if world.is_free(p) and p.distance_to(player.global_position) > 130.0: break
		b.global_position = world.pos_of(world.nearest_free(world.cell_of(p)))
		b.last_pos = b.global_position
		bots.append(b)
	_spawn_loot()
	_helicopters()
	mode = PLAY; hud.set_mode(PLAY)
	z_phase = -1; _next_phase()
	hud.message("24 febbraio 2022 — Aeroporto Antonov, Hostomel", 5.0)
	hud.message2("Le truppe aviotrasportate russe stanno atterrando. Difendi l'aeroporto.", 5.0)

func _loot_item(type: String, p: Vector3) -> void:
	var b = Batch.new(); var n := Node3D.new(); var col := Color.WHITE
	match type:
		"ak", "svd", "pistol":
			var gm: Mesh = Humanoid.gun_mesh(type)
			var g := MeshInstance3D.new(); g.mesh = gm; g.material_override = Humanoid.mat; g.rotation = Vector3(0, 0, PI / 2 * 0.15); g.position.y = 0.5; g.scale = Vector3(1.5, 1.5, 1.5); n.add_child(g); col = Color(1, 0.75, 0.15)
		"ammo", "ammo_ak", "ammo_svd":
			b.at(Vector3(0, 0.25, 0), Vector3(0.7, 0.45, 0.45), Color(0.27, 0.33, 0.18)); b.at(Vector3(0, 0.5, 0), Vector3(0.72, 0.06, 0.47), Color(0.75, 0.62, 0.2)); col = Color(0.95, 0.8, 0.3)
		"med":
			b.at(Vector3(0, 0.25, 0), Vector3(0.55, 0.42, 0.3), Color(0.92, 0.92, 0.9)); b.at(Vector3(0, 0.25, -0.16), Vector3(0.28, 0.09, 0.02), Color(0.85, 0.1, 0.1)); b.at(Vector3(0, 0.25, -0.16), Vector3(0.09, 0.28, 0.02), Color(0.85, 0.1, 0.1)); col = Color(0.95, 0.3, 0.3)
		"armor":
			b.at(Vector3(0, 0.45, 0), Vector3(0.5, 0.65, 0.22), Color(0.22, 0.27, 0.17)); b.at(Vector3(0, 0.45, -0.12), Vector3(0.28, 0.3, 0.03), Color(0.14, 0.16, 0.12)); col = Color(0.35, 0.65, 1.0)
	if type in ["ammo", "ammo_ak", "ammo_svd", "med", "armor"]:
		var mi := MeshInstance3D.new(); mi.mesh = b.build(); mi.material_override = Humanoid.mat; n.add_child(mi)
	var ring := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.7; cm.bottom_radius = 0.7; cm.height = 0.02; cm.radial_segments = 16; ring.mesh = cm
	var rm := StandardMaterial3D.new(); rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; rm.albedo_color = Color(col.r, col.g, col.b, 0.45); rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; ring.material_override = rm; ring.position.y = 0.03; ring.cast_shadow = 0; n.add_child(ring)
	add_child(n); n.global_position = p
	loot.append({"n": n, "type": type})

func _drop(type: String, body_p: Vector3, off: Vector3) -> void:
	var p := body_p + off
	if not ray(body_p + Vector3.UP * 0.5, p + Vector3.UP * 0.5, 1).is_empty(): p = body_p
	_loot_item(type, p)

func _spawn_loot() -> void:
	var spots: Array = world.loot_spots.duplicate(); spots.shuffle()
	var kinds := []
	for k in [["ak", 8], ["svd", 3], ["ammo", 13], ["med", 10], ["armor", 7]]:
		for i in k[1]: kinds.append(k[0])
	kinds.shuffle()
	# Un fucile sempre vicino al punto di partenza: la prima sparatoria non è persa in partenza.
	_loot_item("ak", _near_free(player.global_position, 13.0))
	for k in kinds:
		var p: Vector3
		if not spots.is_empty(): p = spots.pop_back()
		else:
			p = Vector3(randf_range(-320, 320), 0, randf_range(-225, 225))
		_loot_item(k, world.pos_of(world.nearest_free(world.cell_of(p))))

func _near_free(c: Vector3, r: float) -> Vector3:
	for i in 30:
		var a := randf() * TAU
		var p := c + Vector3(cos(a), 0, sin(a)) * r
		if world.is_free(p) and ray(c + Vector3.UP, p + Vector3.UP, 1).is_empty(): return p
	return world.pos_of(world.nearest_free(world.cell_of(c)))

func _helicopters() -> void:
	var b = Batch.new(); var g := Color(0.20, 0.23, 0.17); var X90 := Basis(Vector3.RIGHT, PI / 2)
	b.at(Vector3(0, 0, 0), Vector3(2.5, 2.6, 9), g); b.cyl(Transform3D(X90, Vector3(0, 0, -5.5)), 0.9, 1.2, 1.5, 8, Color(0.1, 0.13, 0.15)); b.at(Vector3(0, 0.7, 9), Vector3(0.7, 0.7, 9), g); b.at(Vector3(0, 1.8, 13), Vector3(0.3, 3, 1.1), g); b.at(Vector3(0, 1.7, 0), Vector3(1.4, 0.7, 3), g)
	var hm: ArrayMesh = b.build()
	var rb = Batch.new(); rb.at(Vector3.ZERO, Vector3(21, 0.06, 0.55), Color(0.08, 0.08, 0.08)); rb.at(Vector3.ZERO, Vector3(0.55, 0.06, 21), Color(0.08, 0.08, 0.08)); var rm: ArrayMesh = rb.build()
	var start := Vector3(420, 42, -60); var dirv := Vector3(-1, 0, 0.18).normalized()
	for i in 3:
		var n := Node3D.new(); var body := MeshInstance3D.new(); body.mesh = hm; body.material_override = Humanoid.mat; n.add_child(body)
		var rr := MeshInstance3D.new(); rr.mesh = rm; rr.material_override = Humanoid.mat; rr.position.y = 2.3; n.add_child(rr)
		add_child(n); n.global_position = start + Vector3(i * 42.0, i * 7.0, i * 28.0 - 28.0); n.look_at(n.global_position - dirv * 1.0, Vector3.UP); n.rotate_y(0.0)
		helis.append({"n": n, "r": rr, "v": dirv * 46.0})
	rotor = AudioStreamPlayer3D.new(); rotor.stream = fx._stream("rotor", true); rotor.unit_size = 60.0; rotor.max_distance = 900.0; rotor.volume_db = 5.0; add_child(rotor); rotor.global_position = start; rotor.play()

func _next_phase() -> void:
	z_phase += 1
	if z_phase >= PHASES.size(): return
	var ph: Array = PHASES[z_phase]
	z_from_c = z_center; z_from_r = z_radius; z_t = ph[0]; z_shrinking = false
	var tr: float = ph[2]
	var maxoff: float = max(z_radius - tr, 0.0) * 0.7
	var a := randf() * TAU; var off := Vector2(cos(a), sin(a)) * randf() * maxoff
	z_to_c = z_center + off
	z_to_c.x = clampf(z_to_c.x, -270 + tr * 0.25, 270 - tr * 0.25); z_to_c.y = clampf(z_to_c.y, -170 + tr * 0.25, 170 - tr * 0.25)
	z_to_r = tr; z_dps = ph[3]
	if z_phase > 0: hud.message("La zona sicura è stata aggiornata", 3.0)

func zone_info() -> Dictionary:
	return {"c": z_center, "r": z_radius, "tc": z_to_c, "tr": z_to_r, "t": z_t, "shrinking": z_shrinking}

func in_zone(p: Vector3) -> bool:
	return Vector2(p.x, p.z).distance_to(z_center) <= z_radius

func zone_danger(p: Vector3) -> bool:
	var q := Vector2(p.x, p.z)
	if q.distance_to(z_center) > z_radius - 8.0: return true
	return (z_shrinking or z_t < 15.0) and q.distance_to(z_to_c) > z_to_r - 6.0

func zone_goal(p: Vector3) -> Vector3:
	var c := z_to_c; var r: float = z_to_r * 0.65
	var a := randf() * TAU; var g := c + Vector2(cos(a), sin(a)) * r * sqrt(randf())
	return Vector3(g.x, 0, g.y)

func patrol_goal_for(b) -> Vector3:
	var c := z_to_c; var r: float = max(z_to_r, 22.0) * 0.85
	if randf() < clampf((match_t - 60.0) / 360.0, 0.0, 0.5) and is_instance_valid(player):
		var pp: Vector3 = player.global_position
		return pp + Vector3(randf_range(-30, 30), 0, randf_range(-30, 30))
	var a := randf() * TAU; var g := c + Vector2(cos(a), sin(a)) * r * sqrt(randf())
	return Vector3(g.x, 0, g.y)

func ray(a: Vector3, b: Vector3, mask: int) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b, mask)
	return get_world_3d().direct_space_state.intersect_ray(q)

func noise(p: Vector3, r: float) -> void:
	# Allerta al massimo i 5 nemici più vicini, così uno sparo non richiama tutta la mappa.
	var n := 0
	for b in bots:
		if not b.dead and b.global_position.distance_to(p) < r * 0.6 and b.alert_t < 2.0:
			b.alert(p, 6.0); n += 1
			if n >= 5: break

func request_token(_b) -> bool:
	if fire_tokens >= max_tokens: return false
	fire_tokens += 1; return true

func take_path_budget() -> bool:
	if path_budget <= 0: return false
	path_budget -= 1; return true

func on_bot_dead(b, by_player: bool) -> void:
	alive -= 1
	if by_player:
		kills += 1; hud.kill_note()
	# Ogni nemico lascia l'arma che impugnava e i suoi proiettili.
	var body_p: Vector3 = b.global_position
	_drop(b.gun, body_p, Vector3(0.75, 0, 0.25))
	_drop("ammo_" + b.gun, body_p, Vector3(-0.75, 0, -0.25))
	if randf() < 0.25:
		_drop("med" if randf() < 0.6 else "armor", body_p, Vector3(0, 0, 0.9))
	if alive <= 0 and mode == PLAY: _end(true)

func on_player_dead() -> void:
	if mode == PLAY: _end(false)

func _end(win: bool) -> void:
	mode = END
	if rotor: rotor.stop()
	var place := 1 if win else alive + 1
	hud.show_end(win, kills, total, place, match_t)

func check_pickups(p: Vector3) -> void:
	for i in range(loot.size() - 1, -1, -1):
		var e = loot[i]
		if e.n.global_position.distance_squared_to(p) < 3.2:
			player.give(e.type); e.n.queue_free(); loot.remove_at(i)

func restart() -> void:
	get_tree().paused = false
	Engine.set_meta("autostart", true)
	get_tree().reload_current_scene()

func to_menu() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func toggle_pause(p: bool) -> void:
	if mode != PLAY: return
	get_tree().paused = p
	hud.show_pause(p)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if mode == PLAY and not get_tree().paused: toggle_pause(true)

func _process(dt: float) -> void:
	_quality_guard(dt)
	if mode == MENU:
		menu_a += dt * 0.05
		menu_cam.global_position = Vector3(-30.0 + sin(menu_a) * 26.0, 7.0, -18.0)
		menu_cam.look_at(Vector3(-26.0 + sin(menu_a) * 10.0, 7.0, -110), Vector3.UP)
		return
	for e in loot:
		e.n.rotate_y(dt * 1.1)
	for h in helis:
		h.n.global_position += h.v * dt
		h.r.rotate_y(dt * 26.0)
	if not helis.is_empty():
		rotor.global_position = helis[1].n.global_position
		if helis[1].n.global_position.x < -480.0:
			for h in helis: h.n.queue_free()
			helis.clear(); rotor.stop()
	if mode == PLAY: _update_zone(dt)

func _physics_process(_dt: float) -> void:
	path_budget = 2

func _update_zone(dt: float) -> void:
	match_t += dt
	if z_phase < PHASES.size():
		z_t -= dt
		if z_t <= 0.0:
			if not z_shrinking:
				z_shrinking = true; z_t = PHASES[z_phase][1]
				hud.message("La zona si sta restringendo: muoviti!", 3.0)
			else:
				z_center = z_to_c; z_radius = z_to_r; _next_phase()
		elif z_shrinking:
			var k: float = 1.0 - z_t / float(PHASES[z_phase][1])
			z_center = z_from_c.lerp(z_to_c, k); z_radius = lerpf(z_from_r, z_to_r, k)
	zone_mesh.visible = z_radius < 430.0
	if zone_mesh.visible:
		zone_mesh.scale = Vector3(z_radius, 120.0, z_radius)
		zone_mesh.global_position = Vector3(z_center.x, 60.0, z_center.y)
	zone_tick -= dt
	if zone_tick <= 0.0:
		zone_tick = 1.0
		if not in_zone(player.global_position):
			player.hurt(z_dps, player.global_position, true)
			hud.message("Sei sotto il bombardamento: rientra nella zona!", 1.2)
		for b in bots:
			if not b.dead and not in_zone(b.global_position): b.take_damage(z_dps, false)
	# bombardamento visibile nella zona rossa
	bomb_t -= dt
	if bomb_t <= 0.0:
		bomb_t = randf_range(1.8, 4.5)
		var a := randf() * TAU; var r := z_radius + randf_range(10, 90)
		var outp := not in_zone(player.global_position)
		var pos: Vector3
		if outp:
			var o: Vector3 = player.global_position
			pos = o + Vector3(cos(a), 0, sin(a)) * randf_range(16, 45)
		else:
			pos = Vector3(z_center.x + cos(a) * r, 0, z_center.y + sin(a) * r)
		if z_radius < 430.0 or outp:
			fx.explosion(pos, 12.0)
			var d: float = pos.distance_to(player.global_position)
			if d < 70.0: player.shake = max(player.shake, (70.0 - d) / 70.0)

# Se il telefono non regge 60 fps riduce da solo risoluzione e ombre.
func _quality_guard(dt: float) -> void:
	fps_t += dt; fps_frames += 1
	if fps_t < 4.0: return
	var fps := fps_frames / fps_t; fps_t = 0.0; fps_frames = 0
	if mode != PLAY or test_mode != "": return
	if fps < 40.0:
		low_fps_n += 1
		if low_fps_n >= 2 and quality > 0:
			low_fps_n = 0; quality -= 1
			if quality == 1:
				get_viewport().scaling_3d_scale = 0.7
			else:
				get_viewport().scaling_3d_scale = 0.55; sun.shadow_enabled = false
	else: low_fps_n = 0
