extends Node3D
# Aeroporto Antonov di Hostomel: pianta semplificata e costruita via codice.
const Batch := preload("res://scripts/mesh_batch.gd")
const HALF := Vector2(350.0, 250.0)
const CELL := 2.5

var batch = Batch.new()
var trees_batch = Batch.new()
var body: StaticBody3D
var astar := AStarGrid2D.new()
var rng := RandomNumberGenerator.new()
var solids := [] # Rect2 usati per evitare sovrapposizioni
var mini_rects := []
var loot_spots: Array[Vector3] = []
var smoke_spots: Array[Vector3] = []
var ground_tex: Texture2D

const WALL := Color(0.55, 0.58, 0.60)
const WALL2 := Color(0.42, 0.46, 0.50)
const BURNT := Color(0.13, 0.12, 0.115)
const SOOT := Color(0.24, 0.23, 0.22)
const CONC := Color(0.50, 0.50, 0.47)
const SAND := Color(0.56, 0.50, 0.36)
const OLIVE := Color(0.27, 0.31, 0.19)
const RUST := Color(0.36, 0.22, 0.14)

func build() -> void:
	rng.seed = 2402
	body = StaticBody3D.new(); body.collision_layer = 1; body.collision_mask = 0; add_child(body)
	_init_grid()
	_ground()
	_bounds()
	_main_hangar()
	_small_hangar(170, -80); _small_hangar(258, -80)
	_tower(-175, 20)
	_terminal(-258, -48)
	_warehouses()
	_tanks()
	_radar(255, 212)
	_parked_plane(-78, 8, 0.5); _parked_plane(84, 22, -0.8)
	_wrecks()
	_defences()
	_scatter()
	_forest()
	# Strutture con griglia Kenney proiettata in coordinate mondo (1 riquadro = 4 m); gli alberi restano in tinta unita.
	var mat: StandardMaterial3D = Batch.material()
	mat.albedo_texture = _gray_tex("res://assets/proto_struct.dat")
	mat.uv1_triplanar = true; mat.uv1_world_triplanar = true; mat.uv1_scale = Vector3.ONE * 0.25
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.albedo_color = Color(1.08, 1.08, 1.08)
	var mi := MeshInstance3D.new(); mi.mesh = batch.build(); mi.material_override = mat; add_child(mi)
	var mt := MeshInstance3D.new(); mt.mesh = trees_batch.build(); mt.material_override = Batch.material(); add_child(mt)
	astar.update()
	_apply_solid_cells()
	batch = null; trees_batch = null

func _gray_tex(path: String) -> ImageTexture:
	var img := Image.new(); img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)); img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

# --- griglia per i percorsi dei bot ---
var _blocked := []
func _init_grid() -> void:
	astar.region = Rect2i(0, 0, int(HALF.x * 2 / CELL), int(HALF.y * 2 / CELL))
	astar.cell_size = Vector2(CELL, CELL)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE

func _apply_solid_cells() -> void:
	for c in _blocked:
		if astar.is_in_boundsv(c): astar.set_point_solid(c, true)
	_blocked.clear()

func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(clampi(int((p.x + HALF.x) / CELL), 0, astar.region.size.x - 1), clampi(int((p.z + HALF.y) / CELL), 0, astar.region.size.y - 1))

func pos_of(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * CELL - HALF.x, 0, (c.y + 0.5) * CELL - HALF.y)

func nearest_free(c: Vector2i) -> Vector2i:
	if not astar.is_point_solid(c): return c
	for r in range(1, 24):
		for dx in range(-r, r + 1):
			for dy in [-r, r]:
				var q := c + Vector2i(dx, dy)
				if astar.is_in_boundsv(q) and not astar.is_point_solid(q): return q
				q = c + Vector2i(dy, dx)
				if astar.is_in_boundsv(q) and not astar.is_point_solid(q): return q
	return c

func is_free(p: Vector3) -> bool:
	return absf(p.x) < HALF.x - 4 and absf(p.z) < HALF.y - 4 and not astar.is_point_solid(cell_of(p))

