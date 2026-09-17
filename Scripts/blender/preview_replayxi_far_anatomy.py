"""Blender-MCP preview of original124 parts; never changes canonical objects."""
import bpy
import math
from mathutils import Matrix, Vector

scene = bpy.data.scenes.new("ReplayXI124 two-team anatomy preview")
bpy.context.window.scene = scene
scene.render.engine = "CYCLES"
scene.cycles.samples = 24
scene.render.resolution_x = 900
scene.render.resolution_y = 700
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = "AgX"
scene.world = bpy.data.worlds.new("ReplayXI124 Studio")
scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs[0].default_value = (.055,.065,.075,1)
scene.world.node_tree.nodes["Background"].inputs[1].default_value = .5

def solid(name, color):
    material = bpy.data.materials.new("ReplayXI124Preview_" + name)
    material.diffuse_color = (*color,1)
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color,1)
    shader.inputs["Roughness"].default_value = .75
    return material

def bands(name, kind, shirt, shorts, skin):
    material = solid(name, shirt)
    nodes, links = material.node_tree.nodes, material.node_tree.links
    texture = nodes.new("ShaderNodeTexCoord")
    separate = nodes.new("ShaderNodeSeparateXYZ")
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    links.new(texture.outputs["UV"], separate.inputs[0])
    links.new(separate.outputs["Y"], ramp.inputs[0])
    links.new(ramp.outputs[0], nodes.get("Principled BSDF").inputs["Base Color"])
    if kind == "Leg":
        stops = [(0,(.014,.016,.019)),(.10,shirt),(.50,skin),(.833,shorts)]
    else:
        stops = [(0,skin),(.717,shirt)]
    while len(ramp.color_ramp.elements)>1:
        ramp.color_ramp.elements.remove(ramp.color_ramp.elements[-1])
    for index,(position,color) in enumerate(stops):
        element = ramp.color_ramp.elements[0] if index == 0 else ramp.color_ramp.elements.new(position)
        element.position=position
        element.color=(*color,1)
    return material

head_material = solid("Face", (.74,.49,.32))
texture = head_material.node_tree.nodes.new("ShaderNodeTexImage")
texture.image = bpy.data.images.load('/Users/zx/Documents/ChatGPT/SPATIAL PLATFORM/ReplayXI/Resources/Players/ReplayXIAthleteSkin1.png',check_existing=True)
head_material.node_tree.links.new(texture.outputs["Color"],head_material.node_tree.nodes.get("Principled BSDF").inputs["Base Color"])

def copied(name, label, material):
    source=bpy.data.objects[name]
    obj=source.copy()
    obj.data=source.data.copy()
    obj.name="ReplayXI124Preview_"+label
    obj.parent=None
    obj.matrix_world=Matrix.Identity(4)
    obj.data.materials.clear()
    obj.data.materials.append(material)
    scene.collection.objects.link(obj)
    return obj

for team,xbase,shirt,shorts in [("White",-.60,(.91,.95,.98),(.025,.07,.16)),
                              ("Red",.60,(.72,.045,.075),(.91,.95,.98))]:
    torso=copied("ReplayXI124_Torso",team+"_Torso",solid(team+"Shirt",shirt))
    torso.location=(xbase,1.04,0)
    pelvis=copied("ReplayXI124_Shorts",team+"_Shorts",solid(team+"Shorts",shorts))
    pelvis.location=(xbase,.90,0)
    head=copied("Face",team+"_Face",head_material)
    head.location=(xbase,1.75,0)
    head.scale=(1.07,1,1)
    for kind,pivot_y,pivot_x,angles in [("Leg",.83,.137,[(.62,1.10,-.30),(-.55,.25,.15)]),
                                      ("Arm",1.51,.218,[(-.46,-1.12,.05),(.46,-.82,-.05)])]:
        material=bands(team+kind,kind,shirt,shorts,(.74,.49,.32))
        for index,side in enumerate([-1,1]):
            source_rig=bpy.data.objects["ReplayXI124_"+kind+"_Rig"]
            rig=source_rig.copy()
            rig.data=source_rig.data.copy()
            rig.name="ReplayXI124Preview_"+team+kind+str(side)
            scene.collection.objects.link(rig)
            rig.location=(xbase+side*pivot_x,pivot_y,0)
            rig.rotation_euler=(angles[index][0],0,side*.025 if kind == "Arm" else 0)
            rig.pose.bones["Bend"].rotation_mode="XYZ"
            rig.pose.bones["Bend"].rotation_euler=(angles[index][1],0,0)
            rig.pose.bones["Tip"].rotation_mode="XYZ"
            rig.pose.bones["Tip"].rotation_euler=(angles[index][2],0,0)
            limb=copied("ReplayXI124_"+kind,team+kind+str(side),material)
            limb.parent=rig
            limb.matrix_parent_inverse=Matrix.Identity(4)
            limb.location=(0,0,0)
            for modifier in limb.modifiers:
                if modifier.type == "ARMATURE": modifier.object=rig

floor_mesh=bpy.data.meshes.new("ReplayXI124PreviewFloor")
floor_mesh.from_pydata([(-4,-.02,-4),(4,-.02,-4),(4,-.02,4),(-4,-.02,4)],[],[(0,3,2,1)])
floor=bpy.data.objects.new("ReplayXI124PreviewFloor",floor_mesh)
scene.collection.objects.link(floor)
floor.data.materials.append(solid("Turf",(.018,.095,.055)))
for name,location,power,size in [("Key",(2,4,3),550,4),("Fill",(-3,2,2),330,3)]:
    data=bpy.data.lights.new("ReplayXI124Preview"+name,"AREA")
    data.energy=power
    data.shape="DISK"
    data.size=size
    light=bpy.data.objects.new(data.name,data)
    scene.collection.objects.link(light)
    light.location=location
    light.rotation_euler=(Vector((0,1,0))-light.location).to_track_quat('-Z','Y').to_euler()
camera_data=bpy.data.cameras.new("ReplayXI124PreviewCamera")
camera=bpy.data.objects.new(camera_data.name,camera_data)
scene.collection.objects.link(camera)
camera.location=(2.7,1.8,5.0)
forward=(Vector((0,.95,0))-camera.location).normalized()
right=forward.cross(Vector((0,1,0))).normalized()
up=right.cross(forward).normalized()
camera.rotation_euler=Matrix((right,up,-forward)).transposed().to_euler()
camera_data.type="ORTHO"
camera_data.ortho_scale=2.95
scene.camera=camera
scene.render.filepath='/Users/zx/Documents/ChatGPT/SPATIAL PLATFORM/.codex-derived/ReplayXI-Players124-Anatomy-01/two-team-posed-preview.png'
bpy.ops.render.render(write_still=True)
print("Original124 Blender preview rendered; illustrative pose, not native runtime validation")
