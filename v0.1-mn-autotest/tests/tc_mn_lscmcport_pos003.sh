#!/usr/bin/bash
#
# Copyright (c) 2017, Inspur. All rights reserved.
#

################################################################################
#
# __stc_assertion_start
#
# ID:	en/tc_lscmcport_pos003
#
# DESCRIPTION:
#	Create a cluster then verify the modify of the cmcport status, including:
#	    1. modify the cmcports' status by ipmitool raw tool;
#	    2. verify the cmcports' status matching the modify.
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
#	2. modify the cmcport status as down, and check the status
#	   2.1 get the initial cmcport status by "ipmitool raw ...";
#	   2.2 modify the cmcport status as down by "ipmitool raw ...";
#	   2.3 execute cli svcinfo lscmcport, get the output;
#	   2.4 check the output status being down;
#
#	3. restore the cmcports' status, and check the status
#	   3.1 restore the cmcport status by "ipmitool raw ...";
#	   3.2 execute cli svcinfo lscmcport, get the output;
#	   3.3 compare the difference between output status and the initial status;
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
		echo 'the state of node being candidate, stop service complete'
	else
		echo 'the state of node being not candidate, stop service wrong'
		return 1
	fi
	return 0
}

function testLscmcport
{
	typeset -i cmc_id=$1
	(( data_cmc_1=cmc_id-1 ))
	(( data_cmc_2=2+data_cmc_1*4 ))
	(( data_cmc_3=3+data_cmc_1*4 ))
	(( data_cmc_4=5+data_cmc_1*4 ))

	typeset cmcport_init=$($S_SVCINFO lscmcport | \
		sed -n ''$data_cmc_2','$data_cmc_4'p' | awk '{print $7}')
	typeset cmc_port_link=$($S_IMM -get_port_status | awk '{print $2}' \
		| sed -n ''$cmc_id'p')
	typeset portn_1=$(echo $cmc_port_link | cut -c 1-4)
	typeset portn_2=$(echo $cmc_port_link | cut -c 11-32)

	typeset portn_3=${portn_1}"0b1b1b"${portn_2}
	echo "portn_3=$portn_3"
	$S_IMM -set_port -target $data_cmc_1 -portn $portn_3 | \
		grep -q "set port complete"
	if (( $? != 0 )) ; then
		echo "set cmc $cmc_id port T status down wrong, exit" >&2
		return 1
	fi
	RUN_NEU sleep 50
	$S_SVCINFO lscmcport | sed -n ''$data_cmc_4'p' | awk '{print $7}' | \
		grep -q "up"
	if (( $? == 0 )); then
		echo "the cmc $cmc_id port T status down wrong, exit" >&2
		return 1
	fi

	typeset portn_3=${portn_1}"1b0b1b"${portn_2}
	echo "portn_3=$portn_3"
	$S_IMM -set_port -target $data_cmc_1 -portn $portn_3 | \
		grep -q "set port complete"
	if (( $? != 0 )) ; then
		echo "set cmc $cmc_id port S2 status down wrong, exit" >&2
		return 1
	fi
	RUN_NEU sleep 50
	$S_SVCINFO lscmcport | sed -n ''$data_cmc_3'p' | awk '{print $7}' | \
		grep -q "up"
	if (( $? == 0 )); then
		echo "the cmc $cmc_id port S2 status down wrong, exit" >&2
		return 1
	fi

	typeset portn_3=${portn_1}"1b1b0b"${portn_2}
	echo "portn_3=$portn_3"
	$S_IMM -set_port -target $data_cmc_1 -portn $portn_3 | \
		grep -q "set port complete"
	if (( $? != 0 )) ; then
		echo "set cmc $cmc_id port S1 status down wrong, exit" >&2
		return 1
	fi
	RUN_NEU sleep 50
	$S_SVCINFO lscmcport | sed -n ''$data_cmc_2'p' | awk '{print $7}' | \
		grep -q "up"
	if (( $? == 0 )); then
		echo "the cmc $cmc_id port S1 status down wrong, exit" >&2
		return 1
	fi

	msg_info "test the cmc $cmc_id port down successfully"

	$S_IMM -set_port -target $data_cmc_1 -portn $cmc_port_link | \
		grep -q "set port complete"
	if (( $? != 0 )) ; then
		echo "set cmc $cmc_id port status initial wrong, exit" >&2
		return 1
	fi
	RUN_NEU sleep 50
	typeset cmcport_test=$($S_SVCINFO lscmcport | \
		sed -n ''$data_cmc_2','$data_cmc_4'p' | awk '{print $7}')
	echo "cmcport_init=$cmcport_init,cmcport_test=$cmcport_test"
	if [[ $cmcport_init != $cmcport_test ]]
	then
		echo "the cmc $cmc_id port status up wrong, exit" >&2
		return 1
	fi
	msg_info "test the cmc $cmc_id port restore successfully"
}

tc_start $0
trap "tc_xres \$?" EXIT

createCluster || exit $STF_UNINITIATED
msg_info "OKAY - cluster is created"
RUN_NEU sleep 120

testLscmcport 1 || exit $STF_WARNING
RUN_NEU sleep 30

testLscmcport 2 || exit $STF_WARNING
RUN_NEU sleep 30

# removePartnerNode || exit $STF_WARNING
# RUN_NEU sleep 30
deleteCluster || exit $STF_WARNING
msg_info "OKAY - cluster is deleted"

exit $STF_PASS
