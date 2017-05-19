#!/usr/bin/bash
#
# Copyright (c) 2017, Inspur. All rights reserved.
#

################################################################################
#
# __stc_assertion_start
#
# ID:	en/tc_mn_lscmcport_pos002
#
# DESCRIPTION:
#	Create a cluster then verify the output of cli svcinfo lscmcport,including:
#	    1. add enclosure into cluster, verify the output of cli svcinfo
#	       lscmcport including the adding enclosure;
#	    2. remove one node of the enclosure, verify the output of cli svcinfo
#	       lscmcport including the removing enclosure;
#	    3. remove the enclosure, verify the output of cli svcinfo lscmcport
#	       not including the removing enclosure;
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
#	2. add enclosure into cluster, and get the enclosure_sn
#	   2.1 check the initial state of enclosure node is candidate
#	   2.2 add enclosure into cluster via CLI "svctask addcontrolenclosure ..."
#	   2.3 check and wait for the state of node being active
#	   2.4 get the enclosure_sn, and record it as enclosure_sn_adding
#
#	3. execute cli svcinfo lscmcport, and verify the output, including:
#	   3.1 get the output of cli svcinfo lscmcport
#	   3.2 filter out the enclosure_sn from the output
#	   3.3 check the output enclosure_sn is equal to enclosure_sn_adding
#
#	4. remove one node of the second enclosure from cluster
#	   4.1 check the initial state of the node is candidate
#	   4.2 get node name via CLI "sainfo lsservicenodes" as NODEX
#	   4.3 delete cluster via CLI "savtask rmnode NODEX"
#	   4.3 check and wait for the node being service
#	   4.4 get the enclosure_sn, and record it as enclosure_sn_removing
#
#	5. execute cli svcinfo lscmcport, and verify the output, including:
#	   5.1 get the output of cli svcinfo lscmcport
#	   5.2 filter out the enclosure_sn from the output
#	   5.3 check the output enclosure_sn is equal to enclosure_sn_removing
#
#	6. remove the other node of the second enclosure from cluster
#	   6.1 check the initial state of the node is candidate
#	   4.2 get node name via CLI "sainfo lsservicenodes" as NODEX
#	   4.3 delete cluster via CLI "savtask rmnode NODEX"
#	   4.3 check and wait for the node being service
#
#	7. execute cli svcinfo lscmcport, and verify the output, including:
#	   7.1 get the output of cli svcinfo lscmcport
#	   7.2 filter out the enclosure_sn from the output
#	   7.3 check the output enclosure_sn is equal to enclosure_sn_removing
#
#	8. remove config node, delete cluster
#	   8.1 check cluster does exist
#	   8.2 get node name via CLI "sainfo lsservicenodes" as NODEX
#	   8.3 delete cluster via CLI "savtask rmnode NODEX"
#	   8.4 wait until the state of node being service
#	   8.5 restore the node to initial state via CLI "satask stopservice"
#	   8.6 wait until the state of node being candidate
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

function addEnclosureIntoCluster
{
	typeset panel_name_1=$($S_SAINFO lsservicenodes | \
		sed -n '4p' | awk '{print $1}')
	typeset panel_name_2=$($S_SAINFO lsservicenodes | \
		sed -n '5p' | awk '{print $1}')

	RUN_POS "$S_SAINFO lsservicenodes | sed -n '4p' | \
		grep -q \"Candidate\""
	if (( $? != 0 )); then
		echo "ERR: the $panel_name_1 is not candidate, can not add" >&2
		return 1
	fi
	RUN_POS "$S_SAINFO lsservicenodes | sed -n '5p' | \
		grep -q \"Candidate\""
	if (( $? != 0 )); then
		echo "ERR: the $panel_name_2 is not candidate, can not add" >&2
		return 1
	fi

	typeset enclosure_sn=${panel_name_1%-*}
	RUN_POS $S_SVCTASK addcontrolenclosure \
		-iogrp io_grp1 -sernum $enclosure_sn
	#RUN_POS $S_SVCTASK chenclosure -managed yes -enclosureid

	local add_complete=0
	for (( i = 0; i < 60; i++ )); do
		echo "wait for $(( 60 * 5 )) secs until add enclosure is done"
		$S_SAINFO lsservicenodes | sed -n '5p' | grep -q "Active"
		if (( $? == 0 )); then
		    add_complete=1
		    break
		fi
		sleep 5
	done
	if (( $add_complete != 1 )); then
		echo 'add enclosure wrong'
		return 1
	fi
	msg_info 'add enclosure complete'
	echo "enclosure_sn=$enclosure_sn"
	return 0
}

