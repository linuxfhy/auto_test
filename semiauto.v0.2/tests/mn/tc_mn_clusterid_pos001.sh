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
#	1. create cluster
#	   1.1 check the initial state of node is candidate
#	   1.2 create cluster via CLI "satask mkcluster"
#	   1.3 check and wait for the state of node being active
#	   1.4 wait for a while (30s), then the active node being config node
#
#	2. get cluster ID by reading the hardware board, and ensure it is a
#	   standard 64-bit binary number
#	3. get field pui        from cluster ID, and ensure it is 0x801
#	4. get field is_cluster from cluster ID, and ensure it is 0x1
#	5. get field seed       from cluster ID, and ensure it is in [0, 255]
#
#	6. delete cluster
#	   6.1 check cluster does exist
#	   6.2 get node name via CLI "sainfo lsservicenodes" as NODEX
#	   6.3 delete cluster via CLI "svctask rmnode NODEX"
#	   6.4 wait until the state of node being service
#	   6.5 restore the node to initial state via CLI "satask stopservice"
#	   6.6 wait until the state of node being candidate
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

S_SAINFO=/compass/bin/sainfo
S_SATASK=/compass/bin/satask
S_SVCTASK=/compass/bin/svctask
S_EC_CHVPD=/compass/ec_chvpd

function createCluster
{
	RUN_POS "$S_SAINFO lsservicenodes | grep -q \"Candidate\""
	if (( $? != 0 )); then
		echo "ERR: the node is not candidate" >&2
		return 1
	else
		echo "mcs is ready"
	fi

	RUN_NEU $S_SATASK chvpd -reset
	RUN_POS $S_SATASK mkcluster \
		-clusterip $CLUSTER_IP -gw $CLUSTER_GW -mask $CLUSTER_MASK
	if (( $? != 0 )); then
		echo "ERR: failed to make cluster" >&2
		return 1
	fi

	local mk_complete=0
	for (( i = 0; i < 20; i++ )); do
		echo "wait for $(( 20 * 5 )) secs until mkclustering is done"
		$S_SAINFO lsservicenodes | grep -q "Active"
		if (( $? == 0 )); then
		    mk_complete=1
		    break
		fi
		sleep 5
	done
	if (( $mk_complete == 0 )); then
		echo "ERR: cluster is not Active" >&2
		return 1
	fi
	return 0
}

function deleteCluster
{
	$S_SAINFO lsservicenodes | grep -q "Active"
	if (( $? != 0 )) ; then
		echo "ERR: cluster does not exist" >&2
		return 1
	fi

	$S_SAINFO lsservicenodes | sed -n '2p' | \
		awk '{print $5}' | grep -q "node"
	if (( $? != 0 )); then
		echo "ERR: the active node has no node name" >&2
		return 1
	fi
	typeset node_name_1=$($S_SAINFO lsservicenodes | \
		sed -n '2p' | awk '{print $5}')

	RUN_NEU $S_SVCTASK rmnode $node_name_1

	typeset -i delete_complete=0
	for (( i = 0; i < 20; i++ )); do
		$S_SAINFO lsservicenodes | grep -q "Service"
		if (( $? == 0 )); then
			delete_complete=1
			break
		fi
		sleep 5
	done
	if (( $delete_complete != 0 )); then
		echo "succeed to remove cluster"
	else
		echo "fail to remove cluster" \
		    "as the state of node not being service" >&2
		return 1
	fi

	RUN_POS $S_SATASK stopservice || return 1

	delete_complete=0
	for (( i = 0; i < 20; i++ )); do
		$S_SAINFO lsservicenodes | grep -q "Candidate"
		if (( $? == 0 )); then
			delete_complete=1
			break
		fi
		sleep 5
	done
	if (( $delete_complete != 0 )); then
		echo "succeed to stop service (state of node is candidate)"
	else
		echo "fail to stop service as" \
		    "the state of node not being not candidate"
		return 1
	fi

	return 0
}

function getClusterID
{
	typeset cluster_id_fd="vpd_mid_latest_cluster_id_e"
	typeset -i cluster_id_sz=16

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
		echo "ERR: pui of cluster id is not 0x801" >&2
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
		echo "ERR: is_cluster of cluster id is not 0x1" >&2
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
		echo "ERR: the seed of cluster id is less than 0" >&2
		return 1
	elif (( $seed > 255 )); then
		echo "ERR: the seed of cluster id is more than 255" >&2
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
RUN_NEU sleep 30

do_test || exit $STF_FAIL

deleteCluster || exit $STF_WARNING
msg_info "OKAY - cluster is deleted"

exit $STF_PASS
