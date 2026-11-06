extends Node3D
# Soldato low-poly con animazione procedurale. Avanti = -Z.
const Batch := preload("res://scripts/mesh_batch.gd")
static var cache := {}
static var mat: StandardMaterial3D
var torso: Node3D; var head: Node3D; var arm_l: Node3D; var arm_r: Node3D; var leg_l: Node3D; var leg_r: Node3D
var gun: MeshInstance3D; var muzzle: Node3D
var phase := 0.0; var crouch_amt := 0.0; var death_t := -1.0

static func _parts(faction: String) -> Dictionary:
	if cache.has(faction): return cache[faction]
	var ua := faction == "ua"
	var coat := Color(0.30, 0.35, 0.21) if ua else Color(0.36, 0.33, 0.23)
	var patch := Color(0.20, 0.25, 0.14) if ua else Color(0.24, 0.20, 0.14)
	var vest := Color(0.17, 0.21, 0.13) if ua else Color(0.20, 0.20, 0.16)
	var band := Color(0.98, 0.82, 0.05) if ua else Color(0.95, 0.95, 0.95)
	var helmet := Color(0.21, 0.26, 0.16) if ua else Color(0.27, 0.27, 0.20)
	var skin := Color(0.78, 0.60, 0.48); var boot := Color(0.10, 0.09, 0.08)
	var t = Batch.new()
	t.at(Vector3(0, 0.28, 0), Vector3(0.44, 0.62, 0.25), coat)
	t.at(Vector3(0, 0.30, -0.02), Vector3(0.46, 0.46, 0.31), vest)
	t.at(Vector3(-0.1, 0.22, -0.18), Vector3(0.11, 0.2, 0.06), patch); t.at(Vector3(0.1, 0.22, -0.18), Vector3(0.11, 0.2, 0.06), patch)
	t.at(Vector3(0, 0.33, 0.21), Vector3(0.34, 0.46, 0.17), patch)
	t.at(Vector3(0, -0.02, 0), Vector3(0.40, 0.18, 0.24), patch)
	var h = Batch.new()
	h.at(Vector3(0, 0.07, 0), Vector3(0.11, 0.14, 0.11), skin)
	h.at(Vector3(0, 0.22, -0.01), Vector3(0.20, 0.23, 0.22), skin)
	h.cyl(Transform3D(Basis(), Vector3(0, 0.25, 0)), 0.165, 0.11, 0.14, 8, helmet)
	if not ua: h.at(Vector3(0, 0.29, 0), Vector3(0.3, 0.035, 0.3), band)
	var a = Batch.new()
	a.at(Vector3(0, -0.26, 0), Vector3(0.13, 0.54, 0.14), coat)
	a.at(Vector3(0, -0.13, 0), Vector3(0.145, 0.07, 0.15), band)
	a.at(Vector3(0, -0.56, 0), Vector3(0.1, 0.1, 0.1), skin)
	var l = Batch.new()
	l.at(Vector3(0, -0.2, 0), Vector3(0.18, 0.42, 0.2), coat)
	l.at(Vector3(0, -0.2, 0.08), Vector3(0.12, 0.22, 0.06), patch)
	l.at(Vector3(0, -0.6, 0), Vector3(0.16, 0.42, 0.18), coat.darkened(0.08))
	l.at(Vector3(0, -0.86, -0.03), Vector3(0.17, 0.14, 0.27), boot)
	if not ua: l.at(Vector3(0, -0.28, 0), Vector3(0.19, 0.06, 0.21), band)
	var d := {"torso": t.build(), "head": h.build(), "arm": a.build(), "leg": l.build()}
	cache[faction] = d
	return d

