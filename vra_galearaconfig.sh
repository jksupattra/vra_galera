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

DBHOST_NODE1="MARIAHA01"
DBHOST_NODE2="MARIAHA02"
DBHOST_NODE3="MARIAHA03"

###########################################################
if [ ${DBIP_NODE1} ] ; then DBIP_NODES+=(${DBIP_NODE1}); fi
if [ ${DBIP_NODE2} ] ; then DBIP_NODES+=(${DBIP_NODE2}); fi
if [ ${DBIP_NODE3} ] ; then DBIP_NODES+=(${DBIP_NODE3}); fi

if [ ${DBHOST_NODE1} ] ; then 
    DBHOST_NODE1="$(echo $DBHOST_NODE1 | tr '[:upper:]' '[:lower:]')";
    DBHOST_NODES+=(${DBHOST_NODE1}); fi
if [ ${DBHOST_NODE2} ] ; then 
    DBHOST_NODE2="$(echo $DBHOST_NODE2 | tr '[:upper:]' '[:lower:]')";
    DBHOST_NODES+=(${DBHOST_NODE2}); fi
if [ ${DBHOST_NODE3} ] ; then 
    DBHOST_NODE3="$(echo $DBHOST_NODE3 | tr '[:upper:]' '[:lower:]')";
    DBHOST_NODES+=(${DBHOST_NODE3}); fi

###########################################################

##########################
##	APP HOST/IP	##
##########################
APPIP_NODE1="192.168.134.171"
APPIP_NODE2="192.168.134.172"

APPHOST_NODE1="JBOSS01"
APPHOST_NODE2="JBOSS02"


###########################################################
if [ ${APPIP_NODE1} ] ; then APPIP_NODES+=(${APPIP_NODE1}); fi
if [ ${APPIP_NODE2} ] ; then APPIP_NODES+=(${APPIP_NODE2}); fi

if [ ${APPHOST_NODE1} ] ; then 
    APPHOST_NODE1="$(echo $APPHOST_NODE1 | tr '[:upper:]' '[:lower:]')";
    APPHOST_NODES+=(${APPHOST_NODE1}); fi
if [ ${APPHOST_NODE2} ] ; then 
    APPHOST_NODE2="$(echo $APPHOST_NODE2 | tr '[:upper:]' '[:lower:]')";
    APPHOST_NODES+=(${APPHOST_NODE2}); fi
###########################################################



## SYSTEM STATIC VARIABLE ##
ROOTPWD="password"
NETDEV0="eth0"
NETDEV1="eth1"

## DB STATIC VARIABLE ##
DB_NAME=${PROJCODE}"db"
APP_USER=${PROJCODE}"usr"
APP_PWD="passsw0rd"



function addHost(){
    IPSERV=$1
    HOSTNAME=$2

    HOSTLISTS=`grep "${IPSERV}" /etc/hosts`
    echo "$1,$2"

    if [ -z "${HOSTLISTS}" ]
    then
        echo "${IPSERV}     ${HOSTNAME}" >> /etc/hosts
    else
        if [ $(echo ${HOSTLISTS[@]} | grep -o " ${HOSTNAME}" | wc -w) == 0 ]
        then
        sed -i -e "/${IPSERV}/ s/$/ $HOSTNAME/" /etc/hosts
        fi
    fi
}


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
	        #exit 99;
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
    	mysql  -uroot -pdbausr_123 "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$APP_USER'@'$APP_HOSTNAME' IDENTIFIED BY '$APP_PWD'"
    done
}

##################################################
##		START SCRIPT TASK 		## 
##################################################
i=0
for IP in "${DBIP_NODES[@]}"; do 
    addHost $IP ${DBHOST_NODES[$i]}
    i=$((i+1));
done

i=0
for IP in "${APPIP_NODES[@]}"; do 
    addHost $IP ${APPHOST_NODES[$i]}
    i=$((i+1));
done
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
#else
    #echo "Error!! some node has problem,service not running after install single."
    #exit 99;
    
fi


## Action by Node1 deploy config to another node ##
## Task(3): config galera on server.cnf ## 
echo "Task(3): config galera on server.cnf" 
#3.1) stop mariadb
`systemctl stop mysql`
sleep 5;

#3.2) config server.cnf
DBCONF="/etc/my.cnf.d/server.cnf"
# backup file config
cp -arx ${DBCONF} ${DBCONF}.single

checkNode
WSREP_CLUSTER_ADDR=$(IFS=, ; echo "gcomm://${DBIP_NODES[*]}")
WSREP_NODE_ADDR="${DBIP_NODES[${NODE}-1]}"
WSREP_NODE_NAME="${DBHOST_NODES[${NODE}-1]}"
#echo "$WSREP_CLUSTER_ADDR"
#echo "$WSREP_NODE_ADDR"
#echo "$WSREP_NODE_NAME"

cat >   ${DBCONF} <<EOF
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
wsrep_cluster_address="$WSREP_CLUSTER_ADDR"
wsrep_cluster_name='galera_cluster'
wsrep_node_address='$WSREP_NODE_ADDR'
wsrep_node_name='$WSREP_NODE_NAME'
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

