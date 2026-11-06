extends CharacterBody3D
const Humanoid := preload("res://scripts/humanoid.gd")
enum { PATROL, ENGAGE, SEEK, ZONE }
var main; var model
var hp := 100.0; var dead := false
var state := PATROL
var path := PackedVector3Array(); var path_i := 0
var think_t := 0.0; var react_t := 0.0; var burst_left := 0; var burst_t := 0.0; var gap_t := 0.0
var has_token := false; var last_seen := Vector3.ZERO; var alert_t := 0.0; var repath_t := 0.0
var strafe := Vector3.ZERO; var strafe_t := 0.0; var patrol_goal := Vector3.ZERO
var last_pos := Vector3.ZERO; var stuck_t := 0.0; var see := false; var despawn_t := 16.0; var speed_now := 0.0
var skill := 1.0; var vision := 130.0; var face_yaw := 0.0

func setup(m, skill_k: float, vision_m: float) -> void:
	main = m; skill = skill_k; vision = vision_m
	collision_layer = 2; collision_mask = 1 | 2 | 4
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var cs := CollisionShape3D.new(); var c := CapsuleShape3D.new(); c.radius = 0.38; c.height = 1.85; cs.shape = c; cs.position.y = 0.925; add_child(cs)
	model = Humanoid.new(); add_child(model); model.setup("ru")
	think_t = randf() * 0.4
	face_yaw = randf() * TAU

func take_damage(d: float, by_player := false) -> void:
	if dead: return
	hp -= d
	if by_player:
		alert(main.player.global_position, 12.0)
		react_t = 0.0
	if hp <= 0.0: _die(by_player)

func _die(by_player: bool) -> void:
	dead = true; _release()
	collision_layer = 0; collision_mask = 0; velocity = Vector3.ZERO
	model.die(); main.on_bot_dead(self, by_player)

func alert(p: Vector3, secs := 9.0) -> void:
	last_seen = p; alert_t = max(alert_t, secs); repath_t = 0.0

func _release() -> void:
	if has_token:
		has_token = false; main.fire_tokens -= 1

func _eye() -> Vector3: return global_position + Vector3(0, 1.5, 0)

func _physics_process(dt: float) -> void:
	if dead:
		model.animate(dt, 0, false)
		despawn_t -= dt
		if despawn_t <= 0.0: visible = false; set_physics_process(false)
		return
	if main.mode != main.PLAY:
		model.animate(dt, 0.0, false); return
	alert_t = maxf(alert_t - dt, 0.0)
	think_t -= dt
	if think_t <= 0.0:
		think_t = 0.2 + randf() * 0.1
		_think(0.25)
	_shoot(dt)
	_move(dt)
	var pd: float = global_position.distance_squared_to(main.player.global_position)
	model.visible = pd < 90000.0
	if model.visible: model.animate(dt, speed_now, false)

func _think(dt: float) -> void:
	var pl = main.player
	var ppos: Vector3 = pl.global_position
	var d := global_position.distance_to(ppos)
	see = false
	if not pl.dead and d < vision and main.match_t > 12.0:
		var to := (ppos - global_position).normalized()
		var fwd := Vector3(-sin(face_yaw), 0, -cos(face_yaw))
		var aware := alert_t > 0.0 or d < 14.0 or fwd.dot(to) > -0.2
		if aware:
			var h: float = 0.95 if pl.crouching else 1.4
			var hit: Dictionary = main.ray(_eye(), ppos + Vector3(0, h, 0), 1)
			see = hit.is_empty()
	var out: bool = main.zone_danger(global_position)
	if see:
		if state != ENGAGE: react_t = randf_range(0.55, 1.15) / skill
		state = ENGAGE; last_seen = ppos; alert_t = max(alert_t, 8.0)
		if out and d > 25.0: state = ZONE
	elif out:
		state = ZONE
	elif alert_t > 0.0:
		state = SEEK
	else:
		state = PATROL
	if state == ENGAGE:
		path = PackedVector3Array(); path_i = 0
		strafe_t -= dt
		if strafe_t <= 0.0:
			strafe_t = randf_range(0.7, 2.1)
			var to := (ppos - global_position); to.y = 0; to = to.normalized()
			var sd := Vector3(-to.z, 0, to.x) * (1.0 if randf() < 0.5 else -1.0)
			var r := randf()
			if d > 70.0 and r < 0.6: strafe = to * 3.2 + sd * 0.6
			elif r < 0.45: strafe = sd * 2.2
			elif d < 12.0: strafe = -to * 2.0
			else: strafe = Vector3.ZERO
	else:
		_release()
		strafe = Vector3.ZERO
		repath_t -= dt
		var empty := path_i >= path.size()
		if state == ZONE and (empty or repath_t <= 0.0):
			_goto(main.zone_goal(global_position)); repath_t = 4.0
		elif state == SEEK and (empty or repath_t <= 0.0):
			_goto(last_seen + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))); repath_t = 2.5
		elif state == PATROL and empty:
			_goto(main.patrol_goal_for(self)); repath_t = 8.0

