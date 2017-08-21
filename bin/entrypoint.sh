#!/usr/bin/env bash

# Exit on error. Append "|| true" if you expect an error.
# set -o errexit
# Exit on error inside any functions or subshells.
# set -o errtrace

print_env() {
  printenv | sort
  echo && IFS=:; printf "%s\n" $PATH && echo
  echo && IFS=:; printf "%s\n" $CLASSPATH && echo
  echo && IFS=:; printf "%s\n" $(hdfs classpath) && echo
}

classpath() {
  # find $1 -type f -name "*.jar" | xargs -I{} dirname {} | uniq | sed -e 's/$/\/\*/' | paste -sd:
  find $1 -type f -name "*.jar" | paste -sd:
}

export CLASSPATH=${CLASSPATH-$(classpath $HADOOP_HOME)}
export SPARK_CLASSPATH=${SPARK_CLASSPATH-$(classpath $SPARK_HOME)}
export JAVA_LIBRARY_PATH=${JAVA_LIBRARY_PATH-"$HADOOP_HOME/lib/native"}
export HDFS_CLUSTER_NAME=${HDFS_CLUSTER_NAME-"the-cluster"}
export SPARK_NO_DAEMONIZE=true

source $HADOOP_PREFIX/libexec/hadoop-config.sh

spark-submit() {
  $SPARK_HOME/bin/spark-submit \
  	--class org.apache.spark.examples.SparkPi \
  	--master yarn \
    --queue default \
  	--deploy-mode client \
    /usr/local/spark/examples/jars/spark-examples_2.11-2.2.0.jar
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
  stdout-logs ${SPARK_HOME}/logs
}

### SparkWorker ### $SPARK_HOME/sbin/start-slave.sh spark://spark-master:7077 ###
sparkworker() {
  # Run a script to start Spark Worker:
  $SPARK_HOME/bin/spark-class org.apache.spark.deploy.worker.Worker \
    spark://${SPARK_MASTER_HOST-spark-master}:${SPARK_MASTER_PORT-7077}
  stdout-logs ${SPARK_HOME}/logs
}

### Spark JobHistory Server ### $SPARK_HOME/bin/spark-class org.apache.spark.deploy.history.HistoryServer 1 ###
spark-history() {
  hdfs dfs -mkdir -p /shared/spark-logs
  # Start the MapReduce Spark Server with the following command, run on the designated server:
  $SPARK_HOME/sbin/start-history-server.sh
  stdout-logs ${SPARK_HOME}/logs
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

# Valid log levels: ALL, TRACE, DEBUG, [INFO], WARN, ERROR, FATAL, OFF
log-level() {
  test -f $HADOOP_CONF_DIR/log4j.properties && \
    sed "s~=\(ALL\|TRACE\|DEBUG\|INFO\|WARN\|ERROR\),\?~=${LOG_LEVEL}~g" $HADOOP_CONF_DIR/log4j.properties
  test -f ${SPARK_HOME-}/conf/log4j.properties && \
    sed "s~=\(ALL\|TRACE\|DEBUG\|INFO\|WARN\|ERROR\),\?~=${LOG_LEVEL}~g" $SPARK_HOME/conf/log4j.properties
}

update_config() {
  if [[ -n "$1" && -f "$2" ]]; then
    echo "${1}" | UPDATE=1 $(dirname $0)/config.sh "$2"
    echo >&2 $(basename "$2") updated
  fi
}
test -n ${LOG_LEVEL-} && log-level
update_config "$core_site" "${HADOOP_CONF_DIR}/core-site.xml"
update_config "$hdfs_site" "${HADOOP_CONF_DIR}/hdfs-site.xml"
update_config "$yarn_site" "${YARN_CONF_DIR}/yarn-site.xml"
update_config "$mapred_site" "${HADOOP_CONF_DIR}/mapred-site.xml"
update_config "$capacity_scheduler" "${HADOOP_CONF_DIR}/capacity-scheduler.xml"

# keep container running by displaying selected service logs
stdout-logs() {
  local logs=${1-${STDOUT_LOGS_TARGET-${HADOOP_PREFIX}/logs}}
  test -e ${logs} && while true; do
    if [[ -d ${logs} ]]; then tail -f ${logs}/*; else tail -f ${logs}; fi
  done
}

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

exec 3>&1
exec 4>&2

with_logger() {
  exec 1> >(while read line; do echo "$(basename $1 .sh): $line"; done >&3)
  exec 2> >(while read line; do echo "$(basename $1 .sh): $line"; done >&4)
  type $1 | grep 'function' > /dev/null && eval "$@" || exec $@
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
    D) with_logger node-manager & datanode ;;
    W) with_logger node-manager & sparkworker ;;
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
STDOUT_LOGS_TARGET=${STDOUT_LOGS_TARGET-${HADOOP_PREFIX}/logs}
# keep container running by displaying selected service logs
stdout-logs ${STDOUT_LOGS_TARGET}
