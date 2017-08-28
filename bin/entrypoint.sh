#!/usr/bin/env bash

# Exit on error. Append "|| true" if you expect an error.
# set -o errexit
# Exit on error inside any functions or subshells.
# set -o errtrace

classpath() { find $1 -type f -name "*.jar" | paste -sd:; }

# Valid log levels: ALL, TRACE, DEBUG, [INFO], WARN, ERROR, FATAL, OFF
set_log_level() {
  test -f "${HADOOP_CONF_DIR}/log4j.properties" && \
    sed -i "s~=\(ALL\|TRACE\|DEBUG\|INFO\|WARN\|ERROR\)~=${1-LOG_LEVEL}~g" "${HADOOP_CONF_DIR}/log4j.properties"
  test -f "${SPARK_HOME-}/conf/log4j.properties" && \
    sed -i "s~=\(ALL\|TRACE\|DEBUG\|INFO\|WARN\|ERROR\)~=${1-LOG_LEVEL}~g" "${SPARK_HOME}/conf/log4j.properties"
}

update_config() {
  if [[ -n "$1" && -f "$2" ]]; then
    echo "${1}" | UPDATE=1 $(dirname $0)/config.sh "$2"
    echo >&2 $(basename "$2") updated
  fi
}

mkdir -p /var/log/logs
test -z "${LOG_LEVEL-}" || set_log_level ${LOG_LEVEL-}

update_config "$core_site" "${HADOOP_CONF_DIR}/core-site.xml"
update_config "$hdfs_site" "${HADOOP_CONF_DIR}/hdfs-site.xml"
update_config "$yarn_site" "${YARN_CONF_DIR}/yarn-site.xml"
update_config "$mapred_site" "${HADOOP_CONF_DIR}/mapred-site.xml"
update_config "$capacity_scheduler" "${HADOOP_CONF_DIR}/capacity-scheduler.xml"

export CLASSPATH=${CLASSPATH-$(classpath $HADOOP_HOME)}
export SPARK_CLASSPATH=${SPARK_CLASSPATH-$(classpath $SPARK_HOME)}
export JAVA_LIBRARY_PATH=${JAVA_LIBRARY_PATH-"$HADOOP_HOME/lib/native"}
export HDFS_CLUSTER_NAME=${HDFS_CLUSTER_NAME-"the-cluster"}
export STDOUT_LOGS_TARGET=${STDOUT_LOGS_TARGET-/var/log/logs}
export SPARK_NO_DAEMONIZE=true
export SPARK_LOG_DIR=/var/log/logs
export HADOOP_LOG_DIR=/var/log/logs

source $HADOOP_PREFIX/libexec/hadoop-config.sh
source $SPARK_HOME/sbin/spark-config.sh
source $SPARK_HOME/bin/load-spark-env.sh

spark-submit() {
  $SPARK_HOME/bin/spark-submit \
  	--class org.apache.spark.examples.SparkPi \
  	--master yarn \
    --queue default \
  	--deploy-mode client \
    $SPARK_HOME/examples/jars/spark-examples_2.11-2.2.0.jar
}

### NameNode ### $HADOOP_PREFIX/sbin/hadoop-daemon.sh --config $HADOOP_CONF_DIR --script hdfs start namenode ###
namenode() {
  # Formats the specified NameNode. Note: -nonInteractive option aborts formating if the name directory exists,.
  hdfs namenode -format $HDFS_CLUSTER_NAME -nonInteractive;
  # Start the HDFS with the following command, run on the designated NameNode:
  hdfs namenode
}

### DataNode ### $HADOOP_PREFIX/sbin/hadoop-daemon.sh --config $HADOOP_CONF_DIR --script hdfs start datanode ###
datanode() {
  # Run a script to start DataNodes on all slaves:
  hdfs datanode
}

### SparkMaster ### $SPARK_HOME/sbin/start-master.sh ###
sparkmaster() {
  # Run a script to start Spark Master:
  $SPARK_HOME/bin/spark-class org.apache.spark.deploy.master.Master
}

### SparkWorker ### $SPARK_HOME/sbin/start-slave.sh spark://spark-master:7077 ###
sparkworker() {
  # Run a script to start Spark Worker:
  $SPARK_HOME/bin/spark-class org.apache.spark.deploy.worker.Worker \
    spark://${SPARK_MASTER_HOST-spark-master}:${SPARK_MASTER_PORT-7077}
}

