#!/usr/bin/env python3
"""Checks for bin/cto. Run through tests/run-cto.sh, which supplies CTO_TEST_TMP.

Every check gets fresh HOME directories under that temp dir. The tool under test runs from a copy
of the repository (or CTO_BIN, if set, dropped into the copy), so nothing here touches the real
checkout or the real ~/.claude and ~/.codex.
"""

import contextlib
import importlib.machinery
import importlib.util
import io
import itertools
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import time
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
TMP = Path(os.environ["CTO_TEST_TMP"]).resolve()
START, END = "<!-- cto-office:start -->", "<!-- cto-office:end -->"
CHECKS = []
_ids = itertools.count(1)


def check(fn):
    CHECKS.append(fn)
    return fn


class Fail(Exception):
    pass


def expect(cond, msg="failed"):
    if not cond:
        raise Fail(msg)


# --------------------------------------------------------------------------- workspace

def make_workspace():
    ws = TMP / "repo"
    skip = shutil.ignore_patterns(".git", "dist", "tests", ".notes", "__pycache__", ".DS_Store")
    shutil.copytree(str(ROOT), str(ws), ignore=skip)
    if os.environ.get("CTO_BIN"):
        shutil.copy(os.environ["CTO_BIN"], str(ws / "bin" / "cto"))
        (ws / "bin" / "cto").chmod(0o755)
    return ws


WS = make_workspace()
BIN = WS / "bin" / "cto"
FAKE = TMP / "fakebin"
FAKE.mkdir()
for _name in ("claude", "codex"):
    (FAKE / _name).write_text("#!/bin/sh\necho stub 1.0\n")
    (FAKE / _name).chmod(0o755)
FAKE_PATH = str(FAKE) + os.pathsep + os.environ["PATH"]
os.environ["PATH"] = FAKE_PATH


def tool_path(*tools, git=True):
    """A PATH holding only the named stub tools (and git), to fake a machine without the others."""
    d = TMP / f"path-{next(_ids)}"
    d.mkdir()
    for t in tools:
        (d / t).symlink_to(FAKE / t)
    if git and shutil.which("git"):
        (d / "git").symlink_to(shutil.which("git"))
    return str(d)


def new_home(tag="h"):
    h = TMP / "homes" / f"{tag}-{next(_ids)}"
    h.mkdir(parents=True)
    return h


def cto(home, *args, path=None, bin_=None):
    env = dict(os.environ, HOME=str(home), PATH=path or FAKE_PATH)
    p = subprocess.run([sys.executable, str(bin_ or BIN)] + list(args), cwd=str(home), env=env,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       universal_newlines=True, timeout=180)
    return p.returncode, p.stdout


def synced(home, *args, **kw):
    rc, out = cto(home, "sync", *args, **kw)
    expect(rc == 0, f"sync rc={rc}: {out[-300:]}")
    return out


def load(home, bin_=None):
    """The tool as a module with HOME pointed at `home`, for fault injection."""
    os.environ["HOME"] = str(home)
    ld = importlib.machinery.SourceFileLoader(f"cto_{next(_ids)}", str(bin_ or BIN))
    mod = importlib.util.module_from_spec(importlib.util.spec_from_loader(ld.name, ld))
    ld.exec_module(mod)
    return mod


def call(fn, *a):
    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
            rc = fn(*a)
    except BaseException as e:
        rc = f"EXC {type(e).__name__}"
    return rc, buf.getvalue()


def rd(p):
    return Path(p).read_text()


def wr(p, text):
    p = Path(p)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text)


def tree(d):
    return sorted(str(p) for p in Path(d).rglob("*") if p.is_file() or p.is_symlink())


def dirs_left(home):
    """Directories under a home that hold no file at all. After remove, none the office made may stay."""
    return [str(p) + "/" for p in sorted(Path(home).rglob("*"))
            if p.is_dir() and not p.is_symlink() and not any(q.is_file() or q.is_symlink() for q in p.rglob("*"))]


def office_left(home):
    """Files in a home that remove should have taken, ignoring the backups it keeps."""
    return [p for p in tree(home) if "cto-backup" not in p and "cto-edited" not in p
            and not p.endswith("/.local/bin/cto") and "/.local/" not in p]


@contextlib.contextmanager
def dist_change(rel, append=None, delete=False):
    p = WS / "dist" / rel
    old = p.read_bytes()
    try:
        if delete:
            p.unlink()
        else:
            p.write_bytes(old + append)
        yield
    finally:
        p.write_bytes(old)


def clone(tag):
    d = TMP / f"clone-{tag}-{next(_ids)}"
    shutil.copytree(str(WS), str(d))
    return d


def git_commit_all(repo, msg="v1"):
    subprocess.run("git init -q && git add -A && git -c commit.gpgsign=false -c user.name=t "
                   "-c user.email=t@t commit -qm " + msg, shell=True, cwd=str(repo), check=True,
                   stdout=subprocess.DEVNULL)


def build_dist():
    p = subprocess.run([sys.executable, str(BIN), "build"], cwd=str(WS), stdout=subprocess.PIPE,
                       stderr=subprocess.STDOUT, universal_newlines=True)
    if p.returncode:
        print("build of the workspace failed:\n" + p.stdout)
        sys.exit(2)


# --------------------------------------------------------------------------------- help, build

@check
def cli_help_exits_zero():
    for args in (["--help"], ["-h"], ["help"], ["init", "--help"], ["sync", "--help"],
                 ["remove", "-h"]):
        h = new_home()
        rc, out = cto(h, *args)
        expect(rc == 0 and "Commands:" in out, f"{args}: rc={rc}")
        expect(not (h / ".claude").exists() and not (h / "--help").exists(), f"{args} acted")


@check
def cli_unknown_command_fails():
    expect(cto(new_home(), "nonsense")[0] == 1)


@check
def build_names_missing_meta_keys():
    c = clone("meta")
    m = c / "experts" / "critic" / "meta.yaml"
    m.write_text("".join(l for l in m.read_text().splitlines(True) if not l.startswith("codex_effort")))
    rc, out = cto(new_home(), "build", bin_=c / "bin" / "cto")
    expect(rc != 0 and "missing required key" in out and "codex_effort" in out and "Traceback" not in out, out[-200:])


