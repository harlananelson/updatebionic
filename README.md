# LHN Container Setup — Lead + Intern Workflow

Bootstrap scripts for the LHN (HealtheDataLab) Docker container on
HDL JupyterHub. Provisions:

- System-level dependencies (apt packages, Quarto CLI, Miniconda)
- Per-user SSH keys, conda environments, and Jupyter kernels
- Two side-by-side LHN environments (`lhn_prod` v0.1.0 + `lhn_dev` v0.2.0-dev)
- An R + Python analysis environment (R 4.4 + Python 3.10)

Designed for **multi-user collaboration on a shared HDL node**: lead
and intern can run the per-user script side by side without colliding,
because every per-user path is suffixed with `<username>`.

---

## TL;DR — for an intern starting today

You don't need any of Harlan's files. From a fresh JupyterHub
terminal:

```bash
# One-line bootstrap (fetches the latest script + runs it):
curl -fsSL https://raw.githubusercontent.com/harlananelson/updatebionic/main/setup-user.sh \
  > setup-user.sh && chmod +x setup-user.sh && ./setup-user.sh
```

That's it. The script auto-detects you (`whoami`), creates
per-user environments, restores your SSH keys if they're in
persistent storage, and registers Jupyter kernels. If Harlan
hasn't run `setup-system.sh` yet today, this script will trigger
it (with `sudo` — you'll be prompted for a password if you have
sudo rights; otherwise tell Harlan to run it).

---

## The two scripts

| Script | Who runs it | What it does | Frequency |
|---|---|---|---|
| **`setup-system.sh`** | Project lead (Harlan), with `sudo` | apt-installs system libs (GDAL, openssh-client, build tools), installs Quarto CLI to `/opt/quarto`, installs Miniconda to `/tmp/miniconda` | Once per day (idempotent; tracks daily sentinel at `/tmp/.lhn-system-ready`) |
| **`setup-user.sh`** | Each user — lead or intern | Restores user's SSH keys, creates per-user conda envs (`lhn_prod-<user>`, `lhn_dev-<user>`, `r_env-<user>`), registers per-user Jupyter kernels | Once after the container restarts; also self-updates from GitHub on every run |

`setup-user.sh` automatically invokes `setup-system.sh` if the
day's sentinel isn't present. So in practice:

- **Lead** (one-time per morning): `bash setup-user.sh` — also handles system setup
- **Intern** (one-time per morning): `bash setup-user.sh` — also handles system setup if lead hasn't already

No special order required. The flock + sentinel mean both users
can run their scripts concurrently and only the first will perform
the shared work.

---

## Self-update (built into `setup-user.sh`)

Every run of `setup-user.sh` first fetches the latest copy of
itself from `harlananelson/updatebionic` on GitHub:

```
Checking GitHub for newer version of setup-user.sh...
Newer version found on GitHub. Updating...
Updated. Re-executing with new version...
```

So **even if your local copy is stale, every invocation runs the
latest script**. You never need to `git pull` updatebionic manually
just to get script fixes.

To bypass (e.g., when debugging locally), set `SKIP_SELF_UPDATE=1`.

---

## PATH bootstrap (for interns running from a fresh shell)

A first-time JupyterHub terminal sometimes has a minimal `PATH` that
doesn't include `/usr/bin` (where apt-installed `ssh`, `git`, `sudo`
live). The lead's shell almost always has conda active, which keeps
PATH normalised, but the intern's brand-new shell doesn't.

`setup-user.sh` normalises PATH at startup:

```bash
export PATH="/opt/conda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"
source /opt/conda/etc/profile.d/conda.sh   # if present
```

After this, `ssh`, `git`, `curl`, `sudo`, and `conda` are all
reachable — no prior `conda activate` step needed.

---

## What the script creates (per user)

All paths suffix with `<username>` so two users on the same node
never collide. Below, `<u>` = `whoami` (e.g. `hnelson3`, `ajones181`).

### A. R + Python analysis environment

