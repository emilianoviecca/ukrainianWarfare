extends CharacterBody3D
const Humanoid := preload("res://scripts/humanoid.gd")
const W := preload("res://scripts/weapons.gd")
var main; var hud; var model
var pivot: Node3D; var arm: SpringArm3D; var cam: Camera3D
var hp := 100.0; var armor := 0.0; var medkits := 1
var owned := ["pistol"]; var cur := "pistol"
var mag := {"pistol": 12, "ak": 0, "svd": 0}
var reserve := {"pistol": 48, "ak": 0, "svd": 0}
var yaw := 0.0; var pitch := 0.0; var aiming := false; var crouching := false; var dead := false
var cool := 0.0; var reload_t := 0.0; var heal_t := 0.0; var speed_now := 0.0; var pick_t := 0.0; var step_t := 0.0
var shots_fired := 0; var shake := 0.0; var on_target := false; var target_t := 0.0; var was_sprint := false
const SENS := [0.11, 0.17, 0.25]
var sens := 0.17

func setup(m, h) -> void:
	main = m; hud = h
	collision_layer = 4; collision_mask = 1 | 2
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var cs := CollisionShape3D.new(); var c := CapsuleShape3D.new(); c.radius = 0.36; c.height = 1.8; cs.shape = c; cs.position.y = 0.9; add_child(cs)
	model = Humanoid.new(); add_child(model); model.setup("ua"); model.set_gun("pistol")
	pivot = Node3D.new(); pivot.top_level = true; add_child(pivot)
	arm = SpringArm3D.new(); arm.collision_mask = 1; arm.spring_length = 4.0; arm.position = Vector3(0.95, 0, 0); arm.margin = 0.18
	var sp := SphereShape3D.new(); sp.radius = 0.15; arm.shape = sp; pivot.add_child(arm)
	cam = Camera3D.new(); cam.near = 0.08; cam.far = 1500.0; cam.fov = 68.0; arm.add_child(cam)
	sens = SENS[main.sensitivity]

func w() -> Dictionary: return W.DATA[cur]
func scoped() -> bool: return aiming and w().scope and reload_t <= 0.0
func busy() -> bool: return reload_t > 0.0 or heal_t > 0.0
func sprinting() -> bool: return was_sprint

func toggle_aim() -> void: aiming = not aiming
func toggle_crouch() -> void: crouching = not crouching

func select(kind: String) -> void:
	if kind == cur or not owned.has(kind) or dead: return
	cur = kind; reload_t = 0.0; heal_t = 0.0; cool = 0.25; model.set_gun(kind)
	main.fx.play2d("reload", -8.0, 1.4)

func reload() -> void:
	if dead or busy() or mag[cur] >= w().mag or reserve[cur] <= 0: return
	reload_t = w().reload; aiming = false
	main.fx.play2d("reload", -3.0)

func heal() -> void:
	if dead or busy() or medkits <= 0 or hp >= 100.0: return
	heal_t = 3.0; aiming = false

func give(type: String) -> void:
	match type:
		"ak", "svd":
			if not owned.has(type):
				owned.append(type); mag[type] = W.DATA[type].mag
				if cur == "pistol" or (cur == "ak" and type == "svd" and false): select(type)
				hud.message("Hai preso: %s" % W.DATA[type].name, 2.0)
			else:
				reserve[type] += W.DATA[type].mag
				hud.message("Caricatore per %s" % W.DATA[type].name, 1.5)
		"ammo":
			reserve.pistol += 24; reserve.ak += 60; reserve.svd += 10
			hud.message("Munizioni +", 1.5)
		"ammo_ak", "ammo_svd":
			var kind := type.substr(5)
			var n: int = randi_range(30, 60) if kind == "ak" else randi_range(10, 20)
			reserve[kind] += n
			hud.message("Proiettili %s +%d" % [W.DATA[kind].name, n], 1.6)
		"med":
			medkits += 1; hud.message("Kit medico +1", 1.5)
		"armor":
			armor = minf(armor + 50.0, 100.0); hud.message("Giubbotto antiproiettile", 1.8)
	main.fx.play2d("pick", -6.0)

func hurt(amount: float, from: Vector3, by_zone := false) -> void:
	if dead: return
	if armor > 0.0 and not by_zone:
		var ab := minf(amount * 0.55, armor); armor -= ab; amount -= ab
	hp -= amount
	if not by_zone:
		hud.add_hit(from); main.fx.play2d("hurt", -2.0, randf_range(0.9, 1.1)); shake = max(shake, 0.25)
		heal_t = 0.0
	else:
		hud.flash_damage(0.3)
	if hp <= 0.0:
		hp = 0.0; dead = true; model.die(); main.on_player_dead()

