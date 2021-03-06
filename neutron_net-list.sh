#!/bin/bash

################################################################################
# Simple Nagios plugin to monitor neutron net-list                             #
# Author: Daniel Shirley                                                       #
################################################################################

VERSION="Version .01a"
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
   echo "Check how long neutron net-list takes"
   echo "Requires enviroment verables set in enviroment.conf and python-neutronclient installed"
   echo "you can install this by typeing -- pip install python-neutronclient"
   
   print_usage

   /bin/cat <<__EOT

Options:
-h
   Print detailed help screen
-V
   Print version information

-w INTEGER
   Exit with WARNING status if neutron net-list takes longer than (sec)
-c INTEGER
   Exit with CRITICAL status if netron net-list takes longer than (sec)
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
               # Threshold is a number (MB)
               thresh=$2
           else
               # Threshold is not a number
               echo "$PROGNAME: Threshold must be an integer"
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
   echo "$PROGNAME: Warning time should be less than critical time"
   print_usage
   exit $STATE_UNKNOWN
fi

# Main #########################################################################

time="$(/bin/date +%s)"
neutron_output="$($NEUTRON list 2>&1)"
if [[ $? -gt 0 ]]; then
   echo "NEUTRON NET-LIST CRITICAL - Command failed please check the logs at /var/log/icinga/neutron_net-list_check.log"
   echo "$(/bin/date)" >> /var/log/icinga/neutron_net-list_check.log
   echo "$neutron_output" >> /var/log/icinga/neutron_net-list_check.log
   exit $STATE_CRITICAL
fi
time="$(($(/bin/date +%s)-time))"

# Verbosity settings ###########################################################
if [[ "$verbosity" -ge 2 ]]; then
   # Print debugging information
   /bin/cat <<__EOT
Debugging information:
  Warning threshold: $thresh_warn SEC
  Critical threshold: $thresh_crit SEC
  Verbosity level: $verbosity
  Completed Time: $time
  NEUTRON Output: $neutron_output
__EOT
fi

# Evaluate #####################################################################

if [[ "$time" -gt "$thresh_crit" ]]; then
   # Neutron net-list took longer than the critical threshold
   echo "NEUTRON NET-LIST CRITICAL - Took $time sec to complete"
   exit $STATE_CRITICAL
elif [[ "$time" -gt "$thresh_warn" ]]; then
   # Neutron net-list took longer than the warning threshold
   echo "NEUTRON NET-LIST WARNING - Took $time sec to complete"
   exit $STATE_WARNING
else
   # Neutron net-list working!
   echo "NEUTRON NET-LIST OK - Took $time sec to complete"
   exit $STATE_OK
fi
