#!/usr/bin/bash
#
# Copyright (c) 2017, Inspur. All rights reserved.
#

function initPS4
{
	export PS4='[${FUNCNAME}@${BASH_SOURCE}:${LINENO}|${SECONDS}]+ '
}

function DEBUG
{
	typeset -l s=$DEBUG
	[[ $s == "yes" || $s == "true" ]] && initPS4 && set -x
}
