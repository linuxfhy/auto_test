#!/usr/bin/bash
#
# Copyright (c) 2017, Inspur. All rights reserved.
#

################################################################################
#
# __stc_assertion_start
#
# ID:	pl/tc_pl_vpd_pos001
#
# DESCRIPTION:
#	Test cases for VPD-access
#
# __stc_assertion_end
#
################################################################################

NAME=$(basename $0)
CDIR=$(dirname  $0)
TMPDIR=${TMPDIR:-"/tmp"}
TSROOT=$CDIR/../../

AWKCMD=awk
LSCMD=ls
trcfile="/dumps/scrumtest.trc"

source $TSROOT/lib/libstr.sh
source $TSROOT/lib/libcommon.sh
source $TSROOT/config.vars

S_SAINFO=/compass/bin/sainfo
S_SATASK=/compass/bin/satask
S_SVCTASK=/compass/bin/svctask
S_EC_CHVPD=/compass/ec_chvpd

function log()
{
    echo "[$(date -d today +"%Y-%m-%d %H:%M:%S")]" $* #>>${trcfile}
}

function remote_exec()
{
    ssh -p 26 ${remote_ip} "$*"
    return $?
}

if [ ! -f ${trcfile} ]
then
    touch ${trcfile}
else
    typeset -i SZ
    SZ=$(${LSCMD} -s ${trcfile} | ${AWKCMD} -F " " '{print $1}')
    SZ=${SZ}*1024
    if [ $SZ -gt 163840 ]
    then
        tail --bytes=163840 ${trcfile} >/tmp/$$ 2>/dev/null
        mv -f /tmp/$$ ${trcfile} 2>/dev/null
    fi
fi


tc_start $0
trap "tc_xres \$?" EXIT

#test case 1.1
function test_case_fun_1_1 ()
{
    total_step_case_1_1=2
    cur_step=1

    log "STEP ${cur_step} of ${total_step_case_1_1}:exec $1"
    cur_step=$((${cur_step}+1))
    sh $1

    if [ $? != 0 ];then
    {
        log "exec $1 fail on ${cur_node} node,cmd_rc is $?"
        exit 1
    }
    fi
    log "STEP ${cur_step} of ${total_step_case_1_1}:write and read check pass,write done"
    return 0
}

log "kill node before start "
kill_node -f >null 2>&1

log ">>>>>>test case 1.1 start<<<<<<"
test_case_fun_1_1 write_midplanevpd_optimized_anyCPUcnt.sh
[ $? -eq 0 ] || exit $STF_FAIL
log ">>>>>>test case 1.1 pass<<<<<<"

log ">>>>>>test case 1.2 start<<<<<<"
test_case_fun_1_1 write_midplanevpd_use_ecchvpd.sh
[ $? -eq 0 ] || exit $STF_FAIL
log ">>>>>>test case 1.2 pass<<<<<<"

exit $STF_PASS
