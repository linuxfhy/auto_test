#!/usr/bin/bash
#
# Copyright (c) 2017, Inspur. All rights reserved.
#

################################################################################
#
# __stc_assertion_start
#
# ID:	en/tc_mn_lscmcport_pos001
#
# DESCRIPTION:
#	Create a cluster then verify the output of cli svcinfo lscmcport, including:
#	    1. verify enclosure_id is matching the output of cli sainfo lsservicenodes;
#	    2. verify port_status is matching the out of ipmitool raw 0x30 0x16;
#	Delete the cluster after all tests above are done.
#
# STRATEGY:
#	1. create cluster for one node in the enclosure
#	   1.1 check the initial state of node is candidate
#	   1.2 create cluster via CLI "satask mkcluster ..."
#	   1.3 wait for a while, then the state of node being active
#	   1.4 wait for a while, then the active node being config node
#	   1.5 check the node being config node, then create cluster complered
#	   1.6 wait for 120 secs, the cluster ip etc. being configured 
#
#	2. execute cli svcinfo lscmcport
#
#	3. verify the output of cli svcinfo lscmcport
#	   3.1 check enclosure_sn is matching the output of cli sainfo lsservicestatus;
#	   3.2 check port_status is matching the out of ipmitool raw 0x30 0x16;
#
#	4. remove config node, delete cluster
#	   4.1 check cluster does exist
#	   4.2 get node name via CLI "sainfo lsservicenodes" as NODEX
#	   4.3 delete cluster via CLI "savtask rmnode NODEX"
#	   4.4 wait until the state of node being service
#	   4.5 restore the node to initial state via CLI "satask stopservice"
#	   4.6 wait until the state of node being candidate
#
# __stc_assertion_end
#
################################################################################

NAME=$(basename $0)
CDIR=$(dirname  $0)
TMPDIR=${TMPDIR:-"/tmp"}
TSROOT=$CDIR/../

source $TSROOT/lib/libstr.sh
source $TSROOT/lib/libcommon.sh

CLUSTER_IP=100.2.45.31
GLUSTER_MASK=255.255.255.0
CLUSTER_GW=100.2.45.1

S_SAINFO=/compass/bin/sainfo
S_SATASK=/compass/bin/satask
S_SVCTASK=/compass/bin/svctask
S_SVCINFO=/compass/bin/svcinfo
S_IMM=/compass/imm_service
S_EC_CHVPD=/compass/ec_chvpd

function createCluster
{
	RUN_POS "$S_SAINFO lsservicenodes | sed -n '2p' | \
		grep -q \"Candidate\""
	if (( $? != 0 )); then
		echo "ERR: the node is not candidate" >&2
		return 1
	else
		echo "mcs is ready"
	fi

	RUN_NEU $S_SATASK chvpd -reset
	RUN_POS $S_SATASK mkcluster \
		-clusterip $CLUSTER_IP -gw $CLUSTER_GW -mask $GLUSTER_MASK
	if (( $? != 0 )); then
		echo "ERR: failed to make cluster" >&2
		return 1
	fi

	local mk_complete=0
	for (( i = 0; i < 40; i++ )); do
		echo "wait for $(( 40 * 10 )) secs until mkclustering is done"
		typeset config_iden="config_node"
		$S_SAINFO lsservicestatus | egrep "^${config_iden} " | \
		grep -q "Yes"
		if (( $? == 0 )); then
		    mk_complete=1
		    break
		fi
		sleep 10
	done
	if (( $mk_complete != 1 )); then
		echo 'mkcluster wrong'
		return 1
	fi
	echo "mkcluster complete"
	return 0
}

function removePartnerNode
{
	typeset node_name=$($S_SAINFO lsservicenodes | \
		sed -n '3p' | awk '{print $5}')
	$S_SAINFO lsservicenodes | sed -n '3p' | grep -q "Active"
	if (( $? != 0 )); then
		echo "ERR: the $node_name is not active, can not delete" >&2
		return 1
	fi

	RUN_POS $S_SVCTASK rmnode $node_name

	local remove_complete=0
	for (( i = 0; i < 60; i++ )); do
		echo "wait for $(( 60 * 5 )) secs until remove $node_name is done"
		$S_SAINFO lsservicenodes | sed -n '3p' | grep -q "Service"
		if (( $? == 0 )); then
		    remove_complete=1
		    break
		fi
		sleep 5
	done
	if (( $remove_complete != 1 )); then
		echo "remove $node_name wrong"
		return 1
	fi
	msg_info "remove $node_name complete"
	return 0
}