@check
def build_rejects_unknown_coordinator():
    c = clone("coord")
    shutil.copytree(str(c / "coordinators" / "head-of-product"), str(c / "coordinators" / "head-of-design"))
    rc, out = cto(new_home(), "build", bin_=c / "bin" / "cto")
    expect(rc != 0 and "COORD_SHORT" in out, out[-200:])


@check
def build_truncates_descriptions_at_a_word():
    for meta in sorted((WS / "experts").glob("*/meta.yaml")):
        desc = re.search(r"^description:\s*(.*)$", meta.read_text(), re.M).group(1).strip("\"'")
        y = (WS / "dist" / "codex" / "skills" / meta.parent.name / "agents" / "openai.yaml").read_text()
        short = json.loads(re.search(r"short_description:\s*(\".*\")", y).group(1))
        expect(desc.startswith(short) and (short == desc or desc[len(short)] in " ,;:-"),
               f"{meta.parent.name}: {short!r}")


@check
def build_copies_skills_and_skips_junk():
    c = clone("skills")
    (c / "skills" / "demo" / "sub").mkdir(parents=True)
    wr(c / "skills" / "demo" / "SKILL.md", "---\nname: demo\n---\n")
    wr(c / "skills" / "demo" / "sub" / "x.txt", "x")
    for junk in (".DS_Store", "._SKILL.md", "notes.md~", "Thumbs.db", "desktop.ini"):
        wr(c / "skills" / "demo" / junk, "junk")
    rc, out = cto(new_home(), "build", bin_=c / "bin" / "cto")
    expect(rc == 0, out)
    for tool in ("claude", "codex"):
        d = c / "dist" / tool / "skills" / "demo"
        expect(rd(d / "SKILL.md").startswith("---") and (d / "sub" / "x.txt").exists(), tool)
        expect(sorted(p.name for p in d.rglob("*") if p.is_file()) == ["SKILL.md", "x.txt"], str(tree(d)))


@check
def build_works_without_a_skills_directory():
    c = clone("noskills")
    shutil.rmtree(str(c / "skills"), ignore_errors=True)
    rc, out = cto(new_home(), "build", bin_=c / "bin" / "cto")
    expect(rc == 0, out)


@check
def build_rejects_skill_named_like_an_expert():
    c = clone("collide")
    (c / "skills" / "critic").mkdir(parents=True)
    wr(c / "skills" / "critic" / "SKILL.md", "x")
    rc, out = cto(new_home(), "build", bin_=c / "bin" / "cto")
    expect(rc != 0 and "collides" in out, out[-200:])


@check
def tool_compiles_on_this_python():
    compile(BIN.read_text(), str(BIN), "exec")


# ---------------------------------------------------------------------------------- sync basics

@check
def sync_installs_and_status_is_clean():
    h = new_home()
    out = synced(h)
    expect(cto(h, "status")[0] == 0, "status not clean")
    m = json.loads(rd(h / ".claude" / ".os-manifest.json"))
    expect(m.get("format") == 2 and m["entries"], "manifest is not format 2")
    expect(not [p for p in tree(h) if "pre-cto-office" in p], "backup-style files created")
    expect(rd(h / ".claude" / "commands" / "hoe.md") == rd(WS / "dist/claude/commands/hoe.md"))
    expect("(0 written)" in cto(h, "sync")[1], "second sync wrote files")


@check
def sync_updates_unedited_files():
    h = new_home()
    synced(h)
    with dist_change("claude/commands/hoe.md", b"\n# new release\n"):
        synced(h)
        expect("new release" in rd(h / ".claude/commands/hoe.md"))


@check
def sync_blocks_on_edited_file_and_force_saves_a_copy():
    h = new_home()
    synced(h)
    f = h / ".claude/commands/hoe.md"
    f.write_text(rd(f) + "\nMY EDIT\n")
    with dist_change("claude/commands/hoe.md", b"\n# new release\n"):
        rc, out = cto(h, "sync")
        expect(rc == 1 and "MY EDIT" in rd(f) and "--force" in out, f"rc={rc}")
        rc, out = cto(h, "sync", "--force")
        side = list((h / ".claude/commands").glob("hoe.md.cto-edited-*"))
        expect(rc == 0 and "MY EDIT" not in rd(f) and len(side) == 1 and "MY EDIT" in side[0].read_text(), out[-200:])


@check
def sync_refuses_a_foreign_file_and_writes_nothing():
    h = new_home()
    wr(h / ".claude/commands/hoe.md", "mine\n")
    rc, out = cto(h, "sync")
    expect(rc == 1 and "move it aside" in out, out[-200:])
    expect(rd(h / ".claude/commands/hoe.md") == "mine\n" and not (h / ".claude/agents").exists(), "wrote")
    expect(not list((h / ".claude/commands").glob("hoe.md.*")), "made a backup")
    rc, out = cto(h, "remove", "--yes")
    expect(rd(h / ".claude/commands/hoe.md") == "mine\n", "remove touched it")


@check
def status_names_foreign_files():
    h = new_home()
    wr(h / ".claude/commands/hoe.md", "mine\n")
    rc, out = cto(h, "status", "--claude")
    expect(rc == 1 and "foreign" in out and "move each aside" in out.lower() and "drifted" not in out, out)


@check
def sync_claims_an_identical_file_without_a_backup():
    h = new_home()
    wr(h / ".claude/commands/hoe.md", rd(WS / "dist/claude/commands/hoe.md"))
    synced(h)
    expect(not list((h / ".claude/commands").glob("*.pre-cto-office")) and cto(h, "status")[0] == 0)


@check
def sync_removes_stale_unedited_and_keeps_stale_edited():
    h = new_home()
    synced(h)
    wr(h / ".claude/commands/hoe.md", rd(h / ".claude/commands/hoe.md") + "MINE\n")
    with dist_change("claude/protocols/report.schema.json", delete=True):
        with dist_change("claude/commands/hoe.md", delete=True):
            rc, out = cto(h, "sync")
    expect(rc == 0, out[-200:])
    expect(not (h / ".claude/protocols/report.schema.json").exists(), "stale file kept")
    expect("MINE" in rd(h / ".claude/commands/hoe.md") and "kept your edited" in out, out[-300:])
    expect("commands/hoe.md" not in rd(h / ".claude/.os-manifest.json"), "entry not dropped")