func _goto(p: Vector3) -> void:
	if not main.take_path_budget():
		think_t = 0.05; return
	path = main.world.find_path(global_position, p); path_i = 1

func _move(dt: float) -> void:
	var v := Vector3.ZERO
	var run := 3.4
	if state == ENGAGE:
		v = strafe
		var to: Vector3 = main.player.global_position - global_position
		_face(atan2(-to.x, -to.z), dt, 8.0)
	elif path_i < path.size():
		var tgt: Vector3 = path[path_i]; tgt.y = 0
		var to := tgt - global_position; to.y = 0
		if to.length() < 1.3:
			path_i += 1
		else:
			if state == ZONE: run = 5.4
			elif state == SEEK: run = 4.6
			v = to.normalized() * run
			_face(atan2(-v.x, -v.z), dt, 6.0)
	velocity = v
	move_and_slide()
	global_position.y = 0.0
	speed_now = velocity.length()
	if v.length() > 0.5:
		if global_position.distance_to(last_pos) < 0.12 * dt * 60.0 * 0.02 + 0.015:
			stuck_t += dt
			if stuck_t > 0.8:
				stuck_t = 0.0; path = PackedVector3Array(); path_i = 0; strafe = -strafe; strafe_t = 0.4
		else: stuck_t = 0.0
	last_pos = global_position

func _face(y: float, dt: float, k: float) -> void:
	face_yaw = lerp_angle(face_yaw, y, min(dt * k, 1.0)); model.rotation.y = face_yaw

func _shoot(dt: float) -> void:
	if state != ENGAGE or not see:
		burst_left = 0; return
	if react_t > 0.0:
		react_t -= dt; return
	if burst_left > 0:
		burst_t -= dt
		if burst_t <= 0.0:
			burst_t = randf_range(0.11, 0.16); burst_left -= 1
			_fire_one()
			if burst_left == 0:
				_release(); gap_t = randf_range(0.9, 2.1) / skill
	else:
		gap_t -= dt
		if gap_t <= 0.0 and main.request_token(self):
			has_token = true
			burst_left = randi_range(3, 5); burst_t = 0.0

func _fire_one() -> void:
	var pl = main.player
	if pl.dead: return
	var mz: Vector3 = model.muzzle.global_position
	var aim: Vector3 = pl.global_position + Vector3(0, 0.95 if pl.crouching else 1.3, 0)
	var d := mz.distance_to(aim)
	var p := clampf(0.30 * (1.0 - d / 130.0), 0.025, 0.30) * skill
	if pl.was_sprint: p *= 0.5
	elif pl.speed_now > 1.0: p *= 0.8
	if pl.crouching: p *= 0.75
	var hit := randf() < p
	var off := Vector3.ZERO
	if not hit:
		off = Vector3(randf_range(-1, 1), randf_range(-0.6, 0.9), randf_range(-1, 1)).normalized() * randf_range(0.5, 1.6 + d * 0.02)
	main.fx.tracer(mz, aim + off + (aim - mz).normalized() * (0.0 if hit else 15.0))
	if d < 170.0: main.fx.flash(mz)
	main.fx.play3d("enemy", mz, -2.0, randf_range(0.92, 1.08))
	main.hud.add_ping(global_position)
	if hit: pl.hurt(randf_range(9.0, 13.0) * main.enemy_damage, global_position)
