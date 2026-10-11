import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('observer', Path(__file__).with_name('plex-history-observer.py'))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class ObserverTests(unittest.TestCase):
    def test_endpoint_allowlist_blocks_all_reporting(self):
        r = m.Reader('https://example.invalid:32400', 'test-only')
        for path in ('/:/timeline', '/:/scrobble', '/:/unscrobble', '/status/sessions/history/1', '/library/metadata/1?x=2'):
            with self.assertRaises(m.AuditError):
                r.get(path)

    def test_origin_rejects_cleartext_credentials_and_queries(self):
        for address in ('http://example.invalid', 'https://user:secret@example.invalid', 'https://example.invalid?token=test', 'https://example.invalid/path'):
            with self.assertRaises(m.AuditError):
                m.Reader(address, 'test-only')

    def test_redirect_never_forwards_token(self):
        with self.assertRaises(m.AuditError):
            m.NoRedirect().redirect_request(None, None, 302, '', {}, 'https://elsewhere.invalid')

    def test_sessions_restrict_account_item_and_client_and_drop_private_fields(self):
        row = {'ratingKey':'123', 'title':'PRIVATE TITLE', 'User':{'id':7, 'title':'PRIVATE USER'},
               'Player':{'machineIdentifier':'test-client', 'state':'playing', 'address':'PRIVATE IP'}, 'viewOffset':4000}
        other = {**row, 'User':{'id':8}}
        result = m.scoped_sessions({'Metadata':[row, other]}, '7', ['123'], 'test-client')
        self.assertEqual(result, [{'item':'item-1','state':'playing','positionMs':4000}])
        self.assertEqual(m.scoped_sessions({'Metadata':[row]}, '7', ['123'], 'another-client'), [])

    def test_history_digest_detects_new_or_modified_rows_but_not_order(self):
        a = {'ratingKey':'123','accountID':7,'historyKey':'/history/1','viewedAt':10,'title':'private'}
        b = {**a,'historyKey':'/history/2','viewedAt':20}
        self.assertEqual(m.history_fingerprint([a,b]),m.history_fingerprint([b,a]))
        self.assertNotEqual(m.history_fingerprint([a]),m.history_fingerprint([a,b]))
        self.assertNotEqual(m.history_fingerprint([a]),m.history_fingerprint([{**a,'viewedAt':11}]))
        self.assertNotIn('private',str(m.history_fingerprint([a])))

    def test_history_rejects_unscoped_rows_and_incomplete_pages(self):
        class Fake:
            def __init__(self, result): self.result = result
            def get(self, *args): return self.result
        for response in ({'Metadata':[{'accountID':8,'ratingKey':'123'}]},
                         {'Metadata':[], 'totalSize':100}):
            with self.assertRaises(m.AuditError):
                m.history(Fake(response), '7', '123')

    def test_state_and_history_changes_are_independent_of_live_position(self):
        item = {'state':dict.fromkeys(m.FIELDS), 'history':m.history_fingerprint([])}
        baseline = {'items':{'item-1':item}, 'sessions':[]}
        during = {**baseline, 'sessions':[{'positionMs':5000}]}
        self.assertEqual(m.changed_fields(baseline,during), [])
        for field in m.FIELDS:
            after = {'items':{'item-1':{**item, 'state':{**item['state'],field:1}}}}
            self.assertEqual(m.changed_fields(baseline,after), ['item-1.'+field])

if __name__ == '__main__':
    unittest.main()
