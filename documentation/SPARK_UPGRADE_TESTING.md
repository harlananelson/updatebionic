# Spark Upgrade Testing Guide

This document describes how to test an upgraded Spark version while maintaining access to the Hive metastore in the IU Health Datalab container environment.

## The Key Discovery

The critical environment variable for metastore connectivity is:

```
HADOOP_CONF_DIR=/etc/jupyter/configs
```

This directory contains the Hive metastore configuration, specifically:
- `hive.metastore.uris = thrift://ip-10-42-66-135.us-east-2.compute.internal:9083`
- `hive.metastore.warehouse.dir = s3://iuh-datalab-persistence-s3-data/warehouse`

Any upgraded Spark needs this environment variable set to connect to the metastore.

## Files Created for Spark Upgrade Testing

| File | Purpose |
|------|---------|
| `setup_spark_upgrade.py` | Full Python module with `create_spark_session()` function |
| `spark_metastore_init.py` | Simple notebook cell to paste at top of notebooks |
| `diagnose_spark_config.py` | Diagnostic script to capture working Spark configuration |

## Testing an Upgraded Spark

### Option 1: Use the Upgraded Spark Kernels

After running `setup-lhn-dual-envs.sh`, two new kernels are available:
- **Spark Upgraded + lhn-prod (Metastore)** - Uses lhn_prod environment
- **Spark Upgraded + lhn-dev (Metastore)** - Uses lhn_dev environment

These kernels set `HADOOP_CONF_DIR=/etc/jupyter/configs` automatically.

### Option 2: Upgrade PySpark in an Environment

```bash
# Activate the environment
conda activate /tmp/lhn_dev

# Upgrade pyspark (choose your version)
pip install pyspark==3.3.0

# Then use the "Spark Upgraded + lhn-dev (Metastore)" kernel
```

### Option 3: Paste Initialization Cell

Copy the contents of `spark_metastore_init.py` at the **top** of your notebook, **before any other imports**:

```python
import os

# Set environment variables BEFORE importing pyspark
os.environ['HADOOP_CONF_DIR'] = '/etc/jupyter/configs'
os.environ['HADOOP_HOME'] = '/usr/local/hadoop'
os.environ['JAVA_HOME'] = '/usr/lib/jvm/java-8-openjdk-amd64/jre/'
os.environ['PYSPARK_SUBMIT_ARGS'] = '--master yarn --deploy-mode client pyspark-shell'

# Now import pyspark and create session
from pyspark.sql import SparkSession

spark = (SparkSession.builder
    .appName("UpgradedSpark")
    .master("yarn")
    .config("spark.submit.deployMode", "client")
    .config("spark.sql.catalogImplementation", "hive")
    .config("hive.metastore.uris", "thrift://ip-10-42-66-135.us-east-2.compute.internal:9083")
    .config("spark.sql.warehouse.dir", "s3://iuh-datalab-persistence-s3-data/warehouse")
    .config("spark.dynamicAllocation.enabled", "true")
    .config("spark.dynamicAllocation.minExecutors", "2")
    .config("spark.dynamicAllocation.maxExecutors", "15")
    .config("spark.shuffle.service.enabled", "true")
    .config("spark.driver.memory", "4g")
    .config("spark.executor.memory", "15g")
    .config("spark.sql.legacy.allowCreatingManagedTableUsingNonemptyLocation", "true")
    .config("hive.exec.dynamic.partition.mode", "nonstrict")
    .enableHiveSupport()
    .getOrCreate()
)

# Verify connection
schemas = [row[0] for row in spark.sql("SHOW SCHEMAS").collect()]
print(f"Connected to metastore: {len(schemas)} schemas found")
```

## Why Upgraded Spark Fails Without Configuration

When you upgrade Spark via pip/conda, the new pyspark:

1. Doesn't inherit `HADOOP_CONF_DIR=/etc/jupyter/configs`
2. Creates its own SparkSession without the hive metastore URI
3. Falls back to a local/empty metastore (only shows "default" schema)

## Critical Configuration for Metastore Access

The upgraded Spark kernels set these environment variables:

| Variable | Value | Purpose |
|----------|-------|---------|
| `HADOOP_CONF_DIR` | `/etc/jupyter/configs` | Contains hive.metastore.uris |
| `HADOOP_HOME` | `/usr/local/hadoop` | Hadoop binaries |
| `JAVA_HOME` | `/usr/lib/jvm/java-8-openjdk-amd64/jre/` | Required for Spark |
| `PYSPARK_SUBMIT_ARGS` | `--master yarn --deploy-mode client pyspark-shell` | Uses YARN |

## Verifying Metastore Connection

After creating a SparkSession, verify the connection:

```python
schemas = spark.sql("SHOW SCHEMAS").collect()
print(f"Found {len(schemas)} schemas")

# Should show 36 schemas including:
# - adhocquery
# - clinical_research_systems
# - demographics
# - real_world_data_ed_*
# - etc.
```

If you only see "default", the metastore connection failed.

## Spark Version Compatibility Notes

| Spark Version | Pandas Support | Notes |
|---------------|----------------|-------|
| 2.4.x | pandas < 1.0 | Current container version |
| 3.0.x | pandas < 1.3 | |
| 3.2.x | pandas < 1.4 | |
| 3.3+ | pandas 1.x and 2.x | Recommended upgrade target |

## Troubleshooting

### "Only default schema found"

- Check that `HADOOP_CONF_DIR` is set before importing pyspark
- Verify `/etc/jupyter/configs` exists and contains the metastore config
- Ensure you're using `.enableHiveSupport()` when building the session

### "Unable to instantiate SparkSession with Hive support"

- Check JAVA_HOME is set correctly
- Verify Hive JARs are available (usually in `/usr/local/spark/jars/`)

### Connection timeout to metastore

- The metastore URI may have changed - run `diagnose_spark_config.py` with a working kernel to get the current URI

## Related Files

- `setup-lhn-dual-envs.sh` - Main setup script (creates the upgraded Spark kernels)
- `spark_diagnostic_report.txt` - Diagnostic output from working Spark configuration
