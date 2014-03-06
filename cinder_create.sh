#!/bin/bash

################################################################################
# Simple Nagios plugin to monitor $CINDER create                                #
# Author: Daniel Shirley                                                       #
################################################################################

VERSION="Version 0.01a"
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
   echo "Check how long $CINDER create takes"
   echo "Requires enviroment verables set in enviroment.conf and python-$CINDERclient installed"
   echo "you can install this by typeing -- pip install python-$CINDERclient"
   
   print_usage

   /bin/cat <<__EOT

Options:
-h
   Print detailed help screen
-V
   Print version information

-w INTEGER
   Exit with WARNING status if $CINDER create takes longer than (sec)
-c INTEGER
   Exit with CRITICAL status if $CINDER create takes longer than (sec)
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

volid=noid
#remove old logger file if present
if [ -e /tmp/cindercreate.tmp ]
  then
    /bin/rm /tmp/cindercreate.tmp
fi

#create temp logging file
/bin/touch /tmp/cindercreate.tmp
#check if temp log file created successfully ... if not abandon all hope
if [ ! -e /tmp/cindercreate.tmp ]
  then
    echo "could not create temp logging file. please check the logs at /var/log/icinga/cinder_create.log"
    echo "could not create temp logging file. /tmp/cindercreate.tmp" >> /var/log/icinga/cinder_create.log
    exit $STATE_UNKNOWN
  else
    /bin/date > /tmp/cindercreate.tmp
fi
#start timeing now
time="$(/bin/date +%s)"

echo "create $CINDER volume" >> /tmp/cindercreate.tmp
$CINDER create 1 &>> /tmp/cindercreate.tmp


volid=$($GREP " id " /tmp/cindercreate.tmp | $CUT -d"|" -f3)
if [ $volid == "noid" ]
then
echo "could not find volume id" >> /tmp/cindercreate.tmp
/bin/cat /tmp/cindercreate.tmp >> /var/log/icinga/cinder_create.log
echo "could not find volume id please check logs /var/log/icinga/$CINDER_create.log"
exit $STATE_CRITICAL
else
echo "useing $volid as volume id" >> /tmp/cindercreate.tmp
fi

TIME=0
AVAILABLE="fasle"

echo "check if volume is available" >> /tmp/cindercreate.tmp
while [ "$AVAILABLE" = "fasle" ]
do

  status=$($CINDER list | $GREP $volid)

  if echo "$status" | $GREP -q "available"
  then
    AVAILABLE="true"
    echo "volume is available" >> /tmp/cindercreate.tmp
    $CINDER list &>> /tmp/cindercreate.tmp
  elif echo "$status" | $GREP -q "error"
  then
    echo "volume created in error" >> /tmp/cindercreate.tmp
    $CINDER list &>> /tmp/cindercreate.tmp
    /bin/cat /tmp/cindercreate.tmp >> /var/log/icinga/cinder_create.log
    echo "volume created in error please check logs /var/log/icinga/$CINDER_create.log"
    exit $STATE_CRITICAL
  fi

  TIME="$(($(/bin/date +%s)-$time))"

  if [ $TIME -gt $thresh_crit ]
  then
    echo "volume did not create in time" >> /tmp/cindercreate.tmp
    $CINDER list &>> /tmp/cindercreate.tmp
    /bin/cat /tmp/cindercreate.tmp >> /var/log/icinga/cinder_create.log
    echo "volume did not create in time please check logs /var/log/icinga/$CINDER_create.log"
    exit $STATE_CRITICAL
  fi

done

echo "deleteing the volume" >> /tmp/cindercreate.tmp

$CINDER delete $volid &>> /tmp/cindercreate.tmp
DELETED="fasle"

while [ "$DELETED" = "fasle" ]
do

  if !($CINDER list | $GREP -q $volid)
  then
    DELETED="true"
    echo "volume was deleted" >> /tmp/cindercreate.tmp
    $CINDER list &>> /tmp/cindercreate.tmp
  fi

  TIME="$(($(/bin/date +%s)-$time))"

  if [ $TIME -gt $thresh_crit ]
  then
    echo "volume did not delete in time" >> /tmp/cindercreate.tmp
    $CINDER list &> /tmp/cindercreate.tmp
    /bin/cat /tmp/cindercreate.tmp >> /var/log/icinga/cinder_create.log
    echo "volume did not delete in time please check logs /var/log/icinga/$CINDER_create.log"
    exit $STATE_CRITICAL
  fi

done


#end timeing
time="$(($(/bin/date +%s)-$time))"


# Verbosity settings ###########################################################
if [[ "$verbosity" -ge 2 ]]; then
   # Print debugging information
   /bin/cat <<__EOT
Debugging information:
  Warning threshold: $thresh_warn SEC
  Critical threshold: $thresh_crit SEC
  Verbosity level: $verbosity
  Completed Time: $time
  $CINDER Volume: $volid
  Volume was available: $AVAILABLE
  Volume was deleted: $DELETED
  Log: 
$(/bin/cat /tmp/cindercreate.tmp)
__EOT
fi

# Evaluate #####################################################################

if [[ "$time" -gt "$thresh_crit" ]]; then
   # Cinder create took longer than the critical threshold
   echo "$CINDER CREATE CRITICAL - Took $time sec to complete"
   exit $STATE_CRITICAL
elif [[ "$time" -gt "$thresh_warn" ]]; then
   # Cinder create took longer than the warning threshold
   echo "$CINDER CREATE WARNING - Took $time sec to complete"
   exit $STATE_WARNING
else
   # Cinder create working!
   echo "$CINDER CREATE OK - Took $time sec to complete"
   exit $STATE_OK
fi
