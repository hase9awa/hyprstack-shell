#!/usr/bin/env python3
"""Atomic per-user deployment with durable backup and rollback journals."""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import tempfile
from datetime import datetime, timezone


def atomic_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=".manifest-")
    try:
        with os.fdopen(fd, "w") as out:
            json.dump(data, out, indent=2)
            out.flush(); os.fsync(out.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)


def read_json(path, fallback=None):
    try: return json.loads(path.read_text())
    except FileNotFoundError: return fallback


@dataclass
class File:
    path: Path
    data: bytes = b""
    mode: int = 0o644
    link: str | None = None
    preserve: bool = False


class Installer:
    def __init__(self, home: Path | None = None):
        self.home = home or Path.home()
        self.config = Path(os.environ.get("XDG_CONFIG_HOME", str(self.home / ".config")))
        self.data = Path(os.environ.get("XDG_DATA_HOME", str(self.home / ".local/share")))
        self.state = Path(os.environ.get("XDG_STATE_HOME", str(self.home / ".local/state")))
        self.bin = self.home / ".local/bin"
        self.root = self.state / "hyprstack-install"
        self.manifest = self.root / "installed.json"
        self.latest = self.root / "latest.json"
        self.pending = self.root / "pending.json"

    def tree(self, source: Path, destination: Path):
        if not source.exists() and not source.is_symlink():
            raise FileNotFoundError(f"Required source is missing: {source}")
        sources = [source] if source.is_file() or source.is_symlink() else sorted(p for p in source.rglob("*")
                  if (p.is_file() or p.is_symlink()) and "__pycache__" not in p.parts and not p.name.endswith(".pyc"))
        for path in sources:
            target = destination if source.is_file() else destination / path.relative_to(source)
            if path.is_symlink():
                yield File(target, link=os.readlink(path))
            else:
                yield File(target, path.read_bytes(), stat.S_IMODE(path.stat().st_mode))

    def plan(self):
        raise NotImplementedError("A deployment plan is required")

    def should_retire(self, path: Path):
        return True

    @staticmethod
    def fingerprint(path: Path):
        if path.is_symlink(): return "link:" + os.readlink(path)
        if not path.exists(): return "absent"
        if not path.is_file(): raise ValueError(f"Refusing to replace a directory: {path}")
        return "file:" + hashlib.sha256(path.read_bytes()).hexdigest() + ":" + oct(stat.S_IMODE(path.stat().st_mode))

    @staticmethod
    def desired(file: File):
        return "link:" + file.link if file.link is not None else "file:" + hashlib.sha256(file.data).hexdigest() + ":" + oct(file.mode)

    def snapshot(self, path: Path, transaction: Path, index: int):
        if path.is_symlink(): return {"kind": "link", "target": os.readlink(path)}
        if not path.exists(): return {"kind": "absent"}
        if not path.is_file(): raise ValueError(f"Refusing to replace a directory: {path}")
        backup = transaction / "files" / str(index)
        backup.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, backup)
        return {"kind": "file", "backup": str(backup), "mode": stat.S_IMODE(path.stat().st_mode)}

    @staticmethod
    def restore(path: Path, node: dict):
        if path.exists() and not path.is_file() and not path.is_symlink():
            raise ValueError(f"Refusing to remove a directory during rollback: {path}")
        if node["kind"] == "absent":
            path.unlink(missing_ok=True)
            return
        path.parent.mkdir(parents=True, exist_ok=True)
        fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=".hyprstack-restore-")
        os.close(fd)
        try:
            if node["kind"] == "link":
                os.unlink(temporary)
                os.symlink(node["target"], temporary)
            else:
                shutil.copy2(node["backup"], temporary)
                os.chmod(temporary, node["mode"])
            os.replace(temporary, path)
        finally:
            if os.path.lexists(temporary):
                os.unlink(temporary)

    def ensure_parents(self, path: Path, created: list[str]):
        missing = []
        parent = path.parent
        while not parent.exists():
            missing.append(parent); parent = parent.parent
        for parent in reversed(missing):
            parent.mkdir()
            created.append(str(parent))

    @staticmethod
    def remove_empty(created: list[str]):
        for directory in sorted(set(created), key=lambda p: len(Path(p).parts), reverse=True):
            try: Path(directory).rmdir()
            except OSError: pass

    def rollback_journal(self, transaction: Path):
        journal = read_json(transaction / "journal.json")
        if journal is None: raise ValueError("No transaction journal")
        for item in reversed(journal["undo"]):
            self.restore(Path(item["path"]), item["before"])
        self.remove_empty(journal["created_dirs"])
        if journal["previous_ledger"] is None: self.manifest.unlink(missing_ok=True)
        else: atomic_json(self.manifest, journal["previous_ledger"])
        journal["rolled_back"] = True
        atomic_json(transaction / "journal.json", journal)
        self.pending.unlink(missing_ok=True)

    def recover_pending(self, dry_run=False):
        pending = read_json(self.pending)
        if pending:
            if dry_run: raise ValueError("Interrupted transaction exists; run ./update.sh --rollback first")
            print("Recovering interrupted transaction:", pending["transaction"])
            self.rollback_journal(Path(pending["transaction"]))

    def transaction(self, action: str, dry_run=False):
        self.recover_pending(dry_run)
        previous = read_json(self.manifest)
        if action == "uninstall" and not previous:
            print("Hyprstack is not installed."); return
        files = list(self.plan()) if action == "install" else []
        if len({str(f.path) for f in files}) != len(files): raise ValueError("Duplicate installation destination")
        changes = [f for f in files if not (f.preserve and (f.path.exists() or f.path.is_symlink()))
                   and self.fingerprint(f.path) != self.desired(f)]
        destinations = {str(file.path) for file in files}
        retired = {path: owned for path, owned in (previous or {}).get("files", {}).items()
                   if path not in destinations and self.should_retire(Path(path))} if action == "install" else {}
        if dry_run:
            if action == "install":
                for file in changes: print("WRITE", file.path)
                for path in retired: print("RETIRE", path)
                print(f"{len(changes)} files would change; existing files will be backed up to {self.root}/backups/")
            else:
                for path in previous["files"]: print("RESTORE", path)
            return
        if action == "install" and not changes and not retired and previous:
            print("Already up to date; existing preferences preserved."); return
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
        identifier = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
        transaction = self.root / "backups" / identifier
        transaction.mkdir(parents=True, mode=0o700)
        journal = {"action": action, "previous_ledger": previous, "undo": [], "created_dirs": [], "complete": False}
        atomic_json(transaction / "journal.json", journal)
        atomic_json(self.pending, {"transaction": str(transaction)})
        ledger = json.loads(json.dumps(previous)) if previous else {"files": {}, "created_dirs": []}
        try:
            if action == "install":
                for path, owned in retired.items():
                    file = Path(path)
                    before = self.snapshot(file, transaction, len(journal["undo"]))
                    journal["undo"].append({"path": path, "before": before})
                    atomic_json(transaction / "journal.json", journal)
                    self.restore(file, owned["original"])
                    del ledger["files"][path]
                for index, file in enumerate(files):
                    path = str(file.path)
                    if file.preserve and (file.path.exists() or file.path.is_symlink()): continue
                    before = self.snapshot(file.path, transaction, index + len(retired))
                    if path not in ledger["files"]: ledger["files"][path] = {"original": before}
                    if file in changes:
                        journal["undo"].append({"path": path, "before": before})
                        self.ensure_parents(file.path, journal["created_dirs"])
                        atomic_json(transaction / "journal.json", journal)
                        # os.replace replaces a symlink itself, preserving its target.
                        fd, temporary = tempfile.mkstemp(dir=file.path.parent, prefix=".hyprstack-")
                        try:
                            if file.link is not None:
                                os.close(fd); os.unlink(temporary); os.symlink(file.link, temporary)
                            else:
                                with os.fdopen(fd, "wb") as out: out.write(file.data)
                                os.chmod(temporary, file.mode)
                            os.replace(temporary, file.path)
                        finally:
                            if os.path.lexists(temporary): os.unlink(temporary)
                    ledger["files"][path]["installed"] = self.desired(file)
                ledger["created_dirs"] = sorted(set(ledger["created_dirs"] + journal["created_dirs"]))
                atomic_json(self.manifest, ledger)
            else:
                for path, owned in ledger["files"].items():
                    file = Path(path)
                    before = self.snapshot(file, transaction, len(journal["undo"]))
                    journal["undo"].append({"path": path, "before": before})
                    atomic_json(transaction / "journal.json", journal)
                    if self.fingerprint(file) != owned["installed"]:
                        print("Preserved post-install edits in rollback backup:", file)
                    self.restore(file, owned["original"])
                self.remove_empty(ledger["created_dirs"])
                self.manifest.unlink()
            journal["complete"] = True
            atomic_json(transaction / "journal.json", journal)
            atomic_json(self.latest, {"transaction": str(transaction)})
            self.pending.unlink()
        except BaseException:
            self.rollback_journal(transaction)
            raise
        print(f"{action.capitalize()} complete. Backup and rollback journal: {transaction}")
