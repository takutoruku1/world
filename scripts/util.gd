extends RefCounted
# Shared helpers: Japanese font, themed UI factory, palette, formatting.

const COL := {
	"bg": Color("14161f"),
	"panel": Color("1d2130"),
	"panel_light": Color("262b40"),
	"border": Color("3a4160"),
	"gold": Color("d9b96a"),
	"text": Color("e8e6df"),
	"sub": Color("9aa3b5"),
	"good": Color("7fc97f"),
	"warn": Color("e0a458"),
	"bad": Color("d96a6a"),
	"tech": Color("d97b4a"),
	"nature": Color("6fbf73"),
	"mystic": Color("8b7fd9"),
}

const RES_ICONS := {
	"food": "🌾", "wood": "🪵", "stone": "🪨",
	"metal": "⚙", "mana": "✨", "knowledge": "📖",
}
const RES_NAMES := {
	"food": "食料", "wood": "木材", "stone": "石材",
	"metal": "金属", "mana": "魔素", "knowledge": "知識",
}
const AXIS_NAMES := {"tech": "機械", "nature": "自然", "mystic": "神秘"}
const DANGER_NAMES := {"war": "戦禍", "blight": "荒廃"}

static var _jp_font: Font = null
static var _theme: Theme = null
static var _texture_cache: Dictionary = {}
static var _model_cache: Dictionary = {}
static var _audio_cache: Dictionary = {}

static func jp_font() -> Font:
	if _jp_font == null:
		var emoji := SystemFont.new()
		emoji.font_names = PackedStringArray(["Segoe UI Emoji", "Segoe UI Symbol"])
		var system := SystemFont.new()
		system.font_names = PackedStringArray(["Yu Gothic UI", "Meiryo", "MS Gothic"])
		system.fallbacks = [emoji]
		# Kiwi Maru (OFL): storybook rounded gothic that fits the hakoniwa look.
		var kiwi_path := ProjectSettings.globalize_path("res://assets/fonts/KiwiMaru-Medium.ttf")
		if FileAccess.file_exists(kiwi_path):
			var kiwi := FontFile.new()
			if kiwi.load_dynamic_font(kiwi_path) == OK:
				kiwi.fallbacks = [system]
				_jp_font = kiwi
				return _jp_font
		_jp_font = system
	return _jp_font

static func make_label(text: String, size: int = 14, color: Color = COL["text"]) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", jp_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func make_richtext(size: int = 13) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.add_theme_font_override("normal_font", jp_font())
	r.add_theme_font_override("bold_font", jp_font())
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_color_override("default_color", COL["text"])
	r.fit_content = true
	r.scroll_active = false
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r

