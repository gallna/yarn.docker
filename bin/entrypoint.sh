#!/usr/bin/env bash

# Exit on error. Append "|| true" if you expect an error.
# set -o errexit
# Exit on error inside any functions or subshells.
# set -o errtrace
echo "$0: ${@-}"

HDFS_CLUSTER_NAME=${HDFS_CLUSTER_NAME-"the-cluster"}

### NameNode
namenode() {
  # Formats the specified NameNode. Note: -nonInteractive option aborts formating if the name directory exists,.
  $HADOOP_PREFIX/bin/hdfs namenode -format $HDFS_CLUSTER_NAME -nonInteractive;
  # Start the HDFS with the following command, run on the designated NameNode:
  $HADOOP_PREFIX/bin/hdfs --config $HADOOP_CONF_DIR namenode
  # $HADOOP_PREFIX/sbin/hadoop-daemon.sh --config $HADOOP_CONF_DIR --script hdfs start namenode
}

### DataNode
datanode() {
  $HADOOP_PREFIX/bin/hdfs --config $HADOOP_CONF_DIR datanode
  # Run a script to start DataNodes on all slaves:
  # $HADOOP_PREFIX/sbin/hadoop-daemon.sh --config $HADOOP_CONF_DIR --script hdfs start datanode
}


### SparkMaster
sparkmaster() {
  # Run a script to start Spark Master:
  $SPARK_HOME/bin/spark-class org.apache.spark.deploy.master.Master
}

### SparkNode
sparkworker() {
  # Run a script to start Spark Worker:
  $SPARK_HOME/bin/spark-class org.apache.spark.deploy.worker.Worker spark://spark-master:7077
}

### Spark JobHistory Server
spark-history() {
  # Start the MapReduce Spark Server with the following command, run on the designated server:
  $HADOOP_PREFIX/bin/hdfs dfs -mkdir -p /shared/spark-logs
  $HADOOP_PREFIX/bin/hdfs dfs -ls /
  $HADOOP_PREFIX/bin/hdfs dfs -ls /shared
  $SPARK_HOME/bin/spark-class org.apache.spark.deploy.history.HistoryServer
  stdout-logs ${SPARK_HOME}/logs
}

### NodeManager
node-manager() {
  # Run a script to start NodeManagers on all slaves:
  $HADOOP_YARN_HOME/sbin/yarn-daemon.sh --config $HADOOP_CONF_DIR start nodemanager
}

