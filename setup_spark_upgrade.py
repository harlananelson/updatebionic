#!/usr/bin/env python3
"""
Spark Upgrade with Metastore Access

This module provides functions to create a SparkSession with an upgraded
Spark version while maintaining access to the Hive metastore.

The key is ensuring the new Spark picks up the Hadoop configuration from
/etc/jupyter/configs which contains the hive.metastore.uris setting.

Usage in a Jupyter notebook:

    # Method 1: Use this module directly
    from setup_spark_upgrade import create_spark_session
    spark = create_spark_session()
    spark.sql("SHOW SCHEMAS").show()

    # Method 2: Copy the create_spark_session function into your notebook

Prerequisites:
    - Install pyspark in your conda environment:
      pip install pyspark==3.3.0  # or your desired version

    - The environment must have access to /etc/jupyter/configs
    - The environment must have access to /usr/local/hadoop and /usr/local/spark JARs
"""

import os
import sys


def setup_environment():
    """
    Set up environment variables required for Spark to connect to the metastore.
    Call this BEFORE importing pyspark.
    """
    # Critical: This directory contains hive-site.xml (or equivalent) with metastore URIs
    os.environ['HADOOP_CONF_DIR'] = '/etc/jupyter/configs'

    # Hadoop and Spark homes from the working container setup
    os.environ['HADOOP_HOME'] = '/usr/local/hadoop'
    os.environ['SPARK_HOME'] = os.environ.get('SPARK_HOME', '/usr/local/spark')

    # Java home
    os.environ['JAVA_HOME'] = '/usr/lib/jvm/java-8-openjdk-amd64/jre/'

    # YARN settings
    os.environ['PYSPARK_SUBMIT_ARGS'] = '--master yarn --deploy-mode client pyspark-shell'

    # Ensure Hadoop binaries are in PATH
    hadoop_bin = '/usr/local/hadoop/bin'
    if hadoop_bin not in os.environ.get('PATH', ''):
        os.environ['PATH'] = f"{hadoop_bin}:{os.environ.get('PATH', '')}"


def get_extra_jars():
    """
    Get paths to extra JARs needed for EMR/S3 functionality.
    These JARs provide the EmrFileSystem and other AWS-specific classes.
    """
    jar_dirs = [
        '/usr/local/spark/jars',
        '/usr/local/hadoop/share/hadoop/common/lib',
        '/usr/local/hadoop/share/hadoop/tools/lib',
    ]

    # Patterns for JARs we need
    jar_patterns = [
        'aws', 'emr', 's3', 'hadoop-aws', 'jets3t'
    ]

    extra_jars = []
    for jar_dir in jar_dirs:
        if os.path.isdir(jar_dir):
            for f in os.listdir(jar_dir):
                if f.endswith('.jar'):
                    if any(p in f.lower() for p in jar_patterns):
                        extra_jars.append(os.path.join(jar_dir, f))

    return extra_jars