static func _flat(bg: Color, border: Color = Color(0, 0, 0, 0), radius: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(1)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	return sb

static func build_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = jp_font()
	t.default_font_size = 14

	t.set_stylebox("panel", "PanelContainer", _flat(COL["panel"], COL["border"]))

	var bn := _flat(COL["panel_light"], COL["border"], 6)
	var bh := _flat(Color("323a58"), COL["gold"], 6)
	var bp := _flat(Color("11131c"), COL["gold"], 6)
	var bd := _flat(Color("191c28"), Color("2a2f45"), 6)
	t.set_stylebox("normal", "Button", bn)
	t.set_stylebox("hover", "Button", bh)
	t.set_stylebox("pressed", "Button", bp)
	t.set_stylebox("disabled", "Button", bd)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", COL["text"])
	t.set_color("font_hover_color", "Button", COL["gold"])
	t.set_color("font_pressed_color", "Button", COL["gold"])
	t.set_color("font_disabled_color", "Button", Color("5a6070"))

	var pb_bg := _flat(Color("11131c"), Color(0, 0, 0, 0), 4)
	pb_bg.content_margin_left = 2.0
	pb_bg.content_margin_right = 2.0
	pb_bg.content_margin_top = 2.0
	pb_bg.content_margin_bottom = 2.0
	var pb_fill := _flat(COL["gold"], Color(0, 0, 0, 0), 4)
	t.set_stylebox("background", "ProgressBar", pb_bg)
	t.set_stylebox("fill", "ProgressBar", pb_fill)

	t.set_stylebox("separator", "HSeparator", _hsep())
	_theme = t
	return t

static func _hsep() -> StyleBoxLine:
	var s := StyleBoxLine.new()
	s.color = COL["border"]
	s.thickness = 1
	return s

static func make_bar(color: Color, width: float = 150.0) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.max_value = 100.0
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(width, 12)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := _flat(color, Color(0, 0, 0, 0), 4)
	pb.add_theme_stylebox_override("fill", fill)
	return pb

static func fmt_time(day: int, minute: float) -> String:
	return "%d日目 %02d:%02d" % [day, int(minute) / 60, int(minute) % 60]

static func fmt_clock(minute: float) -> String:
	return "%02d:%02d" % [int(minute) / 60, int(minute) % 60]

# Loads a PNG at runtime without relying on the editor import pipeline,
# so generated illustrations work even if the project was never opened
# in the Godot editor. Returns null if the file is missing.
static func load_texture_file(res_path: String) -> ImageTexture:
	if _texture_cache.has(res_path):
		return _texture_cache[res_path]
	var global := ProjectSettings.globalize_path(res_path)
	if not FileAccess.file_exists(global):
		return null
	var img := Image.load_from_file(global)
	if img == null:
		return null
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_texture_cache[res_path] = tex
	return tex

# Runtime audio loading (no import pipeline), mirroring load_texture_file.
static func load_audio_file(res_path: String) -> AudioStream:
	if _audio_cache.has(res_path):
		return _audio_cache[res_path]
	var global := ProjectSettings.globalize_path(res_path)
	if not FileAccess.file_exists(global):
		return null
	var stream: AudioStream = null
	if res_path.ends_with(".ogg"):
		stream = AudioStreamOggVorbis.load_from_file(global)
	elif res_path.ends_with(".wav"):
		stream = AudioStreamWAV.load_from_file(global)
	elif res_path.ends_with(".mp3"):
		var mp3 := AudioStreamMP3.new()
		mp3.data = FileAccess.get_file_as_bytes(global)
		stream = mp3
	if stream == null:
		return null
	_audio_cache[res_path] = stream
	return stream

static func load_model(res_path: String) -> Node3D:
	if not _model_cache.has(res_path):
		if res_path.get_extension().to_lower() == "vrm":
			_model_cache[res_path] = _load_vrm_prototype(res_path)
		else:
			var doc := GLTFDocument.new()
			var state := GLTFState.new()
			if doc.append_from_file(res_path, state) != OK:
				_model_cache[res_path] = null
			else:
				_model_cache[res_path] = doc.generate_scene(state)
	var proto = _model_cache[res_path]
	return null if proto == null else proto.duplicate()

# VRM (VRoid Studio etc.) is glTF plus extensions handled by the godot-vrm
# addon (MToon toon shading, spring bones). The extension is registered only
# around VRM loads so plain GLB loading stays untouched.
static func _load_vrm_prototype(res_path: String) -> Node3D:
	var ext_script = load("res://addons/vrm/vrm_extension.gd")
	if ext_script == null:
		push_error("godot-vrm addon missing; cannot load " + res_path)
		return null
	var ext: GLTFDocumentExtension = ext_script.new()
	var doc := GLTFDocument.new()
	doc.register_gltf_document_extension(ext, true)
	var state := GLTFState.new()
	# The addon's editor import plugin normally seeds these options; seed the
	# same defaults here so runtime loads don't log missing-key errors.
	state.set_additional_data(&"vrm/head_hiding_method", 0)
	state.set_additional_data(&"vrm/first_person_layers", 2)
	state.set_additional_data(&"vrm/third_person_layers", 4)
	var scene: Node3D = null
	# 8 = generate tangent arrays; required for blend-shape meshes (Godot 4.2+).
	if doc.append_from_file(res_path, state, 8) == OK:
		scene = doc.generate_scene(state)
	doc.unregister_gltf_document_extension(ext)
	return scene

# Cached prototype scenes are plain orphan nodes; free them on shutdown so the
# engine doesn't report leaked instances at exit.
static func clear_model_cache() -> void:
	for key in _model_cache:
		var proto = _model_cache[key]
		if proto != null and is_instance_valid(proto):
			proto.free()
	_model_cache.clear()

static func model_aabb(root: Node3D) -> AABB:
	var out := {"has": false, "aabb": AABB()}
	_collect_model_aabb(root, Transform3D.IDENTITY, out)
	return out["aabb"]

static func fit_model_to_footprint(model: Node3D, footprint: Vector2, margin := 0.86, max_height := 0.0) -> bool:
	var aabb := model_aabb(model)
	if aabb.size.x <= 0.001 or aabb.size.y <= 0.001 or aabb.size.z <= 0.001:
		return false
	var s := minf(footprint.x * margin / aabb.size.x, footprint.y * margin / aabb.size.z)
	if max_height > 0.0:
		s = minf(s, max_height / aabb.size.y)
	if s <= 0.0:
		return false
	var bottom_center := Vector3(aabb.position.x + aabb.size.x * 0.5, aabb.position.y, aabb.position.z + aabb.size.z * 0.5)
	model.scale = Vector3.ONE * s
	model.position -= bottom_center * s
	return true

static func fit_model_to_height(model: Node3D, height: float) -> bool:
	var aabb := model_aabb(model)
	if aabb.size.y <= 0.001:
		return false
	var s := height / aabb.size.y
	var bottom_center := Vector3(aabb.position.x + aabb.size.x * 0.5, aabb.position.y, aabb.position.z + aabb.size.z * 0.5)
	model.scale = Vector3.ONE * s
	model.position -= bottom_center * s
	return true

# Skinned FBX→GLB conversions can carry broken static mesh AABBs (near zero
# for some polyperfect rigs), so rigged models scale by the skeleton's rest
# pose height instead — bones are what the skinning actually follows.
static func fit_model_to_height_by_bones(model: Node3D, height: float) -> bool:
	var lo := 1e12
	var hi := -1e12
	var found := false
	for sk in model.find_children("*", "Skeleton3D", true, false):
		var s := sk as Skeleton3D
		var xf := _transform_to_ancestor(s, model)
		for i in range(s.get_bone_count()):
			var y := (xf * s.get_bone_global_rest(i)).origin.y
			lo = minf(lo, y)
			hi = maxf(hi, y)
			found = true
	if not found or hi - lo <= 0.0001:
		return false
	var s_factor := height / (hi - lo)
	model.scale = Vector3.ONE * s_factor
	model.position.y -= lo * s_factor
	return true

# Graft animation takes from a donor GLB whose tracks target plain Node3D
# bone hierarchies (ufbx drops the mesh for some polyperfect rigs) onto a rig
# scene whose bones live inside a Skeleton3D: rewrite each track path from
# ".../Root_M" to "<skeleton>:Root_M" and attach a fresh AnimationPlayer.
static func graft_donor_anims(model: Node3D, donor_res_path: String) -> AnimationPlayer:
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return null
	var skeleton: Skeleton3D = skels[0]
	var donor := load_model(donor_res_path)
	if donor == null:
		return null
	var aps := donor.find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		donor.free()
		return null
	var src: AnimationPlayer = aps[0]
	var sk_path := str(model.get_path_to(skeleton))
	var lib := AnimationLibrary.new()
	for anim_name in src.get_animation_list():
		var anim: Animation = src.get_animation(anim_name).duplicate()
		for i in range(anim.get_track_count()):
			var tp := str(anim.track_get_path(i))
			if ":" in tp:
				continue
			var bone := tp.get_slice("/", tp.get_slice_count("/") - 1)
			if skeleton.find_bone(bone) >= 0:
				anim.track_set_path(i, NodePath(sk_path + ":" + bone))
		anim.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(anim_name, anim)
	donor.free()
	var ap := AnimationPlayer.new()
	ap.name = "GraftedAnims"
	model.add_child(ap)
	ap.add_animation_library("", lib)
	return ap

static func _transform_to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != ancestor:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf

static func _collect_model_aabb(node: Node3D, parent_xform: Transform3D, out: Dictionary) -> void:
	var xform := parent_xform * node.transform
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null:
			var mesh_aabb := _transform_aabb(xform, mesh_node.get_aabb())
			out["aabb"] = (out["aabb"] as AABB).merge(mesh_aabb) if bool(out["has"]) else mesh_aabb
			out["has"] = true
	for child in node.get_children():
		if child is Node3D:
			_collect_model_aabb(child as Node3D, xform, out)

static func _transform_aabb(xform: Transform3D, aabb: AABB) -> AABB:
	var p := aabb.position
	var s := aabb.size
	var points := [
		p,
		p + Vector3(s.x, 0.0, 0.0),
		p + Vector3(0.0, s.y, 0.0),
		p + Vector3(0.0, 0.0, s.z),
		p + Vector3(s.x, s.y, 0.0),
		p + Vector3(s.x, 0.0, s.z),
		p + Vector3(0.0, s.y, s.z),
		p + s,
	]
	var out := AABB(xform * points[0], Vector3.ZERO)
	for i in range(1, points.size()):
		out = out.expand(xform * points[i])
	return out

static func fmt_cost(cost: Dictionary) -> String:
	var parts: Array = []
	for k in cost:
		parts.append("%s%d" % [RES_ICONS.get(k, k), int(cost[k])])
	return " ".join(parts)
