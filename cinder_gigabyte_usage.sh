#!/bin/bash

################################################################################
# Simple Nagios plugin to monitor cinder gabytes usage                         #
# Author: Daniel Shirley                                                       #
################################################################################

VERSION="Version 0.10a"
AUTHOR="2014 Daniel Shirley (daniel.l.shirley@hp.com)"
PROGNAME=`/bin/basename $0`
PATH=`/usr/bin/dirname $0`

# Exit codes
STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3

# File Includes ################################################################

. $PATH/enviroment.conf

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
   echo "$AUTHOR"
   echo "Check if Cinder gigabytes usage is close to limits"
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
   Exit with WARNING status if more than INTEGER gigabytes used
-w PERCENT%
   Exit with WARNING status if more than PERCENT gigabytes used
-c INTEGER
   Exit with CRITICAL status if more than INTEGER gigabytes used
-c PERCENT%
   Exit with CRITICAL status if more than PERCENT gigabytes used
-v
   Verbose output
__EOT
}

# Verbosity level
verbosity=0
# Warning threshold
thresh_warn=
# Critical threshold
thresh_crit=


# main #########################################################################

GIGLIMIT=$($CINDER absolute-limits | $GREP  maxTotalVolumeGigabytes | $CUT -d"|" -f3 | $TR -d ' ')
GIGUSED=0
for i in `$CINDER list | $HEAD -n -1 | $TAIL -n +4 | $CUT -d "|" -f 5 | $TR -d " "`;do 
GIGUSED=$(($i + $GIGUSED))
done
GIGUSEDPERC=$(( GIGUSED * 100 / GIGLIMIT ))


# Parse command line options
while [ "$1" ]; do
   case "$1" in
       -h | --help)
           print_help
           exit $STATE_OK
           ;;
       -V | --version)
           print_revision
           exit $STATE_OK
           ;;
       -v | --verbose)
           : $(( verbosity++ ))
           shift
           ;;
       -w | --warning | -c | --critical)
           if [[ -z "$2" || "$2" = -* ]]; then
               # Threshold not provided
               echo "$PROGNAME: Option '$1' requires an argument"
               print_usage
               exit $STATE_UNKNOWN
           elif [[ "$2" = +([0-9]) ]]; then
               # Threshold is a number
               thresh=$2
           elif [[ "$2" = +([0-9])% ]]; then
               # Threshold is a percentage
               thresh=$(( GIGLIMIT * ${2%\%} / 100 ))
           else
               # Threshold is neither a number nor a percentage
               echo "$PROGNAME: Threshold must be integer or percentage"
               print_usage
               exit $STATE_UNKNOWN
           fi
           [[ "$1" = *-w* ]] && thresh_warn=$thresh || thresh_crit=$thresh
           shift 2
           ;;
       -?)
           print_usage
           exit $STATE_OK
           ;;
       *)
           echo "$PROGNAME: Invalid option '$1'"
           print_usage
           exit $STATE_UNKNOWN
           ;;
   esac
done


if [[ -z "$thresh_warn" || -z "$thresh_crit" ]]; then
   # One or both thresholds were not specified
   echo "$PROGNAME: Threshold not set"
   print_usage
   exit $STATE_UNKNOWN
elif [[ "$thresh_crit" -lt "$thresh_warn" ]]; then
   # The warning threshold must be less than the critical threshold
   echo "$PROGNAME: Warning useage should be less than critical useage"
   print_usage
   exit $STATE_UNKNOWN
fi





# Verbosity settings ###########################################################
if [[ "$verbosity" -ge 2 ]]; then
   # Print debugging information
   /bin/cat <<__EOT
Debugging information:
  Warning threshold: $thresh_warn
  Critical threshold: $thresh_crit
  Verbosity level: $verbosity
  Gigabytes limit: $GIGLIMIT
  Gigabytes used: $GIGUSED ($GIGUSEDPERC%)
__EOT
fi

if [[ "$GIGUSED" -gt "$thresh_crit" ]]; then
   # Gigabytes is over the critical threshold
   echo "CINDER GIGABYTE USAGE CRITICAL - $GIGUSEDPERC% used ($GIGUSED out of $GIGLIMIT)"
   exit $STATE_CRITICAL
elif [[ "$GIGUSED" -gt "$thresh_warn" ]]; then
   # Gigabytes is over the warning threshold
   echo "CINDER GIGABYTE USAGE WARNING - $GIGUSEDPERC% used ($GIGUSED out of $GIGLIMIT)"
   exit $STATE_WARNING
else
   # Volumes is less than the warning threshold
   echo "CINDER GIGABYTE USAGE OK - $GIGUSEDPERC% used ($GIGUSED out of $GIGLIMIT)"
   exit $STATE_OK
fi
