#!/bin/bash
#
# Copyright (c) 2017, Inspur. All rights reserved.
#
################################################################################
#
# __stc_assertion_start
#
# ID:   foo/tc_techport_active2backup_004
#
# DESCRIPTION:
#       Dummy Test techport_004
#
# STRATEGY:
#       1. issue check_techport_active2backup, expect to pass
#
# __stc_assertion_end
#
################################################################################

NAME=$(basename $0)
CDIR=$(dirname  $0)
TMPDIR=${TMPDIR:-"/tmp"}

source $CDIR/../lib/libstr.sh
source $CDIR/../lib/libcommon.sh
source $CDIR/../lib/dbg_func.sh
source $CDIR/../lib/mn_comm.sh

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
    local tlink=($[ (0x${state[0]} >> 4) & 3 ]  $[ (0x${state[8]} >> 4) & 3 ])
	return ${tlink[cid]}
}

#
#return: 0 success, other failed
#
check_techport_active2backup()
{
    local i
    local rc
    local cid

    cid=$(get_active_cmc)
    [ $? -eq 0 ] || { dbg_echo "get_active_cmc fail, can not get active cmc id"; return 22; }
    [ $cid -eq 0 ] || [ $cid -eq 1 ] || { dbg_echo "get_active_cmc fail($cid), can not test yet.";  return 20; }

    local ncid=$[ ! $cid ]
    mnet set cmcmode active cmc $ncid
    for (( i=0; i<3; i++))
    do
        cid=$(get_active_cmc)
        [ $cid -eq $ncid ] && break
        sleep 5
    done
    [ $cid -eq $ncid ] || { dbg_echo "switch cmc $ncid backup to active fail"; return 21; }

    sleep 10
    get_techport_status $cid
    rc=$?
    [ $rc -eq 1 ] || { dbg_echo "test techport ip of cmc $cid, but link status($rc) is not up"; return 10; }
    local nodeid=($(ipmitool raw 0x30 0x40))
    rc=$?
    [ $rc -eq 0 ] || { dbg_echo "command 'ipmitool raw 0x30 0x40' fail($rc)."; return 11; }
    local host=$[0x${nodeid[0]} + 1]
    [[ $(ip address show dev ${NIC[cid]} label ${NIC[cid]}:tech |grep 192.168.0.$host) ]] || {
        dbg_echo "techport of cmc $cid no ip 192.168.0.$host in ${NIC[cid]}:tech"; return 12; }

    #recover
    ncid=$[ ! $cid ]
    mnet set cmcmode active cmc $ncid

    return 0
}

RUN_POS check_techport_active2backup || exit $STF_FAIL
exit $STF_PASS