@check
def sync_ignores_unsafe_manifest_entries():
    h = new_home()
    wr(h / "Documents/x", "precious\n")
    wr(h / ".claude/.os-manifest.json", json.dumps(
        {"version": "1", "repo": "x", "files": ["../Documents/x", "/etc/hosts", "a/../../Documents/x"],
         "adopted": []}))
    cto(h, "sync")
    cto(h, "remove", "--yes")
    expect(rd(h / "Documents/x") == "precious\n")


@check
def legacy_adopted_list_is_refused_with_instructions():
    h = new_home()
    wr(h / ".claude/.os-manifest.json", json.dumps(
        {"version": "1", "repo": "x", "files": ["CLAUDE.md"], "adopted": ["CLAUDE.md"]}))
    rc1, o1 = cto(h, "sync")
    rc2, o2 = cto(h, "remove", "--yes")
    expect(rc1 == 1 and rc2 == 1 and "by hand" in o1 and "by hand" in o2, o1 + o2)


@check
def unreadable_manifest_is_refused_everywhere():
    h = new_home()
    synced(h)
    wr(h / ".claude/.os-manifest.json", "{")
    expect(cto(h, "sync")[0] == 1, "sync")
    rc, out = cto(h, "status")
    expect(rc == 1 and "clean." not in out, "status")
    expect(cto(h, "remove", "--yes")[0] == 1, "remove")


@check
def status_reports_missing_and_obsolete_entries():
    h = new_home()
    synced(h)
    (h / ".claude/commands/hoe.md").unlink()
    rc, out = cto(h, "status")
    expect(rc == 1 and "missing" in out, out)
    synced(h)
    p = h / ".claude/.os-manifest.json"
    m = json.loads(rd(p))
    m["entries"]["agents/gone.md"] = {"kind": "file", "hash": None}
    wr(p, json.dumps(m))
    rc, out = cto(h, "status")
    expect(rc == 1 and "obsolete" in out and "clean." not in out, out)


@check
def status_reports_a_deleted_manifest_over_installed_files():
    for tool_args in (["--claude"], ["--codex"]):
        h = new_home()
        synced(h, *tool_args)
        home = h / (".claude" if tool_args == ["--claude"] else ".codex")
        (home / ".os-manifest.json").unlink()
        rc, out = cto(h, "status", *tool_args)
        expect(rc == 1 and "clean." not in out and "ownership" in out, f"{tool_args}: rc={rc} {out[-200:]}")
        expect(cto(h, "sync", *tool_args)[0] == 0 and cto(h, "status", *tool_args)[0] == 0, "sync does not repair it")
    h = new_home()
    expect(cto(h, "status", "--claude")[0] == 1, "an empty home is missing files, not clean")


@check
def sync_rejects_unknown_options():
    expect(cto(new_home(), "sync", "--bogus")[0] == 1)


@check
def sync_leaves_user_files_at_old_temp_names():
    h = new_home()
    wr(h / ".claude/commands/.hoe.md.cto-tmp", "user\n")
    wr(h / ".claude/.CLAUDE.md.cto-tmp", "user\n")
    synced(h)
    expect(rd(h / ".claude/commands/.hoe.md.cto-tmp") == "user\n" and rd(h / ".claude/.CLAUDE.md.cto-tmp") == "user\n")


@check
def sync_leaves_no_temp_file_after_a_failed_rename():
    for k in (1, 2, 7):
        h = new_home()
        m = load(h)
        real, n = os.rename, [0]

        def rn(*a, **kw):
            n[0] += 1
            if n[0] == k:
                raise OSError(5, "injected")
            return real(*a, **kw)
        os.rename = rn
        try:
            call(m.sync, ["--claude"])
        finally:
            os.rename = real
        expect(not [p for p in tree(h) if p.endswith(".cto-tmp")], f"k={k}: temp left")
        expect(call(m.sync, ["--claude"])[0] == 0 and call(m.status, ["--claude"])[0] == 0, f"k={k}: no converge")


# ----------------------------------------------------------------------------------- remove

@check
def remove_deletes_everything_it_made_and_only_that():
    h = new_home()
    wr(h / ".claude/skills/keep.txt", "k")             # pre-existing directory with user content
    (h / ".codex").mkdir()
    synced(h)
    expect(cto(h, "remove", "--yes")[0] == 0)
    expect(not office_left(h / ".claude") or office_left(h / ".claude") == [str(h / ".claude/skills/keep.txt")],
           str(office_left(h / ".claude")))
    expect(not office_left(h / ".codex"), str(office_left(h / ".codex")))
    for d in ("agents", "commands", "protocols"):
        expect(not (h / ".claude" / d).exists(), f"{d} not pruned")


@check
def remove_keeps_a_preexisting_empty_directory():
    h = new_home()
    (h / ".claude/skills").mkdir(parents=True)
    synced(h, "--claude")
    expect(cto(h, "remove", "--yes")[0] == 0)
    expect((h / ".claude/skills").is_dir(), "pruned a directory it did not create")
    expect(not (h / ".claude/agents").exists(), "did not prune a directory it created")


@check
def remove_keeps_edited_files():
    h = new_home()
    synced(h)
    f = h / ".claude/commands/hoe.md"
    f.write_text(rd(f) + "MINE\n")
    rc, out = cto(h, "remove", "--yes")
    expect(rc == 0 and "MINE" in rd(f) and not (h / ".claude/agents").exists(), out[-300:])


@check
def remove_reports_failures_and_keeps_the_manifest():
    if os.geteuid() == 0:
        return
    h = new_home()
    synced(h)
    os.chmod(str(h / ".claude/agents"), 0o555)
    try:
        rc, out = cto(h, "remove", "--yes")
    finally:
        os.chmod(str(h / ".claude/agents"), 0o755)
    expect(rc == 1 and (h / ".claude/.os-manifest.json").exists(), f"rc={rc}")
    expect(cto(h, "remove", "--yes")[0] == 0, "second pass")


@check
def remove_finishes_after_an_interrupted_manifest_unlink():
    for after in (False, True):
        h = new_home()
        synced(h, "--claude")
        m = load(h)
        real = m.fs_unlink

        def boom(home, rel, ok, _real=real, _after=after):
            if rel == m.MANIFEST:
                if not _after:
                    raise KeyboardInterrupt
                _real(home, rel, ok)
                raise KeyboardInterrupt
            return _real(home, rel, ok)
        m.fs_unlink = boom
        call(m.remove, ["--yes"])
        rc, out = cto(h, "remove", "--yes")
        expect(rc == 0 and not (h / ".claude/.os-manifest.json").exists(), out[-200:])
        expect(not dirs_left(h / ".claude"), f"after={after}: directories left {dirs_left(h / '.claude')}")


