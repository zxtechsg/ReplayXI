#!/usr/bin/env python3
"""Six tiny original64px kit maps for the Blender124 torso/shorts UVs."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    output=args.output.resolve()
    if output.exists() or not output.is_relative_to(ROOT/'.codex-derived'):
        raise ValueError('Choose a fresh derived output')
    output.mkdir(parents=True)
    yy,xx=np.mgrid[:64,:64]
    u=(xx+.5)/64
    v=1-(yy+.5)/64
    weave=.979+.01*np.sin(xx*np.pi/2)*np.sin(yy*np.pi/2)
    colours={'Home':((233,241,247),(10,24,43),(19,43,67)),
             'Away':((176,17,29),(237,240,242),(239,242,244)),
             'Keeper':((172,227,34),(24,39,26),(29,47,29))}
    rows=[]
    for team,(shirt,shorts,trim) in colours.items():
        for part,base in [('Torso',shirt),('Shorts',shorts)]:
            pixels=np.empty((64,64,3),dtype=np.float64)
            pixels[:]=base
            if part=='Torso':
                side=((abs(u-.25)<.052)|(abs(u-.75)<.052))&(v<.70)&(v>.05)
                pixels[side]=np.asarray(base)*.80
                seam=((abs(u-.19)<.010)|(abs(u-.31)<.010)|(abs(u-.69)<.010)|(abs(u-.81)<.010))&(v<.71)
                pixels[seam]=np.asarray(base)*.71
                pixels[v>.957]=trim
                # Subtle shoulder insert retains the model's actual curved
                # deltoid silhouette; no baked directional lighting/shadow.
                shoulder=(v>.66)&(v<.80)&((abs(u-.25)<.19)|(abs(u-.75)<.19))
                pixels[shoulder]=np.asarray(base)*.92
            else:
                pixels[v>.925]=trim
                side=(abs(u-.25)<.035)|(abs(u-.75)<.035)
                pixels[side]=np.asarray(trim)*.87
                pixels[v<.035]=np.asarray(base)*.80
            data=np.clip(pixels*weave[...,None],0,255).round().astype(np.uint8)
            filename=f'ReplayXIFar{team}{part}.png'
            Image.fromarray(data).save(output/filename,optimize=True)
            raw=(output/filename).read_bytes()
            rgba=np.concatenate((data,np.full((64,64,1),255,dtype=np.uint8)),axis=2)
            rows.append({'file':filename,'sha256':hashlib.sha256(raw).hexdigest(),
                         'canonicalRGBAPixelSHA256':hashlib.sha256(rgba.tobytes()).hexdigest(),
                         'bytes':len(raw),'width':64,'height':64})
    report={'schemaVersion':1,'originalArtwork':True,'paidReferenceContentCopied':False,
            'baseDecodedBytes':6*64*64*4,'textures':rows}
    (output/'manifest.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))

if __name__=='__main__': main()
