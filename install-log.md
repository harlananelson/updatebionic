In jupyter:


# Import lhn                                                                                                               
import lhn                                                                                                                 
from lhn import Resources                                                                                                  
from lhn.header import *   


---------------------------------------------------------------------------
ModuleNotFoundError                       Traceback (most recent call last)
<ipython-input-2-5cccdb1c9593> in <module>
      1 # Import lhn
----> 2 import lhn
      3 from lhn import Resources
      4 from lhn.header import *

/tmp/lhn_prod_src/lhn/__init__.py in <module>
     38 
     39 
---> 40 from lhn.header import get_logger
     41 logger = get_logger(__name__)
     42 # Get the logger configured in __init__.py

/tmp/lhn_prod_src/lhn/header.py in <module>
     34 
     35 # Pyspark imports
---> 36 from pyspark import SparkConf, SparkContext, Broadcast
     37 from pyspark.sql.window import Window
     38 from pyspark.sql import SparkSession, DataFrame, functions as F, types

ModuleNotFoundError: No module named 'pyspark'