@check
def remove_with_no_manifest_says_so():
    rc, out = cto(new_home(), "remove", "--yes")
    expect(rc == 0 and "nothing installed" in out)


# ----------------------------------------------------------------------------------- symlinks

@check
def sync_refuses_a_symlinked_destination():
    h = new_home()
    wr(h / "dot/CLAUDE.md", "mine\n")
    (h / ".claude/commands").mkdir(parents=True)
    (h / ".claude/commands/hoe.md").symlink_to(h / "dot/CLAUDE.md")
    rc, out = cto(h, "sync", "--claude")
    expect(rc == 1 and rd(h / "dot/CLAUDE.md") == "mine\n" and not (h / ".claude/agents").exists(), out[-200:])


@check
def sync_and_remove_refuse_a_symlinked_parent():
    h = new_home()
    (h / "outside").mkdir()
    (h / ".claude").mkdir()
    (h / ".claude/agents").symlink_to(h / "outside")
    rc, out = cto(h, "sync", "--claude")
    expect(rc == 1 and not tree(h / "outside"), out[-200:])
    h2 = new_home()
    (h2 / "outside").mkdir()
    synced(h2, "--claude")
    shutil.rmtree(str(h2 / ".claude/commands"))
    (h2 / ".claude/commands").symlink_to(h2 / "outside")
    rc, out = cto(h2, "remove", "--yes")
    expect(rc == 1 and not tree(h2 / "outside") and (h2 / ".claude/commands").is_symlink(), out[-200:])


@check
def symlinked_home_works():
    h = new_home()
    (h / "real").mkdir()
    (h / ".claude").symlink_to(h / "real")
    synced(h, "--claude")
    expect(cto(h, "status", "--claude")[0] == 0 and (h / "real/commands/hoe.md").exists())
    expect(cto(h, "remove", "--yes")[0] == 0 and (h / ".claude").is_symlink())
    expect(not [p for p in tree(h / "real") if "cto-backup" not in p], str(tree(h / "real")))


@check
def swapping_a_parent_for_a_symlink_never_writes_outside():
    for where in ("after-plan", "after-walk"):
        h = new_home()
        (h / "outside").mkdir()
        synced(h, "--claude")
        m = load(h)
        swap = lambda: (os.rename(str(h / ".claude/agents"), str(h / ".claude/agents.moved")),
                        os.symlink(str(h / "outside"), str(h / ".claude/agents")))
        done = []
        if where == "after-plan":
            real = m.save_manifest

            def hook(*a, **k):
                if not done:
                    done.append(1)
                    swap()
                return real(*a, **k)
            m.save_manifest = hook
        else:
            real = m.open_parent

            def hook(home, rel, create=False):
                fd = real(home, rel, create)
                if rel.startswith("agents/") and not done:
                    done.append(1)
                    swap()
                return fd
            m.open_parent = hook
        with dist_change("claude/agents/critic.md", b"\n# r2\n"):
            rc, out = call(m.sync, ["--claude"])
        expect(not tree(h / "outside"), f"{where}: wrote outside: {tree(h / 'outside')}")
        expect(rc == 1, f"{where}: rc={rc}")


@check
def a_home_swapped_for_a_symlink_never_redirects_writes():
    h = new_home()
    (h / "outside").mkdir()
    (h / ".claude").mkdir()
    m = load(h)
    os.rename(str(h / ".claude"), str(h / ".claude.moved"))
    (h / ".claude").symlink_to(h / "outside")
    rc, out = call(m.sync, ["--claude"])
    expect(rc != 0 and not tree(h / "outside"), f"rc={rc}")
    h2 = new_home()
    (h2 / "outside").mkdir()
    synced(h2, "--claude")
    m = load(h2)
    real, done = m.save_manifest, []

    def hook(*a, **k):
        if not done:
            done.append(1)
            os.rename(str(h2 / ".claude"), str(h2 / ".claude.moved"))
            (h2 / ".claude").symlink_to(h2 / "outside")
        return real(*a, **k)
    m.save_manifest = hook
    with dist_change("claude/commands/hoe.md", b"\n# r2\n"):
        call(m.sync, ["--claude"])
    expect(not tree(h2 / "outside"), "mid-sync swap redirected writes")


@check
def an_edit_between_plan_and_write_is_kept():
    h = new_home()
    synced(h, "--claude")
    m = load(h)
    real, done = m.save_manifest, []

    def hook(*a, **k):
        if not done:
            done.append(1)
            wr(h / ".claude/commands/hoe.md", "RACED\n")
        return real(*a, **k)
    m.save_manifest = hook
    with dist_change("claude/commands/hoe.md", b"\n# r2\n"):
        rc, out = call(m.sync, ["--claude"])
    expect(rc == 1 and rd(h / ".claude/commands/hoe.md") == "RACED\n", f"rc={rc}")


# ------------------------------------------------------------------------------- fault sweeps

MUT = ["fs_write", "fs_unlink", "fs_copy_aside", "fs_rmdir"]


class Boom(KeyboardInterrupt):
    pass


class OsShim:
    """Stands in for `os` inside the tool, so os.mkdir can be counted without patching the harness."""

    def __init__(self, real, hook):
        self._real, self._hook = real, hook

    def __getattr__(self, name):
        return getattr(self._real, name)

    def mkdir(self, *a, **kw):
        return self._hook(self._real.mkdir, a, kw)


def snapshot(m):
    saved = {n: getattr(m, n) for n in MUT}
    saved["_os"] = m.os
    return saved


def inject(m, k, after=False):
    """Raise on the k-th filesystem mutation: before it runs, or (after=True) once it has completed."""
    cnt = [0]

    def run(real, a, kw):
        cnt[0] += 1
        hit = k is not None and cnt[0] == k
        if hit and not after:
            raise Boom()
        result = real(*a, **kw)
        if hit:
            raise Boom()
        return result
    for name in MUT:
        def wrap(*a, _real=getattr(m, name), **kw):
            return run(_real, a, kw)
        setattr(m, name, wrap)
    m.os = OsShim(m.os, run)
    return cnt


