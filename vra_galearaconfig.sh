#! /bin/bash

source /etc/profile

##################################
##	VRA PASS PARAMETER	##
##################################

PROJCODE="LMS"
if [ -z ${PROJCODE} ]; then exit 99;
else PROJCODE="$(echo $PROJCODE | tr '[:upper:]' '[:lower:]')"; fi

##########################
##	DB HOST/IP	##
##########################

DBIP_NODE1="192.168.134.161"
DBIP_NODE2="192.168.134.162"
DBIP_NODE3="192.168.134.163"

DBHOST_NODE1="mariaha01"
DBHOST_NODE2="mariaha02"
DBHOST_NODE3="mariaha03"

###########################################################
if [ ${DBIP_NODE1} ] ; then DBIP_NODES+=(${DBIP_NODE1}); fi
if [ ${DBIP_NODE2} ] ; then DBIP_NODES+=(${DBIP_NODE2}); fi
if [ ${DBIP_NODE3} ] ; then DBIP_NODES+=(${DBIP_NODE3}); fi

if [ ${DBHOST_NODE1} ] ; then DBHOST_NODES+=(${DBHOST_NODE1}); fi
if [ ${DBHOST_NODE2} ] ; then DBHOST_NODES+=(${DBHOST_NODE2}); fi
if [ ${DBHOST_NODE3} ] ; then DBHOST_NODES+=(${DBHOST_NODE3}); fi
###########################################################

##########################
##	APP HOST/IP	##
##########################
APPIP_NODE1="192.168.134.171"
APPIP_NODE2="192.168.134.172"

APPHOST_NODE1="jboss01"
APPHOST_NODE2="jboss02"

###########################################################
if [ ${APPIP_NODE1} ] ; then APPIP_NODES+=(${APPIP_NODE1}); fi
if [ ${APPIP_NODE2} ] ; then APPIP_NODES+=(${APPIP_NODE2}); fi

if [ ${APPHOST_NODE1} ] ; then APPHOST_NODES+=(${APPHOST_NODE1}); fi
if [ ${APPHOST_NODE2} ] ; then APPHOST_NODES+=(${APPHOST_NODE2}); fi
###########################################################


## SYSTEM STATIC VARIABLE ##
ROOTPWD="password"
NETDEV0="eth0"
NETDEV1="eth1"

## DB STATIC VARIABLE ##
DB_NAME=${PROJCODE}"db"
APP_USER=${PROJCODE}"usr"
APP_PWD="passsw0rd"



function checkNode ()
{

NODE=0
IPNET0=`ifconfig ${NETDEV0}| grep "inet " | awk '{print $2}'`
#echo "${IPNET0}" 
#echo "${DBIP_NODES[${NODE}]}" 

for  IP in "${DBIP_NODES[@]}"; do 
     NODE=$((NODE+1));
     if [ "${IPNET0}" == "${IP}" ];then
	break;
     fi
done
}

checkNode
echo "$NODE"
echo "${DBIP_NODES[${NODE}-1]}" 
exit;

