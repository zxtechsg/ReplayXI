#!/usr/bin/env python3
"""Offline source/credit audit. Does not access Tripo or spend credits."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import struct

REPO = Path(__file__).resolve().parents[1]
LEDGER = REPO / "Docs/ReplayXI/TRIPO_CREDIT_LEDGER.json"


def count(value):
    if type(value) is not int or value < 0:
        raise ValueError("Credit counts must be nonnegative integers")
    return value


def audit_budget(ledger):
    starting = count(ledger["startingBalance"])
    maximum = count(ledger["maximumCumulativeSpend"])
    reserve = count(ledger["minimumRemainingBalance"])
    spent = count(ledger["verifiedCreditsSpent"])
    remaining = count(ledger["latestObservedBalance"])
    if maximum != starting * 7 // 10 or reserve != starting - maximum:
        raise ValueError("Ledger does not preserve the user's 30% reserve")
    quoted = sum(count(job["quotedCredits"]) for job in ledger["jobs"])
    if quoted != spent or spent > maximum or remaining < reserve:
        raise ValueError("Credit spend or reserve audit failed")
    return {"spent": spent, "lastObservedBalance": remaining, "minimumReserve": reserve,
            "additionalSpendCeilingAtObservation": min(maximum - spent, remaining - reserve)}


def glb_document(payload):
    if len(payload) < 28:
        raise ValueError("Truncated GLB")
    magic, version, total, length, kind = struct.unpack_from("<IIIII", payload)
    if (magic, version, total, kind) != (0x46546C67, 2, len(payload), 0x4E4F534A):
        raise ValueError("Invalid GLB header")
    if length % 4 or 20 + length + 8 > len(payload):
        raise ValueError("Invalid GLB JSON bounds")
    binary_length, binary_kind = struct.unpack_from("<II", payload, 20 + length)
    if binary_kind != 0x004E4942 or 28 + length + binary_length != len(payload):
        raise ValueError("Invalid GLB binary bounds")
    return json.loads(payload[20:20 + length])


def main():
    ledger = json.loads(LEDGER.read_text())
    report = {"budget": audit_budget(ledger), "sourceFiles": [],
              "notice": "Ledger snapshot only: recheck live balance before any paid job. Not a skinning or runtime admission audit."}
    for job in ledger["jobs"]:
        if "export" not in job:
            continue
        path = (LEDGER.parent / job["export"]).resolve()
        if not path.is_relative_to(REPO / "Assets/ReplayXI/TripoFootballer"):
            raise ValueError("Export escapes the authoring asset folder")
        payload = path.read_bytes()
        digest = hashlib.sha256(payload).hexdigest()
        if digest != job["exportSHA256"]:
            raise ValueError(f"Source hash changed: {path.name}")
        document = glb_document(payload)
        report["sourceFiles"].append({"file": path.name, "bytes": len(payload),
                                      "sha256": digest, "meshes": len(document.get("meshes", [])),
                                      "skinJointCounts": [len(skin["joints"]) for skin in document.get("skins", [])],
                                      "knownIssue": job.get("knownIssue")})
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