def uninject(m, saved):
    for name in MUT:
        setattr(m, name, saved[name])
    m.os = saved["_os"]


def sweep_scenario(user, seq, edit=False, after=False):
    h = new_home("f")
    m = load(h)
    saved = snapshot(m)
    (h / ".claude").mkdir()
    if user is not None:
        (h / ".claude/CLAUDE.md").write_bytes(user)
    for k in seq:
        inject(m, k, after)
        call(m.sync, ["--claude"])
        uninject(m, saved)
    edited = None
    if edit and (h / ".claude/commands/hoe.md").exists():
        edited = h / ".claude/commands/hoe.md"
        edited.write_text(rd(edited) + "\nUSER EDIT\n")
    call(m.sync, ["--claude"])
    if edited:
        side = [p for p in tree(h) if "hoe.md.cto-edited" in p]
        expect("USER EDIT" in rd(edited) or any("USER EDIT" in rd(p) for p in side), "edit lost")
        call(m.sync, ["--claude", "--force"])
    r2 = call(m.sync, ["--claude"])[0]
    st = call(m.status, ["--claude"])[0]
    rr = call(m.remove, ["--yes"])[0]
    cl = h / ".claude/CLAUDE.md"
    user_ok = (not cl.exists()) if user is None else (cl.exists() and cl.read_bytes() == user)
    left = [p for p in office_left(h / ".claude") if not p.endswith("/CLAUDE.md")] + dirs_left(h / ".claude")
    return r2 == 0 and st == 0 and rr == 0 and not left and user_ok, (r2, st, rr, left[:2], user_ok)


def first_sync_mutations():
    h = new_home()
    (h / ".claude").mkdir()
    (h / ".claude/CLAUDE.md").write_text("U\n")
    m = load(h)
    cnt = inject(m, None)
    call(m.sync, ["--claude"])
    return cnt[0]


@check
def fault_sweep_single_interruption():
    n, bad = first_sync_mutations(), []
    expect(n > 20, f"only {n} mutations counted")
    for user, after in itertools.product((None, b"USER RULES\n", b"no trailing newline"), (False, True)):
        for k in range(1, n + 1):
            ok, why = sweep_scenario(user, [k], after=after)
            if not ok:
                bad.append((user, k, after, why))
    expect(not bad, f"{len(bad)} failures, first {bad[:1]}")


@check
def fault_sweep_repeated_interruption():
    n, bad = first_sync_mutations(), []
    for after in (False, True):
        for k in range(1, n + 1, 3):
            for j in (1, 2, 5, 40, 90):
                ok, why = sweep_scenario(b"USER RULES\n", [k, j], after=after)
                if not ok:
                    bad.append((k, j, after, why))
    expect(not bad, f"{len(bad)} failures, first {bad[:1]}")


@check
def fault_sweep_edit_between_interruption_and_rerun():
    n, bad = first_sync_mutations(), []
    for after, k in itertools.product((False, True), range(1, n + 1)):
        try:
            ok, why = sweep_scenario(b"USER RULES\n", [k], edit=True, after=after)
        except Fail as e:
            ok, why = False, str(e)
        if not ok:
            bad.append((k, after, why))
    expect(not bad, f"{len(bad)} failures, first {bad[:1]}")


@check
def fault_sweep_interrupted_remove():
    h = new_home()
    (h / ".claude").mkdir()
    synced(h, "--claude")
    m = load(h)
    cnt = inject(m, None)
    call(m.remove, ["--yes"])
    n, bad = cnt[0], []
    for after, k in itertools.product((False, True), range(1, n + 1)):
        h = new_home("fr")
        m = load(h)
        saved = snapshot(m)
        wr(h / ".claude/CLAUDE.md", "USER\n")
        call(m.sync, ["--claude"])
        inject(m, k, after)
        call(m.remove, ["--yes"])
        uninject(m, saved)
        # whatever state the interruption left, the next remove must finish the job on its own
        r1 = call(m.remove, ["--yes"])[0]
        left1 = [p for p in office_left(h / ".claude") if not p.endswith("/CLAUDE.md")] + dirs_left(h / ".claude")
        r2 = call(m.sync, ["--claude"])[0]
        r3 = call(m.remove, ["--yes"])[0]
        left = [p for p in office_left(h / ".claude") if not p.endswith("/CLAUDE.md")] + dirs_left(h / ".claude")
        if not (r1 == 0 and not left1 and r2 == 0 and r3 == 0 and not left
                and rd(h / ".claude/CLAUDE.md") == "USER\n"):
            bad.append((k, after, r1, left1[:2], r2, r3, left[:2]))
    expect(n > 20 and not bad, f"{len(bad)} failures of {n}, first {bad[:1]}")


# ------------------------------------------------------------------------------------- legacy

def legacy_install(home, tools=("claude",), whole_file=True, drop=None):
    """A format-1 install of an older release: committed dist copied into the home, plus the
    manifest that release wrote. Returns the repository the new tool runs from."""
    repo = clone("legacy")
    shutil.rmtree(str(repo / "dist"), ignore_errors=True)
    subprocess.run([sys.executable, str(repo / "bin/cto"), "build"], cwd=str(repo), check=True,
                   stdout=subprocess.DEVNULL)
    git_commit_all(repo)
    for tool in tools:
        hd = home / f".{tool}"
        files = []
        for f in sorted((repo / "dist" / tool).rglob("*")):
            if f.is_file():
                rel = f.relative_to(repo / "dist" / tool).as_posix()
                if rel == drop:
                    files.append(rel)
                    continue
                (hd / rel).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(str(f), str(hd / rel))
                files.append(rel)
        wr(hd / ".os-manifest.json", json.dumps(
            {"version": "1", "repo": str(repo), "files": files, "adopted": []}, indent=2))
    # the "new release": a changed file in the working tree, not committed
    with open(str(repo / "dist/claude/commands/hoe.md"), "a") as fh:
        fh.write("\n# new release\n")
    return repo