func _physics_process(dt: float) -> void:
	if main.mode == main.MENU: return
	if dead:
		model.animate(dt, 0.0, false); _update_camera(dt); return
	if main.mode != main.PLAY:
		_update_camera(dt); return
	var ld: Vector2 = hud.take_look()
	var fov_k: float = cam.fov / 68.0
	yaw -= deg_to_rad(ld.x * sens * lerpf(0.55, 1.0, fov_k))
	pitch = clampf(pitch - deg_to_rad(ld.y * sens * lerpf(0.55, 1.0, fov_k)), deg_to_rad(-65), deg_to_rad(62))
	# movimento relativo alla visuale
	var mv: Vector2 = hud.move_vec
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw)); var right := Vector3(cos(yaw), 0, -sin(yaw))
	was_sprint = mv.y < -0.86 and not crouching and not aiming and not busy()
	var sp := 6.1 if was_sprint else (1.9 if crouching else (2.0 if aiming else 3.9))
	var dir := fwd * -mv.y + right * mv.x
	if dir.length() > 1.0: dir = dir.normalized()
	velocity = dir * sp
	move_and_slide()
	global_position.y = 0.0
	speed_now = velocity.length()
	model.rotation.y = yaw
	model.animate(dt, speed_now, crouching, pitch * 0.8)
	model.visible = not scoped() or cam.fov > 40.0
	if speed_now > 2.5:
		step_t -= dt * speed_now
		if step_t <= 0.0:
			step_t = 2.5; main.fx.play2d("step", -24.0, randf_range(0.8, 1.2))
	_update_camera(dt)
	cool -= dt
	if reload_t > 0.0:
		reload_t -= dt
		if reload_t <= 0.0: _finish_reload()
	if heal_t > 0.0:
		heal_t -= dt
		if heal_t <= 0.0:
			heal_t = 0.0; medkits -= 1; hp = minf(hp + 55.0, 100.0); main.fx.play2d("pick", -4.0, 0.8)
	if hud.fire_held and cool <= 0.0 and not busy():
		if mag[cur] > 0: _fire()
		elif reserve[cur] > 0: reload()
		else:
			cool = 0.4; hud.message("Niente munizioni", 1.0); main.fx.play2d("hit", -8.0, 0.6)
	target_t -= dt
	if target_t <= 0.0:
		target_t = 0.1; on_target = _assist_target(3.0) != null
	pick_t -= dt
	if pick_t <= 0.0:
		pick_t = 0.1; main.check_pickups(global_position)

func _finish_reload() -> void:
	var need: int = w().mag - mag[cur]; var got: int = min(need, reserve[cur])
	mag[cur] += got; reserve[cur] -= got; reload_t = 0.0

func _update_camera(dt: float) -> void:
	var h := 1.35 if crouching else 1.9
	var want_len := 4.0; var want_fov := 68.0; var off := 0.95
	if not dead and aiming:
		if w().scope: want_len = 0.15; want_fov = 11.0; off = 0.05
		else: want_len = 1.7; want_fov = 46.0; off = 0.62
	if dead: want_len = 6.0
	var k: float = min(dt * 12.0, 1.0)
	arm.spring_length = lerpf(arm.spring_length, want_len, k)
	arm.position.x = lerpf(arm.position.x, off, k)
	cam.fov = lerpf(cam.fov, want_fov, k)
	pivot.global_position = global_position + Vector3(0, lerpf(pivot.global_position.y - global_position.y if pivot.global_position != Vector3.ZERO else h, h, k), 0)
	shake = max(shake - dt * 1.3, 0.0)
	var sx := randf_range(-1, 1) * shake * 0.03; var sy := randf_range(-1, 1) * shake * 0.03
	pivot.rotation = Vector3(pitch + sx, yaw + sy, 0)

func _aim_points(b) -> Array:
	var p: Vector3 = b.global_position
	return [p + Vector3(0, 1.2, 0), p + Vector3(0, 1.62, 0)]

# Aiuto alla mira per il touch: restituisce il punto del nemico entro `deg` gradi dal mirino.
func _assist_target(deg: float):
	var o := cam.global_position; var f := -cam.global_transform.basis.z
	var best = null; var best_a := deg_to_rad(deg)
	var rng_max: float = w().range
	for b in main.bots:
		if b.dead: continue
		for p in _aim_points(b):
			var v: Vector3 = p - o
			if v.length() > rng_max: continue
			var a := f.angle_to(v)
			if a < best_a:
				var from := o + f * (arm.spring_length + 0.4)
				var hit: Dictionary = main.ray(from, p, 1)
				if hit.is_empty(): best_a = a; best = p
	return best

func _fire() -> void:
	var data := w()
	cool = 60.0 / data.rpm
	mag[cur] -= 1; shots_fired += 1
	var o := cam.global_position; var f := -cam.global_transform.basis.z
	var spread: float = data.ads_spread if aiming else data.spread
	if speed_now > 3.0: spread *= 1.6
	var assist_deg := 0.5 if scoped() else (1.3 if aiming else 2.1)
	var tp = _assist_target(assist_deg)
	var dir: Vector3 = f if tp == null else (tp - o).normalized()
	if tp == null or not aiming:
		var r := deg_to_rad(spread) * sqrt(randf()) * (0.35 if tp != null else 1.0); var a := randf() * TAU
		dir = (dir + cam.global_transform.basis.x * cos(a) * r + cam.global_transform.basis.y * sin(a) * r).normalized()
	var from := o + f * (arm.spring_length + 0.4)
	var to := o + dir * float(data.range)
	var hit: Dictionary = main.ray(from, to, 1 | 2 | 8)
	var end := to
	var mz: Vector3 = model.muzzle.global_position
	if not hit.is_empty():
		end = hit.position
		var col = hit.collider
		if col is CharacterBody3D and col.has_method("take_damage"):
			var head: bool = end.y - col.global_position.y > 1.45
			var dmg: float = data.dmg * (2.0 if head else 1.0)
			col.take_damage(dmg, true)
			hud.show_hitmarker(head)
			main.fx.play2d("hit", -5.0, 1.3 if head else 1.0)
			main.fx.puff(end, Color(0.32, 0.12, 0.08, 0.5), 0.4, 0.22)
		else:
			main.fx.puff(end, Color(0.62, 0.60, 0.55, 0.6), 0.75, 0.42)
	if not scoped():
		main.fx.tracer(mz, end)
		main.fx.flash(mz)
		model.recoil()
	main.fx.play2d(data.sfx, -1.0, randf_range(0.96, 1.04))
	pitch = minf(pitch + float(data.kick), deg_to_rad(62)); yaw += randf_range(-1, 1) * float(data.kick) * 0.4
	shake = max(shake, float(data.kick) * 4.0)
	main.noise(global_position, data.noise)
