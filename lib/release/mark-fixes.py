#!/usr/bin/env python3
"""mark-fixes.py -- tell the agent-index log server which forwarded bugs a release fixes
(developer lib/release, 1.18.0; bug platform outcome 12).

Reads a release-delta manifest. For each entry of its optional "fixes" list,
    {"id": "<upstream bug id, full or >=8-char prefix>", "repo": "<a repo name in this manifest>"}
the version is that repo's manifest "version". Calls the collector's operator door
POST /ops/releases, which moves each listed bug from fixed-pending-release to fixed-released with the
repo, version and release date, and reports (never changes) bugs in any other status. Orgs then see
"fixed in <repo> <version>" in view-bugs / my-bugs.

    python mark-fixes.py <manifest.json> [--env prod|dev] [--creds PATH] [--dry-run]

Run by release-push after the last tag is pushed. A failure here never fails the release (the tags
are already out): it prints what went wrong and the exact command to run again. Safe to re-run.

Credentials (AWS SigV4, service execute-api, us-east-1), first found wins:
  --creds PATH (a bug-admin operator key file: {"access_key_id","secret_access_key"}),
  AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY(/AWS_SESSION_TOKEN),
  the AWS_PROFILE (else "default") profile in ~/.aws/credentials (static keys only).
The identity needs execute-api:Invoke on /ops/* (an admin, or an agent-index-bug-operator user).

Exit: 0 done (or nothing to do), 1 bad manifest/credentials, 3 server, 4 network, 5 refused, 6 auth.
Standard library only. The SigV4 code mirrors bug-admin's apps/ops.py (checked against AWS's
published test vector; run with --selftest).
"""
import argparse
import configparser
import datetime as _dt
import hashlib
import hmac
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BASES = {"prod": "https://v1.logs.agent-index.ai", "dev": "https://v1.logs-dev.agent-index.ai"}
REGION, SERVICE = "us-east-1", "execute-api"


def fail(code, msg):
    print(f"mark-fixes: {msg}", file=sys.stderr)
    sys.exit(code)


def _enc(s):
    return urllib.parse.quote(s, safe="-_.~")


def _canon_path(path):
    return "/".join(_enc(_enc(urllib.parse.unquote(s))) for s in path.split("/")) or "/"


def _canon_query(q):
    return "&".join(f"{k}={v}" for k, v in sorted((_enc(k), _enc(v)) for k, v in q.items()))


def sign(method, host, path, query, body, ak, sk, amz, token=None, extra=None, region=REGION, service=SERVICE):
    h = {"host": host, "x-amz-date": amz}
    if token:
        h["x-amz-security-token"] = token
    for k, v in (extra or {}).items():
        h[k.lower()] = v.strip()
    signed = ";".join(sorted(h))
    creq = "\n".join([method, _canon_path(path), _canon_query(query),
                      "".join(f"{k}:{h[k]}\n" for k in sorted(h)), signed, hashlib.sha256(body).hexdigest()])
    scope = f"{amz[:8]}/{region}/{service}/aws4_request"
    sts = "\n".join(["AWS4-HMAC-SHA256", amz, scope, hashlib.sha256(creq.encode()).hexdigest()])
    k = ("AWS4" + sk).encode()
    for part in (amz[:8], region, service, "aws4_request"):
        k = hmac.new(k, part.encode(), hashlib.sha256).digest()
    sig = hmac.new(k, sts.encode(), hashlib.sha256).hexdigest()
    out = {x: y for x, y in h.items() if x != "host"}
    out["Authorization"] = f"AWS4-HMAC-SHA256 Credential={ak}/{scope}, SignedHeaders={signed}, Signature={sig}"
    return out


def selftest():
    h = sign("GET", "iam.amazonaws.com", "/", {"Action": "ListUsers", "Version": "2010-05-08"}, b"",
             "AKIDEXAMPLE", "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY", "20150830T123600Z",
             extra={"content-type": "application/x-www-form-urlencoded; charset=utf-8"}, service="iam")
    ok = h["Authorization"].endswith("Signature=5d672d79c15b13162d9279b0855cfba6789a8edb4c82c400e06b5924a6f2b5d7")
    print("selftest:", "pass" if ok else "FAIL")
    return 0 if ok else 1


