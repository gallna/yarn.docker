# Hadoop/HDFS + Yarn + Spark docker configuration

## Usage:

`docker-compose up -d`

## Overview/status URL's and ports

Container name    | Description             | URL
---               | ---                     | ---
spark-master      | Spark status            | http://spark-master.docker:8080
namenode          | Hadoop/HDFS overview    | http://namenode.docker:50070
datanode          | NodeManager information | http://datanode.docker:8042
resource-manager  | Resource manager        | http://resource-manager.docker:8088
job-history       | Job History             | http://job-history.docker:19888

+ Hdfs ports
  **EXPOSE** 50010 50020 50070 50075 50090 8020 9000
+ Mapred ports
  **EXPOSE** 10020 19888
+ Yarn ports
  **EXPOSE** 8030 8031 8032 8033 8040 8042 8088
+ Other ports
  **EXPOSE** 49707

## Submit application:

docker run -ti -v /home/tomasz/data/gfstriped/s3:/s3 -v /home/tomasz/projects/big-data/hivexmlserde:/hivexmlserde --label io.rancher.container.network=true gallna/hive:hadoop bash

/usr/local/spark/bin/spark-submit \
  --master yarn \
  --deploy-mode cluster \
  --py-files /app/dist/*.egg \
  /app/xml_reduce.py

/usr/local/spark/bin/spark-submit \
    --class org.apache.spark.examples.SparkPi \
    --master yarn \
    --deploy-mode cluster \
    /usr/local/spark/examples/jars/spark-examples*.jar 10

# Knowledge base

## Docker DNS configuration

[Docker DNS-gen](https://github.com/jderusse/docker-dns-gen)

## HDFS configuration

[Octo blog](http://blog.octo.com/en/hadoop-distributed-file-system-overview-configuration/)
[Hortonworks docs](https://docs.hortonworks.com/HDPDocuments/HDP2/HDP-2.4.2/bk_installing_manually_book/content/ch_setting_up_hadoop_configuration_chapter.html)
[Cloudera docs](https://www.cloudera.com/documentation/enterprise/5-8-x/topics/cdh_ig_hdfs_cluster_deploy.html)
[HDFS Commands Guide](https://hadoop.apache.org/docs/r2.7.0/hadoop-project-dist/hadoop-hdfs/HDFSCommands.html#dfs)
[core-default.xml](https://hadoop.apache.org/docs/r0.23.11/hadoop-project-dist/hadoop-common/core-default.xml)

## Spark+Yarn configuration

[Running Spark on YARN](https://spark.apache.org/docs/latest/running-on-yarn.html)
[mastering apache spark/yarn](https://github.com/jaceklaskowski/mastering-apache-spark-book/tree/master/yarn)
[Docker Container Executor](https://hadoop.apache.org/docs/r2.7.2/hadoop-yarn/hadoop-yarn-site/DockerContainerExecutor.html)
[Docker containers as Apache YARN containers](http://blog.sequenceiq.com/blog/2015/01/07/yarn-containers-docker/)

## Exercises

[Spark & Python series of tutorials](https://www.codementor.io/jadianes/spark-python-data-aggregations-du107on3m)