| | |
|---|---|
| Path | `/tmp/r_env-<u>` |
| R | 4.4.0 |
| Python | 3.10 |
| Purpose | R analysis, Python ML (non-Spark), Quarto rendering, plotting/modeling |
| Packages | Python from `requirements-python.txt`; R from `requirements-R.txt` + CRAN fallback + GitHub (`treeshap`) |
| Jupyter kernels | `Python 3.10 (r_env)`, `R 4.4.0 (r_env)` |

Auto-activated in new terminals.

### B. LHN production environment

| | |
|---|---|
| Path | `/tmp/lhn_prod-<u>` |
| LHN version | `v0.1.0-monolithic` (cloned from `/opt/conda` base) |
| Python | 3.7 |
| pandas | 0.25.3 (Spark 2.4.4 compat) |
| Source | `/tmp/lhn_prod_src-<u>` (ephemeral, fast) |
| Jupyter kernel | `PySpark + lhn-prod (v0.1.0)` |
| Use case | Production validation, regression testing |

### C. LHN development environment

| | |
|---|---|
| Path | `/tmp/lhn_dev-<u>` |
| LHN version | `v0.2.0-dev` (refactored) |
| Python | 3.7 |
| pandas | 0.25.3 |
| Source | `~/work/Users/<u>/lhn` (persistent) |
| Extra deps | `~/work/Users/<u>/spark_config_mapper`, optional `omop_concept_mapper` |
| Jupyter kernel | `PySpark + lhn-dev (v0.2.0)` |
| Use case | Refactoring, feature work, A/B testing against prod |

### D. Jupyter kernels (summary)

Spark-enabled (recommended — automatic Hive metastore access):

- `PySpark + lhn-prod (v0.1.0)`
- `PySpark + lhn-dev (v0.2.0)`

Non-Spark:

- `Python (lhn-prod v0.1.0)`
- `Python (lhn-dev v0.2.0)`
- `Python 3.10 (r_env)`
- `R 4.4.0 (r_env)`

---

## Pandas compatibility (don't fight this)

Both LHN environments **intentionally pin `pandas==0.25.3`** because
Spark 2.4.4 breaks with newer pandas. The refactored LHN code declares
`pandas>=1.0` but is installed with `pip install --no-deps`. If you
hit a pandas-related error in `lhn_dev`, the code likely needs an
adapter for the 0.25.x API — don't upgrade pandas.

---

## Daily workflow (after first-day setup)

The first-day setup is one command (the curl above). Going forward:

```bash
# Container restarted overnight? Re-run setup-user.sh to recreate the
# /tmp/ environments. Persistent state (~/work/Users/<u>/*) survives.
bash setup-user.sh

# Open a notebook in JupyterLab, pick a kernel from the dropdown:
#   - PySpark + lhn-dev (v0.2.0)    ← Spark + dev LHN
#   - Python 3.10 (r_env)           ← non-Spark Python ML
#   - R 4.4.0 (r_env)               ← R analysis
```

Common terminal aliases (added to your `.bashrc` by `setup-user.sh`):

```bash
oldbase   # Activate /opt/conda (where pyspark 2.4.4 lives)
oldconda  # Make /opt/conda available on PATH without activating
```

---

## Multi-user safety

The script is designed so the lead and intern can run it on the
same shared node **without colliding**:

| Resource | How collision is avoided |
|---|---|
| Conda envs (`/tmp/lhn_prod`, `/tmp/lhn_dev`, `/tmp/r_env`) | Per-user suffix: `/tmp/lhn_prod-<u>` etc. |
| Source clones (`/tmp/lhn_prod_src`) | Per-user suffix: `/tmp/lhn_prod_src-<u>` |
| Jupyter kernels | Registered to `~/.local/share/jupyter/kernels/` — separate per-user JupyterHub user |
| `setup-system.sh` (shared work) | Daily sentinel + flock — first runner does the work, subsequent runners no-op |
| Conda package cache | Per-user: `/tmp/conda-pkgs-<u>` |

The lead's `lhn_dev` is at `/tmp/lhn_dev-hnelson3`. The intern's at
`/tmp/lhn_dev-ajones181`. They don't share state.

---

## File expectations

`setup-user.sh` expects these files next to itself (in the same dir
as the script):

