import bpy
import mathutils
import math
import os

bpy.ops.wm.read_factory_settings(use_empty=True)

TEXTURES_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "textures"))

def map_box_uv(obj, u0, v0, w, d, h, tex_w=64, tex_h=64):
    uv_layer = obj.data.uv_layers.active
    if not uv_layer:
        uv_layer = obj.data.uv_layers.new(name="UVMap")

    face_rects = {
        'top':    (u0 + d,       v0,         w, d),
        'bottom': (u0 + d + w,   v0,         w, d),
        'right':  (u0,           v0 + d,     d, h),
        'front':  (u0 + d,       v0 + d,     w, h),
        'left':   (u0 + d + w,   v0 + d,     d, h),
        'back':   (u0 + 2*d + w, v0 + d,     w, h),
    }

    verts = [v.co for v in obj.data.vertices]
    min_x = min(v.co.x for v in obj.data.vertices); max_x = max(v.co.x for v in obj.data.vertices); sx = max(1e-5, max_x - min_x)
    min_y = min(v.co.y for v in obj.data.vertices); max_y = max(v.co.y for v in obj.data.vertices); sy = max(1e-5, max_y - min_y)
    min_z = min(v.co.z for v in obj.data.vertices); max_z = max(v.co.z for v in obj.data.vertices); sz = max(1e-5, max_z - min_z)

    for poly in obj.data.polygons:
        n = poly.normal
        if n.z > 0.5:
            face = 'top'
            u_fn = lambda c: (max_x - c.x) / sx
            v_fn = lambda c: (max_y - c.y) / sy
        elif n.z < -0.5:
            face = 'bottom'
            u_fn = lambda c: (max_x - c.x) / sx
            v_fn = lambda c: (c.y - min_y) / sy
        elif n.y > 0.5:
            face = 'front'
            u_fn = lambda c: (max_x - c.x) / sx
            v_fn = lambda c: (c.z - min_z) / sz
        elif n.y < -0.5:
            face = 'back'
            u_fn = lambda c: (c.x - min_x) / sx
            v_fn = lambda c: (c.z - min_z) / sz
        elif n.x > 0.5:
            face = 'right'
            u_fn = lambda c: (c.y - min_y) / sy
            v_fn = lambda c: (c.z - min_z) / sz
        elif n.x < -0.5:
            face = 'left'
            u_fn = lambda c: (max_y - c.y) / sy
            v_fn = lambda c: (c.z - min_z) / sz
        else:
            continue

        rx, ry, rw, rh = face_rects[face]
        for loop_idx in poly.loop_indices:
            v_idx = obj.data.loops[loop_idx].vertex_index
            c = obj.data.vertices[v_idx].co
            u_norm = max(0.0, min(1.0, u_fn(c)))
            v_norm = max(0.0, min(1.0, v_fn(c)))
            px = rx + u_norm * rw
            py = ry + (1.0 - v_norm) * rh
            u_blender = px / tex_w
            v_blender = 1.0 - (py / tex_h)
            uv_layer.data[loop_idx].uv = (u_blender, v_blender)

def create_box(name, scale, location, bone_name, uv_params, material, parts):
    bpy.ops.mesh.primitive_cube_add(size=1)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    obj.location = location
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    map_box_uv(obj, *uv_params)
    obj.data.materials.append(material)
    vg = obj.vertex_groups.new(name=bone_name)
    vg.add(range(len(obj.data.vertices)), 1.0, 'REPLACE')
    parts.append(obj)
    return obj

