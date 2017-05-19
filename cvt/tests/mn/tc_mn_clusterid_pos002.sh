#!/usr/bin/bash
#
# Copyright (c) 2017, Inspur. All rights reserved.
#

################################################################################
#
# __stc_assertion_start
#
# ID:	mn/tc_mn_clusterid_pos002
#
# DESCRIPTION:
#	based tc_clusterid001, create a cluster, then delete the cluster.
#	repeating the steps, verify cluster ID's field seeds change with
#	the creation of cluster basing on the same node;
#	    1. based tc_clusterid001;
#	    2. verify cluster ID's field seeds increase 1 with the creation of
#	       cluster basing on the same node;
#	    3. specially, cluster ID's field seeds is 255, verify cluster ID's
#	       field seeds become 0 with the next creation of cluster basing
#	       on the same node;
#	Delete the cluster after all tests above are done.
#
# STRATEGY:
#	1. create cluster for one node in the enclosure
#	   1.1 check the initial state of node is candidate
#	   1.2 create cluster via CLI "satask mkcluster ..."
#	   1.3 wait for a while, then the state of node being active
#	   1.4 wait for a while, then the active node being config node
#	   1.5 check the node being config node, then create cluster complered
#	   1.6 wait for 300 secs, the config node adds partner node in service
#	       state unsuccessfully, and reboots; 
#
#	2. get cluster ID and related data, ensure them are in effective range
#	   2.1 get cluster ID , and ensure it is a standard 64-bit binary number
#	   2.2 get field pui        from cluster ID, and ensure it is equal to 0x801
#	   2.3 get field is_cluster from cluster ID, and ensure it is equal to 1
#	   2.4 get field seed       from cluster ID, and ensure it is in [0, 255]
#
#	3. delete cluster by remove the config node
#	   3.1 check cluster does exist
#	   3.2 get node name via CLI "sainfo lsservicenodes" as NODEX
#	   3.3 delete cluster via CLI "savtask rmnode NODEX"
#	   3.4 wait until the state of node being service
#	   3.5 restore the node to initial state via CLI "satask stopservice"
#	   3.6 wait until the state of node being candidate
#
#	4. record the cluster ID's field seed as seed_old
#	5. repeat the step1-step3 on the same node;
#	6. record the cluster ID's field seed as seed_new
#
#	7. compare the difference between seed_old data and seed_new data;
#	   7.1 seed_old being not equal to 255, ensure the difference between seed_new and
#	       and seed_old is 1;
#	   7.2 specially, seed_old being equal to 255, the seed_new is equal to 0;
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
	msg_info "mkcluster complete"
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
	$S_SAINFO lsservicenodes | grep -q "Active"
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
		msg_info 'the state of node being service, remove cluster complete'
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
		msg_info 'the state of node being candidate, stop service complete'
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

#
# the case: create cluster for two nodes in the enclosure
#
function testClusterIdOnce
{
	mkCluster_iden=$(createCluster)
	(( $? != 0 )) && return 1
	msg_info "OKAY - cluster is created"
	RUN_NEU sleep 300

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

	removepartner_iden=$(removePartnerNode)
	(( $? != 0 )) && return 1
	RUN_NEU sleep 60
	deleteCluster_iden=$(deleteCluster)
	(( $? != 0 )) && return 1
	msg_info "OKAY - cluster is deleted"
	echo "seed =$clusterid_seed_iden"

	return 0
}

#
# the case: create cluster for one node in the enclosure
#
function testClusterIdMany
{
	mkCluster_iden=$(createCluster)
	(( $? != 0 )) && return 1
	msg_info "OKAY - cluster is created"
	RUN_NEU sleep 300

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

	deleteCluster_iden=$(deleteCluster)
	(( $? != 0 )) && return 1
	msg_info "OKAY - cluster is deleted"
	echo "seed =$clusterid_seed_iden"

	return 0
}

#
# test cluster ID's field seed changing once
#
function do_test_1
{
	typeset -i seed_old=256
	typeset -i seed_new=256
	testclusterid_once_iden=$(testClusterIdMany)
	(($? != 0)) && return 1
	echo $testclusterid_once_iden | grep -q "seed"
	if (( $? != 0 )); then
		echo "the cluster id seed is not exist, exit"
		return 1
	fi
	seed_old=${testclusterid_once_iden##*=}
	msg_info "the first time make cluster, seed_old=$seed_old"

	RUN_NEU sleep 60
	testclusterid_once_iden=$(testClusterIdMany)
	(($? != 0)) && return 1
	echo $testclusterid_once_iden | grep -q "seed"
	if (( $? != 0 )); then
		echo "the next times make cluster, the cluster id seed is not exist, exit"
		return 1
	fi
	seed_new=${testclusterid_once_iden##*=}
	msg_info "the second time make cluster, seed_new=$seed_new"

	typeset -i d_value=0
	if (( $seed_old != 255 )); then
		((d_value=seed_new-seed_old))
	elif (( $seed_new == 0 )); then
		d_value=1
	fi

	if (( $d_value != 1 )); then
		msg_info "the next times make cluster, the cluster id seed change
		    wrong, exit"
		return 1
	else
		msg_info "test seed Change once completed"
		return 0
	fi
}

#
# test cluster ID's field seed changing many times
#
function do_test_2
{
	typeset -i seed_old=256
	typeset -i seed_new=256
	testclusterid_once_iden=$(testClusterIdMany)
	(($? != 0)) && return 1
	echo $testclusterid_once_iden | grep -q "seed"
	if (( $? != 0 )); then
		echo 'the cluster id seed is not exist, exit'
		return 1
	fi

	seed_old=${testclusterid_once_iden##*=}
	msg_info "the first time make cluster, seed_old=$seed_old"
	seed_new=$seed_old
	typeset -i count_mkcluster=1
	while (( $seed_old != 255 )); do
		((count_mkcluster++))
		RUN_NEU sleep 60
		testclusterid_once_iden=$(testClusterIdMany)
		(( $? != 0 )) && return 1
		echo $testclusterid_once_iden | grep -q "seed"
		if (( $? != 0 )); then
			echo "the $count_mkcluster times make cluster, the
			cluster id seed is not exist, exit"
			return 1
		fi

		seed_new=${testclusterid_once_iden##*=}
		msg_info "the $count_mkcluster times make cluster, seed_new=$seed_new"
		((d_value=seed_new-seed_old))
		if (( $d_value != 1 ));	then
			echo "the $count_mkcluster times make cluster, the cluster id seed
				change wrong, exit"
			return 1
		else
			msg_info "the cluster id seed change successful"
		fi
		seed_old=$seed_new
	done

	((count_mkcluster++))
	RUN_NEU sleep 60
	testclusterid_once_iden=$(testClusterIdMany)
	(($? != 0)) && return 1
	echo $testclusterid_once_iden | grep -q "seed"
	(($? != 0)) && echo "the $count_mkcluster times make cluster, the
		cluster id seed is not exist, exit" && return 1
	seed_new=${testclusterid_once_iden##*=}
	if (( $seed_new != 0 )); then
		echo 'the last cluster id seed=255, the next cluster id seed change wrong, exit'
		return 1
	else
		msg_info "the $count_mkcluster times make cluster, seed_new=$seed_new"
	fi
	msg_info "test ClusterId Many times completed"
}

tc_start $0
trap "tc_xres \$?" EXIT

do_test_1 || exit $STF_FAIL

# RUN_NEU sleep 60
# do_test_2 || exit $STF_FAIL
#

exit $STF_PASS
