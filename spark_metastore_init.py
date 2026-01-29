"""
Spark Metastore Initialization Cell

Copy and paste this entire cell at the TOP of your notebook BEFORE any other imports.
This sets up an upgraded PySpark to connect to the Hive metastore.

IMPORTANT: This must run BEFORE you import pyspark!
"""

import os

# ============================================================
# STEP 1: Set environment variables BEFORE importing pyspark
# ============================================================
os.environ['HADOOP_CONF_DIR'] = '/etc/jupyter/configs'  # Contains metastore config
os.environ['HADOOP_HOME'] = '/usr/local/hadoop'
os.environ['JAVA_HOME'] = '/usr/lib/jvm/java-8-openjdk-amd64/jre/'
os.environ['PYSPARK_SUBMIT_ARGS'] = '--master yarn --deploy-mode client pyspark-shell'

# ============================================================
# STEP 2: Now import pyspark and create session
# ============================================================
from pyspark.sql import SparkSession

spark = (SparkSession.builder
    .appName("UpgradedSpark")
    .master("yarn")
    .config("spark.submit.deployMode", "client")
    # Hive metastore - THE CRITICAL SETTINGS
    .config("spark.sql.catalogImplementation", "hive")
    .config("hive.metastore.uris", "thrift://ip-10-42-66-135.us-east-2.compute.internal:9083")
    .config("spark.sql.warehouse.dir", "s3://iuh-datalab-persistence-s3-data/warehouse")
    # Dynamic allocation
    .config("spark.dynamicAllocation.enabled", "true")
    .config("spark.dynamicAllocation.minExecutors", "2")
    .config("spark.dynamicAllocation.maxExecutors", "15")
    .config("spark.shuffle.service.enabled", "true")
    # Resources
    .config("spark.driver.memory", "4g")
    .config("spark.executor.memory", "15g")
    # Hive compatibility
    .config("spark.sql.legacy.allowCreatingManagedTableUsingNonemptyLocation", "true")
    .config("hive.exec.dynamic.partition.mode", "nonstrict")
    .enableHiveSupport()
    .getOrCreate()
)

# ============================================================
# STEP 3: Verify connection
# ============================================================
print(f"Spark version: {spark.version}")
schemas = [row[0] for row in spark.sql("SHOW SCHEMAS").collect()]
print(f"Connected to metastore: {len(schemas)} schemas found")
if len(schemas) > 1:
    print("✓ Metastore connection successful!")
else:
    print("✗ Warning: Only default schema found - metastore may not be connected")
