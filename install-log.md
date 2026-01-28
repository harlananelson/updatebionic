
hnelson3@ip-10-42-66-158:~/work/Users/hnelson3$
hnelson3@ip-10-42-66-158:~/work/Users/hnelson3$
hnelson3@ip-10-42-66-158:~/work/Users/hnelson3$
hnelson3@ip-10-42-66-158:~/work/Users/hnelson3$
hnelson3@ip-10-42-66-158:~/work/Users/hnelson3$
hnelson3@ip-10-42-66-158:~/work/Users/hnelson3$ bash setup-lhn-dual-envs.sh
========== LHN Dual Environment Setup ==========
Script directory: /home/hnelson3/work/Users/hnelson3
Tue Jan 27 19:08:56 UTC 2026

========== Part 1: Install SSH and Restore Keys ==========
Restoring SSH keys from persistent storage (/home/hnelson3/work/Users/hnelson3/.ssh)...
SSH keys restored successfully.
Starting ssh-agent...
Agent pid 32175
Adding SSH key to agent (you'll be prompted for passphrase once)...
Enter passphrase for /home/hnelson3/.ssh/id_ed25519:
Identity added: /home/hnelson3/.ssh/id_ed25519 (harlananelson@gmaill.com)
Testing GitHub SSH connectivity...
Hi harlananelson! You've successfully authenticated, but GitHub does not provide shell access.

========== Part 2: Verify Prerequisites ==========
Initializing old conda from /opt/conda...
Verifying pyspark in base environment...
pyspark version: 2.4.4
Prerequisites verified successfully.

========== Part 3: Verify/Update Source Repositories ==========

--- Setting up PRODUCTION source (v0.1.0-monolithic) ---
Removing existing production clone at /tmp/lhn_prod_src...
Cloning lhn repository for production to /tmp (fast)...
Cloning into '/tmp/lhn_prod_src'...
remote: Enumerating objects: 113, done.
remote: Counting objects: 100% (113/113), done.
remote: Compressing objects: 100% (101/101), done.
remote: Total 113 (delta 21), reused 103 (delta 11), pack-reused 0 (from 0)
Receiving objects: 100% (113/113), 251.85 KiB | 6.46 MiB/s, done.
Resolving deltas: 100% (21/21), done.
Fetching origin
Branch 'v0.1.0-monolithic' set up to track remote branch 'v0.1.0-monolithic' from 'origin'.
Switched to a new branch 'v0.1.0-monolithic'
Production clone checked out to v0.1.0-monolithic
Available tags:
v0.1.0
v0.2.0-dev

--- Verifying DEVELOPMENT sources (persistent storage) ---
Found lhn at /home/hnelson3/work/Users/hnelson3/lhn
Fetching origin
From github.com:harlananelson/lhn
 * branch            main       -> FETCH_HEAD
Already up to date.
lhn updated to latest main branch
Found spark_config_mapper at /home/hnelson3/work/Users/hnelson3/spark_config_mapper
Already up to date.
Found omop_concept_mapper at /home/hnelson3/work/Users/hnelson3/omop_concept_mapper
Already up to date.

Source repositories ready.

========== Part 4: Create Production Environment (lhn_prod) ==========
Removing existing production environment...
Cloning base environment to /tmp/lhn_prod...
This may take a few minutes...
/opt/conda/lib/python3.7/site-packages/boto3/compat.py:82: PythonDeprecationWarning: Boto3 will no longer support Python 3.7 starting December 13, 2023. To continue receiving service updates, bug fixes, and security updates please upgrade to Python 3.8 or later. More information can be found here: https://aws.amazon.com/blogs/developer/python-support-policy-updates-for-aws-sdks-and-tools/
  warnings.warn(warning, PythonDeprecationWarning)
Source:      /opt/conda
Destination: /tmp/lhn_prod
The following packages cannot be cloned out of the root environment:
 - conda-forge::conda-4.7.12-py37_1
Packages: 498
Files: 38214
Preparing transaction: done
Verifying transaction: done
Executing transaction: - b'Enabling notebook extension jupyter-js-widgets/extension...\n      - Validating: \x1b[32mOK\x1b[0m\n'
done
#
# To activate this environment, use
#
#     $ conda activate /tmp/lhn_prod
#
# To deactivate an active environment, use
#
#     $ conda deactivate

Activating production environment...
Upgrading pip...
Collecting pip
  Using cached pip-24.0-py3-none-any.whl (2.1 MB)
Installing collected packages: pip
  Attempting uninstall: pip
    Found existing installation: pip 20.0.2
    Uninstalling pip-20.0.2:
      Successfully uninstalled pip-20.0.2
Successfully installed pip-24.0
Installing lhn v0.1.0 (monolithic) in editable mode...
Obtaining file:///tmp/lhn_prod_src
  Checking if build backend supports build_editable ... done
  Preparing metadata (pyproject.toml) ... done
Installing collected packages: lhn
  Running setup.py develop for lhn
Successfully installed lhn-0.1.0
Fixing corrupted pandas installation...
Found existing installation: pandas 0.25.3
Uninstalling pandas-0.25.3:
  Successfully uninstalled pandas-0.25.3
Installing pandas 0.25.3 fresh (for pyspark 2.4.4 compatibility)...
Collecting pandas==0.25.3
  Downloading pandas-0.25.3-cp37-cp37m-manylinux1_x86_64.whl.metadata (4.8 kB)
Requirement already satisfied: python-dateutil>=2.6.1 in /tmp/lhn_prod/lib/python3.7/site-packages (from pandas==0.25.3) (2.8.1)
Requirement already satisfied: pytz>=2017.2 in /tmp/lhn_prod/lib/python3.7/site-packages (from pandas==0.25.3) (2019.3)
Requirement already satisfied: numpy>=1.13.3 in /tmp/lhn_prod/lib/python3.7/site-packages (from pandas==0.25.3) (1.17.5)
Requirement already satisfied: six>=1.5 in /tmp/lhn_prod/lib/python3.7/site-packages (from python-dateutil>=2.6.1->pandas==0.25.3)(1.14.0)
Downloading pandas-0.25.3-cp37-cp37m-manylinux1_x86_64.whl (10.4 MB)
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 10.4/10.4 MB 138.3 MB/s eta 0:00:00
Installing collected packages: pandas
  Attempting uninstall: pandas
    Found existing installation: pandas 1.2.4
    Uninstalling pandas-1.2.4:
      Successfully uninstalled pandas-1.2.4
Successfully installed pandas-0.25.3
Installing ipykernel...
Requirement already satisfied: ipykernel in /tmp/lhn_prod/lib/python3.7/site-packages (5.1.4)
Requirement already satisfied: ipython>=5.0.0 in /tmp/lhn_prod/lib/python3.7/site-packages (from ipykernel) (7.11.1)
Requirement already satisfied: traitlets>=4.1.0 in /tmp/lhn_prod/lib/python3.7/site-packages (from ipykernel) (4.3.3)
Requirement already satisfied: jupyter-client in /tmp/lhn_prod/lib/python3.7/site-packages (from ipykernel) (5.3.4)
Requirement already satisfied: tornado>=4.2 in /tmp/lhn_prod/lib/python3.7/site-packages (from ipykernel) (5.1.1)
Requirement already satisfied: setuptools>=18.5 in /tmp/lhn_prod/lib/python3.7/site-packages (from ipython>=5.0.0->ipykernel) (45.1.0.post20200119)
Requirement already satisfied: jedi>=0.10 in /tmp/lhn_prod/lib/python3.7/site-packages (from ipython>=5.0.0->ipykernel) (0.16.0)
Requirement already satisfied: decorator in /tmp/lhn_prod/lib/python3.7/site-packages (from ipython>=5.0.0->ipykernel) (4.4.1)
Requirement already satisfied: pickleshare in /tmp/lhn_prod/lib/python3.7/site-packages (from ipython>=5.0.0->ipykernel) (0.7.5)
Requirement already satisfied: prompt-toolkit!=3.0.0,!=3.0.1,<3.1.0,>=2.0.0 in /tmp/lhn_prod/lib/python3.7/site-packages (from ipython>=5.0.0->ipykernel) (3.0.3)
Requirement already satisfied: pygments in /tmp/lhn_prod/lib/python3.7/site-packages (from ipython>=5.0.0->ipykernel) (2.5.2)
Requirement already satisfied: backcall in /tmp/lhn_prod/lib/python3.7/site-packages (from ipython>=5.0.0->ipykernel) (0.1.0)
Requirement already satisfied: pexpect in /tmp/lhn_prod/lib/python3.7/site-packages (from ipython>=5.0.0->ipykernel) (4.8.0)
Requirement already satisfied: ipython-genutils in /tmp/lhn_prod/lib/python3.7/site-packages (from traitlets>=4.1.0->ipykernel) (0.2.0)
Requirement already satisfied: six in /tmp/lhn_prod/lib/python3.7/site-packages (from traitlets>=4.1.0->ipykernel) (1.14.0)
Requirement already satisfied: jupyter-core>=4.6.0 in /tmp/lhn_prod/lib/python3.7/site-packages (from jupyter-client->ipykernel) (4.6.1)
Requirement already satisfied: pyzmq>=13 in /tmp/lhn_prod/lib/python3.7/site-packages (from jupyter-client->ipykernel) (18.1.1)
Requirement already satisfied: python-dateutil>=2.1 in /tmp/lhn_prod/lib/python3.7/site-packages (from jupyter-client->ipykernel) (2.8.1)
Requirement already satisfied: parso>=0.5.2 in /tmp/lhn_prod/lib/python3.7/site-packages (from jedi>=0.10->ipython>=5.0.0->ipykernel) (0.6.0)
Requirement already satisfied: wcwidth in /tmp/lhn_prod/lib/python3.7/site-packages (from prompt-toolkit!=3.0.0,!=3.0.1,<3.1.0,>=2.0.0->ipython>=5.0.0->ipykernel) (0.1.8)
Requirement already satisfied: ptyprocess>=0.5 in /tmp/lhn_prod/lib/python3.7/site-packages (from pexpect->ipython>=5.0.0->ipykernel) (0.6.0)
Registering Jupyter kernel for production environment...
Installed kernelspec lhn_prod in /home/hnelson3/.local/share/jupyter/kernels/lhn_prod
Verifying lhn installation...
26/01/27 19:12:45 WARN NativeCodeLoader: Unable to load native-hadoop library for your platform... using builtin-java classes where applicable
Using Spark's default log4j profile: org/apache/spark/log4j-defaults.properties
Setting default log level to "WARN".
To adjust logging level use sc.setLogLevel(newLevel). For SparkR, use setLogLevel(newLevel).
26/01/27 19:12:46 WARN Utils: spark.executor.instances less than spark.dynamicAllocation.minExecutors is invalid, ignoring its setting, please update your configs.
26/01/27 19:12:47 WARN Client: Neither spark.yarn.jars nor spark.yarn.archive is set, falling back to uploading libraries under SPARK_HOME.
26/01/27 19:13:25 WARN Utils: spark.executor.instances less than spark.dynamicAllocation.minExecutors is invalid, ignoring its setting, please update your configs.
2026-01-27 19:13:25,929 - root - INFO - Spark Session Started by iuhealth.header.py
2026-01-27 19:13:25,930 - root - WARNING - plotnine currently not installed
Traceback (most recent call last):
  File "<string>", line 1, in <module>
  File "/tmp/lhn_prod_src/lhn/__init__.py", line 77, in <module>
    from lhn.plot import count, plot_counts, plotByTime, plotByTimely, plotTopEntities
  File "/tmp/lhn_prod_src/lhn/plot.py", line 2, in <module>
    from lhn.header import F, pn, datetime, TimestampType, DataFrame, StringType, pd, DateType, IntegerType, np, Window
ImportError: cannot import name 'pn' from 'lhn.header' (/tmp/lhn_prod_src/lhn/header.py)
WARNING: lhn import failed

========== Part 5: Create Development Environment (lhn_dev) ==========
Removing existing development environment...
Cloning base environment to /tmp/lhn_dev...
This may take a few minutes...
/opt/conda/lib/python3.7/site-packages/boto3/compat.py:82: PythonDeprecationWarning: Boto3 will no longer support Python 3.7 starting December 13, 2023. To continue receiving service updates, bug fixes, and security updates please upgrade to Python 3.8 or later. More information can be found here: https://aws.amazon.com/blogs/developer/python-support-policy-updates-for-aws-sdks-and-tools/
  warnings.warn(warning, PythonDeprecationWarning)
Source:      /opt/conda
Destination: /tmp/lhn_dev
The following packages cannot be cloned out of the root environment:
 - conda-forge::conda-4.7.12-py37_1
Packages: 498
Files: 38214
Preparing transaction: done
Verifying transaction: done
Executing transaction: / b'Enabling notebook extension jupyter-js-widgets/extension...\n      - Validating: \x1b[32mOK\x1b[0m\n'
done
#
# To activate this environment, use
#
#     $ conda activate /tmp/lhn_dev
#
# To deactivate an active environment, use
#
#     $ conda deactivate

Activating development environment...
Upgrading pip to support modern package formats...
Collecting pip
  Using cached pip-24.0-py3-none-any.whl (2.1 MB)
Installing collected packages: pip
  Attempting uninstall: pip
    Found existing installation: pip 20.0.2
    Uninstalling pip-20.0.2:
      Successfully uninstalled pip-20.0.2
Successfully installed pip-24.0
Fixing corrupted pandas installation...
Found existing installation: pandas 0.25.3
Uninstalling pandas-0.25.3:
  Successfully uninstalled pandas-0.25.3
Installing pandas 0.25.3 fresh (for pyspark 2.4.4 compatibility)...
Collecting pandas==0.25.3
  Downloading pandas-0.25.3-cp37-cp37m-manylinux1_x86_64.whl.metadata (4.8 kB)
Requirement already satisfied: python-dateutil>=2.6.1 in /tmp/lhn_dev/lib/python3.7/site-packages (from pandas==0.25.3) (2.8.1)
Requirement already satisfied: pytz>=2017.2 in /tmp/lhn_dev/lib/python3.7/site-packages (from pandas==0.25.3) (2019.3)
Requirement already satisfied: numpy>=1.13.3 in /tmp/lhn_dev/lib/python3.7/site-packages (from pandas==0.25.3) (1.17.5)
Requirement already satisfied: six>=1.5 in /tmp/lhn_dev/lib/python3.7/site-packages (from python-dateutil>=2.6.1->pandas==0.25.3) (1.14.0)
Downloading pandas-0.25.3-cp37-cp37m-manylinux1_x86_64.whl (10.4 MB)
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 10.4/10.4 MB 163.0 MB/s eta 0:00:00
Installing collected packages: pandas
  Attempting uninstall: pandas
    Found existing installation: pandas 1.2.4
    Uninstalling pandas-1.2.4:
      Successfully uninstalled pandas-1.2.4
Successfully installed pandas-0.25.3
Installing dependencies for refactored lhn from persistent storage...
Installing spark_config_mapper from /home/hnelson3/work/Users/hnelson3/spark_config_mapper...
  (Using --no-deps to avoid pandas version conflict with pyspark 2.4.4)
Obtaining file:///home/hnelson3/work/Users/hnelson3/spark_config_mapper
  Installing build dependencies ... done
  Checking if build backend supports build_editable ... done
  Getting requirements to build editable ... done
  Preparing editable metadata (pyproject.toml) ... done
Building wheels for collected packages: spark-config-mapper
  Building editable for spark-config-mapper (pyproject.toml) ... done
  Created wheel for spark-config-mapper: filename=spark_config_mapper-0.1.0-0.editable-py3-none-any.whl size=5096 sha256=8ee0f42c7bdd249caab85eea435b64eaf7dee354001a462f2ef17c23629871eb
  Stored in directory: /tmp/pip-ephem-wheel-cache-r448gfok/wheels/a9/86/5d/41da808220424a712ee82ddc922b831da5e6889190bb1678eb
Successfully built spark-config-mapper
Installing collected packages: spark-config-mapper
Successfully installed spark-config-mapper-0.1.0
Installing omop_concept_mapper from /home/hnelson3/work/Users/hnelson3/omop_concept_mapper...
  (Using --no-deps to avoid pandas version conflict)
Obtaining file:///home/hnelson3/work/Users/hnelson3/omop_concept_mapper
  Installing build dependencies ... done
  Checking if build backend supports build_editable ... done
  Getting requirements to build editable ... done
  Preparing editable metadata (pyproject.toml) ... done
Building wheels for collected packages: omop-concept-mapper
  Building editable for omop-concept-mapper (pyproject.toml) ... done
  Created wheel for omop-concept-mapper: filename=omop_concept_mapper-0.1.0-0.editable-py3-none-any.whl size=4934 sha256=570ddbbe6b5840cd3e34962d223c62468a3263a09a4694e6de549120ba3c4289
  Stored in directory: /tmp/pip-ephem-wheel-cache-kda23oea/wheels/63/96/49/b52089d164aab01ae5b6509b5c67632643629ba97a77763b42
Successfully built omop-concept-mapper
Installing collected packages: omop-concept-mapper
Successfully installed omop-concept-mapper-0.1.0
Installing lhn v0.2.0-dev (refactored) from /home/hnelson3/work/Users/hnelson3/lhn...
  (Using --no-deps to avoid pandas version conflict with pyspark 2.4.4)
Obtaining file:///home/hnelson3/work/Users/hnelson3/lhn
  Installing build dependencies ... done
  Checking if build backend supports build_editable ... done
  Getting requirements to build editable ... done
  Preparing editable metadata (pyproject.toml) ... done
Building wheels for collected packages: lhn
  Building editable for lhn (pyproject.toml) ... done
  Created wheel for lhn: filename=lhn-0.2.0.dev0-0.editable-py3-none-any.whl size=4706 sha256=aeba7256a72e86699bce0f8f7241144050c846f40022bbee59f21424be286346
  Stored in directory: /tmp/pip-ephem-wheel-cache-qveggadn/wheels/40/05/cc/4dea4d09c52516c2074d46aca396600adf8e75c735740ea73c
Successfully built lhn
Installing collected packages: lhn
Successfully installed lhn-0.2.0.dev0
Installing ipykernel...
Requirement already satisfied: ipykernel in /tmp/lhn_dev/lib/python3.7/site-packages (5.1.4)
Requirement already satisfied: ipython>=5.0.0 in /tmp/lhn_dev/lib/python3.7/site-packages (from ipykernel) (7.11.1)
Requirement already satisfied: traitlets>=4.1.0 in /tmp/lhn_dev/lib/python3.7/site-packages (from ipykernel) (4.3.3)
Requirement already satisfied: jupyter-client in /tmp/lhn_dev/lib/python3.7/site-packages (from ipykernel) (5.3.4)
Requirement already satisfied: tornado>=4.2 in /tmp/lhn_dev/lib/python3.7/site-packages (from ipykernel) (5.1.1)
Requirement already satisfied: setuptools>=18.5 in /tmp/lhn_dev/lib/python3.7/site-packages (from ipython>=5.0.0->ipykernel) (45.1.0.post20200119)
Requirement already satisfied: jedi>=0.10 in /tmp/lhn_dev/lib/python3.7/site-packages (from ipython>=5.0.0->ipykernel) (0.16.0)
Requirement already satisfied: decorator in /tmp/lhn_dev/lib/python3.7/site-packages (from ipython>=5.0.0->ipykernel) (4.4.1)
Requirement already satisfied: pickleshare in /tmp/lhn_dev/lib/python3.7/site-packages (from ipython>=5.0.0->ipykernel) (0.7.5)
Requirement already satisfied: prompt-toolkit!=3.0.0,!=3.0.1,<3.1.0,>=2.0.0 in /tmp/lhn_dev/lib/python3.7/site-packages (from ipython>=5.0.0->ipykernel) (3.0.3)
Requirement already satisfied: pygments in /tmp/lhn_dev/lib/python3.7/site-packages (from ipython>=5.0.0->ipykernel) (2.5.2)
Requirement already satisfied: backcall in /tmp/lhn_dev/lib/python3.7/site-packages (from ipython>=5.0.0->ipykernel) (0.1.0)
Requirement already satisfied: pexpect in /tmp/lhn_dev/lib/python3.7/site-packages (from ipython>=5.0.0->ipykernel) (4.8.0)
Requirement already satisfied: ipython-genutils in /tmp/lhn_dev/lib/python3.7/site-packages (from traitlets>=4.1.0->ipykernel) (0.2.0)
Requirement already satisfied: six in /tmp/lhn_dev/lib/python3.7/site-packages (from traitlets>=4.1.0->ipykernel) (1.14.0)
Requirement already satisfied: jupyter-core>=4.6.0 in /tmp/lhn_dev/lib/python3.7/site-packages (from jupyter-client->ipykernel) (4.6.1)
Requirement already satisfied: pyzmq>=13 in /tmp/lhn_dev/lib/python3.7/site-packages (from jupyter-client->ipykernel) (18.1.1)
Requirement already satisfied: python-dateutil>=2.1 in /tmp/lhn_dev/lib/python3.7/site-packages (from jupyter-client->ipykernel) (2.8.1)
Requirement already satisfied: parso>=0.5.2 in /tmp/lhn_dev/lib/python3.7/site-packages (from jedi>=0.10->ipython>=5.0.0->ipykernel) (0.6.0)
Requirement already satisfied: wcwidth in /tmp/lhn_dev/lib/python3.7/site-packages (from prompt-toolkit!=3.0.0,!=3.0.1,<3.1.0,>=2.0.0->ipython>=5.0.0->ipykernel) (0.1.8)
Requirement already satisfied: ptyprocess>=0.5 in /tmp/lhn_dev/lib/python3.7/site-packages (from pexpect->ipython>=5.0.0->ipykernel) (0.6.0)
Registering Jupyter kernel for development environment...
Installed kernelspec lhn_dev in /home/hnelson3/.local/share/jupyter/kernels/lhn_dev
Verifying lhn installation...
26/01/27 19:17:06 WARN NativeCodeLoader: Unable to load native-hadoop library for your platform... using builtin-java classes where applicable
Using Spark's default log4j profile: org/apache/spark/log4j-defaults.properties
Setting default log level to "WARN".
To adjust logging level use sc.setLogLevel(newLevel). For SparkR, use setLogLevel(newLevel).
26/01/27 19:17:07 WARN Utils: spark.executor.instances less than spark.dynamicAllocation.minExecutors is invalid, ignoring its setting, please update your configs.
26/01/27 19:17:08 WARN Client: Neither spark.yarn.jars nor spark.yarn.archive is set, falling back to uploading libraries under SPARK_HOME.
26/01/27 19:17:45 WARN Utils: spark.executor.instances less than spark.dynamicAllocation.minExecutors is invalid, ignoring its setting, please update your configs.
lhn imported successfully

========== Setup Complete! ==========

Created two conda environments with lhn:

  PRODUCTION (monolithic v0.1.0):
    Environment: /tmp/lhn_prod
    Source code: /tmp/lhn_prod_src
    Kernel: Python (lhn-prod v0.1.0)
    Activate: conda activate /tmp/lhn_prod

  DEVELOPMENT (refactored v0.2.0-dev):
    Environment: /tmp/lhn_dev
    Source code: /home/hnelson3/work/Users/hnelson3/lhn (persistent)
    Dependencies: /home/hnelson3/work/Users/hnelson3/spark_config_mapper
                  /home/hnelson3/work/Users/hnelson3/omop_concept_mapper
    Kernel: Python (lhn-dev v0.2.0)
    Activate: conda activate /tmp/lhn_dev

========== Jupyter Kernel Usage ==========

In JupyterLab, create two notebooks and select:
  - Notebook 1: Kernel > Change Kernel > Python (lhn-prod v0.1.0)
  - Notebook 2: Kernel > Change Kernel > Python (lhn-dev v0.2.0)

Run cells step-by-step in both to compare behavior.

========== Editable Installs ==========

Both environments use editable installs (-e), so:
  - Changes to /tmp/lhn_prod_src affect the production env (temp, lost on restart)
  - Changes to /home/hnelson3/work/Users/hnelson3/lhn affect the development env (persistent)

Production source is in /tmp (fast but ephemeral).
Development source is in ~/work (persistent S3 mount).

========== Pandas Version Note ==========

IMPORTANT: Both environments use pandas 0.25.3 (from base conda)
for compatibility with pyspark 2.4.4.

The pyproject.toml files in spark_config_mapper and lhn v0.2.0
require pandas>=1.0.0, but this was bypassed using --no-deps.

If you encounter pandas-related import errors, the code may need
to be updated to support pandas 0.25.x API.

========== List Available Kernels ==========
Available kernels:
  lhn_dev     /home/hnelson3/.local/share/jupyter/kernels/lhn_dev
  lhn_prod    /home/hnelson3/.local/share/jupyter/kernels/lhn_prod
  ir          /opt/conda/share/jupyter/kernels/ir
  python3     /opt/conda/share/jupyter/kernels/python3
  pyspark     /usr/local/share/jupyter/kernels/pyspark

Setup completed at: Tue Jan 27 19:17:57 UTC 2026
hnelson3@ip-10-42-66-158:~/work/Users/hnelson3$
hnelson3@ip-10-42-66-158:~/work/Users/hnelson3$
hnelson3@ip-10-42-66-158:~/work/Users/hnelson3$