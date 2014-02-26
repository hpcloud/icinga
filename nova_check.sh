#!/bin/bash

################################################################################
# Simple Nagios plugin to monitor nova instance creation                       #
# Author: Daniel Shirley                                                       #
################################################################################

VERSION="Version 0.10a"
AUTHOR="2014 Daniel Shirley (daniel.l.shirley@hp.com)"
PROGNAME=`/usr/bin/basename $0`

# Exit codes
STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3

# Helper functions #############################################################

function print_revision {
   # Print the revision number
   echo "$PROGNAME - $VERSION"
}

function print_usage {
   # Print a short usage statement
   echo "Usage: $PROGNAME [-v] -w <limit> -c <limit>"
}

function print_help {
   # Print detailed help information
   print_revision
   echo "$AUTHOR\n\nCheck if NOVA will create an instance\n"
   echo "Requires enviroment verables set in enviroment.conf and python-novaclient installed"
   echo "you can install this by typeing -- pip install python-novaclient"
   
   print_usage

   /bin/cat <<__EOT

Options:
-h
   Print detailed help screen
-V
   Print version information

-w INTEGER
   Exit with WARNING status if instance creation takes longer than (min)
-c INTEGER
   Exit with CRITICAL status if instance creation takes longer than (min)
-v
   Verbose output
__EOT
}

# Main #########################################################################


