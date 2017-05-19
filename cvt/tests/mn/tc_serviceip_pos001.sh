#!/usr/bin/bash
#
# Copyright (c) 2017, Inspur. All rights reserved.
#

################################################################################
#
# __stc_assertion_start
#
# ID:	mn/tc_serviceip_pos001
#
# DESCRIPTION:
#	1. verify service ip is changed as the cmd execute
#	2. verify the service ip is stored in midplane
#
# STRATEGY:
#	1. test mcs is running, if not prompt to start mcs
#	2. check service ip is the same between NIC and midplane
#	3. update serviceip using satask cmd
#	4. if the satask execute correct, check again service ip
#	   is the same between NIC and midplane
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
source $CDIR/mn_comm.sh
source $CDIR/sip_comm.sh

SERVICEIP=100.2.45.55
SERVICEGW=100.2.45.1
SERVICEMASK=255.255.255.0

function upd_serviceip_test
{
    local is_run
    local ret
    local cmd
    is_run=$(is_running_mcs)
    [[ $? != 0 || $is_run != 1 ]] && {
        msg_fail "please first run mcs"
        return 1
    }
    cmd="satask chserviceip -serviceip ${SERVICEIP} \
            -gw ${SERVICEGW} -mask ${SERVICEMASK}"
    msg_info $cmd
    RUN_POS satask chserviceip -serviceip ${SERVICEIP} \
                 -gw ${SERVICEGW} -mask ${SERVICEMASK}

    if (($? != 0 )) ; then
        msg_fail "update service ip failed [$ret]"
        return 1
    fi

    return 0
}


tc_start $0
trap "tc_xres \$?" EXIT
msg_info "change service ip to default"
RUN_POS satask chserviceip -default || exit $STF_FAIL

msg_info    "compare before update"
cmp_sip_midplane_local /tmp || exit $STF_FAIL

#update service ip using given ip
upd_serviceip_test || exit $STF_FAIL

msg_info    "compare after update"
cmp_sip_midplane_local || exit $STF_FAIL

exit $STF_PASS