func find_path(a: Vector3, b: Vector3) -> PackedVector3Array:
	var ca := nearest_free(cell_of(a)); var cb := nearest_free(cell_of(b))
	var res := PackedVector3Array()
	for pt in astar.get_id_path(ca, cb):
		res.append(pos_of(pt))
	return res

func _mark(center: Vector3, size: Vector3, rot: float) -> void:
	var r := Vector2(size.x, size.z).length() * 0.5 + 1.0
	var inv := Transform3D(Basis(Vector3.UP, rot), center).affine_inverse()
	for cx in range(int((center.x - r + HALF.x) / CELL), int((center.x + r + HALF.x) / CELL) + 1):
		for cy in range(int((center.z - r + HALF.y) / CELL), int((center.z + r + HALF.y) / CELL) + 1):
			var l := inv * pos_of(Vector2i(cx, cy))
			if absf(l.x) < size.x * 0.5 + 0.6 and absf(l.z) < size.z * 0.5 + 0.6:
				_blocked.append(Vector2i(cx, cy))

# --- elementi solidi ---
func solid(center: Vector3, size: Vector3, col: Color, rot := 0.0, visible_mesh := true, navblock := true) -> void:
	var s := CollisionShape3D.new(); var b := BoxShape3D.new(); b.size = size; s.shape = b
	s.transform = Transform3D(Basis(Vector3.UP, rot), center); body.add_child(s)
	if visible_mesh: batch.at(center, size, col, rot)
	if navblock and center.y - size.y * 0.5 < 1.9: _mark(center, size, rot)
	solids.append(Rect2(center.x - size.x * 0.6, center.z - size.z * 0.6, size.x * 1.2, size.z * 1.2))

func solid_cyl(pos: Vector3, r: float, h: float, col: Color, sides := 10, target = null) -> void:
	var s := CollisionShape3D.new(); var c := CylinderShape3D.new(); c.radius = r; c.height = h
	s.shape = c; s.position = pos + Vector3.UP * h * 0.5; body.add_child(s)
	var bt = batch if target == null else target
	bt.cyl(Transform3D(Basis(), pos), r, r, h, sides, col)
	_mark(pos, Vector3(r * 2, 1, r * 2), 0.0)
	solids.append(Rect2(pos.x - r, pos.z - r, r * 2, r * 2))

func free_rect(x: float, z: float, r: float) -> bool:
	var q := Rect2(x - r, z - r, r * 2, r * 2)
	for s in solids:
		if s.intersects(q): return false
	return true