function removeFirstNode
{
	typeset node_name=$($S_SAINFO lsservicenodes | \
		sed -n '4p' | awk '{print $5}')
	$S_SAINFO lsservicenodes | sed -n '4p' | grep -q "Active"
	if (( $? != 0 )); then
		echo "ERR: the $node_name is not active, can not delete" >&2
		return 1
	fi

	RUN_POS $S_SVCTASK rmnode $node_name

	local remove_complete=0
	for (( i = 0; i < 40; i++ )); do
		echo "wait for $(( 40 * 5 )) secs until remove $node_name is done"
		$S_SAINFO lsservicenodes | sed -n '4p' | grep -q "Service"
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

function removeSecondNode
{
	typeset node_name=$($S_SAINFO lsservicenodes | \
		sed -n '5p' | awk '{print $5}')
	$S_SAINFO lsservicenodes | sed -n '5p' | grep -q "Active"
	if (( $? != 0 )); then
		echo "ERR: the $node_name is not active, can not delete" >&2
		return 1
	fi

	RUN_POS $S_SVCTASK rmnode $node_name

	local remove_complete=0
	for (( i = 0; i < 60; i++ )); do
		echo "wait for $(( 60 * 5 )) secs until remove $node_name is done"
		$S_SAINFO lsservicenodes | sed -n '5p' | grep -q "Service"
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
	msg_info "remove $node_name complete, remove the enclosure
	$enclosure_sn complete"
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
	for (( i = 0; i < 40; i++ )); do
		echo "wait for $(( 40 * 5 )) secs until node become service"
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
	for (( i = 0; i < 40; i++ )); do
		echo "wait for $(( 40 * 5 )) secs until node become candidate"
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

function testLscmcportAddenclosure
{
	enclosure_sn=$(addEnclosureIntoCluster)
	(( $? != 0 )) && return 1
	typeset enclosure_sn_adding=${enclosure_sn##*=}
	msg_info "the adding enclosure_sn=$enclosure_sn_adding"

	RUN_NEU sleep 30
	$S_SVCINFO lscmcport | grep -q "$enclosure_sn_adding"
	if (( $? != 0 )); then
		echo "ERR: add enclosure $S_SVCINFO lscmcport can not show the
		adding enclosure's cmc information" >&2
		return 1
	else
		echo "add enclosure, the $S_SVCINFO lscmcport successfully"
	fi
	echo "enclosure_sn=$enclosure_sn_adding"
	return 0
}

function testLscmcportRemovenode
{
	remove_first_iden=$(removeFirstNode)
	(( $? != 0 )) && return 1
	msg_info "remove one node successfully"

	RUN_NEU sleep 30
	$S_SVCINFO lscmcport | grep -q "$1"
	if (( $? != 0 )); then
		echo "ERR: remove one node, $S_SVCINFO lscmcport can not show 
		the enclosure's cmc information" >&2
		return 1
	else
		echo "remove one node, the $S_SVCINFO lscmcport can show the
		enclosure's cmc information"
	fi
	return 0
}

function testLscmcportRemoveenclosure
{
	remove_second_iden=$(removeSecondNode)
	(( $? != 0 )) && return 1
	msg_info "remove an enclosure successfully"

	RUN_NEU sleep 30
	$S_SVCINFO lscmcport | grep -q "$1"
	if (( $? == 0 )); then
		echo "ERR: remove the enclosure, $S_SVCINFO lscmcport can show 
		the enclosure's cmc information" >&2
		return 1
	else
		echo "remove the enclosure, the $S_SVCINFO lscmcport can not
		show the enclosure's cmc information"
	fi
	return 0
}

function testLscmcport
{
	enclosure_sn_adding=$(testLscmcportAddenclosure)
	(( $? != 0 )) && return 1
	RUN_NEU sleep 30
	msg_info "add enclosure - check the output of lscmcport success"

	enclosure_sn=${enclosure_sn_adding##*=}
	test_lscmcport_iden=$(testLscmcportRemovenode $enclosure_sn)
	(( $? != 0 )) && return 1
	RUN_NEU sleep 30
	msg_info "remove one node - check the output of lscmcport success"

	test_lscmcport_iden=$(testLscmcportRemoveenclosure $enclosure_sn)
	(( $? != 0 )) && return 1
	RUN_NEU sleep 30
	msg_info "remove an enclosure - check the output of lscmcport success"

}

tc_start $0
trap "tc_xres \$?" EXIT

createCluster || exit $STF_UNINITIATED
msg_info "OKAY - cluster is created"
RUN_NEU sleep 120

#testLscmcport || exit $STF_WARNING
#RUN_NEU sleep 30

# removePartnerNode || exit $STF_WARNING
deleteCluster || exit $STF_WARNING
msg_info "OKAY - cluster is deleted"

exit $STF_PASS
