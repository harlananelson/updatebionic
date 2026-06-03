# Capturing the Real Docker Container Environment (for Faithful Local Testing)

**Goal**: Give me an exact snapshot of the running container so I can recreate
a nearly identical Docker container here on the Ubuntu host, drop in the
current `setup-system.sh` / `setup-user.sh`, run them, and verify that the
dual-conda setup (old /opt/conda for Spark/PySpark + new /tmp/miniconda for
modern R 4.x + Python 3.10 `r_env`) produces working Jupyter kernels and
environments.

---

## Step 1: Get the capture script inside your target container

The easiest way (if you have the `updatebionic` repo checked out inside the container, which is common):

```bash
cd ~/updatebionic     # or /home/<you>/updatebionic or wherever it lives
git pull              # get the latest capture-docker-env.sh
bash capture-docker-env.sh
```

If the repo is not present or you want a standalone version:

Inside the container, run:

```bash
cd /tmp
cat > capture-docker-env.sh << 'ENDOFSCRIPT'
[paste the entire content of the capture-docker-env.sh file from the repo here]
ENDOFSCRIPT
chmod +x capture-docker-env.sh
./capture-docker-env.sh
```

(The file is in the repo at `capture-docker-env.sh` — you can view it on GitHub or copy the content from your local checkout.)

---

## Step 2: Collect the output

The script produces:

`/tmp/env-capture-YYYYMMDD-HHMMSS.tar.gz`

Copy it out of the container using whatever mechanism you have
(`docker cp <container>:/tmp/env-capture-....tar.gz .`, scp, etc.).

Send the tarball (or the extracted directory tree) back here.

---

## Step 3: What happens next (on my side)

1. I will unpack the capture and extract the real facts:
   - Exact base OS and apt packages
   - What `/opt/conda/bin/python --version` really is
   - Whether pyspark comes from conda or `/usr/local/spark/python`
   - The exact cloudpickle / import behavior that causes the "bytes object" error
   - Whether `/tmp/miniconda` already exists from previous runs
   - Current Jupyter kernels and how they are registered
   - Mount points for persistent storage (`~/work/Users/<u>/` etc.)
   - sudo capability of the account
   - Exact versions of key packages (pandas, etc.)
   - Any existing r_env / lhn_* envs

2. On this Ubuntu machine I will build a reproduction container that matches
   the captured base as closely as possible (usually something like
   `ubuntu:18.04` + the captured apt packages + the original way the first
   /opt/conda was bootstrapped).

3. I will copy the *current* versions of `setup-system.sh` and `setup-user.sh`
   (the ones we have been fixing — with explicit miniconda paths for r_env,
   kernel.json patching for RETICULATE_PYTHON, tolerant pyspark verification,
   multi-user framing in comments, etc.) into the test container.

4. I will run the setup as a normal (non-root) user, simulating:
   - First user on the node (triggers system setup)
   - Second user on the same node (reuses the shared parts)
   - Fresh shell vs. already-configured shell

5. I will verify:
   - The old `/opt/conda` is still there and can be used for pyspark 2.4.4 work
     (plotnine etc. added only to the per-user lhn clones, pandas pinned to 0.25.3)
   - `/tmp/miniconda` is installed (the "updated" one)
   - `/tmp/r_env-<user>` is created from the miniconda with R 4.4 + Python 3.10
   - Jupyter kernels are registered correctly and launch with the right interpreters
   - In an R session started from the kernel, `reticulate` points at the Python
     inside the same r_env (so you can use plotnine and other modern Python
     packages from R notebooks)
   - The lhn_prod / lhn_dev clones are created with the expected --no-deps tricks
   - No hard failures on the known cloudpickle incompatibility (we made that
     check tolerant)
   - Everything is per-user isolated so two users can coexist

6. I will fix any remaining issues revealed by the real environment, re-test
   locally until it is clean, and give you the updated scripts to use in your
   real container.

---

## Why we need the capture instead of guessing

The scripts have evolved over time with many implicit assumptions about:
- Which `python` / `conda` is first in PATH in a fresh terminal
- How to safely activate the "updated" miniconda without breaking the old one
- How Jupyter kernels record their interpreter (and how to make reticulate
  reliable inside R notebooks)
- What the "old base" pyspark import actually does on the real image
- Sudo rights and who is expected to run what

Capturing the *live* environment removes the guesswork and lets us make the
dual-conda (old for Spark, new for R notebooks) setup actually work for you.

Once you send the tarball, I will drive the local recreation + testing using
the tools available here (Docker on Ubuntu) and report back with results and
any fixes.

Thank you — this will make the setup much more robust.

### Even simpler (no need for full repo checkout):

If the container has outbound internet (for raw.githubusercontent.com):

```bash
cd /tmp
curl -fsSL https://raw.githubusercontent.com/harlananelson/updatebionic/main/capture-docker-env.sh -o capture-docker-env.sh
chmod +x capture-docker-env.sh
./capture-docker-env.sh
```

This fetches only the capture script directly from the repo. Very lightweight.
