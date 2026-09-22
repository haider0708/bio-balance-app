import importlib.util,pathlib,unittest
spec=importlib.util.spec_from_file_location('monitor',pathlib.Path(__file__).resolve().parents[2]/'scripts/external-monitor.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class MonitorTest(unittest.TestCase):
 def test_healthy_is_quiet(self):
  kind,state=m.decide({},[],100);self.assertIsNone(kind);self.assertEqual([],state['incident'])
 def test_incident_deduplicated_and_reminded(self):
  kind,state=m.decide({},['DISK_LOW'],100);self.assertEqual('incident',kind)
  self.assertIsNone(m.decide(state,['DISK_LOW'],101)[0])
  self.assertEqual('incident',m.decide(state,['DISK_LOW'],100+21600)[0])
 def test_changed_incident_notifies(self):
  _,state=m.decide({},['DISK_LOW'],100)
  self.assertEqual('incident',m.decide(state,['DISK_LOW','BACKUP_FAILED'],101)[0])
 def test_recovery_needs_two_healthy_runs(self):
  _,state=m.decide({},['API_UNREACHABLE'],100)
  kind,state=m.decide(state,[],101);self.assertIsNone(kind)
  kind,state=m.decide(state,[],102);self.assertEqual('recovery',kind);self.assertEqual([],state['incident'])
  self.assertIsNone(m.decide(state,[],103)[0])
 def test_interrupted_recovery_resets_count(self):
  _,state=m.decide({},['DISK_LOW'],100);_,state=m.decide(state,[],101)
  _,state=m.decide(state,['DISK_LOW'],102);self.assertEqual(0,state['healthyCount'])
  self.assertIsNone(m.decide(state,[],103)[0])
 def test_test_email_does_not_acknowledge_incident(self):
  kind,state=m.decide({},[],100,True);self.assertEqual('diagnostic',kind);self.assertEqual(0,state['sentAt'])
if __name__=='__main__':unittest.main()
