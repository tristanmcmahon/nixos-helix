#!/usr/bin/env python3
"""Create a Gmail OAuth token using a local OAuth client JSON.

This helper automates the local OAuth consent flow and writes the resulting
credentials JSON to the token path you specify. It does NOT upload or store
your client secret in this repo.

Usage:
  python tools/gmail_oauth_setup.py --credentials ~/.config/gwen/gmail_credentials.json \
      --token ~/.config/gwen/gmail_token.json

After success, export the env vars shown by the script and run the relay.
"""
import argparse
import json
import os
from pathlib import Path

from google_auth_oauthlib.flow import InstalledAppFlow


DEFAULT_SCOPES = ["https://www.googleapis.com/auth/gmail.send"]


def run_flow(credentials_path: Path, token_path: Path, scopes):
    flow = InstalledAppFlow.from_client_secrets_file(str(credentials_path), scopes)
    creds = flow.run_local_server(port=0)
    # Save token
    token_path.parent.mkdir(parents=True, exist_ok=True)
    with token_path.open("w", encoding="utf-8") as f:
        f.write(creds.to_json())
    # Restrict token file permissions when possible
    try:
        token_path.chmod(0o600)
    except Exception:
        pass
    return token_path


def main():
    p = argparse.ArgumentParser(description="Create Gmail OAuth token for relay")
    p.add_argument("--credentials", required=True, help="Path to client_secret JSON")
    p.add_argument("--token", required=True, help="Path to write token JSON")
    p.add_argument("--scopes", default=",".join(DEFAULT_SCOPES), help="Comma-separated scopes")
    args = p.parse_args()

    cred = Path(os.path.expanduser(args.credentials))
    token = Path(os.path.expanduser(args.token))
    scopes = [s.strip() for s in args.scopes.split(",") if s.strip()]

    if not cred.exists():
        print("OAuth client credentials not found:", cred)
        print("Please create a Google OAuth Desktop client in the Cloud Console and download the JSON to this path.")
        print("See README-gwen-conduit.md for instructions.")
        raise SystemExit(2)

    print("Starting local OAuth flow (will open a browser).")
    print("Credentials:", cred)
    print("Token will be written to:", token)

    try:
        out = run_flow(cred, token, scopes)
    except Exception as e:
        print("OAuth flow failed:", e)
        raise SystemExit(3)

    print("Token saved to:", out)
    print()
    print("Next steps: set environment variables before running the relay:")
    print(f"export GMAIL_ENABLED=true")
    print(f"export GMAIL_CREDENTIALS={cred}")
    print(f"export GMAIL_TOKEN={out}")
    print(f"export GMAIL_USER=you@example.com   # optional")
    print("Then run: python tools/relay_to_ollama.py examples/task-example.json")


if __name__ == "__main__":
    main()