### Spark JobHistory Server ### $SPARK_HOME/sbin/start-history-server.sh ###
spark-history() {
  hdfs dfs -mkdir -p /shared/spark-logs
  hdfs dfs -chmod -R 1777 /shared/spark-logs
  hdfs dfs -chown nobody:nobody /shared/spark-logs
  hdfs dfs -ls -R /shared
  # Start the MapReduce Spark Server with the following command, run on the designated server:
  $SPARK_HOME/bin/spark-class org.apache.spark.deploy.history.HistoryServer
}

### MapReduce JobHistory Server ### $HADOOP_PREFIX/sbin/mr-jobhistory-daemon.sh --config $HADOOP_CONF_DIR start historyserver ###
job-history() {
  hdfs dfs -mkdir -p /shared/spark-logs
  # Start the MapReduce JobHistory Server with the following command, run on the designated server:
  $HADOOP_PREFIX/bin/mapred historyserver
}

### NodeManager ### $HADOOP_YARN_HOME/sbin/yarn-daemon.sh start nodemanager ###
node-manager() {
  # Run a script to start NodeManagers on all slaves:
  yarn --config "${YARN_CONF_DIR}" nodemanager "$@"
}

### ResourceManager ### $HADOOP_YARN_HOME/sbin/yarn-daemon.sh start resourcemanager ###
resource-manager() {
  # Start the YARN with the following command, run on the designated ResourceManager:
  yarn --config "${YARN_CONF_DIR}" resourcemanager "$@"
}

### WebAppProxy server
web-app-proxy() {
  # Start a standalone WebAppProxy server. If multiple servers are used with load balancing it should be run on each of them:
  $HADOOP_YARN_HOME/sbin/yarn-daemon.sh start proxyserver
}

# To start a Hadoop cluster you will need to start both the HDFS and YARN cluster.
# Typically you choose one machine in the cluster to act as the NameNode and one machine as to act as the ResourceManager, exclusively.
# The rest of the machines act as both a DataNode and NodeManager and are referred to as slaves.

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

# start bash if nothing selected
[[ 0 == $# ]] && echo "missing command" && exit 2

# keep container running by displaying selected service logs
stdout-logs() {
  local logs=${1-${STDOUT_LOGS_TARGET}}; let counter=1
  while true; do
    if [[ -d ${logs} ]]; then
      [[ $(ls -1q ${logs} | wc -l) -gt 0 ]] && tail --retry -f ${logs}
    else
      [[ -f ${logs} ]] && tail -f ${logs}
    fi
    if (( (counter++ % 15) == 0 )); then
      [[ -e ${logs} ]] || echo >&2 $(date +"%x %H:%M:%S WARN") "Unexpected logs target: ${logs}"
      echo >&2 $(date +"%x %H:%M:%S DEBUG") "Waiting for logs in ${logs} [log-level: ${LOG_LEVEL-}]"
    fi
    sleep 2
  done
}

exec 3>&1
exec 4>&2

with_logger() {
  label=$1; shift
  exec 1> >(while read line; do echo "$label: $line"; done >&3)
  exec 2> >(while read line; do echo "$label: $line"; done >&4)
  eval "$@"
}

OPTIND=1
while getopts "hswWnNdDmrwjJp-:" opt; do
  echo "Option: $opt"
  case "$opt" in
    h) help ;;
    n) namenode ;;
    d) datanode ;;
    s) sparkmaster ;;
    w) sparkworker ;;
    N) namenode ;;
    D) with_logger 'nm' node-manager & datanode ;;
    W) with_logger 'nm' node-manager & sparkworker ;;
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
        spark-submit) spark-submit ;;
      esac;;
    esac
done
shift $((OPTIND-1))
[ "$1" = "--" ] && shift

# exec additional/different command
if [[ $# -gt 0 ]]; then
  echo "executing '$@'"
  exec "$@"
fi

# Use STDOUT_LOGS_TARGET environment to display particular log file/directory
# STDOUT_LOGS_TARGET=${STDOUT_LOGS_TARGET-${HADOOP_PREFIX}/logs}
# keep container running by displaying selected service logs
# stdout-logs ${STDOUT_LOGS_TARGET}
# wait
