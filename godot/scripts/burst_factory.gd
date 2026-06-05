extends Object
## Spectral split burst 💥 — the "wow" moment when an agent fans out a clone.
## Programmatic (flash + shockwave ring + light pillar + soul sparks) in the
## Binbun ExplosionFX spirit: additive, punchy, gone in a second.

static func spawn(host: Node3D, pos: Vector3) -> void:
	var root := Node3D.new()
	host.add_child(root)
	root.position = pos

	# Blinding flash.
	var flash := OmniLight3D.new()
	flash.light_color = Color(0.62, 0.85, 1.0)
	flash.light_energy = 0.0
	flash.omni_range = 6.0
	root.add_child(flash)
	flash.position = Vector3(0, 0.8, 0)
	var ftw := host.create_tween()
	ftw.tween_property(flash, "light_energy", 7.0, 0.06)
	ftw.tween_property(flash, "light_energy", 0.0, 0.45)

	# Ground shockwave ring, racing outward.
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.42
	tm.outer_radius = 0.5
	ring.mesh = tm
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rmat.albedo_color = Color(0.55, 0.85, 1.0, 0.9)
	ring.material_override = rmat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	ring.position = Vector3(0, 0.06, 0)
	ring.scale = Vector3(0.2, 0.5, 0.2)
	var rtw := host.create_tween()
	rtw.set_parallel(true)
	rtw.tween_property(ring, "scale", Vector3(3.4, 0.5, 3.4), 0.55) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	rtw.tween_property(rmat, "albedo_color:a", 0.0, 0.55)

	# Rising light pillar — the soul tearing out.
	var pillar := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.02
	cm.bottom_radius = 0.16
	cm.height = 2.6
	pillar.mesh = cm
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pmat.albedo_color = Color(0.7, 0.9, 1.0, 0.8)
	pillar.material_override = pmat
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(pillar)
	pillar.position = Vector3(0, 1.3, 0)
	pillar.scale = Vector3(1.0, 0.1, 1.0)
	var ptw := host.create_tween()
	ptw.set_parallel(true)
	ptw.tween_property(pillar, "scale:y", 1.0, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ptw.tween_property(pmat, "albedo_color:a", 0.0, 0.7)

	# Soul sparks, one-shot radial burst.
	var sparks := GPUParticles3D.new()
	sparks.amount = 26
	sparks.lifetime = 0.8
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	var sm := ParticleProcessMaterial.new()
	sm.direction = Vector3(0, 1, 0)
	sm.spread = 70.0
	sm.initial_velocity_min = 2.2
	sm.initial_velocity_max = 4.4
	sm.gravity = Vector3(0, -3.2, 0)
	sm.scale_min = 0.5
	sm.scale_max = 1.2
	sm.color = Color(0.66, 0.9, 1.0)
	sparks.process_material = sm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.085, 0.085)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.vertex_color_use_as_albedo = true
	quad.material = qm
	sparks.draw_pass_1 = quad
	root.add_child(sparks)
	sparks.position = Vector3(0, 0.6, 0)
	sparks.emitting = true

	host.get_tree().create_timer(1.5).timeout.connect(root.queue_free)
