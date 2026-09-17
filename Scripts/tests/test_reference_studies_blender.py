import copy
import ast
import json
import math
import struct
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'blender'))
from build_reference_studies import (ContractError, COORDINATES, MAX_EXPORT_BYTES, REPO, RUNTIME,
                                     emit_steps, gait_keys, heading_angles, native_pose_frames,
                                     float32_vector, read_document, validate_document, world_point)


def fixture(duration=7):
    players=[]
    for team in ('home','away'):
        for shirt in range(1,12):
            players.append({'id':f'{team}-{shirt}','displayName':f'QA {shirt}','team':team,
                'shirtNumber':shirt,'isGoalkeeper':shirt==1,
                'evidence':{'origin':'authored','confidence':None,'sourceVisibility':'unknown'},
                'keyframes':[{'time':time,'position':{'x':shirt-6,'z':time/duration*7},'facingDegrees':0}
                             for time in (0,duration)]})
    return {'schemaVersion':1,'coordinateSystem':COORDINATES,'studies':[{
        'id':'qa-only','title':'Synthetic test, not a real match','duration':duration,
        'source':{'url':'https://example.org/reference','windowStartSeconds':10,'windowEndSeconds':20},
        'players':players,'ball':{'source':'native-physics-recording','keyframes':[
            {'time':time,'position':{'x':0,'z':54 if time else 0},'height':0.11} for time in (0,duration)]},
        'contacts':[{'playerID':'home-9','kind':'shot','time':2,'position':{'x':0,'y':0.11,'z':2}}]}]}


def rig_fixture(player_id='home-9', times=(0, 7), names=None):
    return {'playerID':player_id,'source':'native-rig-pose-samples','groundOffset':0.016,
            'jointNames':names or [f'joint-{i}' for i in range(80)],'frames':[
                {'time':time,'translations':[[0.0,0.0,0.0] for _ in range(80)],
                 'rotations':[[0.0,0.0,0.0,1.0] for _ in range(80)],
                 'scales':[[1.0,1.0,1.0] for _ in range(80)]} for time in times]}


def indexed_rig(source, float32=False):
    """Test encoder: dedup exact JSON rows without rounding or sign changes."""
    rig=copy.deepcopy(source)
    table=[];indices={}
    for frame in rig['frames']:
        for field in ('translations','rotations','scales'):
            references=[]
            for row in frame[field]:
                key=json.dumps(row,separators=(',',':'),allow_nan=False)
                if key not in indices:
                    indices[key]=len(table);table.append(row)
                references.append(indices[key])
            frame[field]=references
    rig['transformEncoding']='float32-vector-table-v1' if float32 else 'vector-table-v1'
    rig['vectorTable']=[''.join(struct.pack('>f',value).hex() for value in row) for row in table] if float32 else table
    return rig