func _ground() -> void:
	var img := Image.new(); img.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/ground.dat")); img.generate_mipmaps()
	ground_tex = ImageTexture.create_from_image(img)
	var det := Image.new(); det.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/detail.dat")); det.generate_mipmaps()
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform sampler2D map : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D det : filter_linear_mipmap, repeat_enable;
uniform sampler2D proto : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D proto_lines : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 half_size;
varying vec3 wp;
void vertex(){ wp = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment(){
	vec2 uv = (wp.xz + half_size) / (half_size * 2.0);
	vec3 far_col = vec3(0.42,0.40,0.28);
	vec3 c = texture(map, clamp(uv,0.0,1.0)).rgb;
	float out_d = max(max(-uv.x,uv.x-1.0), max(-uv.y,uv.y-1.0));
	c = mix(c, far_col, clamp(out_d*40.0,0.0,1.0));
	float d = texture(det, wp.xz*0.18).r * 0.6 + texture(det, wp.xz*0.9).r * 0.4;
	float sat = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
	float paved = 1.0 - smoothstep(0.03, 0.09, sat);
	float grid = texture(proto, wp.xz / 16.0).r;
	float lines = texture(proto_lines, wp.xz / 8.0).r;
	ALBEDO = c * (0.72 + 0.56*d) * mix(1.0, (0.86 + 0.26*grid) * lines, paved);
	ROUGHNESS = 1.0;
}"""
	var m := ShaderMaterial.new(); m.shader = sh
	m.set_shader_parameter("map", ground_tex); m.set_shader_parameter("det", ImageTexture.create_from_image(det)); m.set_shader_parameter("half_size", HALF); m.set_shader_parameter("proto", _gray_tex("res://assets/proto_ground.dat")); m.set_shader_parameter("proto_lines", _gray_tex("res://assets/proto_struct.dat"))
	var pm := PlaneMesh.new(); pm.size = Vector2(2400, 2400)
	var g := MeshInstance3D.new(); g.mesh = pm; g.material_override = m; g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(g)
	var gb := StaticBody3D.new(); gb.collision_layer = 8; gb.collision_mask = 0
	var cs := CollisionShape3D.new(); cs.shape = WorldBoundaryShape3D.new(); gb.add_child(cs); add_child(gb)

func _bounds() -> void:
	for d in [[Vector3(0, 5, -HALF.y - 1), Vector3(HALF.x * 2 + 4, 10, 2)], [Vector3(0, 5, HALF.y + 1), Vector3(HALF.x * 2 + 4, 10, 2)], [Vector3(-HALF.x - 1, 5, 0), Vector3(2, 10, HALF.y * 2 + 4)], [Vector3(HALF.x + 1, 5, 0), Vector3(2, 10, HALF.y * 2 + 4)]]:
		var s := CollisionShape3D.new(); var b := BoxShape3D.new(); b.size = d[1]; s.shape = b; s.position = d[0]; body.add_child(s)

# --- hangar principale con il relitto dell'An-225 ---
func _main_hangar() -> void:
	var cx := 0.0; var cz := -120.0; var w := 136.0; var d := 118.0; var h := 25.0
	mini_rects.append(Rect2(cx - w / 2, cz - d / 2, w, d))
	var col_w := WALL
	# parete di fondo con squarcio
	solid(Vector3(cx - 40, h / 2, cz - d / 2), Vector3(w - 80, h, 1.2), col_w)
	solid(Vector3(cx + 43, h / 2, cz - d / 2), Vector3(w - 86, h, 1.2), col_w)
	solid(Vector3(cx - 3, 3, cz - d / 2), Vector3(10, 6, 1.2), SOOT)
	# pareti laterali con brecce percorribili
	for sx in [-1.0, 1.0]:
		var wx: float = cx + sx * w / 2
		solid(Vector3(wx, h / 2, cz - 34), Vector3(1.2, h, 50), col_w)
		solid(Vector3(wx, h / 2, cz + 34), Vector3(1.2, h, 50), col_w)
		batch.at(Vector3(wx, h - 4, cz), Vector3(1.2, 8, 18), SOOT)
	# facciata: portale aperto largo 70 m
	var fz := cz + d / 2
	solid(Vector3(cx - 53, h / 2, fz), Vector3(30, h, 1.5), WALL2)
	solid(Vector3(cx + 53, h / 2, fz), Vector3(30, h, 1.5), WALL2)
	batch.at(Vector3(cx, h - 2.5, fz), Vector3(76, 5, 1.5), WALL2)
	# tetto a campate, parte crollata
	for i in 12:
		for j in 7:
			var hole := (i in [3, 4, 5, 8] and j in [1, 2, 3, 4]) or (i == 9 and j == 5)
			var pos := Vector3(cx - w / 2 + (i + 0.5) * w / 12, h + 0.6 + sin(float(j) / 6.0 * PI) * 4.5, cz - d / 2 + (j + 0.5) * d / 7)
			if hole:
				if rng.randf() < 0.4: batch.at(pos - Vector3(0, 2.5, 0), Vector3(w / 13, 0.4, 2), SOOT, rng.randf())
				continue
			var tone := WALL.darkened(0.15 + rng.randf() * 0.2)
			batch.at(pos, Vector3(w / 12 + 0.1, 0.5, d / 7 + 0.1), tone)
	for i in range(1, 12): # travature
		batch.at(Vector3(cx - w / 2 + i * w / 12, h - 0.5, cz), Vector3(0.8, 1.4, d), RUST.darkened(0.2))
	for i in range(1, 12, 2): # pilastri
		for z in [cz - d / 2 + 4, cz + d / 2 - 4]:
			solid(Vector3(cx - w / 2 + i * w / 12, h / 2, z), Vector3(1.2, h, 1.2), RUST.darkened(0.3))
	_mriya(Vector3(cx + 2, 0, cz + 12))
	# macerie
	for i in 46:
		var p := Vector3(cx + rng.randf_range(-58, 58), 0.6, cz + rng.randf_range(-50, 50))
		if not free_rect(p.x, p.z, 2): continue
		var sz := Vector3(rng.randf_range(1.5, 5), rng.randf_range(0.6, 1.7), rng.randf_range(1.5, 5))
		solid(p + Vector3.UP * (sz.y / 2 - 0.6), sz, SOOT.lerp(WALL, rng.randf() * 0.6), rng.randf() * TAU)
	smoke_spots.append(Vector3(cx + 15, 9, cz + 8)); smoke_spots.append(Vector3(cx - 22, 7, cz - 18))
	for p in [Vector3(-46, 0, -160), Vector3(46, 0, -150), Vector3(-52, 0, -95), Vector3(52, 0, -92), Vector3(-30, 0, -74), Vector3(34, 0, -76)]:
		loot_spots.append(p)

func _mriya(o: Vector3) -> void:
	var r := 4.3; var y := 5.0; var dark := BURNT; var pale := Color(0.52, 0.53, 0.52)
	var X90 := Basis(Vector3.RIGHT, PI / 2)
	# fusoliera spezzata in tre tronconi, disposti come un relitto
	batch.cyl(Transform3D(X90.rotated(Vector3.UP, 0.05), o + Vector3(0, y, -8)), r, r, 30, 12, pale.darkened(0.2), true)
	batch.cyl(Transform3D(X90.rotated(Vector3.UP, -0.09), o + Vector3(1, y - 0.4, -40)), r, r * 0.55, 30, 12, dark, true)
	batch.cyl(Transform3D(X90.rotated(Vector3.UP, 0.26).rotated(Vector3.RIGHT, 0.08), o + Vector3(-1, y - 1.8, 24)), r * 0.98, r * 0.5, 15, 12, dark.lerp(pale, 0.35), true)
	solid(o + Vector3(0, 3.8, 6), Vector3(7.5, 7.6, 30), pale, 0.0, false)
	solid(o + Vector3(0, 3.8, -25), Vector3(6.5, 7.6, 30), dark, 0.0, false)
	solid(o + Vector3(1, 3.2, 31), Vector3(7, 6.4, 14), dark, 0.25, false)
	# ali: una alta e bruciata, l'altra cedutta fino a terra
	var wing_z := o.z - 5
	batch.at(Vector3(o.x + 21, 8.6, wing_z), Vector3(38, 0.8, 11), dark.lerp(pale, 0.25), 0.05)
	var droop := Transform3D(Basis(Vector3.FORWARD, -0.17), Vector3(o.x - 21, 6.0, wing_z))
	batch.box(droop, Vector3(38, 0.8, 11), dark)
	solid(Vector3(o.x - 37, 1.5, wing_z), Vector3(8, 3, 9), dark, 0.0, false)
	for i in 3: # motori
		var ex := 10.0 + i * 9.0
		batch.cyl(Transform3D(X90, Vector3(o.x + ex, 6.5, wing_z - 3)), 1.2, 1.2, 5, 8, dark)
		var ey := 4.2 + (2 - i) * 1.3
		batch.cyl(Transform3D(X90.rotated(Vector3.FORWARD, 0.2), Vector3(o.x - ex, ey, wing_z - 3)), 1.2, 1.2, 5, 8, BURNT)
	# coda bideriva
	var tz := o.z - 46
	batch.at(Vector3(o.x, 8.4, tz), Vector3(32, 0.6, 6), dark)
	for s in [-16.0, 16.0]:
		batch.at(Vector3(o.x + s, 12.5, tz), Vector3(0.6, 9, 6), dark.lerp(Color(0.1, 0.25, 0.45), 0.35))

func _small_hangar(cx: float, cz: float) -> void:
	var w := 58.0; var d := 44.0; var h := 13.0
	mini_rects.append(Rect2(cx - w / 2, cz - d / 2, w, d))
	solid(Vector3(cx, h / 2, cz - d / 2), Vector3(w, h, 0.8), WALL2)
	solid(Vector3(cx - w / 2, h / 2, cz), Vector3(0.8, h, d), WALL2)
	solid(Vector3(cx + w / 2, h / 2, cz), Vector3(0.8, h, d), WALL2)
	solid(Vector3(cx - 22, h / 2, cz + d / 2), Vector3(14, h, 0.8), WALL2)
	solid(Vector3(cx + 22, h / 2, cz + d / 2), Vector3(14, h, 0.8), WALL2)
	batch.at(Vector3(cx, h + 0.3, cz), Vector3(w + 1.5, 0.6, d + 1.5), WALL2.darkened(0.25))
	for i in 5:
		var p := Vector3(cx + rng.randf_range(-20, 20), 1.0, cz + rng.randf_range(-14, 10))
		solid(p, Vector3(rng.randf_range(2, 4), 2, rng.randf_range(2, 4)), Color(0.34, 0.30, 0.20), rng.randf() * 3)
	loot_spots.append(Vector3(cx - 8, 0, cz + 14)); loot_spots.append(Vector3(cx + 10, 0, cz + 2))

func _tower(x: float, z: float) -> void:
	mini_rects.append(Rect2(x - 5, z - 5, 10, 10))
	solid(Vector3(x, 12, z), Vector3(8, 24, 8), Color(0.62, 0.62, 0.58))
	batch.at(Vector3(x, 26, z), Vector3(13, 4, 13), Color(0.10, 0.15, 0.20))
	batch.at(Vector3(x, 28.3, z), Vector3(14, 0.6, 14), CONC)
	batch.cyl(Transform3D(Basis(), Vector3(x, 28.6, z)), 0.12, 0.05, 8, 5, BURNT)
	solid(Vector3(x + 11, 2.5, z), Vector3(16, 5, 10), CONC)
	loot_spots.append(Vector3(x - 8, 0, z + 8))

func _terminal(x: float, z: float) -> void:
	var w := 72.0; var d := 18.0; var h := 9.0
	mini_rects.append(Rect2(x - w / 2, z - d / 2, w, d))
	solid(Vector3(x, h / 2, z), Vector3(w, h, d), Color(0.66, 0.65, 0.60))
	for row in [2.6, 6.0]:
		for i in 14:
			batch.at(Vector3(x - w / 2 + 3 + i * 5.15, row, z + d / 2 + 0.03), Vector3(3.2, 1.8, 0.06), Color(0.08, 0.1, 0.12))
			batch.at(Vector3(x - w / 2 + 3 + i * 5.15, row, z - d / 2 - 0.03), Vector3(3.2, 1.8, 0.06), Color(0.08, 0.1, 0.12))
	loot_spots.append(Vector3(x - 12, 0, z + 13)); loot_spots.append(Vector3(x + 22, 0, z - 13))

func _warehouses() -> void:
	for i in 3:
		var x := -300.0 + i * 54.0; var z := -150.0
		mini_rects.append(Rect2(x - 20, z - 11, 40, 22))
		solid(Vector3(x, 3.5, z), Vector3(40, 7, 22), Color(0.48 + i * 0.03, 0.42, 0.36))
		batch.at(Vector3(x, 7.4, z), Vector3(41, 0.8, 23), WALL2.darkened(0.3))
		loot_spots.append(Vector3(x + 22, 0, z + 14))
	for i in 3:
		var x := -300.0 + i * 54.0; var z := 18.0 + 0.0 * i
		if i == 2: continue
		mini_rects.append(Rect2(x - 15, z - 7, 30, 14))
		solid(Vector3(x, 3, z + 12), Vector3(30, 6, 14), Color(0.60, 0.56, 0.48))

func _tanks() -> void:
	for i in 3:
		var p := Vector3(248.0 + i * 26.0, 0, -168)
		mini_rects.append(Rect2(p.x - 9, p.z - 9, 18, 18))
		solid_cyl(p, 9.0, 11.0, Color(0.68, 0.68, 0.64) if i != 1 else BURNT, 14)
	smoke_spots.append(Vector3(274, 11, -168))
	loot_spots.append(Vector3(261, 0, -150))

func _radar(x: float, z: float) -> void:
	mini_rects.append(Rect2(x - 5, z - 5, 10, 10))
	solid(Vector3(x, 4, z), Vector3(8, 8, 8), CONC)
	batch.cyl(Transform3D(Basis(), Vector3(x, 8, z)), 4.5, 2.2, 3.5, 12, Color(0.8, 0.8, 0.78))
	batch.cyl(Transform3D(Basis(), Vector3(x, 11.5, z)), 2.2, 0.1, 1.2, 12, Color(0.8, 0.8, 0.78))
	loot_spots.append(Vector3(x + 7, 0, z - 6))

func _parked_plane(x: float, z: float, rot: float) -> void:
	var c := Vector3(x, 0, z); var bs := Basis(Vector3.UP, rot); var X90 := Basis(Vector3.RIGHT, PI / 2)
	var pale := Color(0.72, 0.73, 0.72); var b2 := Color(0.13, 0.27, 0.46)
	batch.cyl(Transform3D(bs * X90, c + bs * Vector3(0, 2.7, -11)), 1.8, 1.8, 18, 10, pale)
	batch.cyl(Transform3D(bs * X90, c + bs * Vector3(0, 2.7, 7)), 1.8, 0.6, 4, 10, b2)
	batch.cyl(Transform3D(bs * Basis(Vector3.RIGHT, -PI / 2), c + bs * Vector3(0, 2.8, -11)), 1.8, 0.4, 7, 10, pale)
	batch.box(Transform3D(bs, c + bs * Vector3(0, 4.3, 0)), Vector3(30, 0.4, 4.2), pale)
	batch.box(Transform3D(bs, c + bs * Vector3(0, 7, -15)), Vector3(0.4, 6, 3.5), b2)
	batch.box(Transform3D(bs, c + bs * Vector3(0, 3.5, -15.5)), Vector3(11, 0.3, 2.4), pale)
	for s in [-7.0, 7.0]:
		batch.cyl(Transform3D(bs * X90, c + bs * Vector3(s, 3.5, -2)), 0.9, 0.9, 5, 8, b2)
	solid(c + bs * Vector3(0, 1.6, 0), Vector3(3.0, 3.2, 32), pale, rot, false)
	loot_spots.append(c + bs * Vector3(7, 0, 4))

func _helicopter(p: Vector3, rot: float) -> void:
	var bs := Basis(Vector3.UP, rot).rotated(Vector3.BACK, 0.22); var X90 := Basis(Vector3.RIGHT, PI / 2)
	var c := p + Vector3(0, 1.6, 0)
	batch.box(Transform3D(bs, c), Vector3(2.5, 2.6, 8.0), BURNT)
	batch.cyl(Transform3D(bs * X90, c + bs * Vector3(0, 0, 4)), 1.2, 0.8, 2, 8, Color(0.16, 0.17, 0.15))
	batch.box(Transform3D(bs, c + bs * Vector3(0, 0.8, -7.5)), Vector3(0.8, 0.8, 8), Color(0.2, 0.22, 0.17))
	batch.box(Transform3D(bs, c + bs * Vector3(0, 1.8, -11.4)), Vector3(0.3, 3, 1.1), BURNT)
	batch.box(Transform3D(bs.rotated(Vector3.UP, 0.5), c + bs * Vector3(0, 1.8, 0)), Vector3(9, 0.1, 0.5), BURNT)
	batch.box(Transform3D(bs.rotated(Vector3.UP, 2.0), c + bs * Vector3(0, 1.8, 0)), Vector3(7, 0.1, 0.5), BURNT)
	solid(p + Vector3(0, 1.6, 0), Vector3(3.2, 3.2, 9), BURNT, rot, false)
	smoke_spots.append(c + Vector3.UP)
	loot_spots.append(p + Basis(Vector3.UP, rot) * Vector3(5, 0, 2))

func _vehicle(p: Vector3, rot: float, burnt: bool) -> void:
	var bs := Basis(Vector3.UP, rot)
	var col := BURNT if burnt else OLIVE
	batch.box(Transform3D(bs, p + Vector3(0, 0.9, 0)), Vector3(2.9, 1.1, 5.8), col)
	batch.box(Transform3D(bs, p + bs * Vector3(0, 1.75, -0.3)), Vector3(1.6, 0.7, 2.0), col.darkened(0.1))
	batch.box(Transform3D(bs, p + bs * Vector3(0, 1.8, 1.8)), Vector3(0.14, 0.14, 2.8), BURNT)
	for s in [-1.45, 1.45]:
		batch.box(Transform3D(bs, p + bs * Vector3(s, 0.45, 0)), Vector3(0.45, 0.9, 5.9), Color(0.1, 0.1, 0.1))
	solid(p + Vector3(0, 1.0, 0), Vector3(3.3, 2.0, 6), col, rot, false)

func _truck(p: Vector3, rot: float) -> void:
	var bs := Basis(Vector3.UP, rot); var g := Color(0.28, 0.32, 0.22)
	batch.box(Transform3D(bs, p + bs * Vector3(0, 1.8, 1.6)), Vector3(2.4, 2.1, 4.6), g.darkened(0.1))
	batch.box(Transform3D(bs, p + bs * Vector3(0, 2.0, -2.4)), Vector3(2.3, 2.3, 2.2), g)
	batch.box(Transform3D(bs, p + bs * Vector3(0, 2.3, -3.54)), Vector3(1.9, 0.8, 0.05), Color(0.08, 0.1, 0.12))
	for pz in [-2.6, 1.8]:
		for s in [-1.05, 1.05]:
			batch.cyl(Transform3D(bs * Basis(Vector3.BACK, PI / 2), p + bs * Vector3(s + 0.15, 0.55, pz)), 0.55, 0.55, 0.3, 8, Color(0.08, 0.08, 0.08))
	solid(p + Vector3(0, 1.4, 0), Vector3(2.6, 2.8, 7.4), g, rot, false)

func _wrecks() -> void:
	_helicopter(Vector3(-150, 0, 112), 0.8)
	_helicopter(Vector3(120, 0, 160), -1.2)
	_helicopter(Vector3(-40, 0, -210), 2.2)
	_vehicle(Vector3(-52, 0, 30), 0.4, true)
	_vehicle(Vector3(40, 0, -30), 2.0, true)
	_vehicle(Vector3(210, 0, 118), 1.3, true)
	_vehicle(Vector3(-262, 0, 82), 2.4, true)
	_vehicle(Vector3(-110, 0, 64), 1.5, false)
	_truck(Vector3(-280, 0, -6), 1.57)
	_truck(Vector3(146, 0, -14), 1.3)
	_truck(Vector3(240, 0, -15), 1.6)
	_truck(Vector3(-20, 0, 66), 0.5)

func _sandbag_nest(p: Vector3, rot: float) -> void:
	var bs := Basis(Vector3.UP, rot)
	for seg in [[Vector3(0, 0.55, -3), Vector3(6, 1.1, 1.1), 0.0], [Vector3(-3, 0.55, 0), Vector3(1.1, 1.1, 5), 0.0], [Vector3(3, 0.55, 0), Vector3(1.1, 1.1, 5), 0.0]]:
		solid(p + bs * seg[0], seg[1], SAND.darkened(rng.randf() * 0.18), rot)
	loot_spots.append(p)

func _defences() -> void:
	for d in [[-200, 42, 0.0], [-30, 42, 3.1], [110, 42, 1.0], [240, 42, 0.4], [-120, -30, 2.0], [120, -35, 4.0], [-300, 60, 0.7], [305, 40, 2.6], [-60, 118, 0.0], [70, 110, 3.1], [-250, 128, 1.5], [270, 134, 4.5], [-205, -100, 1.0], [130, -130, 2.0], [-130, 180, 3.5], [40, 182, 0.0], [190, 195, 1.5]]:
		_sandbag_nest(Vector3(d[0], 0, d[1]), d[2])
	# blocchi di cemento lungo la pista, unica copertura allo scoperto
	for i in 26:
		var x := -320.0 + i * 25.0 + rng.randf_range(-6, 6)
		var z := rng.randf_range(92, 148)
		solid(Vector3(x, 0.75, z), Vector3(rng.randf_range(2.5, 6), 1.5, 1.4), CONC.darkened(rng.randf() * 0.2), rng.randf() * PI)
	# recinzione a tratti
	for i in 34:
		var x := -340.0 + i * 20.5
		if i % 5 == 0: continue
		batch.at(Vector3(x, 1.2, 167), Vector3(19.0, 2.4, 0.06), Color(0.3, 0.3, 0.3, 1))
		solid(Vector3(x - 9.5, 1.3, 167), Vector3(0.2, 2.6, 0.2), RUST.darkened(0.3))

func _scatter() -> void:
	var made := 0; var tries := 0
	while made < 70 and tries < 500:
		tries += 1
		var p := Vector3(rng.randf_range(-335, 335), 0, rng.randf_range(-235, 235))
		if not free_rect(p.x, p.z, 4): continue
		var kind := rng.randi() % 4
		if kind == 0:
			var a := rng.randf() * TAU
			solid(p + Vector3(0, 0.9, 0), Vector3(2.4, 1.8, 2.4), Color(0.28, 0.33, 0.24), a)
			solid(p + Basis(Vector3.UP, a) * Vector3(2.5, 0.7, 0.3), Vector3(2, 1.4, 2), Color(0.37, 0.31, 0.21), a + 0.3)
		elif kind == 1:
			solid(p + Vector3(0, 1.2, 0), Vector3(6.0, 2.4, 2.4), Color(0.16, 0.30, 0.36).darkened(rng.randf() * 0.3), rng.randf() * PI)
		elif kind == 2:
			solid(p + Vector3(0, 0.8, 0), Vector3(rng.randf_range(4, 8), 1.6, 1.6), CONC.darkened(rng.randf() * 0.2), rng.randf() * PI)
		else:
			solid_cyl(p, 0.45, 1.0, Color(0.20, 0.26, 0.20), 7)
			solid_cyl(p + Vector3(1.1, 0, 0.3), 0.45, 1.0, RUST, 7)
			loot_spots.append(p + Vector3(0, 0, 2.5))
		made += 1

func _tree(p: Vector3, target, s: float) -> void:
	var tint := rng.randf() * 0.12
	var g := Color(0.13 + tint * 0.3, 0.23 + tint, 0.14 + tint * 0.4)
	var xf := Transform3D(Basis(), p)
	target.cyl(xf, 0.3 * s, 0.14 * s, 7 * s, 5, Color(0.25, 0.17, 0.12), false)
	target.cyl(Transform3D(Basis(), p + Vector3.UP * 4.2 * s), 2.7 * s, 0.7 * s, 4 * s, 7, g, false)
	target.cyl(Transform3D(Basis(), p + Vector3.UP * 7.2 * s), 1.9 * s, 0.05, 4.6 * s, 7, g.lightened(0.05), false)

func _forest() -> void:
	# Foresta di pini intorno all'aeroporto: la parte interna ha collisioni, quella esterna fa da orizzonte.
	var n := 0; var t := 0
	while n < 230 and t < 3000:
		t += 1
		var z := rng.randf_range(176, 245) if rng.randf() < 0.45 else rng.randf_range(-245, -188)
		var x := rng.randf_range(-345, 345)
		if not free_rect(x, z, 3): continue
		var s := rng.randf_range(0.9, 1.4); var p := Vector3(x, 0, z)
		_tree(p, trees_batch, s)
		var sh := CollisionShape3D.new(); var cy := CylinderShape3D.new(); cy.radius = 0.45; cy.height = 8.0; sh.shape = cy; sh.position = p + Vector3.UP * 4; body.add_child(sh)
		_mark(p, Vector3(1, 1, 1), 0.0)
		n += 1
	for i in 420:
		var a := rng.randf() * TAU; var r := rng.randf_range(1.0, 1.7)
		var p := Vector3(cos(a) * (HALF.x + 18) * r, 0, sin(a) * (HALF.y + 18) * r)
		if absf(p.x) < HALF.x + 8 and absf(p.z) < HALF.y + 8: continue
		_tree(p, trees_batch, rng.randf_range(1.1, 1.9))
