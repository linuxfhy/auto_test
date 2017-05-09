#!/usr/bin/bash
#
# Copyright (c) 2017, Inspur. All rights reserved.
#

NAME=$(basename $0)
CDIR=$(dirname  $0)
TMPDIR=${TMPDIR:-"/tmp"}
TSROOT=$CDIR/../../

source $TSROOT/lib/libstr.sh
source $TSROOT/lib/libcommon.sh
source $TSROOT/config.vars

tc_start $0
trap "tc_xres \$?" EXIT

function cleanup
{
	# make sure RHOST1 is alive
	RUN_POS ping -w 5 $SSH_RHOST1 || return 1

	typeset flag=FALSE
	RUN_NEU $SP1 ls -l $IPMITOOL_REAL && flag=TRUE
	if [[ $flag == "TRUE" ]]; then
		RUN_NEU $SP1 rm -f $IPMITOOL
		RUN_NEU $SP1 cp -a $IPMITOOL_REAL $IPMITOOL
	fi

	return 0
}

cleanup || exit $STF_FAIL
exit $STF_PASS