@check
def legacy_install_upgrades_without_force():
    h = new_home()
    repo = legacy_install(h, ("claude", "codex"))
    rc, out = cto(h, "sync", bin_=repo / "bin/cto")
    expect(rc == 0, out[-400:])
    expect("new release" in rd(h / ".claude/commands/hoe.md"), "update not written")
    expect(json.loads(rd(h / ".claude/.os-manifest.json"))["format"] == 2, "manifest not rewritten")
    expect(rd(h / ".claude/CLAUDE.md").startswith(START) and rd(h / ".codex/AGENTS.md").startswith(START),
           "whole files not converted")
    expect(list((h / ".claude").glob("CLAUDE.md.cto-backup-*")), "no backup of the whole file")
    expect(cto(h, "status", bin_=repo / "bin/cto")[0] == 0, "status not clean")
    rc, out = cto(h, "remove", "--yes", bin_=repo / "bin/cto")
    expect(rc == 0 and not office_left(h / ".claude") and not office_left(h / ".codex"), out[-300:])


@check
def legacy_edited_whole_file_needs_force():
    h = new_home()
    repo = legacy_install(h)
    with open(str(h / ".claude/CLAUDE.md"), "a") as fh:
        fh.write("MY MEMORY\n")
    rc, out = cto(h, "sync", bin_=repo / "bin/cto")
    expect(rc == 1 and "MY MEMORY" in rd(h / ".claude/CLAUDE.md"), out[-300:])
    rc, out = cto(h, "sync", "--force", bin_=repo / "bin/cto")
    backups = list((h / ".claude").glob("CLAUDE.md.cto-backup-*"))
    expect(rc == 0 and "MY MEMORY" not in rd(h / ".claude/CLAUDE.md") and
           any("MY MEMORY" in b.read_text() for b in backups), out[-300:])


@check
def legacy_edited_regular_file_is_blocked_and_a_deleted_whole_file_is_not():
    h = new_home()
    repo = legacy_install(h)
    with open(str(h / ".claude/agents/critic.md"), "a") as fh:
        fh.write("MINE\n")
    rc, out = cto(h, "sync", bin_=repo / "bin/cto")
    expect(rc == 1 and "MINE" in rd(h / ".claude/agents/critic.md"), out[-300:])
    h2 = new_home()
    repo2 = legacy_install(h2)
    (h2 / ".claude/CLAUDE.md").unlink()
    rc, out = cto(h2, "sync", bin_=repo2 / "bin/cto")
    expect(rc == 0 and START in rd(h2 / ".claude/CLAUDE.md"), out[-300:])
    expect(cto(h2, "remove", "--yes", bin_=repo2 / "bin/cto")[0] == 0 and not office_left(h2 / ".claude"))


@check
def legacy_without_git_history_is_treated_as_edited_and_says_why():
    h = new_home()
    repo = legacy_install(h)
    rc, out = cto(h, "sync", path=tool_path("claude", git=False), bin_=repo / "bin/cto")
    expect(rc == 1 and "git history" in out, out[-300:])


@check
def legacy_migration_interrupted_at_every_mutation_still_converges():
    h = new_home()
    repo = legacy_install(h)
    m = load(h, repo / "bin/cto")
    cnt = inject(m, None)
    call(m.sync, ["--claude"])
    n = cnt[0]
    expect(n >= 3, f"only {n} mutations")
    for k, after, then_sync in itertools.product(range(1, n + 1), (False, True), (False, True)):
        if True:
            hh = new_home("lm")
            r = legacy_install(hh)
            mm = load(hh, r / "bin/cto")
            saved = snapshot(mm)
            inject(mm, k, after)
            call(mm.sync, ["--claude"])
            uninject(mm, saved)
            if then_sync:
                a, b = call(mm.sync, ["--claude"])[0], call(mm.status, ["--claude"])[0]
                expect(a == 0 and b == 0, f"k={k} after={after}: re-sync {a} status {b}")
            rr = call(mm.remove, ["--yes"])[0]
            left = office_left(hh / ".claude")
            expect(rr == 0 and not left, f"k={k} after={after} resync={then_sync}: remove rc={rr} left {left[:2]}")


# -------------------------------------------------------------------------------------- blocks

@check
def block_is_appended_kept_and_forced_without_touching_user_text():
    h = new_home()
    wr(h / ".claude/CLAUDE.md", "USER RULES\n")
    out = synced(h, "--claude")
    f = h / ".claude/CLAUDE.md"
    expect(rd(f).startswith("USER RULES\n\n" + START) and rd(f).count(START) == 1 and "both sets" in out)
    backups = list((h / ".claude").glob("CLAUDE.md.cto-backup-*"))
    expect(len(backups) == 1 and backups[0].read_text() == "USER RULES\n", "backup")
    before = f.read_bytes()
    synced(h, "--claude")
    expect(f.read_bytes() == before and len(list((h / ".claude").glob("CLAUDE.md.cto-backup-*"))) == 1,
           "second sync changed something")
    f.write_text(rd(f) + "MORE\n")
    expect(cto(h, "sync", "--claude")[0] == 0 and "MORE" in rd(f), "edit outside the block is not drift")
    f.write_text(rd(f).replace(START + "\n", START + "\nINSIDE\n", 1))
    rc, out = cto(h, "sync", "--claude")
    expect(rc == 1 and "INSIDE" in rd(f), "edit inside should block")
    expect(cto(h, "sync", "--claude", "--force")[0] == 0 and "INSIDE" not in rd(f) and "MORE" in rd(f))
    expect(cto(h, "status", "--claude")[0] == 0)


@check
def malformed_markers_are_refused_naming_the_file():
    for body in (f"x\n{START}\n", f"{END}\n{START}\n", f"user {START}\n", f"{START}\n{END}\n{START}\n{END}\n"):
        h = new_home()
        wr(h / ".claude/CLAUDE.md", body)
        rc, out = cto(h, "sync", "--claude")
        expect(rc == 1 and "CLAUDE.md" in out and not (h / ".claude/agents").exists(), repr(body))
        expect(rd(h / ".claude/CLAUDE.md") == body, "modified")


@check
def block_removal_restores_the_users_exact_bytes():
    for body in ("user text", "a\n", "a\n\nb\n", " ", "\n\n", "  \n", "x\n\n\n"):
        h = new_home()
        wr(h / ".claude/CLAUDE.md", body)
        synced(h, "--claude")
        expect(cto(h, "remove", "--yes")[0] == 0, repr(body))
        expect((h / ".claude/CLAUDE.md").read_bytes() == body.encode(), f"{body!r}")
    h = new_home()
    wr(h / ".claude/CLAUDE.md", "")
    synced(h, "--claude")
    cto(h, "remove", "--yes")
    expect(not (h / ".claude/CLAUDE.md").exists(), "zero-length remainder should delete the file")