function startGalera ()
{
    nodeArray=("$@")
    ##echo "${nodeArray[@]}"
    if [[ "${NODE}" == "1" ]] ; then 
	echo "${nodeArray[0]} =>> Starting... galera_new_cluster"
     	if [ -z `/usr/bin/galera_new_cluster` ] ; then 
	    sleep 5;
	    result=`systemctl status mariadb | grep -E "Active:.*.running"`
	    if [ "${result}" ] ; then 
        	echo "      =>> Start galera_new_cluster completed"
	    	for (( i=1; i < ${#nodeArray[@]}; i++ ));
		do
  	    	    OUTPUT=`sshpass -p password ssh -o StrictHostKeyChecking=no \
            	    root\@${nodeArray[${i}]}  grep "^wsrep_on=ON" /etc/my.cnf.d/server.cnf`
		    if [ ${OUTPUT} ]; then  startService ${nodeArray[${i}]} mysql ; fi
		done	
	    else 
                echo "      =>> Start galera_new_cluster failed"
	        exit 99;
	    fi
	fi
     fi
}



function checkService(){
    IPSERV=$1
    SERVICE=$2
    OUTPUT=`sshpass -p password ssh -o StrictHostKeyChecking=no \
	root\@${IPSERV} systemctl status $SERVICE | grep -E "Active:.*.running"`
    echo  "${OUTPUT}" 
    #then
    #return  0; ## service running 
    #fi
    #return 1; ## service dead 
}

function stopService(){
    IPSERV=$1
    SERVICE=$2
    `sshpass -p password ssh -o StrictHostKeyChecking=no \
	root\@${IPSERV} systemctl stop $SERVICE`
    sleep 5;
    OUTPUT=`sshpass -p password ssh -o StrictHostKeyChecking=no \
	root\@${IPSERV} systemctl status $SERVICE | grep -E "Active:.*.dead"`
    if [  "${OUTPUT}" ]
    then
	return  0; ## stop sevice completed 
    fi
    return 1; ## stop service failed 
}

function startService(){
    IPSERV=$1
    SERVICE=$2
    echo "${IPSERV} =>> Starting... service $SERVICE"
    `sshpass -p password ssh -o StrictHostKeyChecking=no \
	root\@${IPSERV} systemctl start $SERVICE`
    sleep 5;
    OUTPUT=`sshpass -p password ssh -o StrictHostKeyChecking=no \
	root\@${IPSERV} systemctl status $SERVICE | grep -E "Active:.*.running"`
    echo "$OUTPUT"
    if [ "${OUTPUT}" ]
    then
	return  0; ## start sevice completed 
    fi
    return 1; ## start service failed 
}

function dbPrepareUser(){
    
    mysql -uroot -pdbausr_123 -e "GRANT ALL PRIVILEGES ON *.* TO 'sst_user'@'localhost' IDENTIFIED BY 'dbpass' ;" 
    mysql -uroot -pdbausr_123 -e "GRANT ALL PRIVILEGES ON *.* TO 'dbausr'@'localhost' IDENTIFIED BY 'dbausr_123' ;"
    for DB_HOSTNAME in "${DBHOST_NODES[@]}"; do 
    	#echo "mysql -uroot -pdbausr_123 -e \"grant select on performance_schema.* to 'conusr'@'$DB_HOSTNAME' identified by 'test_connect' ;"\"
    	mysql -uroot -pdbausr_123 -e "grant select on performance_schema.* to 'conusr'@'$DB_HOSTNAME' identified by 'test_connect' ;" 
    done

    ## create app user on DB ##
    for APP_HOSTNAME in "${APPHOST_NODES[@]}"; do 
    	#echo "mysql -e \"GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$APP_USER'@'$APP_HOSTNAME' IDENTIFIED BY '$APP_PWD'\""
    	mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$APP_USER'@'$APP_HOSTNAME' IDENTIFIED BY '$APP_PWD'"
    done
}

dbPrepareUser ## prepare config database
exit;
##################################################
##		START SCRIPT TASK 		## 
##################################################
## Task(1): check all node are runing mariadb service ##
echo "Task(1): check all node are runing mariadb service"
TRYCHECK=3

i="0";
while [ "$i" -lt "$TRYCHECK" ]
do
NODERUNING=0;
for  IP in "${DBIP_NODES[@]}"; do 
     if [ "$(checkService ${IP} mysql)" ]
     then 
    	echo ">>> ${IP} service running"
        NODERUNING=$((NODERUNING+1));
     else
    	echo ">>> ${IP} service dead"
	#startService ${IP} mysql
     fi
done
i=$((i+1));
echo -e "\n"
if  [ ${NODERUNING} -eq ${#DBIP_NODES[@]} ];then break; fi
done


if  [ ${NODERUNING} -eq ${#DBIP_NODES[@]} ]
then
    ## Task(2): prepare database to config gelara cluster  ##
    echo "Task(2): prepare database to config gelara cluster" 
    dbPrepareUser ## prepare config database
    `systemctl stop mysql`
else
    echo "Error!! some node has problem,service not running after install single."
    exit 99;
    
fi


## Action by Node1 deploy config to another node ##
## Task(3): config galera on server.cnf ## 
echo "Task(3): config galera on server.cnf" 
#3.1) stop mariadb
for  IP in "${IP_NODES[@]}"; do 
     if [ "$(checkService ${IP} mysql)" ]
     then 
        stopService ${IP} mysql
     fi
done
for  IP in "${IP_NODES[@]}"; do 
     if [ -z "$(checkService ${IP} mysql)" ]
     then 
    	echo ">>> ${HOST_NODES[${NODERUNING}]} service stop"
     fi
done

#3.2) config server.cnf

wsrep_cluster_address="gcomm://192.168.134.161,192.168.134.162,192.168.134.163"
wsrep_node_address='192.168.134.161'
wsrep_node_name='mariaha01'

cat >   server.cnf <<EOF
#
# These groups are read by MariaDB server.
# Use it for options that only the server (but not clients) should see
#
# See the examples of server my.cnf files in /usr/share/mysql/
#

# this is read by the standalone daemon and embedded servers
[server]

# this is only for the mysqld standalone daemon
[mysqld]

#
# * Galera-related settings
#
[galera]
# Mandatory settings
wsrep_on=ON
#wsrep_provider=
#wsrep_cluster_address=
#binlog_format=row
default_storage_engine=InnoDB
innodb_autoinc_lock_mode=2
### from db team ###
innodb_locks_unsafe_for_binlog=1
query_cache_size=0
query_cache_type=0
#
# Allow server to accept connections on all interfaces.
#
bind-address=0.0.0.0
#
# Optional setting
#wsrep_slave_threads=1
#innodb_flush_log_at_trx_commit=0

### from db team ###
innodb_log_file_size=100M
innodb_file_per_table=ON
innodb_flush_log_at_trx_commit=2
wsrep_provider=/usr/lib64/galera/libgalera_smm.so
wsrep_cluster_address="gcomm://192.168.134.161,192.168.134.162,192.168.134.163"
wsrep_cluster_name='galera_cluster'
wsrep_node_address='192.168.134.161'
wsrep_node_name='mariaha01'
wsrep_sst_method=rsync
wsrep_sst_auth=sst_user:dbpass
wsrep_auto_increment_control=1


# this is only for embedded server
[embedded]

# This group is only read by MariaDB servers, not by MySQL.
# If you use the same .cnf file for MySQL and MariaDB,
# you can put MariaDB-only options here
[mariadb]

# This group is only read by MariaDB-10.1 servers.
# If you use the same .cnf file for MariaDB of different versions,
# use this group for options that older servers don't understand
[mariadb-10.1]

#### Setup Standard Parameters for MariaDB Single Instance ####
basedir=/usr
datadir=/maria_db/data
tmpdir=/maria_db/data/maria_temp

character-set-server=utf8
collation-server=utf8_general_ci

binlog_format=ROW
expire_logs_days=15
log_bin=/maria_db/backup/mariabinlog/maria-binlog
log-error=/maria_db/backup/maria_log/mariaha01.err
innodb_file_per_table=ON

## Performance Log ##
slow_query_log=1
long_query_time=1
slow_query_log_file=/maria_db/backup/maria_log/mariaha01_slow_query.log
log_queries_not_using_indexes=1
log_output=FILE
log_slow_admin_statements=1
min_examined_row_limit=500
log_slow_rate_limit=50
log_slow_verbosity=query_plan,explain,innodb
log_slow_filter=admin,filesort,filesort_on_disk,full_join,full_scan,query_cache,query_cache_miss,tmp_table,tmp_table_on_disk
query_response_time_stats=1
innodb_status_output_locks=1
performance_schema=1
userstat=1
innodb_print_all_deadlocks=1


## Tuning for Project ##
innodb_buffer_pool_size=614215680
innodb_buffer_pool_instances=8
thread_cache_size=4
EOF
