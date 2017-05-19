#!/usr/bin/bash
#
# Copyright (c) 2017, Inspur. All rights reserved.
#

################################################################################
#
# __stc_assertion_start
#
# ID:	mn/tc_systemip_pos001
#
# DESCRIPTION:
#	1. verify after execute manmager-network.sh (the script locate /compass)
#      the system ip is configered correctly on eth2 and eth3
#	2. check the essential condition for node communicating with cmc
#
# STRATEGY:
#	1. first execute manage-network.sh
#	2. check system ip is configured on eth2 and eth3
#	3. check the physical link is ok
#	4. check ip route is ok
#	   if above is passed, the net config for the node is ok
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

function systemipcheck
{
    local dev=("eth2" "eth3")
    local info
    local ind
    local state
    local flag=(0 0)
    local devs=(eth2 eth3)
    for ind in {0,1}
    do
        msg_info "checking the configuration on ${dev[ind]}"
        #ip check
        info=$(ifconfig ${dev[ind]} | grep -c -w inet)
        if [[ $? == 0 && $info == 1 ]]; then
            log_oak "found ip on ${dev[ind]}"
        else
            flag[ind]=1
            log_oak "no ip found on ${dev[ind}"
        fi
        #link check
        info=$(ethtool ${dev[ind]} | grep "Link detected:")
        [[ $? != 0 ]] && log_oak "${dev[ind]} check link state failed"
        state=$(echo $info | awk '{print $NF}')
        log_oak "$info"
        [[ $state == "no" ]] && flag[ind]=1
        #ip route
        info=$(ip route show| grep -c ${dev[ind]})
        if [[ $info == 0 ]]; then
            flag[ind]=1
            log_oak "no route for ${dev[ind]}"
        else
            log_oak "route is found for ${dev[ind]}"
        fi
    done

    [[ ${flag[0]} == 1 || ${flag[1]} == 1 ]] && return 1
    return 0
}

tc_start $0
trap "tc_xres \$?" EXIT

systemipcheck || exit $STF_FAIL 

exit $STF_PASS
