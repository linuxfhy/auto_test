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

function setup
{
	# make sure RHOST1 is alive
	RUN_POS ping -w 5 $SSH_RHOST1 || return 1

	# backup ipmitool to ipmitool.real
	typeset flag1=FALSE
	RUN_POS $SP1 ls -l $IPMITOOL_REAL  && flag1=TRUE
	if [[ $flag1 == "FALSE" ]]; then
	       	RUN_POS $SP1 \
		    cp $IPMITOOL $IPMITOOL_REAL || return 1
	fi

	# link ipmitool.sh2 to ipmitool
	typeset flag2=FALSE
	typeset flag3=FALSE
	RUN_POS $SP1 ls -l $IPMITOOL_REAL  && flag2=TRUE
	RUN_POS $SP1 ls -l $IPMITOOL_SHELL && flag3=TRUE
	if [[ $flag2 == "TRUE" && $flag3 == "TRUE"  ]]; then
		RUN_POS $SP1 \
		    ln -sb $IPMITOOL_SHELL $IPMITOOL || return 1
	fi

	RUN_POS $SP1 chmod augo+x $IPMITOOL_SHELL
	RUN_POS $SP1 chmod augo+x $IPMITOOL_REAL
	RUN_POS $SP1 chmod augo+x $IPMITOOL
	return 0
}

setup || exit $STF_FAIL
exit $STF_PASS