@check
def a_missing_instruction_file_is_created_and_removed():
    h = new_home()
    synced(h, "--claude")
    expect(rd(h / ".claude/CLAUDE.md").startswith(START))
    cto(h, "remove", "--yes")
    expect(not (h / ".claude/CLAUDE.md").exists())


@check
def a_stale_block_is_stripped_when_unedited_and_kept_when_edited():
    h = new_home()
    wr(h / ".claude/CLAUDE.md", "USER TOP\nuser line")
    synced(h, "--claude")
    with dist_change("claude/CLAUDE.md", delete=True):
        rc, out = cto(h, "sync", "--claude")
    expect(rc == 0 and (h / ".claude/CLAUDE.md").read_bytes() == b"USER TOP\nuser line", out[-300:])
    expect(list((h / ".claude").glob("CLAUDE.md.cto-backup-*")), "no backup")
    h2 = new_home()
    wr(h2 / ".claude/CLAUDE.md", "USER TOP\n")
    synced(h2, "--claude")
    f = h2 / ".claude/CLAUDE.md"
    f.write_text(rd(f).replace(START + "\n", START + "\nMY EDIT\n", 1))
    with dist_change("claude/CLAUDE.md", delete=True):
        rc, out = cto(h2, "sync", "--claude")
    expect(rc == 0 and "MY EDIT" in rd(f) and "kept your edited" in out, out[-300:])


@check
def only_the_five_newest_backups_are_kept():
    h = new_home()
    wr(h / ".claude/CLAUDE.md", "USER\n")
    synced(h, "--claude")
    d = h / ".claude"
    for i in range(1, 8):
        (d / f"CLAUDE.md.cto-backup-2020010{i}-000000").write_text("old")
    decoys = ["CLAUDE.md.cto-backup-notes", "CLAUDE.md.cto-backup-20200101-000000.keep", "other.cto-backup-20200101-000000"]
    for n in decoys:
        (d / n).write_text("mine")
    with dist_change("claude/CLAUDE.md", b"\nextra line\n"):
        rc, out = cto(h, "sync", "--claude")
    names = sorted(p.name for p in d.glob("CLAUDE.md.cto-backup-*")
                   if re.fullmatch(r"CLAUDE\.md\.cto-backup-\d{8}-\d{6}(-\d+)?", p.name))
    expect(rc == 0 and len(names) == 5, f"{len(names)} kept: {names}")
    expect(all((d / n).exists() for n in decoys), "deleted a name the office did not create")
    expect("deleted" in out and "newest" in out, out[-300:])
    expect(not (d / "CLAUDE.md.cto-backup-20200101-000000").exists(), "oldest kept")


# -------------------------------------------------------------------------------------- tools

@check
def claude_only_machine_gets_no_codex_home():
    h = new_home()
    p = tool_path("claude")
    rc, out = cto(h, "sync", path=p)
    expect(rc == 0 and (h / ".claude").is_dir() and not (h / ".codex").exists(), out[-200:])
    expect(cto(h, "status", path=p)[0] == 0)
    rc, out = cto(h, "doctor", path=p + os.pathsep + str(h / ".local/bin"))
    expect(rc == 0 and "healthy" in out, out)


@check
def codex_only_machine_gets_no_claude_home():
    h = new_home()
    p = tool_path("codex")
    rc, out = cto(h, "sync", path=p)
    expect(rc == 0 and (h / ".codex").is_dir() and not (h / ".claude").exists(), out[-200:])
    rc, out = cto(h, "doctor", path=p + os.pathsep + str(h / ".local/bin"))
    expect(rc == 0 and "healthy" in out, out)


@check
def no_tool_at_all_is_an_error_and_a_flag_forces_one():
    h = new_home()
    p = tool_path()
    rc, out = cto(h, "sync", path=p)
    expect(rc == 1 and not (h / ".claude").exists() and not (h / ".codex").exists(), out)
    rc, out = cto(h, "sync", "--codex", path=p)
    expect(rc == 0 and (h / ".codex").is_dir() and not (h / ".claude").exists(), out[-200:])


@check
def doctor_flags_missing_targets_and_vanished_tools():
    h = new_home()
    p = tool_path("claude", "codex") + os.pathsep + str(h / ".local/bin")
    synced(h)
    shutil.rmtree(str(h / ".codex/protocols"))
    rc, out = cto(h, "doctor", path=p)
    expect(rc == 1 and "protocols" in out, out)
    h2 = new_home()
    synced(h2, "--claude")
    shutil.rmtree(str(h2 / ".claude/skills"))
    rc, out = cto(h2, "doctor", path=tool_path("claude") + os.pathsep + str(h2 / ".local/bin"))
    expect(rc == 1 and "skills" in out, out)
    h3 = new_home()
    synced(h3, "--claude")
    rc, out = cto(h3, "doctor", path=tool_path() + os.pathsep + str(h3 / ".local/bin"))
    expect(rc == 1 and "office install" in out, out)


@check
def doctor_checks_git_and_reports_gh_as_a_warning():
    h = new_home()
    p = tool_path("claude")                                  # git present, gh absent
    synced(h, "--claude", path=p)
    rc, out = cto(h, "doctor", path=p + os.pathsep + str(h / ".local/bin"))
    expect(rc == 0 and "git" in out and "gh" in out and "warning" in out.lower() and "healthy" in out, out)
    p2 = tool_path("claude", git=False)                      # no git: a problem
    rc, out = cto(h, "doctor", path=p2 + os.pathsep + str(h / ".local/bin"))
    expect(rc == 1 and "MISS  git" in out, out)
    if shutil.which("gh") is None:                           # gh present but not authenticated: a warning
        d = TMP / f"path-{next(_ids)}"
        d.mkdir()
        (d / "gh").write_text("#!/bin/sh\nexit 1\n")
        (d / "gh").chmod(0o755)
        (d / "claude").symlink_to(FAKE / "claude")
        (d / "git").symlink_to(shutil.which("git"))
        rc, out = cto(h, "doctor", path=str(d) + os.pathsep + str(h / ".local/bin"))
        expect(rc == 0 and "not authenticated" in out, out)