static func gun_mesh(kind: String) -> ArrayMesh:
	var key := "gun_" + kind
	if cache.has(key): return cache[key]
	var b = Batch.new(); var bl := Color(0.09, 0.09, 0.09); var wd := Color(0.34, 0.20, 0.10)
	if kind == "pistol":
		b.at(Vector3(0, 0, -0.1), Vector3(0.04, 0.05, 0.2), bl); b.at(Vector3(0, -0.07, -0.03), Vector3(0.035, 0.11, 0.05), bl)
	elif kind == "svd":
		b.at(Vector3(0, 0, -0.1), Vector3(0.05, 0.08, 0.6), wd); b.at(Vector3(0, 0.01, -0.72), Vector3(0.022, 0.022, 0.72), bl)
		b.at(Vector3(0, -0.02, 0.33), Vector3(0.05, 0.12, 0.34), wd); b.at(Vector3(0, -0.1, -0.06), Vector3(0.04, 0.17, 0.08), bl)
		b.at(Vector3(0, 0.09, -0.08), Vector3(0.05, 0.05, 0.3), bl)
	else:
		b.at(Vector3(0, 0, -0.1), Vector3(0.05, 0.08, 0.45), bl); b.at(Vector3(0, -0.005, -0.3), Vector3(0.05, 0.06, 0.2), wd)
		b.at(Vector3(0, 0.015, -0.56), Vector3(0.022, 0.022, 0.48), bl); b.at(Vector3(0, -0.02, 0.25), Vector3(0.05, 0.11, 0.3), wd)
		b.at(Vector3(0, -0.12, -0.13), Vector3(0.04, 0.17, 0.09), Color(0.35, 0.18, 0.08))
		b.at(Vector3(0, -0.08, 0.03), Vector3(0.035, 0.11, 0.05), bl)
	var m: ArrayMesh = b.build(); cache[key] = m; return m

func _mi(mesh: Mesh, parent: Node3D, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); mi.mesh = mesh; mi.material_override = mat; mi.position = pos; parent.add_child(mi); return mi

func setup(faction: String) -> void:
	if mat == null: mat = Batch.material()
	var p := _parts(faction)
	torso = Node3D.new(); torso.position = Vector3(0, 0.95, 0); add_child(torso)
	_mi(p.torso, torso, Vector3.ZERO)
	head = _mi(p.head, torso, Vector3(0, 0.59, 0))
	arm_l = _mi(p.arm, torso, Vector3(-0.28, 0.5, 0)); arm_r = _mi(p.arm, torso, Vector3(0.28, 0.5, 0))
	leg_l = _mi(p.leg, self, Vector3(-0.11, 0.93, 0)); leg_r = _mi(p.leg, self, Vector3(0.11, 0.93, 0))
	gun = _mi(gun_mesh("ak"), torso, Vector3(0.13, 0.33, -0.32))
	muzzle = Node3D.new(); muzzle.position = Vector3(0, 0.015, -0.82); gun.add_child(muzzle)

func set_gun(kind: String) -> void:
	gun.mesh = gun_mesh(kind)
	gun.position = Vector3(0.2, 0.36, -0.42) if kind == "pistol" else Vector3(0.13, 0.33, -0.32)
	muzzle.position = Vector3(0, 0.0, -0.22) if kind == "pistol" else (Vector3(0, 0.01, -1.08) if kind == "svd" else Vector3(0, 0.015, -0.82))

func animate(dt: float, speed: float, crouching: bool, pitch := 0.0) -> void:
	if death_t >= 0.0:
		death_t += dt
		var k: float = min(death_t / 0.55, 1.0); k = k * k
		rotation.x = 1.5 * k
		position.y = 0.12 * k
		return
	phase += dt * (speed * 2.4 + 0.001)
	crouch_amt = lerpf(crouch_amt, 1.0 if crouching else 0.0, min(dt * 9.0, 1.0))
	var sw := sin(phase) * clampf(speed / 3.0, 0.0, 1.0) * 0.72
	torso.position.y = 0.95 - 0.40 * crouch_amt + absf(sin(phase)) * 0.025 * clampf(speed, 0, 1)
	var hipy := 0.93 - 0.40 * crouch_amt
	leg_l.position.y = hipy; leg_r.position.y = hipy
	leg_l.rotation.x = sw + 0.85 * crouch_amt
	leg_r.rotation.x = -sw - 0.55 * crouch_amt
	torso.rotation.x = 0.28 * crouch_amt + 0.08 * clampf(speed / 6.0, 0, 1)
	arm_r.rotation = Vector3(1.32 + pitch, 0.0, 0.25)
	arm_l.rotation = Vector3(1.32 + pitch, 0.0, -0.62)
	gun.rotation.x = pitch
	head.rotation.x = pitch * 0.5

func die() -> void:
	if death_t < 0.0: death_t = 0.0