if  [ ${NODE} != "1" ] ; then echo -e "Waiting for Node1 start cluster ....." ; fi

## Action by Node1 Stop/Start all node ##
## Task(4): Start galera on Node1 ## 
echo "Task(4): Start galera cluster " 
NODERUNING=0;
## 4.1 check all node db status already stop.
echo "4.1 check all node db status already stop."
for  IP in "${DBIP_NODES[@]}"; do 
     if [ -z "$(checkService ${IP} mysql)" ]
     then 
    	echo ">>> ${HOST_NODES[${NODERUNING}]} service stop"
     fi
done
## check all node stop
## 4.2 start galera on node1 
echo "4.2 start galera on node1"
startGalera 
## 4.3 start db on other node ##
echo "4.3 start db on other node" 
i=1
while [ "$i" -lt "${#DBIP_NODES[@]}" ]
do
     IP=${DBIP_NODES[$i]}
     startService ${IP} mysql
     if [ "$(checkService ${IP} mysql)" ]
     then 
    	echo ">>> ${IP} service running"
        NODERUNING=$((NODERUNING+1));
     else
    	echo ">>> ${IP} service dead"
	#startService ${IP} mysql
     fi
    i=$((i+1))
done


GALERA_SIZE=${#DBIP_NODES[@]}
LOCAL_NODE="${DBHOST_NODES[${NODE}-1]}"
CONUSR_PA="test_connect"

echo "GALERA_SIZE=$GALERA_SIZE"
echo "LOCAL_NODE=$LOCAL_NODE"


##Task(5): Check galera sync status 
echo "Task(5): Check galera connect localnode and sync status"

#### Check MariaDB status (Local Node) ####
echo "5.1 Check status MariaDB Galera Instance on ${LOCAL_NODE}"
echo "Expectation: Running"

unset MARIA_STATUS
MARIA_STATUS=$(/sbin/pidof mysqld || echo "MariaDB not startup")
export MARIA_STATUS

## Summary MariaDB Parameter on Local Node (via test connection) ##
PLATFORM_INFOR=$(cat /etc/redhat-release) 
DB_VERSION=$(mysql -uconusr -p${CONUSR_PA} -h${LOCAL_NODE} -e "status" | grep "Server version" | awk '{print $3 " " $4 " " $5}')
DB_HOSTNAME=$(mysql -uconusr -p${CONUSR_PA} -h${LOCAL_NODE} -e "select @@hostname" | grep -v "hostname" | awk '{print $1}')
export PLATFORM_INFOR DB_VERSION DB_HOSTNAME
##
echo "DB_HOSTNAME=$DB_HOSTNAME"

echo "5.2 Test MariaDB Galera Connection on Local Node (${LOCAL_NODE})"
echo "Type: Database Server"
echo ""

echo "Hostname: ${DB_HOSTNAME}"
echo "Platform: ${PLATFORM_INFOR}"
echo ""
echo "MariaDB Type: MairaDB Galera --${GALERA_SIZE}-- Nodes"
echo "MariaDB Version: ${DB_VERSION}"

echo ""
echo "MariaDB Server Parameters:"
mysql -uconusr -p${CONUSR_PA} -h${LOCAL_NODE} -e "show variables like 'server_id'" | grep -i "server_id" | awk '{print "    - " $1 ": " $2}'
mysql -uconusr -p${CONUSR_PA} -h${LOCAL_NODE} -e "show variables like 'port'" | grep -i "port" | awk '{print "    - " $1 ": " $2}'
mysql -uconusr -p${CONUSR_PA} -h${LOCAL_NODE} -e "show variables like 'datadir'" | grep -i "datadir" | awk '{print "    - " $1 ": " $2}'
mysql -uconusr -p${CONUSR_PA} -h${LOCAL_NODE} -e "show variables like 'tmpdir'" | grep -i "tmpdir" | awk '{print "    - " $1 ": " $2}'
mysql -uconusr -p${CONUSR_PA} -h${LOCAL_NODE} -e "show variables like 'tx_isolation'" | grep -i "tx_isolation" | awk '{print "    - " $1 ": " $2}'
mysql -uconusr -p${CONUSR_PA} -h${LOCAL_NODE} -e "show variables like 'character_set_%'" | egrep "server|database" | grep -i "char" | awk '{print "    - " $1 ": " $2}' | sort -r
mysql -uconusr -p${CONUSR_PA} -h${LOCAL_NODE} -e "show variables like 'collation_%'" | egrep "server|database" | grep -i "colla" | awk '{print "    - " $1 ": " $2}' | sort -r
mysql -uconusr -p${CONUSR_PA} -h${LOCAL_NODE} -e "show variables like 'log%'" | egrep "log_bin|log_error|log_output" | grep -v "log_bin_trust" | grep -i "log" | awk '{print "    - " $1 ": " $2}'
mysql -uconusr -p${CONUSR_PA} -h${LOCAL_NODE} -e "show variables like 'binlog_format'" | grep -v "log_bin_trust" | grep -i "log" | awk '{print "    - " $1 ": " $2}'
mysql -uconusr -p${CONUSR_PA} -h${LOCAL_NODE} -e "show variables like 'slow_query_log_file'" | grep -v "Value" | grep -i "slow_query_log_file" | awk '{print "    - " $1 ": " $2}'
echo ""

WSREP_CLS_SIZE=$(mysql -uconusr -p${CONUSR_PA} -h${LOCAL_NODE} -e "show status like 'wsrep_cluster_size'" | grep -iv "Value" | awk '{print $2}')
WSREP_READY=$(mysql -uconusr -p${CONUSR_PA} -h${LOCAL_NODE} -e "show status like 'wsrep_ready'" | grep -iv "Value" | awk '{print $2}')
WSREP_STATE=$(mysql -uconusr -p${CONUSR_PA} -h${LOCAL_NODE} -e "show status like 'wsrep_local_state_comment'" | grep -iv "Value" | awk '{print $2}')
export WSREP_CLS_SIZE WSREP_READY WSREP_STATE

echo "MariaDB Server Galera Parameters:"
mysql -uconusr -p${CONUSR_PA} -h${LOCAL_NODE} -e "show variables like 'wsrep_cluster_name'" | grep -v "Value" | grep -i "wsrep_cluster_name" | awk '{print "    - " $1 ": " $2}'
mysql -uconusr -p${CONUSR_PA} -h${LOCAL_NODE} -e "show variables like 'wsrep_node_name'" | grep -v "Value" | grep -i "wsrep_node_name" | awk '{print "    - " $1 ": " $2}'
mysql -uconusr -p${CONUSR_PA} -h${LOCAL_NODE} -e "show variables like 'wsrep_node_address'" | grep -v "Value" | grep -i "wsrep_node_address" | awk '{print "    - " $1 ": " $2}'
mysql -uconusr -p${CONUSR_PA} -h${LOCAL_NODE} -e "show status like 'wsrep_cluster_size'" | grep -iv "Value" | awk '{print "    - " $1 ": " $2}'
mysql -uconusr -p${CONUSR_PA} -h${LOCAL_NODE} -e "show status like 'wsrep_ready'" | grep -iv "Value" | awk '{print "    - " $1 ": " $2}' 
mysql -uconusr -p${CONUSR_PA} -h${LOCAL_NODE} -e "show status like 'wsrep_local_state_comment'" | grep -iv "Value" | awk '{print "    - " $1 ": " $2}'
echo ""
echo "Remark: wsrep_cluster_size should be --${GALERA_SIZE}--, wsrep_ready should be --ON--, wsrep_local_state_comment should be --Synced--"


### Check MariaDB Connection for Local Node ###
#if [ "${MARIA_STATUS}" != "MariaDB not startup" ] && [ "${PROCESS_START}" = "yes" ] && [ "${DB_HOSTNAME}" = "${HOSTNAME}" ]
if [ "${MARIA_STATUS}" != "MariaDB not startup" ] && [ "${DB_HOSTNAME}" = "${HOSTNAME}" ]
then
        echo ""
        echo "*********************************************************************************************"
        echo "  ==> Test MariaDB Galera Connection (--${LOCAL_NODE}--): Connection COMPLETED !!!           "
        echo "*********************************************************************************************"
else
        echo ""
        echo "**************************************************************************************************"
        echo "  ==> Test MariaDB Galera Connection (--${LOCAL_NODE}--): Connection ERROR !!!                    "
        echo "  ==> Please contact DBA Team to verify again, MariaDB may be start but cannot connect !!!        "
        echo "**************************************************************************************************"

        exit 99
fi

### Check MariaDB Connection ans Galera Synchronization ###
if [ "${DB_HOSTNAME}" = "${HOSTNAME}" ] && [ "${WSREP_READY}" = "ON" ] && [ "${WSREP_CLS_SIZE}" = ${GALERA_SIZE} ] && [ "${WSREP_STATE}" = "Synced" ]
then
        echo ""
        echo "*****************************************************************************"
        echo "  ==> MariaDB Galera Status (Cluster Synchronization): SYNC COMPLETED !!!    "
        echo "*****************************************************************************"


else
        echo ""
        echo "********************************************************************************************"
        echo "  ==> MariaDB Galera Status (Cluster Synchronization): SYNC ERROR !!!                       "
        echo "  ==> Please contact DBA TEAM to verify again, MariaDB Galera Status not Synchronous !!!    "
        echo "********************************************************************************************"

        exit 99
fi

## Task(6): Shutdown MariaDB instance then start again.
echo "Task(6): Shutdown MariaDB instance then start again."
mysql -udbausr -pdbausr_123 -hlocalhost -e "shutdown"
sleep 5;
startService ${DBIP_NODES[$NODE-1]} mysql
checkService ${DBIP_NODES[$NODE-1]} mysql


