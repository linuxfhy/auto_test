#!/usr/bin/bash
#
# Copyright (c) 2017, Inspur. All rights reserved.
#

################################################################################
#
# __stc_assertion_start
#
# ID:	mn/tc_mn_clusterid_pos001
#
# DESCRIPTION:
#	Create a cluster then verify some fields of cluster ID, including:
#	    1. verify cluster ID is a standard 64-bit binary number;
#	    2. verify cluster ID's field pui        is 0x801;
#	    3. verify cluster ID's field is_cluster is 0x1;
#	    4. verify cluster ID's field seed       is in [0, 255].
#	Delete the cluster after all tests above are done.
#
# STRATEGY:
#	1. create cluster for two nodes in the enclosure
#	   1.1 check the initial state of node is candidate
#	   1.2 create cluster via CLI "satask mkcluster"
#	   1.3 wait for a while, then the state of node being active
#	   1.4 wait for a while, then the active node being config node
#	   1.5 wait for a while, then the partner node being active
#	   1.6 when the partner node being active, create cluster complered
#
#	2. get cluster ID by reading the hardware board, and ensure it is a
#	   standard 64-bit binary number
#	3. get field pui        from cluster ID, and ensure it is equal to 0x801
#	4. get field is_cluster from cluster ID, and ensure it is equal to 1
#	5. get field seed       from cluster ID, and ensure it is in [0, 255]
#
#	6. remove config's partner node from cluster
#	   6.1 check the status of config's partner node is active;
#	   6.2 get node name via CLI "sainfo lsservicenodes" as NODEX
#	   6.3 delete cluster via CLI "savtask rmnode NODEX"
#	   6.4 wait until the state of node being service
#
#	7. delete cluster by remove the config node
#	   7.1 check cluster does exist
#	   7.2 get node name via CLI "sainfo lsservicenodes" as NODEX
#	   7.3 delete cluster via CLI "svctask rmnode NODEX"
#	   7.4 wait until the state of node being service
#	   7.5 restore the node to initial state via CLI "satask stopservice"
#	   7.6 wait until the state of node being candidate
#
# __stc_assertion_end
#
################################################################################

NAME=$(basename $0)
CDIR=$(dirname  $0)
TMPDIR=${TMPDIR:-"/tmp"}
TSROOT=$CDIR/../../

source $TSROOT/lib/libstr.sh
source $TSROOT/lib/libcommon.sh
source $TSROOT/config.vars
source $TSROOT/include/commands

function createCluster
{
	RUN_POS "$S_SAINFO lsservicenodes | sed -n '2p' | \
		grep -q \"Candidate\""
	if (( $? != 0 )); then
		echo "ERR: the node is not candidate" >&2
		return 1
	fi
	RUN_POS "$S_SAINFO lsservicenodes | sed -n '3p' | \
		grep -q \"Candidate\""
	if (( $? != 0 )); then
		echo "ERR: the partner node is not candidate" >&2
		return 1
	fi
	echo "mcs is ready"

	RUN_NEU $S_SATASK chvpd -reset
	RUN_POS $S_SATASK mkcluster \
		-clusterip $CLUSTER_IP -gw $CLUSTER_GW -mask $CLUSTER_MASK
	if (( $? != 0 )); then
		echo "ERR: failed to make cluster" >&2
		return 1
	fi

	local mk_complete=0
	for (( i = 0; i < 40; i++ )); do
		echo "wait for $(( 40 * 10 )) secs until mkclustering is done"
		$S_SAINFO lsservicenodes | sed -n '3p' | grep -q "Active"
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
	echo 'mkcluster complete'
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
		echo "wait for $(( 60 * 5 )) secs until remove $node_name done"
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

function getClusterID
{
	typeset cluster_id_fd="vpd_mid_latest_cluster_id_e"
	typeset -i cluster_id_sz="16"

	typeset cluster_id=$($S_EC_CHVPD -sa | egrep "^${cluster_id_fd} " | \
		awk '{print $2}')

	if [[ -z $cluster_id ]]; then
		echo "ERR: clusterid is invalid, which should not be \"\"" >&2
		return 1
	fi

	if (( ${#cluster_id} != $cluster_id_sz )); then
		echo "ERR: clusterid is not a standard 64-bit binary number" >&2
		return 1
	fi

	echo $cluster_id
	return 0
}

#
# FD pui is the [30th .. 41th] bits of ClusterID
#
function get_puiFromClusterID
{
	typeset cluster_id=${1?"*** Cluster ID,e.g. 00000200772105e2"}
	typeset s_hex="0x"$cluster_id
	typeset pui=$(printf "0x%x\n" $(( ($s_hex >> 30) & 0xFFF )))
	if [[ $pui != 0x801 ]]; then
		echo 'pui of cluster id is not equal to 0x801, exit' >&2
		return 1
	fi
	echo $pui
	return 0
}

#
# FD is_cluster is the 29th bit of ClusterID
#
function get_is_clusterFromClusterID
{
	typeset cluster_id=${1?"*** Cluster ID,e.g. 00000200772105e2"}
	typeset s_hex="0x"$cluster_id
	typeset is_cluster=$(printf "0x%x\n" $(( ($s_hex >> 29) & 0x1 )))
	if [[ $is_cluster != 0x1 ]]; then
		echo 'is_cluster of cluster id is not equal to 0x1, exit' >&2
		return 1
	fi
	echo $is_cluster
	return 0
}

#
# FD seed is the [21th .. 29th] bits of ClusterID
#
function get_seedFromClusterID
{
	typeset cluster_id=${1?"*** Cluster ID,e.g. 00000200772105e2"}
	typeset s_hex="0x"$cluster_id
	typeset seed=$(printf "0x%x\n" $(( ($s_hex >> 21) & 0xFF )))
	if (( $seed < 0 )); then
		echo 'the seed of cluster id is less than 0, exit'
		return 1
	elif (( $seed > 255 )); then
		echo 'the seed of cluster id is more than 255, exit'
		return 1
	fi
	echo $(( $seed ))
	return 0
}

function do_test
{
	clusterid_iden=$(getClusterID)
	(( $? != 0 )) && return 1
	msg_info "ClusterID = 0x$clusterid_iden"

	clusterid_pui_iden=$(get_puiFromClusterID $clusterid_iden)
	(( $? != 0 )) && return 1
	msg_info "pui        of ClusterID = $clusterid_pui_iden"

	clusterid_iscluster_iden=$(get_is_clusterFromClusterID $clusterid_iden)
	(( $? != 0 )) && return 1
	msg_info "is_cluster of ClusterID = $clusterid_iscluster_iden"

	clusterid_seed_iden=$(get_seedFromClusterID $clusterid_iden)
	(( $? != 0 )) && return 1
	msg_info "seed       of ClusterID = $clusterid_seed_iden"
}

tc_start $0
trap "tc_xres \$?" EXIT

createCluster || exit $STF_UNINITIATED
msg_info "OKAY - cluster is created"
RUN_NEU sleep 60

do_test || exit $STF_FAIL

removePartnerNode || exit $STF_WARNING
RUN_NEU sleep 60
deleteCluster || exit $STF_WARNING
msg_info "OKAY - cluster is deleted"

exit $STF_PASS
