#
# Copyright (c) 2017, Inspur. All rights reserved.
#

SETUP	= setup
CLEANUP	= cleanup
SRCS	= $(shell ls -1 tc_*.sh)
TCS	= ${SRCS:%.sh=%}

TARGETS = ${SETUP} \
	  ${CLEANUP} \
	  ${TCS}

all: ${TARGETS}

%: %.sh
	cp $< $@ && chmod 0755 $@

clean:

clobber: clean
	rm -f ${TARGETS}
cl: clobber
