#!/usr/bin/env python3

"""Validate canonical Helix reinstall manifests, archives, and staged trees."""

from __future__ import annotations

import os
import posixpath
import re
import stat
import sys
import tarfile
from pathlib import Path, PurePosixPath


REQUIRED_ARTIFACTS = {
    "BACKUP-README.txt",
    "home-tristan.tar",
    "etc-nixos-secrets.tar",
    "machine-identity.tar",
    "ssh-host-key-fingerprints.txt",
    "repository-head.txt",
    "origin-main.txt",
    "repository-branch.txt",
    "repository-status.txt",
    "repository-diff.patch",
    "repository-cached-diff.patch",
    "repository-untracked-files.txt",
    "hardware-configuration-repository.nix",
    "hardware-configuration-installed.nix",
    "lsblk.txt",
    "blkid.txt",
    "findmnt.txt",
    "bootctl-status.txt",
    "nixos-version.txt",
    "uname.txt",
    "system-closures.txt",
    "nixos-generations.txt",
    "package-inventory.txt",
    "home-size-audit.txt",
    "ssh-metadata.txt",
}

NM_PROFILE = "etc/NetworkManager/system-connections/towerofdoom.nmconnection"
SSH_KEY = re.compile(r"^etc/ssh/(ssh_host_[A-Za-z0-9_-]+_key)(\.pub)?$")


def fail(message: str) -> None:
    raise SystemExit(f"FAIL: {message}")


def safe_member_name(name: str, expected_root: str) -> str:
    if not name or name.startswith("/") or any(char in name for char in "\r\n\0"):
        fail("archive contains an absolute, empty, or control-character path")
    parts = PurePosixPath(name).parts
    if ".." in parts or "." in parts:
        fail(f"archive contains an unsafe path: {name}")
    normalized = posixpath.normpath(name.rstrip("/"))
    if normalized != expected_root and not normalized.startswith(expected_root + "/"):
        fail(f"archive path is outside {expected_root}: {name}")
    return normalized


def safe_link_target(member: tarfile.TarInfo, expected_root: str) -> str:
    target = member.linkname
    if not target or any(char in target for char in "\r\n\0"):
        fail(f"archive link has an unsafe target: {member.name}")
    if member.issym() and target.startswith("/"):
        absolute_root = "/" + expected_root
        if target != absolute_root and not target.startswith(absolute_root + "/"):
            fail(f"archive link has an unsafe absolute target: {member.name}")
        resolved = target.removeprefix("/")
    elif member.issym():
        resolved = posixpath.normpath(posixpath.join(posixpath.dirname(member.name), target))
    else:
        resolved = posixpath.normpath(target)
    if resolved != expected_root and not resolved.startswith(expected_root + "/"):
        fail(f"archive link escapes {expected_root}: {member.name}")
    return resolved


def validate_archive(archive: Path, expected_root: str) -> tuple[int, int]:
    try:
        with tarfile.open(archive, mode="r:") as handle:
            members = handle.getmembers()
    except (tarfile.TarError, OSError) as error:
        fail(f"archive is unreadable: {error}")
    if not members:
        fail("archive is empty")

    names: dict[str, tarfile.TarInfo] = {}
    total_bytes = 0
    for member in members:
        normalized = safe_member_name(member.name, expected_root)
        if normalized in names:
            fail(f"archive contains a duplicate path: {member.name}")
        names[normalized] = member
        if not (member.isfile() or member.isdir() or member.issym() or member.islnk()):
            fail(f"archive contains an unsupported special file: {member.name}")
        if member.issym() or member.islnk():
            safe_link_target(member, expected_root)
        if member.isfile():
            total_bytes += member.size

    root_member = names.get(expected_root)
    if root_member is None or not root_member.isdir():
        fail(f"archive lacks directory root {expected_root}")
    if expected_root == "home/tristan":
        for representative in (".config", ".ssh", "Projects"):
            path = f"{expected_root}/{representative}"
            if path not in names or not names[path].isdir():
                fail(f"home archive lacks representative directory {representative}")
    for member in members:
        if member.islnk():
            target = safe_link_target(member, expected_root)
            target_member = names.get(target)
            if target_member is None or not (target_member.isfile() or target_member.islnk()):
                fail(f"hardlink target is absent or not a regular file: {member.name}")
    return len(members), total_bytes


