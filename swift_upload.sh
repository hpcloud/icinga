#!/bin/bash

################################################################################
# Simple Nagios plugin to monitor swift upload                                 #
# Author: Daniel Shirley                                                       #
################################################################################

VERSION="Version 1.0"
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
   echo "Check how long swift upload takes"
   echo "Requires enviroment verables set in enviroment.conf and python-swiftclient installed and my require python-keystoneclient"
   echo "you can install this by typeing -- pip install python-swiftclient -- and -- pip install python-keystoneclient"
   
   print_usage

   /bin/cat <<__EOT

Options:
-h
   Print detailed help screen
-V
   Print version information

-w INTEGER
   Exit with WARNING status if swift stat takes longer than (sec)
-c INTEGER
   Exit with CRITICAL status if swift stat takes longer than (sec)
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
               # Threshold is a number (SEC)
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

# Create random file names to use
TESTCONTAINER=$RANDOM
TESTFILE=$RANDOM
TESTFILEPATH=/tmp/$TESTFILE

#remove old logger file if present
if [ -e /tmp/swiftupload.tmp ]
  then
    /bin/rm /tmp/swiftupload.tmp
fi

#create temp logging file
/bin/touch /tmp/swiftupload.tmp
#check if temp log file created successfully ... if not abandon all hope
if [ ! -e /tmp/swiftupload.tmp ]
  then
    echo "could not create temp logging file. please check the logs at /var/log/icinga/swift_upload_check.log"
    echo "could not create temp logging file. /tmp/swiftupload.tmp" >> /var/log/icinga/swift_upload_check.log
    exit $STATE_UNKNOWN
  else
    echo $(/bin/date) >> /tmp/swiftupload.tmp
    echo "TEST CONTAINER : $TESTCONTAINER" >> /tmp/swiftupload.tmp
    echo "TEST FILE: $TESTFILE" >> /tmp/swiftupload.tmp 
    echo "TEST FILE LOCATION: $TESTFILEPATH" >> /tmp/swiftupload.tmp
fi

#create temp file for uploading
echo "create temp file" >> /tmp/swiftupload.tmp
/bin/touch $TESTFILEPATH
#test if file was created successfully ... if not abandon all hope
if [ -e $TESTFILEPATH ]
  then
    echo "successfully created temp file" >> /tmp/swiftupload.tmp
  else
    echo "could not create temp file" >> /tmp/swiftupload.tmp
    echo "could not create temp file please check the logs at /var/log/icinga/swift_upload_check.log"
    cat /tmp/swiftupload.tmp >> /var/log/icinga/swift_upload_check.log
    /bin/rm /tmp/swiftupload.tmp
exit $STATE_UNKNOWN
fi

#start timeing now
time="$(/bin/date +%s)"

#upload the new file to a new container
echo "upload the file $TESTFILE to new container $TESTCONTAINER" >> /tmp/swiftupload.tmp
/usr/bin/swift upload $TESTCONTAINER $TESTFILEPATH >> /tmp/swiftupload.tmp 2>&1

#check if new file is in the new container ... and log everything
echo "check if new container was createed"  >> /tmp/swiftupload.tmp
/usr/bin/swift list >> /tmp/swiftupload.tmp 2>&1
if [[ $(/usr/bin/swift list 2>/dev/null) == *$TESTCONTAINER* ]]
  then
    echo "new container was created"  >> /tmp/swiftupload.tmp
    UPLOADED=true
  else
    echo "new container was NOT created"  >> /tmp/swiftupload.tmp
    /bin/cat /tmp/swiftupload.tmp >> /var/log/icinga/swift_upload_check.log
    /bin/rm /tmp/swiftupload.tmp
    /bin/rm $TESTFILEPATH
    echo "the new container was not created please check the logs at /var/log/icinga/swift_upload_check.log"
    exit $STATE_CRITICAL
fi
echo "check if new file was uploaded"  >> /tmp/swiftupload.tmp
/usr/bin/swift list $TESTCONTAINER >> /tmp/swiftupload.tmp 2>&1
if [[ $(/usr/bin/swift list $TESTCONTAINER 2>/dev/null) == *$TESTFILE* ]]
  then
    echo "new file was uploaded"  >> /tmp/swiftupload.tmp
    UPLOADED=true
  else
    echo "new file was NOT uploaded"  >> /tmp/swiftupload.tmp
    /bin/cat /tmp/swiftupload.tmp >> /var/log/icinga/swift_upload_check.log
    /bin/rm /tmp/swiftupload.tmp
    /bin/rm $TESTFILEPATH
    echo "file was not uploaded to swift please check the logs at /var/log/icinga/swift_upload_check.log"
    exit $STATE_CRITICAL
fi

#delete the new file and container
echo "delete container" >> /tmp/swiftupload.tmp
/usr/bin/swift delete $TESTCONTAINER >> /tmp/swiftupload.tmp 2>&1

#check if the container is gone ... and log everything
echo "check if container was deleted" >> /tmp/swiftupload.tmp
/usr/bin/swift list >> /tmp/swiftupload.tmp 2>&1
if [[ $(/usr/bin/swift list 2>/dev/null) == *$TESTCONTAINER* ]]
  then
    echo "file was not deleted"  >> /tmp/swiftupload.tmp
    cat /tmp/swiftupload.tmp >> /var/log/icinga/swift_upload_check.log
    /bin/rm /tmp/swiftupload.tmp
    /bin/rm $TESTFILEPATH
    echo "file was not deleted please check the logs at /var/log/icinga/swift_upload_check.log"
    exit $STATE_CRITICAL
  else
    echo "container was deleted" >> /tmp/swiftupload.tmp
    DELETED=true
fi

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
  Test container: $TESTCONTAINER
  Test upload file: $TESTFILE
  Command's Output:
`/bin/cat /tmp/swiftupload.tmp`
__EOT
fi


# Evaluate #####################################################################

if [[ "$time" -gt "$thresh_crit" ]]; then
   # Nova list took longer than the critical threshold
   echo "SWIFT STAT CRITICAL - Took $time sec to complete"
   /bin/rm /tmp/swiftupload.tmp
   /bin/rm $TESTFILEPATH
   exit $STATE_CRITICAL
elif [[ "$time" -gt "$thresh_warn" ]]; then
   # Swift stat took longer than the warning threshold
   echo "SWIFT STAT WARNING - Took $time sec to complete"
   /bin/rm /tmp/swiftupload.tmp
   /bin/rm $TESTFILEPATH
   exit $STATE_WARNING
else
   # Swift stat working!
   echo "SWIFT STAT OK - Took $time sec to complete"
   /bin/rm /tmp/swiftupload.tmp
   /bin/rm $TESTFILEPATH
   exit $STATE_OK
fi

