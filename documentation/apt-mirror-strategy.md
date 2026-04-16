# APT Mirror Strategy for LHN Docker Container

## Current Approach: Retry Logic

The setup script (`setup-lhn-dual-envs.sh`) uses retry logic (3 attempts, 30s delay) to handle intermittent download failures during `apt-get install`. This works because:

- apt caches already-downloaded `.deb` files in `/var/cache/apt/archives/`
- Different packages fail each run (not a dead mirror — it's flaky connectivity)
- Each retry only needs to fetch the handful that failed

## Why Downloads Fail

The LHN Docker container runs on **AWS** (confirmed by hostname pattern `ip-10-42-66-151`). By default, Ubuntu's `sources.list` points at `archive.ubuntu.com` and `security.ubuntu.com`, which resolve to Canonical's public mirrors. Traffic from the container routes **out to the public internet** and back, which is:

- Slow (~22-24 KB/s observed)
- Prone to TCP connection drops on long fetches (38-42 minutes for ~63 MB)
- Affected by intermittent network path issues

The failing packages are **system-level C/C++ libraries** needed by R and Python packages:

| System library | Needed by |
|---|---|
| `libgdal-dev`, `libgeos-dev`, `libproj-dev` | `sf` (R), `geopandas` (Python) |
| `libudunits2-dev` | `units` (R) |
| `libfreetype6-dev`, `libpng-dev` | `ragg`, `svglite` (R plotting) |
| `libhdf5-dev` | HDF5 data access |
| `libqhull-dev` | computational geometry |
| `libspatialite-dev` | spatial database backend |

## If Retries Aren't Enough: Switch to AWS Mirror

Ubuntu maintains mirrors hosted **within AWS** that route traffic inside Amazon's network — much faster and more reliable.

### Step 1: Find the AWS region

```bash
# From inside the container:
curl -s http://169.254.169.254/latest/meta-data/placement/region
```

### Step 2: Swap mirrors

Replace `REGION` with the actual region (e.g., `us-east-1`, `us-west-2`):

```bash
sudo sed -i 's|http://archive.ubuntu.com|http://REGION.ec2.archive.ubuntu.com|g' /etc/apt/sources.list
sudo sed -i 's|http://security.ubuntu.com|http://REGION.ec2.archive.ubuntu.com|g' /etc/apt/sources.list
```

### Step 3: Update and install

```bash
sudo apt-get update
sudo apt-get install -y --fix-missing <packages>
```

### Available AWS mirrors

Format: `http://<region>.ec2.archive.ubuntu.com/ubuntu/`

Common regions: `us-east-1`, `us-east-2`, `us-west-1`, `us-west-2`, `eu-west-1`, `ap-southeast-1`

## Adding Mirror Swap to the Setup Script

If you determine the region and want to automate it, add this block **before** the `apt-get update` in Part 2 of `setup-lhn-dual-envs.sh`:

```bash
# Detect AWS region and use local mirror for faster downloads
AWS_REGION=$(curl -s --connect-timeout 5 http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null) || true
if [[ -n "$AWS_REGION" ]]; then
    echo "Detected AWS region: $AWS_REGION — switching to regional Ubuntu mirror..."
    sudo sed -i "s|http://archive.ubuntu.com|http://${AWS_REGION}.ec2.archive.ubuntu.com|g" /etc/apt/sources.list
    sudo sed -i "s|http://security.ubuntu.com|http://${AWS_REGION}.ec2.archive.ubuntu.com|g" /etc/apt/sources.list
fi
```

This auto-detects the region via the EC2 instance metadata service. If the metadata endpoint isn't available (e.g., blocked by the container runtime), it falls back silently to the default mirrors.

## Evidence (April 16, 2026)

Two runs of `setup-lhn-dual-envs.sh` logged in `logs/error-0.log`:

- **Run 1** (12:52 UTC): 12 packages failed, 42 minutes, ~22.7 KB/s
- **Run 2** (13:49 UTC): 11 packages failed (different set), 38 minutes, ~24.5 KB/s

Both fetched ~57 MB of 63 MB successfully. Different packages failed each time, confirming intermittent connectivity rather than a dead mirror.
