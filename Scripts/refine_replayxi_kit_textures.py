#!/usr/bin/env python3
"""Original Replay XI kit detail on the admitted MIT body's unchanged UVs.

Does not copy the paid visual-reference package. Existing face/skin texels,
weights, shape, normal maps and texture dimensions are retained. Uses a
canonical body-UV export from the exact admitted Rocketbox USDZ.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SOURCE_HASH = "7cfb694888f111928643e8aca7041d21925f5d55f3f5adbd353a972ca255e772"

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def export_geometry(destination):
    # Run this one mode with Blender's Python, which provides OpenUSD. Texture
    # authoring below uses the existing Pillow/numpy workspace runtime.
    from pxr import Usd, UsdGeom
    source=ROOT/"ReplayXI/Resources/Players/ReplayXIRocketboxAthlete.usdz"
    if digest(source)!=SOURCE_HASH or destination.exists():
        raise ValueError("Source changed or geometry destination already exists")
    stage=Usd.Stage.Open(str(source))
    for prim in stage.Traverse():
        if not prim.IsA(UsdGeom.Mesh): continue
        mesh=UsdGeom.Mesh(prim)
        points=mesh.GetPointsAttr().Get()
        if len(points)!=3288: continue
        uv=UsdGeom.PrimvarsAPI(mesh).GetPrimvar("st").ComputeFlattened()
        payload={"positions":[list(p) for p in points],"uvs":[list(p) for p in uv],
                 "indices":list(mesh.GetFaceVertexIndicesAttr().Get()),
                 "normals":[list(p) for p in mesh.GetNormalsAttr().Get()]}
        destination.parent.mkdir(parents=True,exist_ok=True)
        destination.write_text(json.dumps(payload))
        return
    raise ValueError("Admitted Body mesh missing")

def raster(document, size=512):
    positions = np.asarray(document["positions"], dtype=np.float64)
    uv = np.asarray(document["uvs"], dtype=np.float64)
    triangles = np.asarray(document["indices"], dtype=int).reshape(-1,3)
    if positions.shape != (3288,3) or uv.shape != (3288,2) or triangles.shape != (5018,3):
        raise ValueError("Only the admitted unchanged near-body UV contract is supported")
    xy = uv * (size-1)
    xy[:,1] = size-1-xy[:,1]
    field = np.zeros((size,size,3),dtype=np.float64)
    coverage = np.zeros((size,size),dtype=bool)
    for triangle in triangles:
        a,b,c = xy[triangle]
        low = np.maximum(np.floor(np.min([a,b,c],axis=0)).astype(int),0)
        high = np.minimum(np.ceil(np.max([a,b,c],axis=0)).astype(int),size-1)
        if np.any(high<low): continue
        determinant = (b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
        if abs(determinant)<1e-9: continue
        yy,xx=np.mgrid[low[1]:high[1]+1,low[0]:high[0]+1]
        w0=((b[1]-c[1])*(xx-c[0])+(c[0]-b[0])*(yy-c[1]))/determinant
        w1=((c[1]-a[1])*(xx-c[0])+(a[0]-c[0])*(yy-c[1]))/determinant
        w2=1-w0-w1
        inside=(w0>=-1e-5)&(w1>=-1e-5)&(w2>=-1e-5)
        values=w0[...,None]*positions[triangle[0]]+w1[...,None]*positions[triangle[1]]+w2[...,None]*positions[triangle[2]]
        field[yy[inside],xx[inside]]=values[inside]
        coverage[yy[inside],xx[inside]]=True
    return field,coverage

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--geometry",type=Path)
    parser.add_argument("--baseline",type=Path,help="Original15 maps from the manifest's baseline Git revision")
    parser.add_argument("--output",type=Path)
    parser.add_argument("--export-geometry",type=Path)
    args=parser.parse_args()
    if args.export_geometry:
        export_geometry(args.export_geometry.resolve())
        return
    if not args.geometry or not args.output or not args.baseline:
        parser.error("Texture mode requires --geometry, --baseline and --output")
    from PIL import Image
    output=args.output.resolve()
    if output.exists() or not output.is_relative_to(ROOT/".codex-derived"):
        raise ValueError("Choose a fresh derived output")
    (output/"baseline").mkdir(parents=True)
    (output/"refined").mkdir()
    source=args.baseline.resolve()
    manifest=json.loads((ROOT/"Docs/ReplayXI/PLAYER124_ASSET_MANIFEST.json").read_text())
    for record in manifest["bodyTextureRefinement"]["textures"]:
        if digest(source/record["file"])!=record["beforeSHA256"]:
            raise ValueError("Baseline texture changed: "+record["file"])
    expected=SOURCE_HASH
    if digest(ROOT/"ReplayXI/Resources/Players/ReplayXIRocketboxAthlete.usdz") != expected:
        raise ValueError("Admitted geometry changed; re-audit its UV export")
    field,covered=raster(json.loads(args.geometry.read_text()))
    # Exact flat-cloth colours are separable from all existing skin shades.
    # Only these cloth interiors change. Antialiased boundaries and source
    # skin remain byte-for-byte untouched rather than recoloured by guesswork.
    reference=np.asarray(Image.open(source/"ReplayXIRocketboxHomeSkin0.png").convert("RGB"),dtype=np.float64)
    swatches=np.asarray([(232,242,250),(7,18,41),(7,8,10)],dtype=np.float64)*.985
    distances=np.linalg.norm(reference[:,:,None,:]-swatches[None,None,:,:],axis=3)
    cloth=np.min(distances,axis=2)<8
    group=np.argmin(distances,axis=2)
    x,y,z=field[:,:,0],field[:,:,1],field[:,:,2]
    ax=np.abs(x)
    yy,xx=np.mgrid[:512,:512]
    weave=.977+.014*np.sin(xx*np.pi/2)*np.sin(yy*np.pi/2)+.006*np.sin((xx+yy)*np.pi/5)
    kits={"Home":{"shirt":(233,241,247),"shorts":(10,24,43),"sock":(232,239,245),"trim":(19,43,67)},
          "Away":{"shirt":(176,17,29),"shorts":(237,240,242),"sock":(176,17,29),"trim":(239,242,244)},
          "Keeper":{"shirt":(172,227,34),"shorts":(24,39,26),"sock":(172,227,34),"trim":(29,47,29)}}
    rows=[]
    for kit,colours in kits.items():
        colour=np.zeros((512,512,3),dtype=np.float64)
        colour[:]=colours["shirt"]
        pants=group==1
        boots=group==2
        socks=(group==0)&covered&(y<.57)
        shirt=(group==0)&covered&(y>.98)
        colour[pants]=colours["shorts"]
        colour[socks]=colours["sock"]
        colour[boots]=(11,15,20)
        # Fitted side panels and a clean collar, no sponsor/club artwork.
        side=shirt&(ax>.155)&(ax<.238)&(y<1.38)
        colour[side]=np.asarray(colours["shirt"])*.83
        collar=shirt&(y>1.49)&(ax<.105)
        colour[collar]=colours["trim"]
        shoulder=shirt&(y>1.40)&(ax>.11)&(ax<.39)
        colour[shoulder]=np.asarray(colours["shirt"])*.91
        # Narrow sleeve cuffs follow the actual arm UV island, not image rows.
        cuffs=shirt&(ax>.326)&(ax<.349)
        colour[cuffs]=colours["trim"]
        sleeve_seam=shirt&(ax>.239)&(ax<.248)
        colour[sleeve_seam]=np.asarray(colours["shirt"])*.74
        waistband=pants&covered&(y>.992)
        colour[waistband]=colours["trim"]
        shorts_seam=pants&covered&(ax>.202)&(ax<.217)
        colour[shorts_seam]=np.asarray(colours["trim"])*.83
        sock_cuff=socks&(y>.484)&(y<.503)
        colour[sock_cuff]=colours["trim"]
        sock_ankle=socks&(y>.15)&(y<.171)
        colour[sock_ankle]=np.asarray(colours["sock"])*.71
        # Small lace/side accents stay on boots, not on neighbouring skin.
        laces=boots&covered&(z>.07)&(z<.12)&(y>.054)&(y<.11)
        colour[laces]=np.asarray(colours["trim"])*.75
        colour=np.clip(colour*weave[...,None],0,255).round().astype(np.uint8)
        for skin in range(5):
            filename=f"ReplayXIRocketbox{kit}Skin{skin}.png"
            original=source/filename
            (output/"baseline"/filename).write_bytes(original.read_bytes())
            before=np.asarray(Image.open(original).convert("RGB"))
            after=before.copy()
            after[cloth]=colour[cloth]
            if not np.array_equal(after[~cloth],before[~cloth]): raise ValueError("Skin/boundary texels changed")
            Image.fromarray(after).save(output/"refined"/filename,optimize=True)
            rows.append({"file":filename,"beforeSHA256":digest(original),
                         "afterSHA256":digest(output/"refined"/filename),
                         "changedPixels":int(np.any(after!=before,axis=2).sum()),
                         "preservedNonClothPixels":int((~cloth).sum()),
                         "size":[512,512]})
    (output/"manifest.json").write_text(json.dumps({"schemaVersion":1,"sourceAssetSHA256":expected,
        "uvFixtureSHA256":digest(args.geometry),"geometryUnchanged":True,"normalMapsUnchanged":True,
        "originalArtwork":True,"paidReferenceContentCopied":False,"textures":rows},indent=2)+"\n")
    print(json.dumps({"textures":len(rows),"clothPixels":int(cloth.sum()),
                      "preservedNonClothPixels":int((~cloth).sum()),"output":str(output)},indent=2))

if __name__=="__main__": main()
