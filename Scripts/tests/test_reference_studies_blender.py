import copy
import math
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'blender'))
from build_reference_studies import (ContractError, COORDINATES, RUNTIME, emit_steps, gait_keys,
                                     heading_angles, validate_document, world_point)


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


if __name__=='__main__':unittest.main()
