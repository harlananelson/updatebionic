# Reasoning for Dual-Env Setup Changes (Old Conda for Spark + Miniconda r_env for R Jupyter Notebooks)

**Date:** 2026-06-02 (updates applied)
**Context:** Work in `~/projects/updatebionic` (the shared setup scripts used across projects like allison, SCDCerner, etc. on LHN/Databricks jumpbox containers).
**Triggering observation:** Review of `~/projects/allison/logs/debugging/setup-user-1.log` (run as user ajones181) + inspection of `setup-system.sh`, `setup-user.sh`, `add-r-kernel.sh`, `requirements-*.txt`, `documentation/SETUP_STEPS.md`, `KNOWN_ISSUES.md`, etc.
**Goal of this document:** Capture the full reasoning, problem analysis, design intent, specific code changes, and why they make the "R Jupyter notebooks" side work correctly while preserving the "very old conda" for Spark/PySpark.

**Historical context for comments and design:** This setup was originally developed for a single-user environment on the container. It is now being extended and modified to support multiple users sharing the same container/node safely. All comments, help text, and documentation should be framed around the transition from single-user to multi-user shared use (e.g., per-user isolation for environments, kernels, and caches so that concurrent users do not interfere), rather than role-based distinctions.

This document is located in the `documentation/` subdirectory of the updatebionic project.

## 1. The Core Design Constraint (User's Requirement)
The container/Docker shell (LHN HealtheDataLab style, Ubuntu 18.04 Bionic base with old GLIBC) ships with:
- A **very old conda** at `/opt/conda` (historically conda 4.7.x + Python 3.7 + pyspark 2.4.4 baked in).
- This old base **must be preserved** because "spark and pyspark are just too hard to update and get running" (metastore config, YARN, cloudpickle compatibility, lhn package expectations, etc.).

