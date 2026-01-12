# CHRWD Data Science Environment (Nix)

Reproducible R/Python data science environment using Nix flakes.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Docker Container (Ubuntu 18.04)                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  /opt/conda (base)          │  /tmp/nix-portable (r_env)   │
│  ├─ Python 3.7.6            │  ├─ Python 3.10              │
│  ├─ PySpark 2.4.x           │  ├─ R 4.4.x                  │
│  └─ Spark jobs              │  ├─ targets pipeline         │
│     (large data ETL)        │  ├─ Quarto                   │
│                             │  └─ Jupyter kernels          │
│                             │                               │
│  ← Use for initial          │  ← Use for analytical        │
│    data pipeline            │    pipeline & modeling       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Comparison: Bash Script vs Nix

| Aspect | `updatebionic-ml.sh` | `flake.nix` |
|--------|---------------------|-------------|
| **Reproducibility** | Versions drift over time | Pinned nixpkgs = identical builds |
| **Build time** | ~15-30 min (compiles some packages) | First run: ~20-40 min, cached after |
| **Declarative** | Imperative shell script | Declarative Nix expression |
| **Portability** | Ubuntu 18.04 specific | Works on any Linux with nix-portable |
| **Debugging** | Grep through logs | `nix build --show-trace` |
| **Rollback** | Not possible | `nix profile rollback` |
| **rix integration** | N/A | Native compatibility |

## Quick Start

```bash
# 1. Copy files to your working directory
cp flake.nix bootstrap-nix.sh setup-nix-env.sh ~/work/

# 2. Run setup (do this on every container restart)
cd ~/work
./setup-nix-env.sh

# 3. Activate in current shell
source ./activate-nix-env.sh

# 4. Verify
R --version
python --version
quarto --version
```

## Daily Workflow

Since `/tmp` is ephemeral, run on each container restart:

```bash
cd ~/work
./setup-nix-env.sh
source ./activate-nix-env.sh
```

After first build, subsequent runs are fast because nix-portable caches build artifacts.

## Files

| File | Purpose |
|------|---------|
| `flake.nix` | Declarative environment definition |
| `flake.lock` | Pinned dependency versions (auto-generated) |
| `bootstrap-nix.sh` | Standalone nix-portable installer |
| `setup-nix-env.sh` | Combined setup + build script |
| `activate-nix-env.sh` | Source this to activate (auto-generated) |

## Package Management

### Adding R Packages

1. Check if package exists in nixpkgs:
   ```bash
   nix search nixpkgs rPackages.packagename
   ```

2. If found, add to `rPackagesFromNixpkgs` list in `flake.nix`

3. If not found, use `buildRPackage` from CRAN (see commented example)

4. Rebuild:
   ```bash
   ./setup-nix-env.sh
   ```

### Adding Python Packages

1. Add to `pythonEnv` section in `flake.nix`
2. Rebuild

## rix Integration

[rix](https://github.com/ropensci/rix) can generate Nix expressions from R. To use:

```r
# In an R session (can be outside Nix)
install.packages("rix")
library(rix)

# Generate a flake.nix from your renv.lock or package list
rix(
  r_ver = "4.4.0",
  r_pkgs = c("targets", "tidyverse", "data.table"),
  system_pkgs = c("quarto"),
  project_path = ".",
  overwrite = TRUE
)
```

This creates an alternative to hand-crafting `flake.nix`.

## Troubleshooting

### "GLIBC_X.XX not found"

nix-portable bundles its own runtime and should avoid this. If you see this error:

1. Ensure you're using nix-portable, not system nix
2. Check: `which nix` should show `/tmp/nix-portable/...`

### Package not found in nixpkgs

Some CRAN packages aren't in nixpkgs. Options:

1. Use `buildRPackage` (see flake.nix comments)
2. Install via `install.packages()` in R session to `R_LIBS_USER`
3. Use rix to auto-generate derivations

### Build fails with hash mismatch

Update `flake.lock`:

```bash
/tmp/nix-portable/nix-portable nix flake update
```

### Jupyter kernel not appearing

Manually register:

```bash
R -e "IRkernel::installspec(name = 'r_nix', displayname = 'R (Nix)')"
python -m ipykernel install --user --name python_nix --display-name "Python 3.10 (Nix)"
```

## Known Limitations

1. **Ephemeral builds**: First build on fresh container takes 20-40 min
2. **Binary cache**: Requires network access to cache.nixos.org
3. **Some CRAN packages**: May need custom derivations
4. **PySpark interop**: Use base `/opt/conda` for Spark jobs, Nix env for R/targets

## Migration Path

To fully migrate from `updatebionic-ml.sh`:

1. ✅ Core R packages (tidyverse, targets, tidymodels)
2. ✅ Python packages (pandas, polars, geopandas)
3. ✅ Quarto
4. ⚠️ Some specialty packages may need manual derivations
5. ❌ PySpark stays in /opt/conda (intentional - different use case)

## References

- [Nix Flakes](https://nixos.wiki/wiki/Flakes)
- [nix-portable](https://github.com/DavHau/nix-portable)
- [rix](https://github.com/ropensci/rix)
- [nixpkgs R packages](https://search.nixos.org/packages?channel=24.05&from=0&size=50&sort=relevance&type=packages&query=rPackages)
