"""Tests of the monitoring scripts (run: python3 -m unittest discover -s scripts/tests)."""
import importlib.util
import pathlib
import subprocess
import unittest
from unittest import mock

SCRIPTS = pathlib.Path(__file__).resolve().parent.parent


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), SCRIPTS / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


report = load('monitor-report')
external = load('external-monitor')

NOW = 1_000_000.0


def parse(stamp):
    """Stands in for `date --date=<stamp> +%s`: stamps here are seconds, 'n/a' is not a date."""
    if stamp in ('', 'n/a'):
        raise ValueError(stamp)
    return float(stamp)


class MonitorStale(unittest.TestCase):
    def test_a_recent_run_is_fresh(self):
        data = {'ActiveState': 'inactive', 'ExecMainExitTimestamp': str(NOW - 30)}
        self.assertFalse(report.monitor_stale(data, NOW, parse))

    def test_no_run_for_five_minutes_is_stale(self):
        data = {'ActiveState': 'inactive', 'ExecMainExitTimestamp': str(NOW - 301)}
        self.assertTrue(report.monitor_stale(data, NOW, parse))

    def test_a_run_in_progress_has_no_exit_time_and_is_not_stale(self):
        # The false alarm of 17, 28 and 30 October: systemd reports "n/a" while the check runs.
        data = {
            'ActiveState': 'activating',
            'ExecMainExitTimestamp': 'n/a',
            'ExecMainStartTimestamp': str(NOW - 2),
        }
        self.assertFalse(report.monitor_stale(data, NOW, parse))

    def test_a_run_stuck_for_minutes_is_stale(self):
        data = {
            'ActiveState': 'activating',
            'ExecMainExitTimestamp': 'n/a',
            'ExecMainStartTimestamp': str(NOW - 600),
        }
        self.assertTrue(report.monitor_stale(data, NOW, parse))

    def test_an_unreadable_time_is_stale(self):
        self.assertTrue(report.monitor_stale({'ActiveState': 'inactive'}, NOW, parse))

    def test_a_failing_date_command_is_stale(self):
        def broken(_):
            raise subprocess.TimeoutExpired('date', 10)

        data = {'ActiveState': 'inactive', 'ExecMainExitTimestamp': str(NOW)}
        self.assertTrue(report.monitor_stale(data, NOW, broken))


class HostConfirmation(unittest.TestCase):
    def check(self, *readings):
        with mock.patch.object(external, 'check_host', side_effect=list(readings)):
            return external.check_host_confirmed(pause=0)

    def test_a_healthy_host_is_read_once(self):
        with mock.patch.object(external, 'check_host', return_value=[]) as host:
            self.assertEqual(external.check_host_confirmed(pause=0), [])
            self.assertEqual(host.call_count, 1)

    def test_a_one_off_reading_is_not_an_incident(self):
        self.assertEqual(self.check(['MONITOR_STALE'], []), [])

    def test_a_problem_that_stays_is_reported(self):
        self.assertEqual(self.check(['DISK_LOW'], ['DISK_LOW']), ['DISK_LOW'])

    def test_only_the_problems_seen_twice_are_reported(self):
        self.assertEqual(
            self.check(['DISK_LOW', 'MONITOR_STALE'], ['DISK_LOW']), ['DISK_LOW']
        )


class IncidentMail(unittest.TestCase):
    def test_a_new_incident_sends_one_mail_and_recovery_needs_two_healthy_checks(self):
        kind, state = external.decide({}, ['DISK_LOW'], 1000)
        self.assertEqual(kind, 'incident')
        kind, state = external.decide(state, [], 2000)
        self.assertIsNone(kind)
        kind, state = external.decide(state, [], 3000)
        self.assertEqual(kind, 'recovery')


class MessagingChecks(unittest.TestCase):
    def codes(self, **data):
        return report.messaging_problems(data)

    def test_a_successful_check_raises_nothing(self):
        self.assertEqual(self.codes(Result='success', ExecMainStatus='0'), [])

    def test_a_dead_whatsapp_session_is_named(self):
        self.assertEqual(self.codes(Result='exit-code', ExecMainStatus='1'), ['WHATSAPP_DOWN'])

    def test_failed_messages_are_named(self):
        self.assertEqual(self.codes(Result='exit-code', ExecMainStatus='2'), ['JOBS_FAILED'])

    def test_both_problems_are_named_together(self):
        self.assertEqual(
            self.codes(Result='exit-code', ExecMainStatus='3'), ['WHATSAPP_DOWN', 'JOBS_FAILED']
        )

    def test_a_check_that_could_not_run_is_its_own_problem(self):
        for status in ('64', '127', '', 'n/a'):
            self.assertEqual(
                self.codes(Result='exit-code', ExecMainStatus=status), ['MESSAGING_CHECK_FAILED']
            )

    def test_every_code_the_server_can_report_has_a_mail_text(self):
        for code in (
            'WHATSAPP_DOWN', 'JOBS_FAILED', 'MESSAGING_CHECK_FAILED', 'MESSAGING_TIMER',
            'LOCAL_CHECK_FAILED', 'MONITOR_STALE',
        ):
            self.assertIn(code, external.CODES)


if __name__ == '__main__':
    unittest.main()