class ReferenceStudiesTests(unittest.TestCase):
    def test_short_study_and_ball_beyond_goal_line_are_supported(self):
        self.assertEqual(validate_document(fixture())['studies'][0]['duration'],7)
        validate_document(fixture(89))

    def test_five_distinct_studies_are_supported(self):
        doc=fixture()
        doc['studies']=[copy.deepcopy(doc['studies'][0]) for _ in range(5)]
        for i,study in enumerate(doc['studies']):study['id']=f'qa-{i}'
        validate_document(doc)
        doc['studies'].append(copy.deepcopy(doc['studies'][0]))
        with self.assertRaises(ContractError):validate_document(doc)

    def test_unknown_confidence_is_not_replaced_with_a_number(self):
        doc=validate_document(fixture())
        self.assertIsNone(doc['studies'][0]['players'][0]['evidence']['confidence'])
        self.assertEqual(doc['studies'][0]['players'][0]['evidence']['sourceVisibility'],'unknown')

    def test_unsafe_ids_duplicate_shirts_and_partial_squads_rejected(self):
        for mutation in ('id','shirt','roster'):
            doc=fixture();study=doc['studies'][0]
            if mutation=='id':study['id']='../../unsafe'
            elif mutation=='shirt':study['players'][1]['shirtNumber']=1
            else:study['players'].pop()
            with self.assertRaises(ContractError):validate_document(doc)

    def test_uncovered_or_nonfinite_tracks_rejected(self):
        for field,value in [('time',0),('time',8),('facingDegrees',math.nan)]:
            doc=fixture();doc['studies'][0]['players'][0]['keyframes'][-1][field]=value
            with self.assertRaises(ContractError):validate_document(doc)

    def test_contact_cannot_name_an_unrelated_player(self):
        doc=fixture();doc['studies'][0]['contacts'][0]['playerID']='unknown'
        with self.assertRaises(ContractError):validate_document(doc)

    def test_ball_cannot_be_mislabeled_as_native(self):
        doc=fixture();doc['studies'][0]['ball']['source']='measured'
        with self.assertRaises(ContractError):validate_document(doc)

    def test_coordinate_mapping_preserves_distances_and_handedness(self):
        self.assertEqual(world_point(2,3,4),(-2,4,3))
        x,y,z=world_point(1,0,0),world_point(0,1,0),world_point(0,0,1)
        cross=(x[1]*y[2]-x[2]*y[1],x[2]*y[0]-x[0]*y[2],x[0]*y[1]-x[1]*y[0])
        self.assertEqual(cross,z)
        self.assertEqual(sum(v*v for v in world_point(2,3,4)),29)

    def test_heading_wrap_does_not_spin_the_body(self):
        frames=[{'facingDegrees':x} for x in (179,181,-177)]
        values=heading_angles(frames)
        self.assertAlmostEqual(values[1]-values[0],math.radians(2))
        self.assertAlmostEqual(values[2]-values[1],math.radians(2))

    def test_gait_phase_is_distance_based_and_stops_without_foot_cycle(self):
        frames=[{'time':t,'position':{'x':0,'z':z}} for t,z in ((0,0),(1,2.4),(2,2.4),(3,2.4))]
        keys=gait_keys(frames,30)
        self.assertEqual([key[1] for key in keys],[0,1,1,1])
        self.assertEqual(keys[-1][2],0)
        self.assertEqual(keys[-1][0],91)

    def test_runtime_has_no_safe_mode_bypass_or_implicit_physics(self):
        for forbidden in ('exec(', 'eval(', 'libraries.load', 'subprocess', 'bpy.app.handlers',
                          'bpy.app.timers', 'driver_add', 'read_factory_settings', 'open_mainfile', 'bpy.data.texts'):
            self.assertNotIn(forbidden,RUNTIME)
        self.assertIn('native',RUNTIME.lower())
        self.assertIn('rotation deliberately unkeyed',RUNTIME)
        self.assertIn('q.dot(previous[name])<0',RUNTIME)

    def test_native_ball_spin_requires_a_unit_quaternion(self):
        doc=fixture()
        doc['studies'][0]['ball']['keyframes'][0]['rotation']=[0,0,0,1]
        validate_document(doc)
        doc['studies'][0]['ball']['keyframes'][0]['rotation']=[0,0,0,0]
        with self.assertRaises(ContractError):validate_document(doc)

    def test_native_joint_samples_are_bounded_and_not_mislabeled_mocap(self):
        doc=fixture();study=doc['studies'][0]
        rig={'playerID':'home-9','source':'native-rig-pose-samples','groundOffset':0.016,
             'jointNames':[f'joint-{i}' for i in range(80)],'frames':[
                 {'time':time,'translations':[[0,0,0] for _ in range(80)],
                  'rotations':[[0,0,0,1] for _ in range(80)],'scales':[[1,1,1] for _ in range(80)]}
                 for time in (0,7)]}
        study['rigPoses']=[rig]
        validate_document(doc)
        rig['frames'][1]['rotations'][3]=[0,0,0,0]
        with self.assertRaises(ContractError):validate_document(doc)

    def test_vector_table_roundtrip_keeps_exact_rows_and_negative_zero(self):
        original=rig_fixture()
        original['frames'][1]['translations'][7]=[-0.0,1.1754943508222875e-38,0.12345678901234567]
        original['frames'][1]['rotations'][7]=[1e-15,0.0,0.0,-1.0]
        packed=json.loads(json.dumps(indexed_rig(original)))
        frames=list(native_pose_frames(packed))
        self.assertEqual(frames,original['frames'])
        self.assertEqual(math.copysign(1,frames[1]['translations'][7][0]),-1)
        self.assertLess(len(json.dumps(packed)),len(json.dumps(original)))
        doc=fixture();doc['studies'][0]['rigPoses']=[packed]
        before=copy.deepcopy(doc)
        validate_document(doc)
        self.assertEqual(doc,before,'Validation must not inflate or mutate compact source metadata')

    def test_blender_decoder_matches_host_decoder_without_running_blender(self):
        # Execute only our pure numeric decoder in the test host, not generated
        # scene code. No bpy import, Blender connection or data mutation occurs.
        node=next(node for node in ast.parse(RUNTIME).body
                  if isinstance(node,ast.FunctionDef) and node.name=='rx_pose_frame')
        namespace={'math':math}
        exec(compile(ast.Module(body=[node],type_ignores=[]),'<numeric-decoder-test>','exec'),namespace)
        original=rig_fixture();original['frames'][1]['translations'][5]=[-0.0,0.002,-0.002]
        packed=indexed_rig(original)
        decoded=[namespace['rx_pose_frame'](packed,frame) for frame in packed['frames']]
        self.assertEqual(decoded,list(native_pose_frames(packed)))
        self.assertEqual(decoded,original['frames'])
        packed['frames'][0]['rotations'][0]=True
        with self.assertRaises(ValueError):namespace['rx_pose_frame'](packed,packed['frames'][0])

    def test_float32_codec_preserves_original_bits_and_blender_values(self):
        original=rig_fixture()
        original['frames'][1]['translations'][4]=float32_vector('80000000000000013eaaaaab')
        original['frames'][1]['rotations'][4]=float32_vector('000000000000000000000000bf800000')
        packed=json.loads(json.dumps(indexed_rig(original,float32=True)))
        host=list(native_pose_frames(packed))
        self.assertEqual(host,original['frames'])
        self.assertEqual(math.copysign(1,host[1]['translations'][4][0]),-1)
        self.assertEqual(host[1]['translations'][4][1],2**-149)
        node=next(node for node in ast.parse(RUNTIME).body
                  if isinstance(node,ast.FunctionDef) and node.name=='rx_pose_frame')
        namespace={'math':math}
        exec(compile(ast.Module(body=[node],type_ignores=[]),'<numeric-decoder-test>','exec'),namespace)
        runtime=[namespace['rx_pose_frame'](packed,frame) for frame in packed['frames']]
        self.assertEqual(runtime,host)
        # Runtime scratch is never accepted back as untrusted source metadata.
        with self.assertRaises(ContractError):list(native_pose_frames(packed))
        fresh=indexed_rig(original,float32=True)
        doc=fixture();doc['studies'][0]['rigPoses']=[fresh]
        validate_document(doc)

    def test_float32_codec_rejects_nonfinite_words_bad_hex_and_wrong_lengths(self):
        for word in ('7f800000','ff800000','7fc00001','zzzzzzzz','FFFFFFFF'):
            with self.subTest(word=word):
                rig=indexed_rig(rig_fixture(),float32=True)
                rig['vectorTable'][0]=word+'0000000000000000'
                with self.assertRaises(ContractError):list(native_pose_frames(rig))
        for length in (0,8,23,25,33,800):
            with self.assertRaises(ContractError):float32_vector('0'*length)

    def test_vector_indices_reject_bool_fraction_negative_and_out_of_range(self):
        for value in (True,1.5,-1,1000000,'0',None):
            with self.subTest(value=value):
                doc=fixture();rig=indexed_rig(rig_fixture());doc['studies'][0]['rigPoses']=[rig]
                rig['frames'][0]['rotations'][0]=value
                with self.assertRaises(ContractError):validate_document(doc)

    def test_vector_encoding_rejects_wrong_width_nonfinite_and_unknown_codec(self):
        for mutation in ('width','nan','encoding','unmarked','missing','short-indices'):
            with self.subTest(mutation=mutation):
                doc=fixture();rig=indexed_rig(rig_fixture());doc['studies'][0]['rigPoses']=[rig]
                if mutation=='width':rig['frames'][0]['rotations'][0]=rig['frames'][0]['translations'][0]
                elif mutation=='nan':rig['vectorTable'][0][0]=math.nan
                elif mutation=='encoding':rig['transformEncoding']='executable'
                elif mutation=='unmarked':del rig['transformEncoding']
                elif mutation=='missing':del rig['vectorTable']
                else:rig['frames'][0]['scales'].pop()
                with self.assertRaises(ContractError):validate_document(doc)

    def test_compact_rows_still_enforce_scale_and_unit_quaternion_contracts(self):
        for field,row in (('scales',[0,0,0]),('rotations',[0,0,0,0])):
            doc=fixture();rig=rig_fixture();rig['frames'][1][field][0]=row
            doc['studies'][0]['rigPoses']=[indexed_rig(rig)]
            with self.assertRaises(ContractError):validate_document(doc)

    def test_all_player_sampling_requires_exact_roots_contacts_and_attention(self):
        doc=fixture();study=doc['studies'][0]
        study['rigSampling']={'scope':'all-players','frequencyHz':20,
                              'includesExactContacts':True,'tacticalAttention':True}
        study['rigPoses']=[indexed_rig(rig_fixture(p['id'],times=(0,2,7))) for p in study['players']]
        for player in study['players']:
            player['keyframes'].insert(1,{'time':2,'position':{'x':0,'z':2},'facingDegrees':0})
        validate_document(doc)
        for mutation in ('missing-rig','missing-root','missing-contact','no-attention'):
            broken=copy.deepcopy(doc);study=broken['studies'][0]
            if mutation=='missing-rig':study['rigPoses'].pop()
            elif mutation=='missing-root':study['players'][0]['keyframes'].pop(1)
            elif mutation=='missing-contact':
                next(r for r in study['rigPoses'] if r['playerID']=='home-9')['frames'].pop(1)
            else:study['rigSampling']['tacticalAttention']=False
            with self.assertRaises(ContractError):validate_document(broken)

    def test_only_header_contact_may_declare_a_support_leg(self):
        doc=fixture();contact=doc['studies'][0]['contacts'][0]
        contact['kind']='header';contact['headerSupportLeg']='right'
        validate_document(doc)
        contact['headerSupportLeg']='both'
        with self.assertRaises(ContractError):validate_document(doc)
        contact['headerSupportLeg']='right';contact['kind']='shot'
        with self.assertRaises(ContractError):validate_document(doc)

    def test_original_40_megabyte_input_limit_remains_enforced(self):
        with tempfile.TemporaryDirectory(prefix='replayxi-reference-cap-') as temporary:
            path=Path(temporary)/'oversized.json'
            with path.open('wb') as stream:stream.truncate(MAX_EXPORT_BYTES+1)
            with self.assertRaisesRegex(ContractError,'40 MB'):read_document(path)

    def test_generated_steps_are_plain_python_and_refuse_existing_outputs(self):
        with tempfile.TemporaryDirectory(prefix='replayxi-reference-contract-') as temporary:
            root=Path(temporary)
            report=emit_steps(fixture(),'0'*64,root/'steps',root/'new.blend')
            for name in report['steps']:
                code=(root/'steps'/name).read_text()
                compile(code,name,'exec')
                self.assertNotIn('bpy.data.texts',code)
                self.assertNotIn('libraries.load',code)
            self.assertTrue(any('verify' in name for name in report['steps']))
            with self.assertRaises(ContractError):
                emit_steps(fixture(),'0'*64,root/'steps',root/'new.blend')

    def test_selective_build_keeps_source_digest_and_does_not_reload_assets(self):
        doc=fixture()
        second=copy.deepcopy(doc['studies'][0]);second['id']='qa-second'
        doc['studies'].append(second)
        with tempfile.TemporaryDirectory(prefix='replayxi-reference-selection-') as temporary:
            root=Path(temporary)
            report=emit_steps(doc,'a'*64,root/'steps',root/'new.blend',
                              shared_assets_loaded=True,exclude_studies=['qa-second'])
            self.assertEqual(report['studies'],['qa-only'])
            self.assertEqual(report['manifestSHA256'],'a'*64)
            self.assertFalse(any('prepare-assets' in name or 'source-actions' in name for name in report['steps']))
            code='\n'.join((root/'steps'/name).read_text() for name in report['steps'])
            self.assertIn('RX127_Study_qa-only',code)
            self.assertNotIn('RX127_Study_qa-second',code)
            for name in report['steps']:compile((root/'steps'/name).read_text(),name,'exec')

    def test_empty_or_unknown_selection_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix='replayxi-reference-selection-') as temporary:
            root=Path(temporary)
            for exclusions in (['unknown'],['qa-only']):
                with self.assertRaises(ContractError):
                    emit_steps(fixture(),'0'*64,root/'steps',root/'new.blend',exclude_studies=exclusions)

    def test_all_native_steps_retain_compact_payload_and_report_work(self):
        doc=fixture();study=doc['studies'][0]
        names=[joint['name'] for joint in json.loads(
            (REPO/'ReplayXI/Resources/Players/ReplayXIRocketboxMotion.json').read_text())['joints']]
        study['rigSampling']={'scope':'all-players','frequencyHz':20,
                              'includesExactContacts':True,'tacticalAttention':True}
        study['contacts']=[]
        study['rigPoses']=[indexed_rig(rig_fixture(p['id'],names=names),float32=True) for p in study['players']]
        with tempfile.TemporaryDirectory(prefix='replayxi-reference-all-native-') as temporary:
            root=Path(temporary)
            report=emit_steps(doc,'b'*64,root/'steps',root/'new.blend',shared_assets_loaded=True)
            self.assertEqual(report['stepCount'],len(report['steps']))
            self.assertEqual(report['nativePoseFrames'],44)
            self.assertGreater(report['metadataBytes'],0)
            code='\n'.join((root/'steps'/name).read_text() for name in report['steps'])
            self.assertIn('vector-table-v1',code)
            self.assertNotIn('"_gaitKeys"',code)
            for name in report['steps']:compile((root/'steps'/name).read_text(),name,'exec')


if __name__=='__main__':unittest.main()
