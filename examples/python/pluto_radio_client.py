#!/usr/bin/env python3
"""Minimal app-builder client for the Pluto radio firmware API."""

import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request


DEFAULT_BASE_URL = "http://192.168.2.1"


class PlutoRadioClient:
    def __init__(self, base_url):
        self.base_url = base_url.rstrip("/")

    def call(self, method, path, payload=None):
        url = urllib.parse.urljoin(f"{self.base_url}/", path.lstrip("/"))
        data = None
        headers = {"Accept": "application/json"}
        if method != "GET":
            data = json.dumps(payload or {}).encode("utf-8")
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=15) as response:
                raw = response.read().decode("utf-8")
        except urllib.error.HTTPError as exc:
            raw = exc.read().decode("utf-8")
        return json.loads(raw or "{}")

    def get(self, path):
        return self.call("GET", path)

    def post(self, path, payload=None):
        return self.call("POST", path, payload or {})


def print_json(payload):
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if payload.get("ok", True) else 1


def add_common_tx_args(parser):
    parser.add_argument("--profile", default="TX_TEST_TONE")
    parser.add_argument("--duration-seconds", type=int, default=1)
    parser.add_argument("--tx-mode")
    parser.add_argument("--tx-gain-db", type=float)
    parser.add_argument("--tx-amplitude", type=float)
    parser.add_argument("--tx-audio-tone-hz", type=int)
    parser.add_argument("--tx-fm-deviation-hz", type=int)
    parser.add_argument("--cw-text")
    parser.add_argument("--cw-wpm", type=int)


def tx_payload(args):
    payload = {
        "profile": args.profile,
        "simulate": True,
        "duration_seconds": args.duration_seconds,
    }
    optional = {
        "tx_mode": args.tx_mode,
        "tx_gain_db": args.tx_gain_db,
        "tx_amplitude": args.tx_amplitude,
        "tx_audio_tone_hz": args.tx_audio_tone_hz,
        "tx_fm_deviation_hz": args.tx_fm_deviation_hz,
        "tx_cw_text": args.cw_text,
        "tx_cw_wpm": args.cw_wpm,
    }
    payload.update({key: value for key, value in optional.items() if value is not None})
    return payload


def build_parser():
    parser = argparse.ArgumentParser(description="Pluto radio firmware API sample client")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL, help="Pluto base URL")
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("health")
    subparsers.add_parser("profiles")
    subparsers.add_parser("self-test")
    subparsers.add_parser("calibration")

    guardrails = subparsers.add_parser("guardrails")
    guardrails.add_argument("--profile", default="TX_TEST_TONE")
    guardrails.add_argument("--duration-seconds", type=int, default=1)

    audio = subparsers.add_parser("audio-sim")
    audio.add_argument("--profile", default="NOAA_NFM")

    loopback = subparsers.add_parser("loopback-sim")
    loopback.add_argument("--profile", default="LOOPBACK_TEST")
    loopback.add_argument("--duration-seconds", type=int, default=1)

    tx = subparsers.add_parser("tx-sim")
    add_common_tx_args(tx)

    return parser


def main(argv=None):
    args = build_parser().parse_args(argv)
    client = PlutoRadioClient(args.base_url)

    if args.command == "health":
        return print_json(client.get("/system/health"))
    if args.command == "profiles":
        return print_json(client.get("/radio/profile/list"))
    if args.command == "self-test":
        return print_json(client.post("/system/self-test"))
    if args.command == "calibration":
        return print_json(client.get("/radio/calibration/status"))
    if args.command == "guardrails":
        return print_json(
            client.post(
                "/radio/tx/guardrails",
                {"profile": args.profile, "simulate": True, "duration_seconds": args.duration_seconds},
            )
        )
    if args.command == "audio-sim":
        return print_json(client.post("/radio/audio/start", {"profile": args.profile, "simulate": True}))
    if args.command == "loopback-sim":
        return print_json(
            client.post(
                "/radio/loopback/start",
                {"profile": args.profile, "simulate": True, "duration_seconds": args.duration_seconds},
            )
        )
    if args.command == "tx-sim":
        return print_json(client.post("/radio/tx/start", tx_payload(args)))
    raise SystemExit(f"unknown command: {args.command}")


if __name__ == "__main__":
    sys.exit(main())
