#!/usr/bin/bash
#
# Copyright (c) 2017, Inspur. All rights reserved.
#

################################################################################
#
# __stc_assertion_start
#
# ID:	mn/tc_mn_clusterid_pos003
#
# DESCRIPTION:
#	create a cluster, then simulate the cluster exit abnormally. create a cluster
#	on the same node again, verify cluster ID's field seeds change;
#	    1. in the case of the cluster exit abnormally, verify cluster ID's field
#	       seeds change;
#	    2. verify cluster ID's field seeds increase 1 with the creation of
#	       cluster basing on the same node;
#	    3. specially, cluster ID's field seeds is 255, verify cluster ID's field
#	       seeds become 0 with the next creation of cluster basing on the same node;
#	restore the candidate state on the node after all tests above are done.
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
#	2. get cluster ID and related data, and ensure them are in effective range
#	   2.1 get cluster ID , and ensure it is a standard 64-bit binary number
#	   2.2 get field pui        from cluster ID, and ensure it is equal to 0x801
#	   2.3 get field is_cluster from cluster ID, and ensure it is equal to 1
#	   2.4 get field seed       from cluster ID, and ensure it is in [0, 255]
#
#	3. simulate the node exiting cluster abnormally
#	   3.1 kill the mcs via "kill_node -f" to simulate cluster fault
#	   3.2 start the mcs via "compass_start"
#	   3.3 check and wait for the node being candidate
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

function exitClusterAbnor
{
	typeset -i restore_state=0
	RUN_NEU kill_node -f
	if (( $? != 0 )); then
		echo "kill node not success, exit"
		return 1
	fi
	RUN_NEU compass_start
	if (( $? != 0 )); then
		echo "compass start mcs not success, exit"
		return 1
	fi
	RUN_NEU sleep 50

	RUN_POS "$S_SAINFO lsservicenodes | sed -n '2p' | \
		grep -q \"Candidate\""
	if (( $? != 0 )); then
		echo "ERR: the node is not candidate" >&2
		return 1
	else
		echo "mcs is ready"
		return 0
	fi
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
	deleteCluster_iden=$(exitClusterAbnor)
	(( $? != 0 )) && return 1
	msg_info "OKAY - cluster is exis abnormally"
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

	deleteCluster_iden=$(exitClusterAbnor)
	(( $? != 0 )) && return 1
	msg_info "OKAY - cluster is deleted"
	echo "seed =$clusterid_seed_iden"

	return 0
}

function do_test_1
{
	typeset -i seed_old=256
	typeset -i seed_new=256
	testclusterid_once_iden=$(testClusterIdMany)
	(( $? != 0 )) && return 1
	echo $testclusterid_once_iden | grep -q "seed"
	if (( $? != 0 )); then
		echo 'the cluster id seed is not exist, exit'
		return 1
	fi
	seed_old=${testclusterid_once_iden##*=}
	msg_info "the first time make cluster, seed_old=$seed_old"

	RUN_NEU sleep 60
	testclusterid_once_iden=$(testClusterIdMany)
	(( $? != 0 )) && return 1
	echo $testclusterid_once_iden | grep -q "seed"
	if (( $? != 0 )); then
		echo 'the next times make cluster, the cluster id seed is not \
		    exist, exit'
		return 1
	fi
	seed_new=${testclusterid_once_iden##*=}
	msg_info "the $count_mkcluster times make cluster, seed_new=$seed_new"

	typeset -i d_value=0
	if (( $seed_old != 255 )); then
		(( d_value=seed_new-seed_old ))
	elif (( $seed_new == 0 )); then
		d_value=1
	fi

	if (( $d_value != 1 )); then
		msg_info "the next times make cluster, the cluster id seed change \
		    wrong, exit"
		return 1
	else
		msg_info "test seed Change once completed"
		return 0
	fi
}

function do_test_2
{
	typeset -i seed_old=256
	typeset -i seed_new=256
	testclusterid_once_iden=$(testClusterIdMany)
	(( $? != 0 )) && return 1
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
		(( count_mkcluster++ ))
		RUN_NEU sleep 60
		testclusterid_once_iden=$(testClusterIdMany)
		(( $? != 0 )) && return 1
		echo $testclusterid_once_iden | grep -q "seed"
		if (( $? != 0 )); then
			echo "the $count_mkcluster times make cluster, the cluster id \
			    seed is not exist, exit"
			return 1
		fi

		seed_new=${testclusterid_once_iden##*=}
		msg_info "the $count_mkcluster times make cluster, seed_new=$seed_new"
		(( d_value=seed_new-seed_old ))
		if (( $d_value != 1 )); then
			echo "the $count_mkcluster times make cluster, the cluster \
			    id seed change wrong, exit"
			return 1
		else
			msg_info "the cluster id seed change successful"
		fi
		seed_old=$seed_new
	done

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
	if (( $seed_new != 0 )); then
		echo "the last cluster id seed=255, the next cluster id seed \
		    change wrong, exit"
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