def archive_root_owner(archive: Path, expected_root: str) -> tuple[int, int]:
    validate_archive(archive, expected_root)
    with tarfile.open(archive, mode="r:") as handle:
        for member in handle.getmembers():
            if member.name.rstrip("/") == expected_root:
                return member.uid, member.gid
    fail(f"archive lacks directory root {expected_root}")


def validate_machine_identity(archive: Path, expected_uid: int = 0, expected_gid: int = 0) -> tuple[int, int, int]:
    """Accept only the one NM profile and complete OpenSSH host-key pairs."""
    try:
        with tarfile.open(archive, mode="r:") as handle:
            members = handle.getmembers()
    except (tarfile.TarError, OSError) as error:
        fail(f"machine identity archive is unreadable: {error}")
    if not members:
        fail("machine identity archive is empty")

    names: set[str] = set()
    private_keys: set[str] = set()
    public_keys: set[str] = set()
    total_bytes = 0
    for member in members:
        name = member.name.rstrip("/")
        if not name or name.startswith("/") or ".." in PurePosixPath(name).parts:
            fail(f"machine identity archive contains an unsafe path: {member.name}")
        if name in names:
            fail(f"machine identity archive contains a duplicate path: {member.name}")
        names.add(name)
        match = SSH_KEY.fullmatch(name)
        if name != NM_PROFILE and match is None:
            fail(f"machine identity archive contains an unexpected path: {member.name}")
        if not member.isfile():
            fail(f"machine identity member is not a regular file: {member.name}")
        if member.uid != expected_uid or member.gid != expected_gid:
            fail(f"machine identity member is not owned by root: {member.name}")
        mode = stat.S_IMODE(member.mode)
        if name == NM_PROFILE and mode != 0o600:
            fail("NetworkManager profile mode is not 0600")
        if match:
            key_name = match.group(1)
            if match.group(2):
                public_keys.add(key_name)
                if mode != 0o644:
                    fail(f"SSH public host key mode is not 0644: {member.name}")
            else:
                private_keys.add(key_name)
                if mode != 0o600:
                    fail(f"SSH private host key mode is not 0600: {member.name}")
        total_bytes += member.size
    if NM_PROFILE not in names:
        fail("machine identity archive lacks the NetworkManager profile")
    if not private_keys or private_keys != public_keys:
        fail("machine identity archive lacks complete SSH host-key pairs")
    return len(members), total_bytes, len(private_keys)


def validate_fingerprints(path: Path, archive: Path, uid: int = 0, gid: int = 0) -> int:
    _, _, pair_count = validate_machine_identity(archive, uid, gid)
    with tarfile.open(archive, mode="r:") as handle:
        expected = {
            PurePosixPath(member.name).name
            for member in handle.getmembers()
            if member.name.endswith("_key.pub")
        }
    pattern = re.compile(r"^(ssh_host_[A-Za-z0-9_-]+_key\.pub)\t(SHA256:[A-Za-z0-9+/]+={0,2})$")
    try:
        lines = path.read_text(encoding="ascii").splitlines()
    except (OSError, UnicodeError) as error:
        fail(f"host-key fingerprint record is unreadable: {error}")
    recorded: set[str] = set()
    for line in lines:
        match = pattern.fullmatch(line)
        if match is None or match.group(1) in recorded:
            fail("host-key fingerprint record is malformed or duplicated")
        recorded.add(match.group(1))
    if recorded != expected or len(recorded) != pair_count:
        fail("host-key fingerprint record does not match the archive")
    return len(recorded)


