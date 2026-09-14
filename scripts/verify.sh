#!/usr/bin/env bash
# Smoke test against a running locateanything-server.
#
# Usage:
#   ./scripts/verify.sh http://127.0.0.1:8080
#   ./scripts/verify.sh http://127.0.0.1:8080 /path/to/image.png
set -euo pipefail

URL="${1:-http://127.0.0.1:8080}"
IMG="${2:-}"

if [ -z "$IMG" ] || [ ! -f "$IMG" ]; then
    echo "usage: $0 <server-url> <image-path>" >&2
    echo "  or pass an image that exists on disk" >&2
    exit 2
fi

echo "[verify] health check"
curl -sS "$URL/health"
echo

echo "[verify] /v1/models"
curl -sS "$URL/v1/models" | python3 -m json.tool | head -20
echo

B64=$(base64 -w0 "$IMG")
PAYLOAD=/tmp/locateanything-verify.json
python3 -c "
import base64, json
b64 = base64.b64encode(open('$IMG','rb').read()).decode()
body = {
  'model': '/models/LocateAnything-3B-Q4_K_M.gguf',
  'messages': [{'role':'user','content':[
      {'type':'image_url','image_url':{'url':'data:image/jpeg;base64,'+b64}},
      {'type':'text','text':'Locate all the instances that matches the following description: object.'}]}],
  'max_tokens': 256, 'temperature': 0,
}
open('$PAYLOAD','w').write(json.dumps(body))
"

echo "[verify] /v1/chat/completions (1 request, no streaming)"
RESP=$(curl -sS "$URL/v1/chat/completions" -H "Content-Type: application/json" -d "@$PAYLOAD")
echo "$RESP" | python3 -c "
import json, sys, re
d = json.loads(sys.stdin.read())
msg = d['choices'][0]['message']['content']
finish = d['choices'][0]['finish_reason']
print('  raw    :', repr(msg))
print('  finish :', finish)
boxes = re.findall(r'<box>(.*?)</box>', msg)
refs  = re.findall(r'<ref>(.*?)</ref>', msg)
ends  = msg.endswith('<|im_end|>')
print(f'  refs   : {len(refs)} -> {refs}')
print(f'  boxes  : {len(boxes)} -> {boxes[:3]}')
print(f'  im_end : {ends}')
ok = len(refs) >= 1 and (ends or len(boxes) >= 1)
print('  PASS' if ok else '  FAIL')
sys.exit(0 if ok else 1)
"