@check
def notes_live_in_the_repository_and_old_ones_get_a_hint():
    h = new_home()
    synced(h, "--claude")
    wr(WS / ".notes" / "critic.md", "a note\n")
    wr(h / ".claude/os-notes/old.md", "old\n")
    try:
        rc, out = cto(h, "doctor", path=tool_path("claude") + os.pathsep + str(h / ".local/bin"))
        expect("1 member(s) with queued notes" in out and "os-notes" in out and "move" in out, out)
        expect(rd(h / ".claude/os-notes/old.md") == "old\n", "moved a note by itself")
        cto(h, "remove", "--yes")
        expect((WS / ".notes/critic.md").exists() and (h / ".claude/os-notes/old.md").exists(), "remove touched notes")
    finally:
        shutil.rmtree(str(WS / ".notes"))


# ------------------------------------------------------------------------------------ launcher

def link_of(h):
    p = h / ".local/bin/cto"
    return os.readlink(str(p)) if p.is_symlink() else None


@check
def launcher_lookalikes_are_left_alone():
    h = new_home()
    (h / ".local/bin").mkdir(parents=True)
    (h / ".local/bin/cto").symlink_to(h / "oldco/bin/cto")             # dangling, ends in bin/cto
    rc, out = cto(h, "sync", "--claude")
    expect(link_of(h) == str(h / "oldco/bin/cto") and "ln -sfn" in out, out[-300:])
    cto(h, "remove", "--yes")
    expect(link_of(h) == str(h / "oldco/bin/cto"), "remove deleted it")
    h2 = new_home()
    (h2 / "co/bin").mkdir(parents=True)
    (h2 / "co/doctrine").mkdir()
    (h2 / "co/experts").mkdir()
    wr(h2 / "co/bin/cto", "x")
    (h2 / ".local/bin").mkdir(parents=True)
    (h2 / ".local/bin/cto").symlink_to(h2 / "co/bin/cto")
    cto(h2, "sync", "--claude")
    expect(link_of(h2) == str(h2 / "co/bin/cto"), "replaced another checkout's link")


@check
def launcher_is_recorded_kept_and_removed():
    h = new_home()
    synced(h, "--claude")
    expect(link_of(h) == str(BIN) and str(BIN) in json.loads(rd(h / ".claude/.os-manifest.json"))["launcher"])
    synced(h, "--claude")
    expect(link_of(h) == str(BIN))
    cto(h, "remove", "--yes")
    expect(link_of(h) is None and not (h / ".local/bin/cto").exists())


@check
def launcher_follows_a_moved_repository():
    h = new_home()
    a = clone("mv")
    subprocess.run([sys.executable, str(a / "bin/cto"), "build"], cwd=str(a), check=True, stdout=subprocess.DEVNULL)
    expect(cto(h, "sync", bin_=a / "bin/cto")[0] == 0)
    # forget what the claude manifest knows, so only the codex manifest still names the old target
    p = h / ".claude/.os-manifest.json"
    m = json.loads(rd(p))
    m["launcher"], m["repo"] = [], "elsewhere"
    wr(p, json.dumps(m))
    b = TMP / f"moved-{next(_ids)}"
    shutil.move(str(a), str(b))
    rc, out = cto(h, "sync", "--claude", bin_=b / "bin/cto")
    expect(rc == 0 and link_of(h) == str(b / "bin/cto"), f"{link_of(h)} {out[-200:]}")
    cto(h, "remove", "--yes", bin_=b / "bin/cto")
    expect(link_of(h) is None)


@check
def a_launcher_that_cannot_be_linked_is_one_line_and_leaves_a_consistent_install():
    h = new_home()
    wr(h / ".local", "i am a file\n")
    rc, out = cto(h, "sync", "--claude")
    expect(rc == 1 and "Traceback" not in out and "linking" in out, out[-300:])
    expect(cto(h, "status", "--claude")[0] == 0, "installed files are not consistent")


# ---------------------------------------------------------------------------------------- init

def git_ok():
    return bool(shutil.which("git"))


@check
def init_refuses_symlinks_out_of_the_project():
    for make in (lambda p, o: (p / "AGENTS.md").symlink_to(o / "AGENTS.md"),
                 lambda p, o: (p / ".os").symlink_to(o),
                 lambda p, o: (p / ".gitignore").symlink_to(o / "gi")):
        h = new_home()
        p, o = h / "proj", h / "outside"
        p.mkdir()
        o.mkdir()
        wr(o / "AGENTS.md", "keep\n")
        make(p, o)
        rc, out = cto(h, "init", str(p))
        expect(rc == 1 and rd(o / "AGENTS.md") == "keep\n" and not (o / "gi").exists()
               and not [x for x in o.iterdir() if x.name not in ("AGENTS.md",)], out[-200:])


@check
def init_makes_the_kept_files_unignored():
    for rule in (".os/", ".os", "/.os/", ".os/*"):
        h = new_home()
        p = h / "proj"
        p.mkdir()
        subprocess.run(["git", "init", "-q"], cwd=str(p), check=True)
        wr(p / ".gitignore", f"node_modules\n{rule}\n")
        rc, out = cto(h, "init", str(p))
        expect(rc == 0, f"{rule}: rc={rc}: {out[-200:]}")
        for f in ("state.md", "verify-state.sh", "verify-mutation.sh"):
            r = subprocess.run(["git", "check-ignore", "-q", ".os/" + f], cwd=str(p))
            expect(r.returncode == 1, f"{rule}: .os/{f} still ignored")
        before = rd(p / ".gitignore")
        cto(h, "init", str(p))
        expect(rd(p / ".gitignore") == before, f"{rule}: not idempotent")


@check
def init_exits_nonzero_when_git_still_ignores_the_files():
    h = new_home()
    p = h / "proj"
    p.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=str(p), check=True)
    wr(p / ".gitignore", ".*\n")
    rc, out = cto(h, "init", str(p))
    expect(rc == 1 and "WARNING" in out, out[-300:])


# ------------------------------------------------------------------------------------- driver

def main():
    build_dist()
    failed = 0
    for fn in CHECKS:
        name = fn.__name__
        t0 = time.time()
        try:
            fn()
        except Fail as e:
            print(f"FAIL {name}: {e}")
            failed += 1
        except Exception as e:
            print(f"FAIL {name}: {type(e).__name__}: {str(e)[:200]}")
            failed += 1
        else:
            print(f"ok   {name}")
        sys.stdout.flush()
    print(f"\n{len(CHECKS)} checks, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
