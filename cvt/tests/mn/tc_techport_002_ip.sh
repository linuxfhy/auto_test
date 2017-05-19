#!/bin/bash
#
# Copyright (c) 2017, Inspur. All rights reserved.
#

################################################################################
#
# __stc_assertion_start
#
# ID:   mn/tc_techport_ip_002
#
# DESCRIPTION:
#       Test techport_002
#
# STRATEGY:
#       1. issue check_techport_ip, expect to pass
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
source $CDIR/mn_comm.sh

tc_start $0
trap "tc_xres \$?" EXIT

NIC=(eth2 eth3)

#
#return: 0 link down, 1 link up, 2 or 3 link unknown, 10 input cmc id error.
#
get_techport_status()
{
    local cid=$1
    [ "$cid" = "0" ] || [ "$cid" = "1" ] || {
         dbg_echo "$NAME: input cmc id ($cid) error while get techport status"; return 10; }
    local state=($(ipmitool raw 0x30 0x16))
    local rc=$?
    [ $rc -eq 0 ] || { dbg_echo "$NAME: command 'ipmitool raw 0x30 0x16' fail($rc)."; return 10; }
    local tlink=($[ (0x${state[0]} >> 4) & 3 ]  $[ (0x${state[0]} >> 4) & 3 ])
	return ${tlink[cid]}
}

#
#return: 0 success, other failed
#
check_techport_ip()
{
    local rc
    local cid=$(get_active_cmc)
    get_techport_status $cid
    rc=$?
    [ $rc -eq 1 ] || { dbg_echo "$NAME: test techport ip of cmc $cid, but link status($rc) is not up"; return 10; }
    local nodeid=($(ipmitool raw 0x30 0x40))
    rc=$?
    [ $rc -eq 0 ] || { dbg_echo "$NAME: command 'ipmitool raw 0x30 0x40' fail($rc)."; return 11; }
    local host=$[0x${nodeid[0]} + 1]
    [[ $(ip address show dev ${NIC[cid]} label ${NIC[cid]}:tech |grep 192.168.0.$host) ]] || {
        dbg_echo "$NAME: techport of cmc $cid no ip 192.168.0.$host in ${NIC[cid]}:tech"; return 12; }
    return 0
}

RUN_POS check_techport_ip || exit $STF_FAIL
exit $STF_PASS