function deleteCluster
{
	$S_SAINFO lsservicenodes | sed -n '2p' | grep -q "Active"
	if (( $? != 0 )) ; then
		echo "cluster does not exist, exit" >&2
		return 1
	fi

	$S_SAINFO lsservicenodes | sed -n '2p' | \
		awk '{print $5}' | grep -q "node"
	if (( $? != 0 )); then
	       echo "the active node has no node name, exit" >&2
	       return 1
	fi
	typeset node_name_1=$($S_SAINFO lsservicenodes | \
		sed -n '2p' | awk '{print $5}')

	RUN_NEU $S_SVCTASK rmnode $node_name_1

	typeset -i delete_complete=0
	for (( i = 0; i < 60; i++ )); do
		echo "wait for $(( 60 * 5 )) secs until node become service"
		$S_SAINFO lsservicenodes | sed -n '2p' | grep -q "Service"
		if (( $? == 0 )); then
			delete_complete=1
			break
		fi
		sleep 5
	done
	if (( $delete_complete != 0 )); then
		echo 'the state of node being service, remove cluster complete'
	else
		echo 'the state of node being not service, remove cluster wrong'
		return 1
	fi

	RUN_NEU $S_SATASK stopservice
	if (( $? != 0 )); then
		echo "stop service is not success, exit"
		return 1
	fi

	delete_complete=0
	for (( i = 0; i < 60; i++ )); do
		echo "wait for $(( 60 * 5 )) secs until node become candidate"
		$S_SAINFO lsservicenodes | sed -n '2p' | grep -q "Candidate"
		if (( $? == 0 )); then
			delete_complete=1
			break
		fi
		sleep 5
	done
	if (( $delete_complete != 0 )); then
		echo "the state of node being candidate, stop service complete"
	else
		echo "the state of node being not candidate, stop service wrong"
		return 1
	fi
	return 0
}

function testLscmcport
{
	typeset enclosure_sn_iden="product_serial"
	typeset enclosure_sn=$($S_SAINFO lsservicestatus | \
		egrep "^${enclosure_sn_iden} " | awk '{print $2}')
	typeset enclosure_sn_test=$($S_SVCINFO lscmcport | \
		sed -n '2p' | awk '{print $3}')
	if [[ $enclosure_sn != $enclosure_sn_test ]]; then
		echo "the enclosure_sn of $S_SVCINFO lscmcport is not matching"
		return 1
	fi
	msg_info "the enclosure_sn of $S_SVCINFO lscmcport is matching"

	port_status_array=("down" "up" "unknown" "reserved")
	typeset -i j=0
	for (( i = 1; i < 5; i++ )); do
		(( j=2*i+1 ))
		typeset port_status_0=$($S_IMM -get_cmc_port | cut -c $j)
		(( j=i+1 ))
		typeset port_status_test_0=$($S_SVCINFO lscmcport | \
		sed -n ''$j'p' | awk '{print $7}')
		(( j=i-1 ))
		if [ "${port_status_array["$port_status_0"]}" != "$port_status_test_0" ]
		then
			echo "index=$j, the port_status of $S_SVCINFO lscmcport
			is not matching"
			return 1
		fi		
	done

	for (( i = 1; i < 5; i++ )); do
		(( j=2*i+11 ))
		typeset port_status_0=$($S_IMM -get_cmc_port | cut -c $j)
		(( j=i+5 ))
		typeset port_status_test_0=$($S_SVCINFO lscmcport | \
		sed -n ''$j'p' | awk '{print $7}')
		(( j=i+3 ))
		if [ "${port_status_array["$port_status_0"]}" != "$port_status_test_0" ]
		then
			echo "index=$j, the port_status of $S_SVCINFO lscmcport
			is not matching"
			return 1
		fi		
	done

	msg_info "the port_status of $S_SVCINFO lscmcport is matching"
}

tc_start $0
trap "tc_xres \$?" EXIT

createCluster || exit $STF_UNINITIATED
msg_info "OKAY - cluster is created"
RUN_NEU sleep 120

testLscmcport || exit $STF_WARNING
RUN_NEU sleep 30

# removePartnerNode || exit $STF_WARNING
# RUN_NEU sleep 60
deleteCluster || exit $STF_WARNING
msg_info "OKAY - cluster is deleted"

exit $STF_PASS
