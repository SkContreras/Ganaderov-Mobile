"""Compare a recreated backend's verified client config with the APK identity.

This is an identity check, not a replacement for running the real HTTP harness.
It prints no API keys or credentials.
"""

import hashlib
import json
from pathlib import Path
import sys
from urllib.parse import urlparse


def main():
    if len(sys.argv) != 3:
        raise SystemExit("Usage: python verify_test_backend.py build-info.json client-config.json")
    info = json.loads(Path(sys.argv[1]).read_text())
    config = json.loads(Path(sys.argv[2]).read_text())
    identity = {
        "profile": config.get("profile", "").strip(),
        "url": config.get("url", "").strip().rstrip("/"),
        "publishableKey": config.get("publishableKey", "").strip(),
        "projectRef": config.get("projectRef", "").strip(),
    }
    fingerprint = hashlib.sha256(json.dumps(identity, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    if (
        info.get("applicationId") != "com.ganaderov.mobile.d4test"
        or info.get("debugBuild") is not True
        or config.get("backendReady") is not True
        or fingerprint != info.get("backendIdentitySha256")
    ):
        raise SystemExit("Backend does not match this APK or has not passed the harness. Rebuild the test APK from the new verified client config; do not substitute production credentials.")
    print("Verified: backend identity matches this test APK and its harness completed.")
    if identity["profile"] == "local":
        uri = urlparse(identity["url"])
        if uri.hostname in {"127.0.0.1", "localhost"}:
            print(f"For a USB-connected Android device: adb reverse tcp:{uri.port} tcp:{uri.port}")


if __name__ == "__main__":
    main()
