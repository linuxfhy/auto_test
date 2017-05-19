#!/usr/bin/bash

NAME=$(basename $0)
CDIR=$(dirname  $0)
TMPDIR=${TMPDIR:-"/tmp"}

source $CDIR/../lib/libstr.sh
source $CDIR/../lib/libcommon.sh

tc_start $0
trap "tc_xres \$?" EXIT

echo "this is dummy setup"
exit $STF_PASS