User workflow on top of that:
- Add a **few Python packages** (e.g. `plotnine` for grammar-of-graphics plotting, lifelines, etc.) that are needed for analysis.
- Then layer on **another updated conda** (downloaded Miniconda, pinned to a py3.10 build compatible with the container's glibc: Miniconda3-py310_23.11.0-2-Linux-x86_64).
- Inside the updated Miniconda, create a modern `r_env` (R 4.4.0 + Python 3.10) **specifically for R Jupyter notebooks**.
- The R notebooks need to work correctly, including:
  - Modern tidyverse / tidymodels / targets / survival / etc. (via the requirements-R.txt + CRAN/GitHub installs).
  - Reticulate interop to the companion Python 3.10 inside the *same* env (so you can do things like `plotnine` from R, or general Python ML from R code).
  - Reliable kernel launch from JupyterHub/JupyterLab ("R 4.4.0 (r_env)" and the sibling "Python 3.10 (r_env)").

The scripts (`setup-system.sh` + `setup-user.sh` + the standalone `add-r-kernel.sh`) implement the "dual env" architecture:
- Old `/opt/conda` (py3.7 + pyspark 2.4.4) → cloned into per-user `/tmp/lhn_prod-<user>` and `/tmp/lhn_dev-<user>` for the lhn Spark work (with pandas pinned to 0.25.3 + --no-deps for editable lhn installs + plotnine added on top).
- New `/tmp/miniconda` (py3.10) → used to create/solve/clone the per-user `/tmp/r_env-<user>` (R + py for notebooks).

See `documentation/SETUP_STEPS.md` for the table of environments/kernels and `KNOWN_ISSUES.md` for the documented "pyspark Version Incompatibility" and "Cloned Conda Environment pip Corruption" mitigations.

## 2. Symptoms Observed (from a real multi-user run log + code review)
From a setup log captured during extension to multi-user support (e.g. a run under the allison project showing the symptoms described by the user):

- The r_env clone from a sibling user's environment succeeded.
- "Cloned env already contains geospatial + Python + CRAN + GitHub packages; skipping rebuilds."
- R environment setup complete.
- Then **R registration**:
  ```
  Registering Python 3.10 kernel...
  Defaulting to user installation because normal site-packages is not writeable
  ... (ipykernel went to ~/.local/lib/python3.10/site-packages, and references to /tmp/miniconda/lib/python3.10 ...)
  Installed kernelspec python310_renv ...
  Registering R 4.4.0 kernel...
  > IRkernel::installspec(...)
  ```
  (Note: the R banner showed a newer version than the script's 4.4.0 creation pin — the sibling environment had r-base updated after initial creation. Registration must use the actual version for the kernel name.)
- Then Part 6:
  ```
  Verifying pyspark in base environment...
  ... traceback from /usr/local/spark/python/pyspark/cloudpickle.py ...
  TypeError: 'bytes' object cannot be interpreted as an integer
  ERROR: pyspark not found in base environment
  ```
  (The script then aborts before completing the lhn_prod/dev clones and their kernel registrations.)

**Key problems diagnosed:**
- **Multiple condas + PATH bootstrap + activate timing bugs**: Early `export PATH="/opt/conda/bin:..."` (to find old base tools). Later miniconda init. Clone sometimes used the "wrong" `conda` (the one first in PATH at that moment). `conda activate "$R_ENV_PATH"` (using whichever `conda` was resolved) did not reliably make bare `python` and `R` resolve *inside the r_env* for the registration commands. Result: Python kernel registration for the "r_env" side used a miniconda-base python (or fell back to user site), not the isolated r_env python. This means the recorded kernel.json for "Python 3.10 (r_env)" was not guaranteed to point at the modern companion Python.
- **No guarantee of RETICULATE_PYTHON**: Even if R registration picked up the right R binary (it did, via the cloned tree), nothing wired `reticulate` (installed while env active) to the *sibling Python 3.10 inside the same r_env*. In JupyterHub kernel launch context (different PATH, no full conda activate shell), R notebooks using `library(reticulate); py_import("plotnine")` or similar could silently pick the old /opt/conda python or system python → version conflicts, missing packages, or "it doesn't work correctly".
- **Clone divergence on shared nodes**: When one user has already built an r_env, others clone it for speed. The cloned env may contain a different R version than the creation-time pin in the script; registration must detect and advertise the actual version.
- **Hard failure on known incompatibility**: The pyspark check (intended to validate the old base before cloning it for lhn) blew up on the exact cloudpickle py-version mismatch that the KNOWN_ISSUES and code comments acknowledge is expected ("pyspark 2.4.4 only imports under Python 3.7"). The `|| exit 1` prevented completing the rest of per-user setup (even though the R side had already succeeded). This breaks users who primarily care about the R notebooks side.
- **Registration not robust to JupyterHub launch**: Bare `python -m ipykernel install` and `R -e "IRkernel..."` (even under activate) can produce kernel.json that depends on the runtime PATH. In the container, the hub launches kernels with its own env (often preferring system /usr/local or the old conda first). Result: R notebooks don't get the modern R + its py.

These exactly match the user's description: "there is a very old conda but I have to use that because sparke and pyspark are just to hard to update... but I add a few python packages like plotnine. but then add another updated conda based on downloading miniconda. of that I put a new version of R and python. this is used for R jupyter notebooks. I need it to work correctly."

The log illustrated the breakage encountered while extending the (originally single-user) setup for multi-user shared node use.

## 3. Design Principles We Must Preserve
- **Isolation**: r_env (modern R+py) must never pollute or depend on the old /opt/conda in a way that breaks Spark. Conversely, the old base (and its clones) must stay usable for lhn + pyspark 2.4.4 work. (See comments in setup-system.sh lines ~165-169: explicitly do *not* install plotnine/duckdb into the true base; do it into the per-user clones.)
- **Clone optimization on shared node**: r_env is expensive to solve (many R packages + geospatial + CRAN + GitHub). Clone from sibling if present (fast `conda create --clone`), but still do per-user kernel registration (kernels live in $HOME, not in the env prefix).
- **Explicit over implicit**: Because of the two condas + system /usr/local/spark + JupyterHub kernel launcher + user .local pollution + clone-from-other-user, we cannot trust bare `python`/`R` or `conda activate` side-effects in the script.
- **R notebooks first-class**: The r_env side exists *for* R analysis in Jupyter (IRkernel + reticulate to its py). Python side of r_env is the companion for reticulate (plotnine etc. from R) + standalone "Python 3.10 (r_env)" ML work.
- **Tolerate the known old-pyspark wart**: The container + old pyspark 2.4.4 has the cloudpickle incompatibility when you naively import from the old python. Hybrid kernels work via launch-time env vars (HADOOP_CONF_DIR, PYTHONPATH to /usr/local/spark/python, etc.). The check must not abort the whole per-user setup.
- **Idempotent + safe for shared node + multiple users**: Per-user paths (`/tmp/r_env-$USER`, per-user conda pkgs cache, kernels in $HOME). Flock + daily sentinel for system parts. Self-update from GitHub.
- **Match existing docs**: The changes must be consistent with SETUP_STEPS.md (the env/kernel tables), KNOWN_ISSUES.md (the documented workarounds for pandas/plotnine/pyspark), SPARK_UPGRADE_TESTING.md (hybrid kernels), etc.

## 4. Specific Changes Made (and Why)
All changes are in the live scripts in this directory (`setup-user.sh`, `add-r-kernel.sh`). (setup-system.sh was reviewed but needed only minor implicit support via the Miniconda install + micromamba.)

### In `setup-user.sh` (the main per-user script)
- **Explicit Miniconda paths for clone and create (around the CLONED_R_ENV block and the creation solve)**:
  ```bash
  MINICONDA_CONDA="/tmp/miniconda/bin/conda"
  ...
  if [ -x "$MINICONDA_CONDA" ]; then
      CLONE_CMD=("$MINICONDA_CONDA" "create" "-p" "$R_ENV_PATH" "--clone" "$candidate" "-y")
  ...
  ```
  (And similar for the micromamba/conda SOLVE_CMD in the from-scratch path.)
  **Why**: The early PATH bootstrap puts `/opt/conda/bin` first. Using bare `conda` for the r_env clone/create could (and did) pick the *old* conda's conda, producing an env whose later activate/kernel launch would resolve python/R to the wrong (old) interpreters. Forcing the miniconda's conda guarantees the r_env tree is owned by the updated conda. This directly fixes the "python registration used miniconda base instead of r_env" symptom.

- **Force miniconda hook + PATH + explicit activate before registration + post-activate verification** (just before the `conda activate "$R_ENV_PATH"` in the success path):
  ```bash
  if [ -f /tmp/miniconda/etc/profile.d/conda.sh ]; then
      source /tmp/miniconda/etc/profile.d/conda.sh
  fi
  export PATH="/tmp/miniconda/bin:$PATH"
  conda activate "$R_ENV_PATH" || echo "WARNING..."
  ```
  **Why**: Makes activation deterministic regardless of which `conda` the shell thinks is primary at that moment in the script. (The script has multiple points where it sources old vs. miniconda conda.sh.)

- **Full explicit paths for registration + actual R version detection + kernel.json patch for RETICULATE_PYTHON** (the block after the CLONED if/else):
  ```bash
  R_ENV_PYTHON="$R_ENV_PATH/bin/python"
  R_ENV_R="$R_ENV_PATH/bin/R"
  ...
  "$R_ENV_PYTHON" -m pip install ipykernel
  "$R_ENV_PYTHON" -m ipykernel install --user ...
  ...
  ACTUAL_R_VER=$("$R_ENV_R" --version ... )
  "$R_ENV_R" -e "IRkernel::installspec(name = 'r_env', displayname = 'R ${ACTUAL_R_VER} (r_env)')"
  ...
  # Patch ...
  python -c '
  ... 
  k["env"]["RETICULATE_PYTHON"] = r_env + "/bin/python"
  # (PATH is deliberately NOT set — see note below)
  ' "$R_KERNEL_DIR" "$R_ENV_PATH"
  ```
  **Why**:
  - Full paths → kernel.json (written by ipykernel installspec and IRkernel) records the *exact* modern python/R from the r_env, not whatever `which python`/`which R` would find at Jupyter launch time.
  - ACTUAL_R_VER → display name matches reality even for cloned envs that users later upgraded inside (e.g. 4.5.3 in the log).
  - The python -c patch (using sys.argv for the values so they expand at *setup* time) adds the `RETICULATE_PYTHON` entry to the r_env kernel.json "env" dict. This is the standard way to point an R kernel's reticulate at a specific interpreter. Now, when you open an R notebook with that kernel, `reticulate::py_config()` or `import("plotnine")` will reliably see the Python 3.10 sibling inside the same r_env (with its plotnine etc. from requirements-python.txt), not the old conda or ~/.local pollution.
  - **PATH is deliberately NOT set in the kernel.json env.** (Earlier revisions also set `k["env"]["PATH"] = rbin`.) IRkernel writes no PATH, so `old_path` was empty and the patch produced a `PATH` of `<r_env>/bin` *only*. Because Jupyter applies the kernel.json `env` over the launch environment (it replaces those keys), the R kernel would launch with only `<r_env>/bin` on PATH — hiding system tools the kernel shells out to (pandoc for knitr, git, gcc, …). `RETICULATE_PYTHON` alone is sufficient for the reticulate goal, so the PATH override was removed.
  - The `python -m pip install ipykernel` now uses the r_env python → no more "Defaulting to user installation" into ~/.local for the r_env py kernel.

- **Tolerant pyspark verification** (the Part 6 block, replacing the hard `|| { echo ERROR; exit 1 }`):
  ```bash
  ... try import pyspark ...
  except ... :
      if "bytes" in msg or "cloudpickle" ... :
          print("  (known pyspark 2.4.4 + py>=3.8 ... — expected)")
          ...
  ; then
      echo "WARNING: ... but continuing (R env + lhn setup may still succeed)."
  fi
  ```
  **Why**: Matches the documented design (KNOWN_ISSUES.md "pyspark Version Incompatibility", script comments about 3.7 vs. 3.8+ cloudpickle, the fact that lhn hybrid kernels use launch config not naked import). The R side (and lhn clones) can now complete even when the "validate old base" step hits the expected wart. The log's exact error no longer kills the run.

  **Quoting fix (required for the above to actually work):** the interpreter is invoked via
  `PY_CHECK="$OLD_CONDA_PATH/bin/python"` (double quotes). An earlier revision used
  single quotes (`PY_CHECK='$OLD_CONDA_PATH/bin/python'`), which never expands — the shell
  then tried to exec a file literally named `$OLD_CONDA_PATH/bin/python`, failed with
  "No such file or directory", and fell straight into the generic WARNING branch *without
  ever importing pyspark*. That defeated the known-vs-unexpected error discrimination
  (the `raise` path was dead). With double quotes the check runs the real old-base
  interpreter and the cloudpickle case is correctly identified.

- Minor: The registration code now lives after the clone "skipping rebuilds" message (was already the case), and the activate is forced to the right conda root before it.

### In `add-r-kernel.sh` (standalone "just add the R side" script, for users who don't want the full lhn dual-env dance)
- Parallel changes: explicit `R_ENV_PYTHON` / `R_ENV_R`, full-path registration, ACTUAL_R_VER, and the exact same kernel.json patch for RETICULATE_PYTHON (PATH deliberately not set, same as `setup-user.sh`).
- This makes the standalone script produce the same reliable R notebook experience.

No changes were needed to `setup-system.sh` (it already correctly downloads the pinned Miniconda once, installs micromamba for fast solves, makes /tmp/miniconda world-readable, and avoids polluting the old base with plotnine etc.). The per-user conda pkgs cache (`$CONDA_PKGS_DIRS`) logic was already good for shared-node multi-user safety.

## 5. How This Makes "R Jupyter Notebooks Work Correctly"
- **Isolation preserved**: r_env creation/registration now *explicitly* goes through the miniconda tree. Old /opt/conda (and its clones for lhn) are untouched except for the intentional plotnine + pandas pin + --no-deps in the clone steps (exactly as the user described doing manually, now automated and safe per the comments).
- **Kernel resolution independent of PATH/activate/JupyterHub magic**: Full paths in the registration commands + post-registration patch mean the two kernels ("Python 3.10 (r_env)" and "R <actual> (r_env)") will launch the right interpreters even if the hub's PATH puts /opt/conda or /usr/bin first.
- **Reticulate wired up**: The patch ensures that inside an R notebook, `reticulate` sees the Python 3.10 that lives next to it in the r_env (the one that has plotnine, the one the user wants for "new version of R and python"). This was the missing piece for "used for R jupyter notebooks" to feel correct.
- **No more silent wrong-python pollution**: The previous "Defaulting to user..." during r_env py registration is eliminated because we drive it with the r_env python explicitly.
- **Clone safety + version truth**: Clone still works for speed (great for shared nodes), but registration now detects and advertises the real R version, and the patch still applies.
- **Setup completes for R users**: The known pyspark error no longer aborts everything after the R side is done.
- **Idempotent / re-runnable**: `FORCE_R_ENV_SOLVE=1` still forces a clean from-scratch solve under the right miniconda if you want to blow away a weird clone.

After a re-run (and optionally cleaning old bad kernels with `rm -rf ~/.local/share/jupyter/kernels/*r_env*`), selecting the R kernel in JupyterLab should give a working modern R session whose `reticulate` (and thus any py packages like plotnine) is the companion from the same updated miniconda env.

## 6. Verification Steps (What to Do After These Changes)
1. `cd ~/work/Users/<yourname>/updatebionic` (or wherever your local copy lives) && git pull (or manually sync the two .sh files from the central `~/projects/updatebionic`).
2. (Clean) `rm -rf /tmp/r_env-$USER ~/.local/share/jupyter/kernels/python310_renv ~/.local/share/jupyter/kernels/r_env`
3. `./setup-user.sh` (or the wrapper). Watch for the new "Using /tmp/miniconda/bin/conda explicitly...", "Registering ... (using $R_ENV_...)", and the "Patched r_env kernel.json with RETICULATE_PYTHON" messages.
4. In JupyterLab: refresh kernels. Open an R notebook with "R <ver> (r_env)".
5. Test:
   - `library(tidyverse); library(reticulate)`
   - `py_config()` — should show the python inside /tmp/r_env-*/bin/python (py 3.10).
   - `py_run_string("import plotnine as p9; print(p9.__version__)")` or equivalent.
   - Basic ggplot2 + reticulate plotnine interop if desired.
6. For the old side: the lhn_prod/dev clones and their (pure Python or hybrid PySpark) kernels should still appear and the pandas 0.25.3 + plotnine dance should have happened in the clones.
7. If you hit the cloudpickle message, it will now be a WARNING + continue (not ERROR + exit).

## 7. Files Changed / Documents
- `setup-user.sh` (main logic + comments explaining the "why" for each robustness change).
- `add-r-kernel.sh` (parallel for the standalone path).
- This reasoning document (placed at root of updatebionic, with a copy also in `documentation/REASONING-DUAL-ENV-R-KERNELS.md`).

No other files were modified (requirements-*.txt, environment-ml.yml, the documentation/ .md files, etc. were already correct for the design).

## 8. Future / Open Items (for Completeness)
- If the container ever gets a true modern pyspark that works on py3.10, the "old base" side can be revisited, but per user requirement we treat that as out of scope.
- The kernel.json patch is a post-facto edit; a more elegant long-term thing would be a small wrapper script that the kernel.json argv calls (that does the source/activate + exec), but the patch is minimal, robust, and matches how other conda + reticulate setups in the wild solve the same problem.
- If more users report R version drift or reticulate issues, we can consider pinning r-base more strictly or adding a post-clone "conda install r-base=4.4.0" step (but that would re-introduce solve cost, which the clone optimization exists to avoid).
- The allison log also showed the R registration used a sibling that had R 4.5; the ACTUAL detection now makes that visible and correct in the kernel name.

This captures the "why" behind the fixes. The changes are surgical (they touch only the r_env creation/registration + the one verification guard) and are fully explained in the added comments in the scripts themselves.

If you run the setup again and something still doesn't feel right for the R notebooks, share the new log + the two kernel.json files + output of `R -e 'reticulate::py_config()'` from inside an R notebook, and we can iterate.

(End of reasoning document.)

## Note on Comment and Documentation Framing

This system was originally developed for use by a single person. It is now being modified and extended to support use by more than one person sharing the same container/node.

All comments, help text, error messages, and this reasoning document should be positioned around that transition:
- Focus on safe multi-user sharing of the node (per-user isolation via username-suffixed paths for /tmp environments, conda caches, source clones, and Jupyter kernels in $HOME so users do not collide or interfere).
- Avoid role-based distinctions (such as "intern" vs. "lead") or personal names.
- The design (node-wide sentinel for shared setup-system, per-user r_env and lhn clones, explicit paths for registration, etc.) exists to enable this multi-user scenario while preserving the original single-user constraints around the very old conda for Spark/PySpark compatibility.

When reviewing or editing comments, reframe them in terms of "previously single-user" to "now supporting multiple concurrent users on a shared container" rather than assuming different permission levels or roles between users.