def create_spark_session(app_name="UpgradedSpark", extra_config=None):
    """
    Create a SparkSession with Hive metastore access.

    This function:
    1. Sets up required environment variables
    2. Configures Spark to use the existing Hadoop configuration
    3. Enables Hive support with the correct metastore URIs

    Args:
        app_name: Name for the Spark application
        extra_config: Optional dict of additional Spark configurations

    Returns:
        SparkSession with Hive metastore access

    Example:
        spark = create_spark_session()
        spark.sql("SHOW SCHEMAS").show()  # Should show all 36 schemas
    """
    # Set up environment BEFORE importing pyspark
    setup_environment()

    # Now import pyspark
    from pyspark.sql import SparkSession

    # Build the session
    builder = SparkSession.builder.appName(app_name)

    # Essential configurations for metastore access
    essential_config = {
        # Hive metastore connection - THE KEY SETTINGS
        'spark.sql.catalogImplementation': 'hive',
        'hive.metastore.uris': 'thrift://ip-10-42-66-135.us-east-2.compute.internal:9083',
        'spark.sql.warehouse.dir': 's3://iuh-datalab-persistence-s3-data/warehouse',

        # YARN settings
        'spark.master': 'yarn',
        'spark.submit.deployMode': 'client',

        # Dynamic allocation
        'spark.dynamicAllocation.enabled': 'true',
        'spark.dynamicAllocation.minExecutors': '2',
        'spark.dynamicAllocation.maxExecutors': '15',
        'spark.shuffle.service.enabled': 'true',

        # Resource settings
        'spark.driver.memory': '4g',
        'spark.driver.cores': '3',
        'spark.executor.memory': '15g',
        'spark.executor.cores': '3',

        # Hive compatibility settings
        'spark.sql.legacy.allowCreatingManagedTableUsingNonemptyLocation': 'true',
        'hive.exec.dynamic.partition.mode': 'nonstrict',

        # S3/EMR settings (may need adjustment for newer Spark)
        'spark.sql.parquet.fs.optimized.committer.optimization-enabled': 'true',

        # Authentication (from original config)
        'spark.authenticate': 'true',
        'spark.authenticate.enableSaslEncryption': 'true',

        # Event logging
        'spark.eventLog.enabled': 'true',
        'spark.eventLog.dir': 'hdfs:///var/log/spark/apps',
    }

    # Apply essential config
    for key, value in essential_config.items():
        builder = builder.config(key, value)

    # Apply any extra config
    if extra_config:
        for key, value in extra_config.items():
            builder = builder.config(key, value)

    # Add extra JARs for EMR/S3 support if available
    extra_jars = get_extra_jars()
    if extra_jars:
        builder = builder.config('spark.jars', ','.join(extra_jars))

    # Enable Hive support - critical for metastore access
    builder = builder.enableHiveSupport()

    # Create the session
    spark = builder.getOrCreate()

    return spark


def test_metastore_connection(spark):
    """Test that the metastore connection is working."""
    print("Testing metastore connection...")
    schemas = spark.sql("SHOW SCHEMAS").collect()
    schema_names = [row[0] for row in schemas]

    print(f"Found {len(schema_names)} schemas:")
    for name in sorted(schema_names)[:10]:
        print(f"  - {name}")
    if len(schema_names) > 10:
        print(f"  ... and {len(schema_names) - 10} more")

    if len(schema_names) > 1:
        print("\n✓ Metastore connection successful!")
        return True
    else:
        print("\n✗ Metastore connection may have failed (only default schema found)")
        return False


# Jupyter kernel setup helper
def print_kernel_json():
    """Print a kernel.json that can be used to create a Jupyter kernel with metastore access."""
    import json

    kernel_spec = {
        "argv": [
            sys.executable,
            "-m", "ipykernel_launcher",
            "-f", "{connection_file}"
        ],
        "display_name": "PySpark Upgraded (with Metastore)",
        "language": "python",
        "env": {
            "HADOOP_CONF_DIR": "/etc/jupyter/configs",
            "HADOOP_HOME": "/usr/local/hadoop",
            "JAVA_HOME": "/usr/lib/jvm/java-8-openjdk-amd64/jre/",
            "PYSPARK_SUBMIT_ARGS": "--master yarn --deploy-mode client pyspark-shell",
            "PYSPARK_PYTHON": sys.executable,
            "PYSPARK_DRIVER_PYTHON": sys.executable,
            "PATH": f"/usr/local/hadoop/bin:{os.environ.get('PATH', '')}"
        }
    }

    print("Kernel specification (save as kernel.json):")
    print(json.dumps(kernel_spec, indent=2))
    print("\nTo install this kernel, create a directory and save the above JSON:")
    print("  mkdir -p ~/.local/share/jupyter/kernels/pyspark-upgraded")
    print("  # Save the JSON above to ~/.local/share/jupyter/kernels/pyspark-upgraded/kernel.json")


if __name__ == "__main__":
    print("Spark Upgrade with Metastore Access")
    print("=" * 50)

    # Create session and test
    spark = create_spark_session()
    print(f"\nSpark version: {spark.version}")
    print(f"Spark master: {spark.sparkContext.master}")

    test_metastore_connection(spark)

    print("\n" + "=" * 50)
    print("Kernel specification for Jupyter:")
    print("=" * 50)
    print_kernel_json()