def validate_manifest(backup_set: Path) -> int:
    manifest = backup_set / "SHA256SUMS"
    entries: set[str] = set()
    pattern = re.compile(r"^[0-9a-f]{64} [ *](?:\./)?([^/]+)$")
    try:
        lines = manifest.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError) as error:
        fail(f"checksum manifest is unreadable: {error}")
    for line in lines:
        match = pattern.fullmatch(line)
        if match is None:
            fail("checksum manifest contains an unsafe or malformed entry")
        name = match.group(1)
        if name in entries:
            fail("checksum manifest contains duplicate entries")
        entries.add(name)
    actual = {
        path.name
        for path in backup_set.iterdir()
        if path.is_file() and path.name not in {"COMPLETE", "SHA256SUMS"}
    }
    if entries != actual:
        fail("checksum manifest does not cover exactly the completed artifacts")
    missing = REQUIRED_ARTIFACTS - entries
    if missing:
        fail(f"backup lacks {len(missing)} required artifact(s)")
    return len(entries)


def collision_names(archive: Path, expected_root: str, destination: Path) -> list[str]:
    with tarfile.open(archive, mode="r:") as handle:
        members = handle.getmembers()
    collisions: list[str] = []
    for member in members:
        normalized = safe_member_name(member.name, expected_root)
        if normalized == expected_root:
            continue
        relative = normalized.removeprefix(expected_root + "/")
        if os.path.lexists(destination / relative):
            collisions.append(relative)
    return collisions


def validate_staged(staging: Path) -> int:
    roots = (staging / "home/tristan", staging / "etc/nixos/secrets")
    for root in roots:
        if not root.is_dir() or root.is_symlink():
            fail(f"staged restore lacks expected directory {root.relative_to(staging)}")
    count = 0
    for expected_root in roots:
        lexical_root = PurePosixPath(expected_root.relative_to(staging).as_posix())
        for directory, directories, files in os.walk(expected_root, followlinks=False):
            for name in directories + files:
                path = Path(directory) / name
                count += 1
                mode = path.lstat().st_mode
                relative = PurePosixPath(path.relative_to(staging).as_posix())
                if stat.S_ISLNK(mode):
                    target = os.readlink(path)
                    if target.startswith("/"):
                        if lexical_root != PurePosixPath("home/tristan") or (
                            target != "/home/tristan"
                            and not target.startswith("/home/tristan/")
                        ):
                            fail(f"staged symlink has an unsafe absolute target: {relative}")
                        resolved = PurePosixPath(target.removeprefix("/"))
                    else:
                        resolved = PurePosixPath(posixpath.normpath(
                            posixpath.join(str(relative.parent), target)
                        ))
                    if resolved != lexical_root and lexical_root not in resolved.parents:
                        fail(f"staged symlink escapes its restore root: {relative}")
                elif not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)):
                    fail(f"staged tree contains an unexpected special file: {relative}")
    return count


def main() -> None:
    if len(sys.argv) < 2:
        fail("validator mode is required")
    mode = sys.argv[1]
    if mode == "manifest" and len(sys.argv) == 3:
        print(validate_manifest(Path(sys.argv[2])))
    elif mode == "archive" and len(sys.argv) == 4:
        entries, size = validate_archive(Path(sys.argv[2]), sys.argv[3])
        print(entries, size)
    elif mode == "root-owner" and len(sys.argv) == 4:
        uid, gid = archive_root_owner(Path(sys.argv[2]), sys.argv[3])
        print(uid, gid)
    elif mode == "machine-identity" and len(sys.argv) in (3, 5):
        uid = int(sys.argv[3]) if len(sys.argv) == 5 else 0
        gid = int(sys.argv[4]) if len(sys.argv) == 5 else 0
        entries, size, pairs = validate_machine_identity(Path(sys.argv[2]), uid, gid)
        print(entries, size, pairs)
    elif mode == "fingerprints" and len(sys.argv) in (4, 6):
        uid = int(sys.argv[4]) if len(sys.argv) == 6 else 0
        gid = int(sys.argv[5]) if len(sys.argv) == 6 else 0
        print(validate_fingerprints(Path(sys.argv[2]), Path(sys.argv[3]), uid, gid))
    elif mode == "collisions" and len(sys.argv) == 5:
        names = collision_names(Path(sys.argv[2]), sys.argv[3], Path(sys.argv[4]))
        print(len(names))
        print("\n".join(names))
    elif mode == "staged" and len(sys.argv) == 3:
        print(validate_staged(Path(sys.argv[2])))
    else:
        fail("invalid validator invocation")


if __name__ == "__main__":
    main()
