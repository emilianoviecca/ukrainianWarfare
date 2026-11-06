extends RefCounted
# Raccoglie geometria low-poly in un'unica mesh: una sola chiamata di disegno.
var v := PackedVector3Array()
var n := PackedVector3Array()
var c := PackedColorArray()

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