### ResourceManager
resource-manager() {
  # Start the YARN with the following command, run on the designated ResourceManager:
  $HADOOP_YARN_HOME/sbin/yarn-daemon.sh --config $HADOOP_CONF_DIR start resourcemanager || cat ${logs}/*
}

### WebAppProxy server
web-app-proxy() {
  # Start a standalone WebAppProxy server. If multiple servers are used with load balancing it should be run on each of them:
  $HADOOP_YARN_HOME/sbin/yarn-daemon.sh --config $HADOOP_CONF_DIR start proxyserver
}

### MapReduce JobHistory Server
job-history() {
  $HADOOP_PREFIX/bin/mapred --config $HADOOP_CONF_DIR historyserver
  # Start the MapReduce JobHistory Server with the following command, run on the designated server:
  # $HADOOP_PREFIX/sbin/mr-jobhistory-daemon.sh --config $HADOOP_CONF_DIR start historyserver
  PID=$(cat $(find ${HADOOP_MAPRED_PID_DIR-/tmp} -name "mapred-*.pid"))
}

# To start a Hadoop cluster you will need to start both the HDFS and YARN cluster.
# Typically you choose one machine in the cluster to act as the NameNode and one machine as to act as the ResourceManager, exclusively.
# The rest of the machines act as both a DataNode and NodeManager and are referred to as slaves.

mapred-site() {
  sed -i $(printf "s|<value>\w*:10020|<value>%s:10020|g" ${HDFS_MASTER_HOST-$(hostname)}) $HADOOP_CONF_DIR/mapred-site.xml
  sed -i $(printf "s|<value>\w*:19888|<value>%s:19888|g" ${HDFS_MASTER_HOST-$(hostname)}) $HADOOP_CONF_DIR/mapred-site.xml
  cat $HADOOP_CONF_DIR/mapred-site.xml
}
yarn-site() {
  sed -i $(printf "s|<value>resource-manager.docker</value>|<value>%s</value>|g" ${RESOURCE_MANAGER_HOST-$(hostname)}) $HADOOP_CONF_DIR/yarn-site.xml
  sed -i $(printf "s|http://\w*:19888/jobhistory/logs|http://%s:19888/jobhistory/logs|g" ${JOB_HISTORY_HOST-$(hostname)}) $HADOOP_CONF_DIR/hdfs-site.xml
  cat $HADOOP_CONF_DIR/yarn-site.xml
}
core-site() {
  sed -i $(printf "s|hdfs://\w*:8020|hdfs://%s:8020|g" ${HDFS_MASTER_HOST-$(hostname)}) $HADOOP_CONF_DIR/core-site.xml
  cat $HADOOP_CONF_DIR/core-site.xml
}

# keep container running by displaying selected service logs
stdout-logs() {
  local logs=${1-${STDOUT_LOGS_TARGET-${HADOOP_PREFIX}/logs}}
  args=( --retry ); test -z ${PID-} || args=( --pid=${PID} )
  test -e ${logs} && while true; do
    if [[ -d ${logs} ]]; then
      tail ${args[@]} -f ${logs}/*
    else
      tail ${args[@]} -f ${logs}
    fi
  done
}

# start bash if nothing selected
[[ 0 == $# ]] && echo "missing command"&& exit 2

help() {
  cat <<HELPMESSAGE
  Usage: `basename $0` [-h] [-c] [-y] [-e] [-n] [-N] [-d] [-D] [-m] [-r] [-w] [-j]

    Configuration:
      -c, --core-site         replace nodename hostname in core-site.xml
      -y, --yarn-site         replace resource-manager and job-history hostname in yarn-site.xml
      -e, --mapred-site       replace job-history hostname in mapred-site.xml

    Options:
      -n, --namenode          NameNode
      -N                      shortcut: --namenode --core-site
      -d, --datanode          DataNode
      -D                      shortcut: --datanode --node-manager
      -s, --sparkmaster       SparkMaster
      -w, --sparkworker       SparkWorker
      -W                      shortcut: --sparkworker --node-manager
      -m, --node-manager      NodeManager
      -r, --resource-manager  ResourceManager
      -p, --web-app-proxy     WebAppProxy server
      -j, --job-history       MapReduce JobHistory Server
      -J, --spark-history     MapRedSparkuce JobHistory Server

HELPMESSAGE
  exit 0;
}

OPTIND=1
while getopts "hcyeswWnNdDmrwjJp-:" opt; do
  echo "Option: $opt"
  case "$opt" in
    h) help ;;
    c) core-site ;;
    y) yarn-site ;;
    e) mapred-site ;;
    n) namenode ;;
    d) datanode ;;
    s) sparkmaster ;;
    w) sparkworker ;;
    N)
      core-site
      namenode
      ;;
    D)
      node-manager &
      datanode
      ;;
    W)
      node-manager &
      sparkworker
      ;;
    m) node-manager ;;
    r) resource-manager ;;
    p) web-app-proxy ;;
    j) job-history ;;
    J) spark-history ;;
    -)
      case "${OPTARG}" in
        help) help ;;
        core-site) core-site ;;
        yarn-site) yarn-site ;;
        mapred-site) mapred-site ;;
        namenode) namenode ;;
        datanode) datanode ;;
        sparkmaster) sparkmaster ;;
        sparkworker) sparkworker ;;
        node-manager) node-manager ;;
        resource-manager) resource-manager ;;
        web-app-proxy) web-app-proxy ;;
        job-history) job-history ;;
        spark-history) spark-history ;;
      esac;;
    esac
done
shift $((OPTIND-1))
[ "$1" = "--" ] && shift

# exec additional/different command
if [[ "$@" ]]; then
  echo "unrecognized option '$@'"
  exec "$@"
fi

# Use STDOUT_LOGS_TARGET environment to display particular log file/directory
STDOUT_LOGS_TARGET=${STDOUT_LOGS_TARGET-${HADOOP_PREFIX}/logs}

# keep container running by displaying selected service logs
stdout-logs ${STDOUT_LOGS_TARGET}

# test -d /usr/local/hadoop/logs && tail -f /usr/local/hadoop/logs/*.log || exec "$@"
