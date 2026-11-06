extends Node3D
# Soldato basato su Blocky Characters di Kenney (CC0) con divise dipinte. Avanti = -Z.
const Batch := preload("res://scripts/mesh_batch.gd")
const GUN_Y := 1.2
static var cache := {}
static var mat: StandardMaterial3D
static var scene: PackedScene
var inst: Node3D; var ap: AnimationPlayer
var torso: Node3D; var head: Node3D; var arm_l: Node3D; var arm_r: Node3D; var leg_l: Node3D; var leg_r: Node3D
var gun_pivot: Node3D; var gun: MeshInstance3D; var muzzle: Node3D
var crouch_amt := 0.0; var dead_flag := false; var cur_anim := ""; var kick := 0.0
var hold_l := Quaternion.IDENTITY; var hold_r := Quaternion.IDENTITY

static func _faction_mat(faction: String) -> StandardMaterial3D:
	var key := "mat_" + faction
	if cache.has(key): return cache[key]
	var img := Image.new(); img.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/soldier_%s.dat" % faction)); img.generate_mipmaps()
	var m := StandardMaterial3D.new(); m.albedo_texture = ImageTexture.create_from_image(img); m.roughness = 0.95; m.metallic_specular = 0.15
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	cache[key] = m; return m

static func _helmet_mesh(faction: String) -> ArrayMesh:
	var key := "helmet_" + faction
	if cache.has(key): return cache[key]
	var ua := faction == "ua"
	var col := Color(0.20, 0.25, 0.15) if ua else Color(0.25, 0.25, 0.18)
	var b = Batch.new()
	# Elmetto squadrato, coerente con la testa cubica del modello (coordinate del cubo testa: da -1 a 1).
	b.at(Vector3(0, 0.66, 0), Vector3(2.16, 0.86, 2.16), col)
	b.at(Vector3(0, 1.2, 0), Vector3(1.75, 0.3, 1.75), col.lightened(0.06))
	b.at(Vector3(0, 0.25, -0.06), Vector3(2.32, 0.1, 2.46), col.darkened(0.2))
	if not ua: b.at(Vector3(0, 0.68, 0), Vector3(2.2, 0.2, 2.2), Color(0.92, 0.92, 0.92))
	var m: ArrayMesh = b.build(); cache[key] = m; return m

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

func _find(n: String) -> Node3D:
	return inst.find_child(n, true, false) as Node3D

func setup(faction: String) -> void:
	if mat == null: mat = Batch.material()
	if scene == null: scene = load("res://assets/models/soldier.glb")
	inst = scene.instantiate(); add_child(inst)
	inst.rotation.y = PI
	var fm := _faction_mat(faction)
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = fm
	torso = _find("torso"); head = _find("head"); arm_l = _find("arm-left"); arm_r = _find("arm-right"); leg_l = _find("leg-left"); leg_r = _find("leg-right")
	inst.scale = Vector3.ONE * 0.72
	ap = inst.find_children("*", "AnimationPlayer", true, false)[0]
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for a in ["idle", "walk", "sprint"]:
		ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	ap.get_animation("die").loop_mode = Animation.LOOP_NONE
	ap.play("holding-both"); ap.seek(ap.get_animation("holding-both").length * 0.5, true)
	# Braccia più strette e convergenti sull'arma, che è impugnata sul lato destro.
	arm_l.position.x = 0.3; arm_r.position.x = -0.3
	hold_l = Quaternion(Vector3.UP, -0.52) * arm_l.quaternion
	hold_r = Quaternion(Vector3.UP, 0.1) * arm_r.quaternion
	head.scale *= 0.78
	_play("idle")
	var hm := MeshInstance3D.new(); hm.mesh = _helmet_mesh(faction); hm.material_override = mat
	head.get_child(0).add_child(hm)
	gun_pivot = Node3D.new(); gun_pivot.position = Vector3(0, GUN_Y, -0.1); add_child(gun_pivot)
	gun = MeshInstance3D.new(); gun.mesh = gun_mesh("ak"); gun.material_override = mat; gun_pivot.add_child(gun)
	muzzle = Node3D.new(); gun.add_child(muzzle)
	set_gun("ak")

func _play(a: String) -> void:
	if a == cur_anim: return
	cur_anim = a; ap.play(a, 0.14)

func set_gun(kind: String) -> void:
	gun.mesh = gun_mesh(kind)
	gun.position = Vector3(0.1, 0.03, -0.62) if kind == "pistol" else Vector3(0.14, 0.03, -0.34)
	muzzle.position = Vector3(0, 0.0, -0.22) if kind == "pistol" else (Vector3(0, 0.01, -1.08) if kind == "svd" else Vector3(0, 0.015, -0.82))

func animate(dt: float, speed: float, crouching: bool, pitch := 0.0) -> void:
	if dead_flag:
		ap.advance(dt); return
	var a := "idle"
	if speed > 4.6: a = "sprint"
	elif speed > 0.3: a = "walk"
	_play(a)
	ap.speed_scale = clampf(speed / 3.2, 0.7, 1.5) if a == "walk" else 1.0
	ap.advance(dt)
	crouch_amt = lerpf(crouch_amt, 1.0 if crouching else 0.0, min(dt * 9.0, 1.0))
	kick = max(kick - dt * 9.0, 0.0)
	# Gambe dall'animazione; braccia fisse sull'arma, inclinate con la mira.
	var pq := Quaternion(Vector3.RIGHT, pitch * -1.0 + kick * 0.12)
	arm_l.quaternion = pq * hold_l
	arm_r.quaternion = pq * hold_r
	if crouch_amt > 0.01:
		leg_l.rotation.x += 1.05 * crouch_amt
		leg_r.rotation.x -= 0.5 * crouch_amt
	inst.position.y = -0.42 * crouch_amt
	gun_pivot.position.y = GUN_Y - 0.42 * crouch_amt
	gun_pivot.rotation.x = pitch
	gun_pivot.position.z = -0.1 + kick * 0.04

func recoil() -> void:
	kick = 1.0

func die() -> void:
	if dead_flag: return
	dead_flag = true
	gun_pivot.visible = false
	ap.speed_scale = 1.0
	cur_anim = "die"; ap.play("die", 0.08)
