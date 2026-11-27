"""Verify the actual Android package, then collect only the reviewable outputs."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import xml.etree.ElementTree as ET


def main():
    apk = Path("build/app/outputs/flutter-apk/app-d4test-debug.apk")
    if not apk.is_file():
        raise SystemExit("The d4test debug APK was not produced.")
    manifest = ET.fromstring(
        subprocess.check_output(["apkanalyzer", "manifest", "print", str(apk)])
    )
    android = "{http://schemas.android.com/apk/res/android}"
    app = manifest.find("application")
    if (
        manifest.get("package") != "com.ganaderov.mobile.d4test"
        or app is None
        or app.get(f"{android}debuggable") != "true"
    ):
        raise SystemExit("Refusing to publish an unexpected package or a non-debug APK.")
    schemes = {
        item.get(f"{android}scheme")
        for item in manifest.findall(".//intent-filter/data")
    }
    if "com.ganaderov.mobile.d4test" not in schemes or "com.ganaderov.mobile" in schemes:
        raise SystemExit("The test APK must use its isolated authentication callback.")
    signing_tool = Path(os.environ["ANDROID_HOME"]) / "build-tools/36.0.0/apksigner"
    signature = subprocess.check_output(
        [str(signing_tool), "verify", "--verbose", "--print-certs", str(apk)],
        text=True,
    )
    destination = Path("build/test-apk")
    destination.mkdir(parents=True, exist_ok=True)
    output = destination / "ganaderov-d4test.apk"
    shutil.copyfile(apk, output)
    with output.open("rb") as content:
        digest = hashlib.file_digest(content, "sha256").hexdigest()
    (destination / "SHA256SUMS").write_text(f"{digest}  {output.name}\n")
    (destination / "signing-certificate.txt").write_text(signature)
    info = json.loads((Path(os.environ["RUNNER_TEMP"]) / "d4-build-info.json").read_text())
    defines = json.loads((Path(os.environ["RUNNER_TEMP"]) / "d4-test-defines.json").read_text())
    identity = {
        "profile": defines["D4_TEST_PROFILE"],
        "url": defines["SUPABASE_URL"],
        "publishableKey": defines["SUPABASE_PUBLISHABLE_KEY"],
        "projectRef": defines["D4_TEST_PROJECT_REF"],
    }
    fingerprint = hashlib.sha256(json.dumps(identity, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    info.update({"apkSha256": digest, "apkBytes": output.stat().st_size, "backendIdentitySha256": fingerprint})
    (destination / "build-info.json").write_text(json.dumps(info, indent=2) + "\n")
    shutil.copyfile("docs/android-test-apk.md", destination / "INSTRUCCIONES.md")
    shutil.copyfile("tool/verify_test_backend.py", destination / "verify_test_backend.py")
    shutil.copyfile("tool/configure_local_supabase.py", destination / "configure_local_supabase.py")
    print(f"Verified debug package com.ganaderov.mobile.d4test; SHA256 {digest}")


if __name__ == "__main__":
    main()