def build_model():
    # 1. CREATE MATERIALS
    def make_material(name, texture_name):
        mat = bpy.data.materials.new(name=name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        tex_node = mat.node_tree.nodes.new('ShaderNodeTexImage')
        tex_path = os.path.join(TEXTURES_DIR, texture_name)
        if os.path.exists(tex_path):
            tex_node.image = bpy.data.images.load(tex_path)
            mat.node_tree.links.new(tex_node.outputs['Color'], bsdf.inputs['Base Color'])
        return mat

    mat_body = make_material("BodyMat", "pale_watcher_body.png")
    mat_suit = make_material("SuitMat", "pale_watcher_suit.png")
    mat_tie = make_material("TieMat", "pale_watcher_tie.png")

    parts = []

    # 2. BODY PARTS
    # Head: pale blank face
    create_box("Head", (0.35, 0.35, 0.4), (0, 0, 2.95), "Head", (0, 0, 8, 8, 8), mat_body, parts)

    # Torso: Victorian suit jacket
    create_box("Torso", (0.4, 0.25, 1.2), (0, 0, 2.1), "Torso", (16, 16, 8, 5, 24), mat_suit, parts)

    # 3D Modeled Necktie (attached to front of chest, parented to Torso bone)
    create_box("Tie_Knot", (0.08, 0.02, 0.08), (0, 0.13, 2.62), "Torso", (56, 16, 2, 1, 2), mat_tie, parts)
    create_box("Tie_Blade", (0.06, 0.015, 0.52), (0, 0.128, 2.30), "Torso", (56, 19, 2, 1, 11), mat_tie, parts)

    # Arms (Suit sleeves)
    create_box("Arm_L_Upper", (0.1, 0.1, 0.9), (-0.3, 0, 2.25), "Arm_L_Upper", (32, 0, 2, 2, 12), mat_suit, parts)
    create_box("Arm_L_Lower", (0.1, 0.1, 0.9), (-0.3, 0, 1.35), "Arm_L_Lower", (40, 0, 2, 2, 12), mat_suit, parts)
    create_box("Arm_R_Upper", (0.1, 0.1, 0.9), (0.3, 0, 2.25), "Arm_R_Upper", (48, 0, 2, 2, 12), mat_suit, parts)
    create_box("Arm_R_Lower", (0.1, 0.1, 0.9), (0.3, 0, 1.35), "Arm_R_Lower", (56, 0, 2, 2, 12), mat_suit, parts)

    # Legs (Suit trousers)
    create_box("Leg_L", (0.15, 0.15, 1.5), (-0.125, 0, 0.75), "Leg_L", (0, 16, 3, 3, 24), mat_suit, parts)
    create_box("Leg_R", (0.15, 0.15, 1.5), (0.125, 0, 0.75), "Leg_R", (44, 16, 3, 3, 24), mat_suit, parts)

    # Bony Claws / Fingers (Body skin)
    for side, sign in [("L", -1), ("R", 1)]:
        hand_u0 = 0 if side == "L" else 0
        hand_v0 = 44 if side == "L" else 52
        for i, (dx, dy) in enumerate([(0, 0.03), (0.03, -0.03), (-0.03, -0.03)]):
            ox = 0.3 * sign + dx * sign
            u0 = hand_u0 + i * 4
            create_box(f"Finger_{side}_{i+1}", (0.02, 0.02, 0.4), (ox, dy, 0.7),
                       f"Finger_{side}_{i+1}", (u0, hand_v0, 1, 1, 6), mat_body, parts)

    # ARMATURE
    bpy.ops.object.armature_add(enter_editmode=True)
    armature = bpy.context.active_object
    armature.name = "PaleWatcher_Rig"
    ebones = armature.data.edit_bones
    if "Bone" in ebones: ebones.remove(ebones["Bone"])

    def add_bone(name, head, tail, parent=None):
        b = ebones.new(name)
        b.head = head; b.tail = tail
        if parent: b.parent = ebones[parent]
        return b

    add_bone("Root", (0,0,0), (0,0,1.5))
    add_bone("Torso", (0,0,1.5), (0,0,2.7), "Root")
    add_bone("Head", (0,0,2.7), (0,0,3.1), "Torso")
    add_bone("Leg_L", (-0.125,0,1.5), (-0.125,0,0), "Root")
    add_bone("Leg_R", (0.125,0,1.5), (0.125,0,0), "Root")
    add_bone("Arm_L_Upper", (-0.3,0,2.7), (-0.3,0,1.8), "Torso")
    add_bone("Arm_L_Lower", (-0.3,0,1.8), (-0.3,0,0.9), "Arm_L_Upper")
    add_bone("Arm_R_Upper", (0.3,0,2.7), (0.3,0,1.8), "Torso")
    add_bone("Arm_R_Lower", (0.3,0,1.8), (0.3,0,0.9), "Arm_R_Upper")

    for side, sign in [("L", -1), ("R", 1)]:
        for i, (dx, dy) in enumerate([(0, 0.03), (0.03, -0.03), (-0.03, -0.03)]):
            ox = 0.3 * sign + dx * sign
            add_bone(f"Finger_{side}_{i+1}", (ox, dy, 0.9), (ox, dy, 0.5), f"Arm_{side}_Lower")

    # TENDRILS (Built explicitly backward -Y and outward)
    bpy.ops.object.mode_set(mode='OBJECT')
    def add_tendril_segment(name, head, tail, parent_bone, t_idx):
        bpy.context.view_layer.objects.active = armature
        bpy.ops.object.mode_set(mode='EDIT')
        ebones = armature.data.edit_bones
        b = ebones.new(name)
        b.head = head; b.tail = tail
        if parent_bone: b.parent = ebones[parent_bone]

        bpy.ops.object.mode_set(mode='OBJECT')
        vec = mathutils.Vector(tail) - mathutils.Vector(head)
        l = vec.length
        bpy.ops.mesh.primitive_cube_add(size=1)
        obj = bpy.context.active_object
        obj.name = name; obj.scale = (0.05, l, 0.05)
        obj.rotation_euler = mathutils.Vector((0,1,0)).rotation_difference(vec).to_euler()
        obj.location = mathutils.Vector(head) + vec/2
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        # Tendrils UV map in [16..47, 46..63]
        u0 = 16 + (t_idx % 4) * 8
        v0 = 46 + (t_idx // 4) * 9
        map_box_uv(obj, u0, v0, 2, 2, 8)
        obj.data.materials.append(mat_body)
        vg = obj.vertex_groups.new(name=name)
        vg.add(range(len(obj.data.vertices)), 1.0, 'REPLACE')
        parts.append(obj)

    tendril_defs = [
        (1, (-0.15, -0.15, 2.4), (-0.65, -0.65, 2.7), (-1.0, -1.0, 2.3)), # TL
        (2, (0.15, -0.15, 2.4), (0.65, -0.65, 2.7), (1.0, -1.0, 2.3)),   # TR
        (3, (-0.15, -0.15, 1.9), (-0.65, -0.65, 1.6), (-1.0, -1.0, 1.2)), # BL
        (4, (0.15, -0.15, 1.9), (0.65, -0.65, 1.6), (1.0, -1.0, 1.2))    # BR
    ]
    for idx, head, mid, tail in tendril_defs:
        add_tendril_segment(f"Tendril_{idx}_Base", head, mid, "Torso", (idx - 1) * 2)
        add_tendril_segment(f"Tendril_{idx}_Tip", mid, tail, f"Tendril_{idx}_Base", (idx - 1) * 2 + 1)

    # MESH JOIN (Preserves all 3 material slots: BodyMat, SuitMat, TieMat)
    bpy.ops.object.select_all(action='DESELECT')
    for p in parts: p.select_set(True)

    # Find the first Body, Suit, and Tie objects to establish order: BodyMat (0), SuitMat (1), TieMat (2)
    # Ensure active object has all 3 materials pre-allocated in exact order
    active_obj = parts[0] # Head (has BodyMat)
    if mat_suit.name not in active_obj.data.materials:
        active_obj.data.materials.append(mat_suit)
    if mat_tie.name not in active_obj.data.materials:
        active_obj.data.materials.append(mat_tie)

    bpy.context.view_layer.objects.active = active_obj
    bpy.ops.object.join()
    mesh_obj = bpy.context.active_object
    mesh_obj.name = "PaleWatcher_Mesh"

    print("Final Mesh Material Slots:", [m.name for m in mesh_obj.data.materials])

    # Parent mesh to armature
    bpy.ops.object.select_all(action='DESELECT')
    mesh_obj.select_set(True)
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.parent_set(type='ARMATURE')

    # ANIMATIONS
    bpy.ops.object.mode_set(mode='POSE')
    pbones = armature.pose.bones

    def ensure_action(name):
        return bpy.data.actions.get(name) or bpy.data.actions.new(name)

    act_stand = ensure_action("stand")
    act_walk = ensure_action("stalk_glide")
    act_attack = ensure_action("attack")
    act_stun = ensure_action("stun")
    act_death = ensure_action("death_implode")

    def set_kf(action, bone, rot, f):
        if not armature.animation_data: armature.animation_data_create()
        armature.animation_data.action = action
        pbones[bone].rotation_mode = 'XYZ'
        pbones[bone].rotation_euler = rot
        pbones[bone].keyframe_insert(data_path="rotation_euler", frame=f)

    # 1. Stand: Creepy twitching
    for f, tilt, finger in [(1, 0, 0), (20, -0.05, 0.1), (40, 0, 0)]:
        set_kf(act_stand, "Torso", (tilt, 0, 0), f)
        set_kf(act_stand, "Head", (-tilt, 0, 0), f)
        set_kf(act_stand, "Arm_L_Upper", (0, 0, 0.05), f)
        set_kf(act_stand, "Arm_L_Lower", (0.1, 0, 0), f)
        set_kf(act_stand, "Arm_R_Upper", (0, 0, -0.05), f)
        set_kf(act_stand, "Arm_R_Lower", (0.1, 0, 0), f)
        for side in ["L", "R"]:
            for i in range(3):
                set_kf(act_stand, f"Finger_{side}_{i+1}", (finger - i*0.02, 0, 0), f)
        for i in range(4):
            sign = 1 if i % 2 == 0 else -1
            set_kf(act_stand, f"Tendril_{i+1}_Base", (0.1 * tilt, 0, sign * tilt), f)

    # 2. Stalk Glide: Walking gait with eerie long leg strides and writhing tendrils
    for f, tilt, sway, leg_stride in [
        (1, -0.2, 0.1, 0.35),
        (20, -0.25, -0.1, -0.35),
        (40, -0.2, 0.1, 0.35)
    ]:
        set_kf(act_walk, "Torso", (tilt, 0, 0), f)
        set_kf(act_walk, "Head", (-tilt/2, 0, 0), f)
        set_kf(act_walk, "Leg_L", (leg_stride, 0, 0), f)
        set_kf(act_walk, "Leg_R", (-leg_stride, 0, 0), f)
        set_kf(act_walk, "Arm_L_Upper", (-0.1 + sway, 0, 0), f)
        set_kf(act_walk, "Arm_L_Lower", (0.2, 0, 0), f)
        set_kf(act_walk, "Arm_R_Upper", (-0.1 - sway, 0, 0), f)
        set_kf(act_walk, "Arm_R_Lower", (0.2, 0, 0), f)
        for side in ["L", "R"]:
            for i in range(3):
                set_kf(act_walk, f"Finger_{side}_{i+1}", (0.1, 0, 0), f)
        for i in range(4):
            sign = 1 if i % 2 == 0 else -1
            set_kf(act_walk, f"Tendril_{i+1}_Base", (0.25, 0, sign * sway), f)
            set_kf(act_walk, f"Tendril_{i+1}_Tip", (0.35, 0, -sign * sway), f)

    # 3. Attack: Aggressive reaching forward, scorpion-tail stings, scratching fingers
    for f, arm_up, elbow_bend in [(1, 0, 0), (15, 1.2, 0.5), (30, 0, 0)]:
        set_kf(act_attack, "Torso", (-0.2, 0, 0), f)
        set_kf(act_attack, "Head", (0.2, 0, 0), f)
        set_kf(act_attack, "Arm_L_Upper", (arm_up, 0, 0), f)
        set_kf(act_attack, "Arm_L_Lower", (elbow_bend, 0, 0), f)
        set_kf(act_attack, "Arm_R_Upper", (arm_up, 0, 0), f)
        set_kf(act_attack, "Arm_R_Lower", (elbow_bend, 0, 0), f)
        for side in ["L", "R"]:
            for i in range(3):
                flex = -0.6 if f == 15 else 0.1
                spread = (i - 1) * 0.4 if f == 15 else 0
                set_kf(act_attack, f"Finger_{side}_{i+1}", (flex, 0, spread), f)
        for i in range(4):
            if f == 15:
                if i < 2:
                    base_x, tip_x = -0.4, 1.8
                else:
                    base_x, tip_x = 0.5, 1.0
            else:
                base_x, tip_x = 0, 0
            set_kf(act_attack, f"Tendril_{i+1}_Base", (base_x, 0, 0), f)
            set_kf(act_attack, f"Tendril_{i+1}_Tip", (tip_x, 0, 0), f)

    # 4. Stun / Stagger: Blinding light flash impact - reeling backward, shielding face
    for f, torso_tilt, head_recoil, arm_cover, arm_cross, shudder in [
        (1, 0, 0, 0, 0, 0),
        (10, 0.45, 0.35, 1.45, 0.45, 0.08),
        (25, 0.38, 0.28, 1.35, 0.40, -0.08),
        (40, 0.45, 0.35, 1.45, 0.45, 0.08),
        (55, 0.30, 0.20, 1.15, 0.35, 0.0),
    ]:
        set_kf(act_stun, "Torso", (torso_tilt, 0, 0), f)
        set_kf(act_stun, "Head", (head_recoil, 0, 0.35), f)
        set_kf(act_stun, "Arm_L_Upper", (arm_cover, 0, -arm_cross), f)
        set_kf(act_stun, "Arm_L_Lower", (1.2, 0, 0), f)
        set_kf(act_stun, "Arm_R_Upper", (arm_cover, 0, arm_cross), f)
        set_kf(act_stun, "Arm_R_Lower", (1.2, 0, 0), f)
        for side in ["L", "R"]:
            for i in range(3):
                set_kf(act_stun, f"Finger_{side}_{i+1}", (0.4 + shudder, 0, 0.15), f)
        for i in range(4):
            sign = 1 if i % 2 == 0 else -1
            set_kf(act_stun, f"Tendril_{i+1}_Base", (sign * 0.6 + shudder, 0, sign * 0.5), f)
            set_kf(act_stun, f"Tendril_{i+1}_Tip", (-sign * 0.7, 0, -sign * 0.4), f)
        set_kf(act_stun, "Leg_L", (-0.35 + shudder, 0, 0), f)
        set_kf(act_stun, "Leg_R", (0.25 - shudder, 0, 0), f)

    # 5. Death Implode
    for f, tilt, arm_in, elbow_in, leg_split in [(1, 0, 0, 0, 0), (20, -0.5, -0.8, 1.0, 0.5), (40, -1.2, -1.5, 1.5, 1.0)]:
        set_kf(act_death, "Torso", (tilt, 0, 0), f)
        set_kf(act_death, "Arm_L_Upper", (0, 0, -arm_in), f)
        set_kf(act_death, "Arm_L_Lower", (elbow_in, 0, 0), f)
        set_kf(act_death, "Arm_R_Upper", (0, 0, arm_in), f)
        set_kf(act_death, "Arm_R_Lower", (elbow_in, 0, 0), f)
        for side in ["L", "R"]:
            for i in range(3):
                set_kf(act_death, f"Finger_{side}_{i+1}", (elbow_in, 0, 0), f)
        set_kf(act_death, "Leg_L", (0, 0, leg_split), f)
        set_kf(act_death, "Leg_R", (0, 0, -leg_split), f)
        for i in range(4):
            set_kf(act_death, f"Tendril_{i+1}_Base", (tilt, 0, 0), f)

    act_idle = act_stand.copy(); act_idle.name = "idle"
    act_walk_std = act_walk.copy(); act_walk_std.name = "walk"
    act_punch = act_attack.copy(); act_punch.name = "punch"
    act_stagger = act_stun.copy(); act_stagger.name = "stagger"
    act_death_std = act_death.copy(); act_death_std.name = "death"

    actions_to_export = [
        ("idle", act_idle),
        ("stand", act_stand),
        ("walk", act_walk_std),
        ("stalk_glide", act_walk),
        ("attack", act_attack),
        ("punch", act_punch),
        ("stun", act_stun),
        ("stagger", act_stagger),
        ("death", act_death_std),
        ("death_implode", act_death),
    ]
    for track_name, act in actions_to_export:
        track = armature.animation_data.nla_tracks.new()
        track.name = track_name
        track.strips.new(track_name, int(act.frame_start), act)

    out_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "models"))
    os.makedirs(out_dir, exist_ok=True)

    if bpy.context.object and bpy.context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='DESELECT')
    mesh_obj.select_set(True)
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature

    bpy.ops.export_scene.gltf(
        filepath=os.path.join(out_dir, "pale_watcher_mob.glb"),
        export_format='GLB',
        use_selection=True,
        export_animations=True,
        export_materials='EXPORT'
    )
    blend_path = os.path.join(os.path.dirname(__file__), "..", "blend", "pale_watcher_mob.blend")
    os.makedirs(os.path.dirname(blend_path), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    print("Model and animations exported successfully!")

build_model()
