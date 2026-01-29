#!/usr/bin/env python3
"""
Spark/Hive Metastore Configuration Diagnostic Script

Run this in a Jupyter notebook cell using the WORKING pyspark kernel
(the one where spark.sql("show schemas") returns all your schemas).

This script captures all configuration needed to replicate the metastore
connection in an upgraded Spark version.

Usage:
    # In a Jupyter notebook cell:
    %run /path/to/diagnose_spark_config.py

    # Or copy/paste the entire script into a cell
"""

import os
import sys
import subprocess
from pathlib import Path

# Output file for the diagnostic report
OUTPUT_FILE = "/tmp/spark_diagnostic_report.txt"

def write_section(f, title, content):
    """Write a section to the report file."""
    f.write(f"\n{'='*60}\n")
    f.write(f"{title}\n")
    f.write(f"{'='*60}\n")
    f.write(content)
    f.write("\n")

def run_cmd(cmd):
    """Run a shell command and return output."""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
        return result.stdout + result.stderr
    except Exception as e:
        return f"Error running command: {e}"

def main():
    print("=" * 60)
    print("Spark/Hive Metastore Configuration Diagnostic")
    print("=" * 60)
    print(f"\nOutput will be saved to: {OUTPUT_FILE}\n")

    with open(OUTPUT_FILE, 'w') as f:
        f.write("SPARK/HIVE METASTORE CONFIGURATION DIAGNOSTIC REPORT\n")
        f.write(f"Generated: {subprocess.run(['date'], capture_output=True, text=True).stdout}\n")

        # ============================================================
        # Section 1: Spark Session Info
        # ============================================================
        print("1. Checking Spark session...")
        try:
            from pyspark.sql import SparkSession
            spark = SparkSession.builder.getOrCreate()
            sc = spark.sparkContext

            spark_info = f"""
Spark Version: {spark.version}
Spark Home: {os.environ.get('SPARK_HOME', 'NOT SET')}
App Name: {sc.appName}
Master: {sc.master}
"""
            write_section(f, "1. SPARK SESSION INFO", spark_info)
            print("   Spark session found")
        except Exception as e:
            write_section(f, "1. SPARK SESSION INFO", f"ERROR: Could not get Spark session: {e}")
            print(f"   ERROR: {e}")
            spark = None
            sc = None

        # ============================================================
        # Section 2: All Spark Configuration
        # ============================================================
        print("2. Extracting Spark configuration...")
        if sc:
            try:
                all_conf = sorted(sc.getConf().getAll())
                conf_text = "\n".join([f"{k} = {v}" for k, v in all_conf])
                write_section(f, "2. ALL SPARK CONFIGURATION", conf_text)
                print(f"   Found {len(all_conf)} config entries")
            except Exception as e:
                write_section(f, "2. ALL SPARK CONFIGURATION", f"ERROR: {e}")

        # ============================================================
        # Section 3: Hive/Metastore Specific Configuration
        # ============================================================
        print("3. Extracting Hive/Metastore configuration...")
        if sc:
            try:
                hive_keywords = ['hive', 'metastore', 'warehouse', 'kerberos', 'principal',
                                'keytab', 'auth', 'sasl', 'thrift', 'javax.jdo', 'datanucleus']
                hive_conf = [(k, v) for k, v in all_conf
                            if any(kw in k.lower() for kw in hive_keywords)]
                conf_text = "\n".join([f"{k} = {v}" for k, v in sorted(hive_conf)])
                if not conf_text:
                    conf_text = "(No hive/metastore specific configs found in Spark conf)"
                write_section(f, "3. HIVE/METASTORE SPECIFIC CONFIGURATION", conf_text)
                print(f"   Found {len(hive_conf)} hive-related config entries")
            except Exception as e:
                write_section(f, "3. HIVE/METASTORE SPECIFIC CONFIGURATION", f"ERROR: {e}")

        # ============================================================
        # Section 4: Hadoop Configuration
        # ============================================================
        print("4. Extracting Hadoop configuration...")
        if sc:
            try:
                hadoop_conf = sc._jsc.hadoopConfiguration()
                hadoop_entries = []
                iterator = hadoop_conf.iterator()
                while iterator.hasNext():
                    entry = iterator.next()
                    key = entry.getKey()
                    value = entry.getValue()
                    hadoop_entries.append((key, value))

                # Filter for relevant entries
                relevant_keywords = ['hive', 'metastore', 'fs.', 'dfs.', 'yarn.', 'hadoop.',
                                    'kerberos', 'principal', 'keytab', 'auth', 'security']
                relevant_entries = [(k, v) for k, v in hadoop_entries
                                   if any(kw in k.lower() for kw in relevant_keywords)]

                conf_text = "\n".join([f"{k} = {v}" for k, v in sorted(relevant_entries)])
                write_section(f, "4. HADOOP CONFIGURATION (relevant entries)", conf_text)
                print(f"   Found {len(relevant_entries)} relevant Hadoop config entries")

                # Also save full hadoop config
                full_conf_text = "\n".join([f"{k} = {v}" for k, v in sorted(hadoop_entries)])
                write_section(f, "4b. HADOOP CONFIGURATION (ALL entries)", full_conf_text)
            except Exception as e:
                write_section(f, "4. HADOOP CONFIGURATION", f"ERROR: {e}")

        # ============================================================
        # Section 5: Environment Variables
        # ============================================================
        print("5. Extracting environment variables...")
        env_keywords = ['spark', 'hadoop', 'hive', 'java', 'classpath', 'yarn',
                       'hdfs', 'kerberos', 'krb', 'keytab', 'principal', 'pyspark',
                       'pythonpath', 'conda', 'metastore']
        relevant_env = {k: v for k, v in os.environ.items()
                       if any(kw in k.lower() for kw in env_keywords)}
        env_text = "\n".join([f"{k} = {v}" for k, v in sorted(relevant_env.items())])
        write_section(f, "5. RELEVANT ENVIRONMENT VARIABLES", env_text)
        print(f"   Found {len(relevant_env)} relevant environment variables")

        # ============================================================
        # Section 6: Config File Locations
        # ============================================================
        print("6. Searching for config files...")
        config_search = """
--- Searching for hive-site.xml ---
"""
        config_search += run_cmd("find /opt /etc /usr /home -name 'hive-site.xml' 2>/dev/null | head -20")
        config_search += """
--- Searching for core-site.xml ---
"""
        config_search += run_cmd("find /opt /etc /usr /home -name 'core-site.xml' 2>/dev/null | head -20")
        config_search += """
--- Searching for hdfs-site.xml ---
"""
        config_search += run_cmd("find /opt /etc /usr /home -name 'hdfs-site.xml' 2>/dev/null | head -20")
        config_search += """
--- Searching for yarn-site.xml ---
"""
        config_search += run_cmd("find /opt /etc /usr /home -name 'yarn-site.xml' 2>/dev/null | head -20")
        config_search += """
--- Spark conf directory ---
"""
        spark_home = os.environ.get('SPARK_HOME', '/opt/conda/lib/python3.7/site-packages/pyspark')
        config_search += run_cmd(f"ls -la {spark_home}/conf/ 2>/dev/null || echo 'No conf dir at SPARK_HOME'")
        config_search += """
--- /etc/spark/conf ---
"""
        config_search += run_cmd("ls -la /etc/spark/conf/ 2>/dev/null || echo 'No /etc/spark/conf'")
        config_search += """
--- /etc/hive/conf ---
"""
        config_search += run_cmd("ls -la /etc/hive/conf/ 2>/dev/null || echo 'No /etc/hive/conf'")
        config_search += """
--- /etc/hadoop/conf ---
"""
        config_search += run_cmd("ls -la /etc/hadoop/conf/ 2>/dev/null || echo 'No /etc/hadoop/conf'")

        write_section(f, "6. CONFIG FILE LOCATIONS", config_search)
        print("   Config file search complete")

        # ============================================================
        # Section 7: Config File Contents
        # ============================================================
        print("7. Reading config file contents...")

        # Find and read hive-site.xml
        hive_sites = run_cmd("find /opt /etc /usr /home -name 'hive-site.xml' 2>/dev/null").strip().split('\n')
        config_contents = ""
        for hive_site in hive_sites:
            if hive_site and os.path.isfile(hive_site):
                config_contents += f"\n--- Contents of {hive_site} ---\n"
                config_contents += run_cmd(f"cat '{hive_site}'")

        # Find and read core-site.xml
        core_sites = run_cmd("find /opt /etc /usr /home -name 'core-site.xml' 2>/dev/null").strip().split('\n')
        for core_site in core_sites:
            if core_site and os.path.isfile(core_site):
                config_contents += f"\n--- Contents of {core_site} ---\n"
                config_contents += run_cmd(f"cat '{core_site}'")

        if not config_contents:
            config_contents = "(No config files found or readable)"

        write_section(f, "7. CONFIG FILE CONTENTS", config_contents)
        print("   Config file reading complete")

        # ============================================================
        # Section 8: Classpath and JARs
        # ============================================================
        print("8. Checking classpath and JARs...")
        classpath_info = """
--- HADOOP_CLASSPATH ---
"""
        classpath_info += os.environ.get('HADOOP_CLASSPATH', '(not set)') + "\n"
        classpath_info += """
--- SPARK_CLASSPATH ---
"""
        classpath_info += os.environ.get('SPARK_CLASSPATH', '(not set)') + "\n"
        classpath_info += """
--- Hadoop classpath command ---
"""
        classpath_info += run_cmd("hadoop classpath 2>/dev/null || echo 'hadoop command not found'")
        classpath_info += """
--- Hive-related JARs in Spark ---
"""
        spark_home = os.environ.get('SPARK_HOME', '/opt/conda/lib/python3.7/site-packages/pyspark')
        classpath_info += run_cmd(f"find {spark_home} -name '*hive*.jar' 2>/dev/null | head -30")
        classpath_info += """
--- Metastore JDBC driver JARs ---
"""
        classpath_info += run_cmd(f"find {spark_home} /opt -name '*mysql*.jar' -o -name '*postgres*.jar' -o -name '*mariadb*.jar' 2>/dev/null | head -20")

        write_section(f, "8. CLASSPATH AND JARS", classpath_info)
        print("   Classpath check complete")

        # ============================================================
        # Section 9: Test Metastore Connection
        # ============================================================
        print("9. Testing metastore connection...")
        if spark:
            try:
                schemas = spark.sql("SHOW SCHEMAS").collect()
                schema_list = [row[0] for row in schemas]
                test_result = f"Found {len(schema_list)} schemas:\n"
                test_result += "\n".join(f"  - {s}" for s in sorted(schema_list))
                write_section(f, "9. METASTORE CONNECTION TEST", test_result)
                print(f"   Found {len(schema_list)} schemas")
            except Exception as e:
                write_section(f, "9. METASTORE CONNECTION TEST", f"ERROR: {e}")
                print(f"   ERROR: {e}")

        # ============================================================
        # Section 10: SparkSession Builder Code
        # ============================================================
        print("10. Generating SparkSession builder code...")
        if sc:
            try:
                # Generate Python code to recreate this session
                all_conf = sorted(sc.getConf().getAll())
                builder_code = '''"""
Auto-generated SparkSession builder code.
Use this to create a SparkSession with the same configuration.
"""
from pyspark.sql import SparkSession

spark = (SparkSession.builder
    .appName("UpgradedSpark")
'''
                for k, v in all_conf:
                    # Escape quotes in values
                    v_escaped = v.replace('\\', '\\\\').replace('"', '\\"')
                    builder_code += f'    .config("{k}", "{v_escaped}")\n'

                builder_code += '''    .enableHiveSupport()
    .getOrCreate())

# Test connection
spark.sql("SHOW SCHEMAS").show()
'''
                write_section(f, "10. SPARKSESSION BUILDER CODE", builder_code)
                print("   Builder code generated")
            except Exception as e:
                write_section(f, "10. SPARKSESSION BUILDER CODE", f"ERROR: {e}")

        # ============================================================
        # Section 11: Kerberos Info (if applicable)
        # ============================================================
        print("11. Checking Kerberos configuration...")
        kerberos_info = """
--- klist (current tickets) ---
"""
        kerberos_info += run_cmd("klist 2>/dev/null || echo 'No Kerberos tickets or klist not available'")
        kerberos_info += """
--- /etc/krb5.conf ---
"""
        if os.path.isfile('/etc/krb5.conf'):
            kerberos_info += run_cmd("cat /etc/krb5.conf")
        else:
            kerberos_info += "(file not found)"
        kerberos_info += """
--- Keytab files ---
"""
        kerberos_info += run_cmd("find /etc /opt /home -name '*.keytab' 2>/dev/null | head -10")

        write_section(f, "11. KERBEROS CONFIGURATION", kerberos_info)
        print("   Kerberos check complete")

        # ============================================================
        # Section 12: Python/PySpark Path Info
        # ============================================================
        print("12. Checking Python/PySpark paths...")
        path_info = f"""
Python executable: {sys.executable}
Python version: {sys.version}
sys.path:
"""
        for p in sys.path:
            path_info += f"  {p}\n"

        path_info += f"""
PySpark location:
"""
        try:
            import pyspark
            path_info += f"  {pyspark.__file__}\n"
        except:
            path_info += "  (could not determine)\n"

        write_section(f, "12. PYTHON/PYSPARK PATHS", path_info)
        print("   Path check complete")

    # ============================================================
    # Done - print summary
    # ============================================================
    print("\n" + "=" * 60)
    print("DIAGNOSTIC COMPLETE")
    print("=" * 60)
    print(f"\nReport saved to: {OUTPUT_FILE}")
    print("\nTo view the report:")
    print(f"  cat {OUTPUT_FILE}")
    print("\nTo download (copy to persistent storage):")
    print(f"  cp {OUTPUT_FILE} ~/work/Users/$USER/")
    print("\nKey sections to review:")
    print("  - Section 3: Hive/Metastore specific config")
    print("  - Section 7: Config file contents (hive-site.xml)")
    print("  - Section 10: SparkSession builder code")
    print("  - Section 11: Kerberos configuration (if used)")

    # Also print the most critical info to stdout
    print("\n" + "=" * 60)
    print("QUICK SUMMARY - Metastore Connection Info")
    print("=" * 60)
    if sc:
        for k, v in sorted(sc.getConf().getAll()):
            if 'metastore' in k.lower() and 'uris' in k.lower():
                print(f"  {k} = {v}")
            if 'warehouse' in k.lower() and 'dir' in k.lower():
                print(f"  {k} = {v}")

if __name__ == "__main__":
    main()