```
setup-user.sh             ← this file
setup-system.sh           ← shared system setup (auto-invoked)
requirements.txt          ← shared
requirements-python.txt   ← r_env Python deps
requirements-R.txt        ← r_env R deps via conda
environment-ml.yml        ← optional ML conda env
```

Per-user persistent storage (created at first run if missing):

```
~/work/Users/<u>/.ssh/            ← SSH keys (restored on container restart)
~/work/Users/<u>/lhn/             ← clone of lhn (dev environment source)
~/work/Users/<u>/spark_config_mapper/
~/work/Users/<u>/omop_concept_mapper/  (optional)
```

---

## Troubleshooting

### `ssh: command not found` early in `setup-user.sh`

PATH is missing `/usr/bin`. The script's bootstrap block normalises
this, but if it's been bypassed (e.g., you sourced the script
instead of executing it), confirm:

```bash
echo $PATH       # should contain /usr/bin
which ssh        # should be /usr/bin/ssh
```

If `ssh` is genuinely not installed, run `setup-system.sh` (or ask
the lead to run it):

```bash
bash setup-system.sh
```

### `Permission denied: /home/<other-user>/`

You don't have read access to other users' home directories on HDL.
You shouldn't need to. Everything you need lives under your own
`~/work/Users/<u>/`. If a script appears to be trying to read another
user's home, file a bug.

### `setup-system.sh failed: needs sudo`

You don't have sudo rights on this HDL node. Tell the lead to run
`setup-system.sh` first; then re-run `setup-user.sh`.

### Conda envs disappeared after container restart

That's expected — `/tmp/` is ephemeral. Re-run `setup-user.sh` to
recreate them (your persistent state under `~/work/Users/<u>/`
survives).

### Self-update fails with "Could not reach GitHub"

Network blip. Script continues with the current local version.
Either wait and re-run, or set `SKIP_SELF_UPDATE=1` to force-skip.

### "Already running the latest version"

Self-update is working correctly — your local copy matches GitHub
`main`. No action needed.

---

## Design philosophy

- **Per-user isolation** — every path suffixes with `whoami`
- **Self-bootstrapping** — single curl gets you everything
- **Self-updating** — script always runs the latest version from GitHub
- **Daily sentinel + flock** — shared work runs once per day, regardless of who triggers it first
- **PATH normalisation** — works from a fresh JupyterHub shell with no prior conda activation
- **Spark compatibility first** — pandas 0.25.3 + pyspark 2.4.4 are non-negotiable
- **Editable installs everywhere** — local edits to `lhn` / `spark_config_mapper` pick up immediately
- **No Docker image changes required** — everything is per-user state in `/tmp/` or `~/work/`

---

## Files in this repo

| File | Purpose |
|---|---|
| `setup-system.sh` | System-wide setup (sudo, daily) |
| `setup-user.sh` | Per-user setup (no sudo, recreates `/tmp/` envs) |
| `setup-lhn-dual-envs.sh` | Older single-script flow (kept for back-compat; new work uses the two-script split above) |
| `requirements-python.txt` | r_env Python deps |
| `requirements-R.txt` | r_env R deps (conda) |
| `requirements.txt` | Shared pip-installable deps |
| `environment-ml.yml` | Optional ML conda env |
| `add-r-kernel.sh` | Standalone Jupyter R kernel registration |
| `diagnose_spark_config.py` | Diagnostic for Spark/Hive metastore connectivity |
| `setup_spark_upgrade.py` | (Optional) upgrade pyspark in `lhn_dev` while preserving Hive access |
| `spark_metastore_init.py` | Hive metastore initialisation helper |
| `scripts/` | Utility scripts |
| `nix/` | (Experimental) Nix-based packaging |

---

## After running

You should have:

- ✅ R 4.4 + Python 3.10 analysis environment per user
- ✅ LHN production and development environments per user
- ✅ Spark-safe kernels with Hive metastore access
- ✅ Quarto ready for publishing
- ✅ One-command rebuild when the container resets
- ✅ Self-updating script — no manual git pull needed for script fixes

Optimised for **daily, real-world LHN development across a lead +
intern team on a shared HDL container**.
