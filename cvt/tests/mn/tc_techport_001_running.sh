#!/bin/bash
#
# Copyright (c) 2017, Inspur. All rights reserved.
#
################################################################################
#
# __stc_assertion_start
#
# ID:   mn/tc_techport_running_001
#
# DESCRIPTION:
#       Test techport_001
#
# STRATEGY:
#       1. issue check_techport_oak_running, expect to pass
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

tc_start $0
trap "tc_xres \$?" EXIT

PIDFILE=/var/run/techport.pid

#
#return: 0 success, other failed
#
check_techport_oak_running()
{
    [ -f $PIDFILE ] || ( dbg_echo "$PIDFILE not exist."; return 1 )
    local techpid=$(cat $PIDFILE)
    [ "$techpid" != "" ] || ( dbg_echo "techport.pid is empty."; return 2 )
    [[ $(ps -p $techpid) ]] || ( dbg_echo "techport.pid can not find process"; return 3 )
    return 0
}

RUN_POS check_techport_oak_running || exit $STF_FAIL
exit $STF_PASS
