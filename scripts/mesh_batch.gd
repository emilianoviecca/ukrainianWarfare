extends RefCounted
# Raccoglie geometria low-poly in un'unica mesh: una sola chiamata di disegno.
var v := PackedVector3Array()
var n := PackedVector3Array()
var c := PackedColorArray()
static var _baked := {}

func tri(a: Vector3, b: Vector3, d: Vector3, nor: Vector3, col: Color) -> void:
	# Godot considera frontali i triangoli in senso orario.
	if (b - a).cross(d - a).dot(nor) > 0.0:
		var t := b; b = d; d = t
	v.append(a); v.append(b); v.append(d)
	n.append(nor); n.append(nor); n.append(nor)
	c.append(col); c.append(col); c.append(col)

func quad(a: Vector3, b: Vector3, d: Vector3, e: Vector3, nor: Vector3, col: Color) -> void:
	tri(a, b, d, nor, col); tri(a, d, e, nor, col)

func box(xf: Transform3D, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var P := func(x: float, y: float, z: float) -> Vector3: return xf * Vector3(x * h.x, y * h.y, z * h.z)
	var bs := xf.basis.orthonormalized()
	quad(P.call(1,-1,-1), P.call(1,1,-1), P.call(1,1,1), P.call(1,-1,1), bs.x, col)
	quad(P.call(-1,-1,-1), P.call(-1,1,-1), P.call(-1,1,1), P.call(-1,-1,1), -bs.x, col)
	var top := col.lightened(0.05)
	quad(P.call(-1,1,-1), P.call(1,1,-1), P.call(1,1,1), P.call(-1,1,1), bs.y, top)
	quad(P.call(-1,-1,-1), P.call(1,-1,-1), P.call(1,-1,1), P.call(-1,-1,1), -bs.y, col)
	quad(P.call(-1,-1,1), P.call(1,-1,1), P.call(1,1,1), P.call(-1,1,1), bs.z, col)
	quad(P.call(-1,-1,-1), P.call(1,-1,-1), P.call(1,1,-1), P.call(-1,1,-1), -bs.z, col)

func at(p: Vector3, size: Vector3, col: Color, rot_y := 0.0) -> void:
	box(Transform3D(Basis(Vector3.UP, rot_y), p), size, col)

# Cilindro o cono lungo +Y a partire dall'origine di xf.
func cyl(xf: Transform3D, r0: float, r1: float, h: float, sides: int, col: Color, caps := true) -> void:
	var bs := xf.basis.orthonormalized()
	for i in sides:
		var a0 := TAU * i / sides; var a1 := TAU * (i + 1) / sides
		var d0 := Vector3(cos(a0), 0, sin(a0)); var d1 := Vector3(cos(a1), 0, sin(a1))
		var nor := bs * ((d0 + d1).normalized() + Vector3(0, (r0 - r1) / max(h, 0.01), 0)).normalized()
		quad(xf * (d0 * r0), xf * (d1 * r0), xf * (d1 * r1 + Vector3.UP * h), xf * (d0 * r1 + Vector3.UP * h), nor, col)
		if caps:
			if r1 > 0.001: tri(xf * Vector3(0, h, 0), xf * (d0 * r1 + Vector3.UP * h), xf * (d1 * r1 + Vector3.UP * h), bs.y, col)
			if r0 > 0.001: tri(xf.origin, xf * (d0 * r0), xf * (d1 * r0), -bs.y, col)

# Aggiunge un modello cotto da tools/bake_vehicle.py; restituisce larghezza, altezza e lunghezza.
func add_baked(path: String, xf: Transform3D, burnt: bool) -> Vector3:
	if not _baked.has(path):
		var by := FileAccess.get_file_as_bytes(path)
		var cnt := by.decode_s32(0)
		var d := {"dim": Vector3(by.decode_float(4), by.decode_float(8), by.decode_float(12))}
		var f := by.slice(16).to_float32_array()
		var pp := PackedVector3Array(); pp.resize(cnt)
		var nn := PackedVector3Array(); nn.resize(cnt)
		var cc := PackedColorArray(); cc.resize(cnt)
		var bb := PackedColorArray(); bb.resize(cnt)
		var o1 := cnt * 3; var o2 := cnt * 6; var o3 := cnt * 10
		for i in cnt:
			var k := i * 3; var q := i * 4
			pp[i] = Vector3(f[k], f[k + 1], f[k + 2])
			nn[i] = Vector3(f[o1 + k], f[o1 + k + 1], f[o1 + k + 2])
			cc[i] = Color(f[o2 + q], f[o2 + q + 1], f[o2 + q + 2])
			bb[i] = Color(f[o3 + q], f[o3 + q + 1], f[o3 + q + 2])
		d.p = pp; d.n = nn; d.c = cc; d.b = bb
		_baked[path] = d
	var e: Dictionary = _baked[path]
	v.append_array(xf * e.p)
	n.append_array(Transform3D(xf.basis.orthonormalized(), Vector3.ZERO) * e.n)
	c.append_array(e.b if burnt else e.c)
	return e.dim

func build() -> ArrayMesh:
	var m := ArrayMesh.new()
	if v.is_empty(): return m
	var arr := []; arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v; arr[Mesh.ARRAY_NORMAL] = n; arr[Mesh.ARRAY_COLOR] = c
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

static func material() -> StandardMaterial3D:
	var s := StandardMaterial3D.new()
	s.vertex_color_use_as_albedo = true
	s.vertex_color_is_srgb = true
	s.roughness = 0.95
	s.metallic_specular = 0.15
	return s
