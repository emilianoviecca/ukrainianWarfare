extends Node3D
# Traccianti, lampi, fumo, esplosioni e suoni: tutto da pool per non allocare durante il gioco.
var main
var tracers := []; var flashes := []; var puffs := []; var booms := []
var sfx3d := []; var sfx2d := []
var streams := {}
var tex_smoke: Texture2D
var i_tr := 0; var i_fl := 0; var i_pf := 0; var i_bm := 0; var i_3d := 0; var i_2d := 0

func _unshaded(c: Color, additive := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if additive: m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.disable_fog = true
	return m

func _stream(name_s: String, loop := false) -> AudioStreamWAV:
	var s := AudioStreamWAV.new(); s.data = FileAccess.get_file_as_bytes("res://assets/%s.bin" % name_s)
	s.format = AudioStreamWAV.FORMAT_16_BITS; s.mix_rate = 22050; s.stereo = false
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD; s.loop_end = s.data.size() / 2
	return s

func setup() -> void:
	var img := Image.new(); img.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/smoke.dat")); tex_smoke = ImageTexture.create_from_image(img)
	for n in ["ak", "pistol", "svd", "enemy", "boom", "reload", "hit", "hurt", "pick", "step"]:
		streams[n] = _stream(n)
	var trm := BoxMesh.new(); trm.size = Vector3(0.035, 0.035, 1.0); trm.material = _unshaded(Color(1.0, 0.85, 0.45, 0.9), true)
	for i in 28:
		var t := MeshInstance3D.new(); t.mesh = trm; t.visible = false; t.cast_shadow = 0; add_child(t)
		tracers.append({"n": t, "t": 0.0})
	var fm := QuadMesh.new(); fm.size = Vector2(0.65, 0.65)
	var fmat := _unshaded(Color(1, 0.72, 0.28, 1), true); fmat.albedo_texture = tex_smoke; fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED; fm.material = fmat
	for i in 12:
		var f := MeshInstance3D.new(); f.mesh = fm; f.visible = false; f.cast_shadow = 0; add_child(f)
		flashes.append({"n": f, "t": 0.0})
	var pm := QuadMesh.new(); pm.size = Vector2(1, 1)
	for i in 24:
		var mt := _unshaded(Color(0.6, 0.58, 0.54, 0.7)); mt.albedo_texture = tex_smoke; mt.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		var p := MeshInstance3D.new(); p.mesh = pm; p.material_override = mt; p.visible = false; p.cast_shadow = 0; add_child(p)
		puffs.append({"n": p, "t": 0.0, "m": mt, "life": 0.5, "s": 1.0, "c": Color.WHITE})
	var bm := QuadMesh.new(); bm.size = Vector2(1, 1)
	for i in 6:
		var mt := _unshaded(Color(1, 0.6, 0.2, 1), true); mt.albedo_texture = tex_smoke; mt.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		var b := MeshInstance3D.new(); b.mesh = bm; b.material_override = mt; b.visible = false; b.cast_shadow = 0; add_child(b)
		booms.append({"n": b, "t": 0.0, "m": mt})
	for i in 12:
		var a := AudioStreamPlayer3D.new(); a.unit_size = 22.0; a.max_distance = 520.0; a.attenuation_filter_cutoff_hz = 9000; add_child(a); sfx3d.append(a)
	for i in 5:
		var a := AudioStreamPlayer.new(); add_child(a); sfx2d.append(a)
	var w := AudioStreamPlayer.new(); w.stream = _stream("wind", true); w.volume_db = -19.0; w.autoplay = true; add_child(w)

func play2d(n: String, db := 0.0, pitch := 1.0) -> void:
	var a: AudioStreamPlayer = sfx2d[i_2d]; i_2d = (i_2d + 1) % sfx2d.size()
	a.stream = streams[n]; a.volume_db = db; a.pitch_scale = pitch; a.play()

func play3d(n: String, p: Vector3, db := 0.0, pitch := 1.0) -> void:
	var a: AudioStreamPlayer3D = sfx3d[i_3d]; i_3d = (i_3d + 1) % sfx3d.size()
	a.stream = streams[n]; a.volume_db = db; a.pitch_scale = pitch; a.global_position = p; a.play()

func tracer(a: Vector3, b: Vector3) -> void:
	var d := a.distance_to(b)
	if d < 1.5: return
	var e = tracers[i_tr]; i_tr = (i_tr + 1) % tracers.size()
	var len_t: float = min(d * 0.55, 18.0)
	var mid := a.lerp(b, 0.5)
	var n: MeshInstance3D = e.n
	n.look_at_from_position(mid, b, Vector3.UP if absf((b - a).normalized().y) < 0.98 else Vector3.RIGHT)
	n.scale = Vector3(1, 1, len_t); n.visible = true; e.t = 0.055

func flash(p: Vector3) -> void:
	var e = flashes[i_fl]; i_fl = (i_fl + 1) % flashes.size()
	e.n.global_position = p; e.n.visible = true; e.t = 0.045

func puff(p: Vector3, c := Color(0.62, 0.60, 0.55, 0.65), size := 0.8, life := 0.4) -> void:
	var e = puffs[i_pf]; i_pf = (i_pf + 1) % puffs.size()
	e.n.global_position = p; e.n.visible = true; e.t = life; e.life = life; e.s = size; e.c = c; e.m.albedo_color = c

func explosion(p: Vector3, big := 11.0) -> void:
	var e = booms[i_bm]; i_bm = (i_bm + 1) % booms.size()
	e.n.global_position = p + Vector3.UP * 3; e.n.visible = true; e.t = 0.42; e.s = big
	puff(p + Vector3.UP * 3, Color(0.17, 0.16, 0.15, 0.85), big * 0.95, 1.3)
	play3d("boom", p, 5.0, randf_range(0.82, 1.15))

func _process(dt: float) -> void:
	for e in tracers:
		if e.t > 0.0:
			e.t -= dt
			if e.t <= 0.0: e.n.visible = false
	for e in flashes:
		if e.t > 0.0:
			e.t -= dt
			if e.t <= 0.0: e.n.visible = false
	for e in puffs:
		if e.t > 0.0:
			e.t -= dt
			var k: float = clampf(e.t / e.life, 0, 1)
			var s: float = e.s * (1.8 - k)
			e.n.scale = Vector3(s, s, s)
			e.n.global_position.y += dt * 0.5
			e.m.albedo_color.a = e.c.a * k
			if e.t <= 0.0: e.n.visible = false
	for e in booms:
		if e.t > 0.0:
			e.t -= dt
			var k: float = clampf(e.t / 0.42, 0, 1)
			var s: float = e.s * (1.45 - k)
			e.n.scale = Vector3(s, s, s)
			e.m.albedo_color.a = k
			if e.t <= 0.0: e.n.visible = false
