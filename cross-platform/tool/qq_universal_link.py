#!/usr/bin/env python3
"""Generate reviewable AASA/entitlements only from an actual signing team and domain."""
import argparse
import json
import pathlib
import plistlib
import re
import urllib.parse

parser = argparse.ArgumentParser()
parser.add_argument('--team-id', required=True)
parser.add_argument('--bundle-id', default='cc.huevia.next')
parser.add_argument('--universal-link', required=True)
parser.add_argument('--output', type=pathlib.Path, required=True)
args = parser.parse_args()
url = urllib.parse.urlsplit(args.universal_link)
if not re.fullmatch(r'[A-Z0-9]{10}', args.team_id) or not re.fullmatch(r'[A-Za-z0-9.-]+', args.bundle_id):
    parser.error('Provide the actual signing Team ID and Bundle ID')
if url.scheme != 'https' or not url.hostname or url.username or url.password or url.query or url.fragment or url.port not in (None, 443) or not url.path.endswith('/'):
    parser.error('Universal Link must be an HTTPS URL ending in / without credentials or query')
args.output.mkdir(parents=True, exist_ok=True)
association = {'applinks': {'apps': [], 'details': [{'appID': args.team_id + '.' + args.bundle_id,
    'paths': [url.path + '*']}]}}
(args.output / 'apple-app-site-association').write_text(json.dumps(association, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
with (args.output / 'QQAssociatedDomains.entitlements').open('wb') as file:
    plistlib.dump({'com.apple.developer.associated-domains': ['applinks:' + url.hostname]}, file)
(args.output / 'QQInfo.plist').write_bytes(plistlib.dumps({'HueviaQqUniversalLink': args.universal_link}))
print(json.dumps({'generated': str(args.output), 'deploy': 'https://' + url.hostname + '/.well-known/apple-app-site-association',
    'appID': args.team_id + '.' + args.bundle_id, 'qqConsoleUniversalLink': args.universal_link,
    'deploymentPerformed': False}, ensure_ascii=False))
