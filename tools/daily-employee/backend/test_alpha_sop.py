import copy
import unittest
from datetime import datetime,timezone
from alpha_sop import render,SECTIONS

class SopTests(unittest.TestCase):
    def setUp(self):
        self.now=datetime(2026,9,9,9,tzinfo=timezone.utc)
        self.r={'schema_version':'ALPHA_SOP_V1','project_ref':'rclbninptekxitkdtmrs',
                'as_of':'2026-09-09T08:00:00Z',
                'report_mode':'READ_ONLY_EVIDENCE_NOT_ORDER_AUTHORIZATION',
                **{key:[] for key,_ in SECTIONS}}
    def test_all_sections_empty_is_not_success_or_fabricated_plan(self):
        text=render(self.r,self.now)
        self.assertEqual(text.count('## '),18)
        self.assertEqual(text.count('NO RECORDS RETURNED'),18)
        self.assertIn('not new recommendations',text)
    def test_escape_source_text_preserve_null_and_real_shadow_separation(self):
        self.r['curiosity']=[{'question':'a|b\n<script>BUY</script>','answer':None}]
        self.r['paper_trades']=[{'ticker':'SHADOWONLY','lane':'PAPER_ONLY'}]
        text=render(self.r,self.now)
        self.assertIn('a&#124;b<br>&lt;script&gt;',text)
        self.assertNotIn('<script>',text)
        self.assertIn('NOT AVAILABLE',text)
        self.assertNotIn('SHADOWONLY',text.split('## 9.')[0])
    def test_wrong_project_future_missing_section_rejected(self):
        for key,value in [('project_ref','wrong'),('as_of','2026-09-10T08:00:00Z'),
                          ('report_mode','ORDERS_AUTHORIZED')]:
            bad=copy.deepcopy(self.r);bad[key]=value
            with self.assertRaises(ValueError):render(bad,self.now)
        del self.r['portfolio']
        with self.assertRaises(ValueError):render(self.r,self.now)
    def test_no_mutation_and_deterministic(self):
        before=copy.deepcopy(self.r)
        self.assertEqual(render(self.r,self.now),render(self.r,self.now))
        self.assertEqual(before,self.r)

if __name__=='__main__': unittest.main()