def credentials(path):
    if path:
        try:
            with open(path, encoding="utf-8-sig") as f:
                c = json.load(f)
            return c["access_key_id"], c["secret_access_key"], c.get("session_token"), f"key file {path}"
        except (OSError, ValueError, KeyError) as e:
            fail(1, f"credentials file {path} unreadable: {e}")
    if os.environ.get("AWS_ACCESS_KEY_ID") and os.environ.get("AWS_SECRET_ACCESS_KEY"):
        return (os.environ["AWS_ACCESS_KEY_ID"], os.environ["AWS_SECRET_ACCESS_KEY"],
                os.environ.get("AWS_SESSION_TOKEN"), "environment")
    profile = os.environ.get("AWS_PROFILE") or "default"
    cred_file = os.environ.get("AWS_SHARED_CREDENTIALS_FILE") or os.path.join(os.path.expanduser("~"), ".aws", "credentials")
    cp = configparser.ConfigParser()
    if cp.read(cred_file) and cp.has_section(profile) and cp.has_option(profile, "aws_access_key_id"):
        s = cp[profile]
        return s["aws_access_key_id"], s["aws_secret_access_key"], s.get("aws_session_token"), f"profile {profile}"
    fail(1, f"no AWS credentials: pass --creds <operator key file>, set AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY, "
            f"or add static keys for profile '{profile}' to {cred_file} (SSO profiles: export credentials first)")


def call(base, creds, method, path, payload=None):
    host = urllib.parse.urlparse(base).netloc
    body = b"" if payload is None else json.dumps(payload).encode()
    extra = {"content-type": "application/json"} if payload is not None else {}
    last = ""
    for attempt, delay in enumerate((0, 3, 10)):
        time.sleep(delay)
        amz = _dt.datetime.now(_dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        headers = sign(method, host, path, {}, body, creds[0], creds[1], amz, creds[2], extra)
        if payload is not None:
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(base + path, data=body if payload is not None else None, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.loads(r.read().decode() or "{}")
        except urllib.error.HTTPError as e:
            text = e.read().decode("utf-8", "replace")[:300]
            if e.code in (401, 403):
                fail(6, f"HTTP {e.code}: the server refused these credentials ({creds[3]}): {text}")
            if e.code >= 500:
                last = f"HTTP {e.code}: {text}"
                continue
            fail(5, f"HTTP {e.code}: {text}")
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            last = f"network: {e}"
    fail(4 if last.startswith("network") else 3, f"{base} failed after retries ({last})")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("manifest", nargs="?")
    ap.add_argument("--env", choices=sorted(BASES), default="prod")
    ap.add_argument("--creds")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        sys.exit(selftest())
    if not a.manifest:
        fail(1, "usage: mark-fixes.py <manifest.json> [--env prod|dev] [--creds PATH] [--dry-run]")
    try:
        with open(a.manifest, encoding="utf-8-sig") as f:
            m = json.load(f)
    except (OSError, ValueError) as e:
        fail(1, f"cannot read manifest {a.manifest}: {e}")
    fixes = m.get("fixes") or []
    if not fixes:
        print("mark-fixes: this release lists no fixes -- nothing to do.")
        return
    versions = {r["name"]: r.get("version", "") for r in m.get("repos", [])}
    for f in fixes:
        if not f.get("id") or f.get("repo") not in versions or not versions[f["repo"]]:
            fail(1, f"fix {f!r}: needs an id and a repo that is in this manifest's repos with a version")
    print(f"mark-fixes: {len(fixes)} fix(es) for the {a.env} log server")
    if a.dry_run:
        for f in fixes:
            print(f"  would mark {f['id']} fixed in {f['repo']} {versions[f['repo']]}")
        return
    creds = credentials(a.creds)
    base = BASES[a.env]
    resolved = []
    for f in fixes:
        bid = f["id"].strip().lower()
        if len(bid) != 36:  # a short id: resolve it to the full one
            bid = call(base, creds, "GET", "/ops/bugs/" + urllib.parse.quote(bid, safe=""))["bug"]["id"]
        resolved.append({"id": bid, "repo": f["repo"], "version": versions[f["repo"]]})
    out = call(base, creds, "POST", "/ops/releases", {"fixes": resolved})
    for i in out.get("released", []):
        r = next(x for x in resolved if x["id"] == i)
        print(f"  released  {i[:8]}  fixed in {r['repo']} {r['version']}")
    pending = [s for s in out.get("skipped", []) if s.get("status") != "fixed-released"]
    for s in out.get("skipped", []):
        if s.get("status") == "fixed-released":
            print(f"  already   {s['id'][:8]}  already fixed-released -- nothing to do")
        else:
            print(f"  skipped   {s['id'][:8]}  status is {s['status']} (only fixed-pending-release bugs are marked; set it in bug-admin and re-run)")
    for i in out.get("not_found", []):
        print(f"  not found {i}")
    if pending or out.get("not_found"):
        print("mark-fixes: some bugs were not marked (above). The release itself is fine.")


if __name__ == "__main__":
    main()

# AIFS:FILE-END
