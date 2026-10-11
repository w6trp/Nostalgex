#!/usr/bin/env python3
"""Read-only, interactively stepped Plex history observer. Never sends playback reports."""
import argparse
import getpass
import hashlib
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

FIELDS = ('viewCount', 'viewOffset', 'lastViewedAt')

class AuditError(Exception):
    pass

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise AuditError('Redirect refused; verify the direct HTTPS server address.')

class Reader:
    def __init__(self, server, token):
        parsed = urllib.parse.urlsplit(server)
        if (parsed.scheme != 'https' or not parsed.hostname or parsed.username
                or parsed.password or parsed.query or parsed.fragment or parsed.path not in ('', '/')):
            raise AuditError('A direct HTTPS server origin without credentials or a path is required.')
        self.server = server.rstrip('/')
        self.token = token
        self.opener = urllib.request.build_opener(NoRedirect())

    def get(self, path, params=None):
        allowed = path in ('/', '/status/sessions', '/status/sessions/history/all')
        allowed |= path.startswith('/library/metadata/') and path.rsplit('/', 1)[-1].isdigit()
        if not allowed:
            raise AuditError('Endpoint is outside the read-only allowlist.')
        url = self.server + path
        if params:
            url += '?' + urllib.parse.urlencode(params)
        req = urllib.request.Request(url, headers={
            'X-Plex-Token': self.token, 'Accept': 'application/json',
            'X-Plex-Product': 'CouchWave Read-only Observer',
            'X-Plex-Client-Identifier': 'couchwave-readonly-observer',
        }, method='GET')
        try:
            with self.opener.open(req, timeout=15) as response:
                raw = response.read(4_000_001)
                if len(raw) > 4_000_000:
                    raise AuditError('Response exceeded the observation limit.')
                container = json.loads(raw)['MediaContainer']
                total = response.headers.get('X-Plex-Container-Total-Size')
                if total is not None and 'totalSize' not in container:
                    container['totalSize'] = int(total)
                return container
        except urllib.error.HTTPError as error:
            raise AuditError('Read failed with HTTP ' + str(error.code)) from None
        except (urllib.error.URLError, ValueError, KeyError):
            raise AuditError('Read failed; verify server, permissions and JSON support locally.') from None


def history_fingerprint(rows):
    # IDs/titles never leave memory; preserve row changes without exposing them.
    selected = [{k: row.get(k) for k in ('historyKey', 'key', 'ratingKey', 'accountID', 'viewedAt', 'viewOffset')}
                for row in rows]
    packed = sorted(json.dumps(row, sort_keys=True) for row in selected)
    return {'count': len(rows), 'digest': hashlib.sha256('\n'.join(packed).encode()).hexdigest()}


def history(reader, account, key):
    rows = []
    for page in range(100):
        container = reader.get('/status/sessions/history/all', {
            'accountID': account, 'metadataItemID': key, 'sort': 'viewedAt:desc',
            'X-Plex-Container-Start': page * 100, 'X-Plex-Container-Size': 100,
        })
        batch = container.get('Metadata', [])
        # Reject a server that ignores scope, rather than retain unrelated history.
        if any(str(row.get('accountID')) != account or str(row.get('ratingKey')) != key for row in batch):
            raise AuditError('History response did not match the approved account/item scope.')
        rows.extend(batch)
        total = container.get('totalSize')
        if total is not None and len(rows) >= int(total):
            return history_fingerprint(rows)
        if len(batch) < 100:
            if total is not None and len(rows) != int(total):
                raise AuditError('Incomplete history pagination; result is inconclusive.')
            return history_fingerprint(rows)
    raise AuditError('History pagination limit reached; result is inconclusive.')


def scoped_sessions(container, account, keys, client):
    aliases = {key: 'item-' + str(i + 1) for i, key in enumerate(keys)}
    result = []
    for row in container.get('Metadata', []):
        player = row.get('Player', {})
        if (str(row.get('User', {}).get('id')) != account
                or str(row.get('ratingKey')) not in aliases
                or player.get('machineIdentifier') != client):
            continue
        result.append({'item': aliases[str(row['ratingKey'])],
                       'state': player.get('state'), 'positionMs': row.get('viewOffset')})
    return result


def snapshot(user, observer, account, keys, client):
    items = {}
    for i, key in enumerate(keys):
        data = user.get('/library/metadata/' + key, {'skipRefresh': 1}).get('Metadata', [])
        if len(data) != 1 or str(data[0].get('ratingKey')) != key:
            raise AuditError('Expected test-item metadata was not returned.')
        items['item-' + str(i + 1)] = {
            'state': {field: data[0].get(field) for field in FIELDS},
            'history': history(user, account, key),
        }
    sessions = scoped_sessions(observer.get('/status/sessions'), account, keys, client)
    return {'capturedAt': datetime.now(timezone.utc).isoformat(), 'items': items, 'sessions': sessions}


def changed_fields(before, after):
    changes = []
    for alias, original in before['items'].items():
        current = after['items'][alias]
        changes += [alias + '.' + field for field in FIELDS if original['state'][field] != current['state'][field]]
        if original['history'] != current['history']:
            changes.append(alias + '.history')
    return changes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--server', required=True, help='Approved direct HTTPS Plex origin')
    parser.add_argument('--account-id', required=True, help='Verified disposable test profile ID')
    parser.add_argument('--rating-key', required=True, action='append', help='Approved sample item; repeat for surfing')
    parser.add_argument('--client-id', required=True, help='Verified test app client identifier')
    args = parser.parse_args()
    if not args.account_id.isdigit() or not all(key.isdigit() for key in args.rating_key):
        raise AuditError('Numeric account and sample item IDs are required.')
    print('Observer only: no reporting, scrobble, history deletion or account creation. Use approved test credentials only.', file=sys.stderr)
    user = Reader(args.server, getpass.getpass('Existing disposable-profile token (hidden): '))
    observer = Reader(args.server, getpass.getpass('Existing authorized admin token for session reads (hidden): '))
    version = observer.get('/').get('version')
    print(json.dumps({'serverVersion': version, 'mode': 'read-only'}), flush=True)
    baseline = snapshot(user, observer, args.account_id, args.rating_key, args.client_id)
    print(json.dumps({'phase': 'baseline', **baseline}), flush=True)
    print('At each checkpoint press Enter to capture. Type q to finish. No playback is started by this tool.', file=sys.stderr)
    index = 0
    while True:
        print('Capture checkpoint [Enter/q]: ', end='', file=sys.stderr, flush=True)
        if input().strip().lower() == 'q':
            break
        index += 1
        current = snapshot(user, observer, args.account_id, args.rating_key, args.client_id)
        changes = changed_fields(baseline, current)
        print(json.dumps({'phase': 'checkpoint-' + str(index), **current, 'changedSinceBaseline': changes}), flush=True)
        if changes:
            print('Persistent state changed. Stop the experiment; do not clear or restore real history.', file=sys.stderr)
            return 2
    return 0

if __name__ == '__main__':
    try:
        sys.exit(main())
    except (AuditError, KeyboardInterrupt, EOFError) as error:
        print(str(error) if isinstance(error, AuditError) else 'Observation stopped.', file=sys.stderr)
        sys.exit(1)
