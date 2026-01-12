### Spark Installation Documentation

#### Overview
Apache Spark is an open-source distributed computing system used for big data processing and analytics. This document provides details about the Spark installation on your system.

#### Installation Details

- **Spark Version**: 2.4.4
- **Scala Version**: 2.11.12
- **Java Version**: OpenJDK 64-Bit Server VM, 1.8.0_242

#### Environment Variables

- **`SPARK_HOME`**: `/usr/local/spark`
  - This variable points to the directory where Spark is installed.

- **`PYTHONPATH`**: `/usr/local/spark/python:/usr/local/spark/python/lib/py4j-0.10.7-src.zip`
  - This variable includes paths to the PySpark modules, allowing Python to locate and use PySpark.

#### Key Directories

- **Spark Installation Directory**: `/usr/local/spark-2.4.4-bin-hadoop2.7`
  - This is the root directory of the Spark installation.

- **PySpark Directory**: `/usr/local/spark/python/pyspark`
  - This directory contains the PySpark library, which allows you to use Spark with Python.

#### Verifying the Installation

To verify that Spark is correctly installed and accessible, you can perform the following steps:

1. **Check Spark Version**:
   ```bash
   /usr/local/spark/bin/spark-submit --version
   ```

2. **Start PySpark Shell**:
   ```bash
   /usr/local/spark/bin/pyspark
   ```

3. **Run a Test Script**:
   Create a Python script named `test_spark.py` with the following content:
   ```python
   from pyspark.sql import SparkSession

   spark = SparkSession.builder \
       .appName("Test App") \
       .getOrCreate()

   print("Spark version:", spark.version)
   ```

   Run the script using:
   ```bash
   python test_spark.py
   ```

#### Using Spark

- **Accessing Spark Shell**:
  You can start the Spark shell by running:
  ```bash
  /usr/local/spark/bin/spark-shell
  ```

- **Accessing PySpark Shell**:
  You can start the PySpark shell by running:
  ```bash
  /usr/local/spark/bin/pyspark
  ```

#### Additional Information

- **Spark Configuration**:
  Configuration files for Spark are typically located in the `$SPARK_HOME/conf` directory. You can modify these files to configure Spark settings as needed.

- **Running Spark Jobs**:
  To run a Spark job, use the `spark-submit` script located in the `$SPARK_HOME/bin` directory. For example:
  ```bash
  /usr/local/spark/bin/spark-submit --master local[4] your_spark_script.py
  ```

#### Troubleshooting

- **Environment Variables**:
  Ensure that the `SPARK_HOME` and `PYTHONPATH` environment variables are correctly set. You can add these to your shell configuration file (e.g., `.bashrc`, `.zshrc`) to make them persistent.

- **Permissions**:
  Ensure that you have the necessary permissions to access the Spark directories and execute the scripts.
