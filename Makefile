#
# Copyright (c) 2017, Inspur. All rights reserved.
#

SETUP	=
CLEANUP	=
SRCS	= $(shell ls -1 run_tests.sh)
TCS	= ${SRCS:%.sh=%}

TARGET	= ${SETUP} \
	  ${CLEANUP} \
	  ${TCS}

all: ${TARGET}
	rm -f run && ln -s $< run

%: %.sh
	cp $< $@ && chmod 0755 $@

clean:

clobber: clean
	rm -f run ${TARGET}
cl: clobber
