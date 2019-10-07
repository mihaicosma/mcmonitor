#!/bin/bash

#default values -- this are the absolute worst case values
#SCRIPT PARAMETERS
SCRIPT_VERSION="mcmonitor 0.99 RC"

ECHO_DISPLAY="OFF"
FORCE_EMAIL="FALSE"
NO_EMAIL="FALSE"
UPDATE_ROWNUM="TRUE"
DEBUG="FALSE"

sender='raspberry@gmail.com'
subject="McMonitor status mail"
recipient=""

SCRIPT_LOG="/tmp/mcmonitor_script.log"
STATUS_FILE="/tmp/mcmonitor_status.txt"
JSON_FILE="/tmp/mcmonitor_json.json"
MIN_SEVERITY_TO_DISPLAY=0
MIN_SEVERITY_TO_MAIL=1

SCRIPT_LOCATION=`dirname $0`
CONFIG="$SCRIPT_LOCATION/mcmonitor.ini"

#This values are the worst case defaults
#The mcmonitor.ini values take precedence over these values
#The runtime command line arguments take precedence over any other default values

# Determine OS
OS=`uname`

if [[ $OS == "HP-UX" ]]; then
   df_command="bdf"
   nslookup_command="/usr/bin/nslookup"
   tail_command="tail -n "
else
   df_command="df -h"
   nslookup_command="/usr/sbin/nslookup"
   tail_command="tail -"
fi

##############################################################################
#
# Procedures
#

function display_and_mail {
if [[ $SEVERITY == "" ]]; then
   debug "Severity for current test was not set"
   fi
if [[ $SEVERITY -ge $MIN_SEVERITY_TO_DISPLAY ]]; then 
      echo $* > /dev/null
      if [[ $ECHO_DISPLAY = "ON" ]]; then
	      echo $*
      fi
	  message="$message \n $* \n"
fi
}

function log {
 
      echo $* > /dev/null
      todays_date=`date`
      if [[ $ECHO_DISPLAY = "ON" ]]; then
        echo $todays_date: $*
      fi  
      echo $todays_date $* >> $SCRIPT_LOG 
}

function debug {
 
      echo $* > /dev/null
      if [[ $DEBUG = "TRUE" ]]; then
        log $*
      fi
}


function json_add {
      
      id=`echo $* | cut -d\" -f4`
      if [ ! ${#id} -ge 1 ]; then     
         debug "Adding to json failed for some reason"
      else 
         debug "Adding info about $id to json."
         cat $JSON_FILE | grep -v "\"$id\"" | head -n -2 > $JSON_FILE.tmp
         echo $*, >> $JSON_FILE.tmp
         tail -2 $JSON_FILE >> $JSON_FILE.tmp
         mv -f $JSON_FILE.tmp $JSON_FILE
      fi
      if [[ $DEBUG = "TRUE" ]]; then
        log $*
      fi
}

function json_add_loopback {

      id=`echo $* | cut -d\" -f4`
      if [ ! ${#id} -ge 1 ]; then
         debug "Adding to json failed for some reason"
      else
         debug "Adding info about $id to json."
         cat $JSON_FILE | grep -v "\"$id\"" | head -n -2 > $JSON_FILE.tmp
         echo $* >> $JSON_FILE.tmp
         tail -1 $JSON_FILE >> $JSON_FILE.tmp
         mv -f $JSON_FILE.tmp $JSON_FILE
      fi
      if [[ $DEBUG = "TRUE" ]]; then
        log $*
      fi
}



function jsonval {
    temp=`echo $json | sed 's/\\\\\//\//g' | sed 's/[{}]//g' | awk -v k="text" '{n=split($0,a,","); for (i=1; i<=n; i++) print a[i]}' | sed 's/\"\:\"/\|/g' | sed 's/[\,]/ /g' | sed 's/\"//g' | grep -w $prop`
    echo ${temp##*|}
}


function usage {
 
	  echo "Usage: mcmonitor [--option] [--option] [...]"
      echo "  -e | --echo            Echos messages to display"
	  echo "  -d | --debug           Debug mode"
      echo "  -f | --force_email     Forces sending of email even if everything is OK"
      echo "  -n | --no_email        Disables sending of email"
      echo "  -r | --no_row_update   Disables the updating of the log rows cursor"
      echo "  -h | --help            Prints this message"

}

function check_severity {
   SEVERITY=${severity[$COUNTER]}
   if (( ${severity[$COUNTER]} > $MAX_SEVERITY ))
      then
	    MAX_SEVERITY=${severity[$COUNTER]}
   fi
}

function check_subject {
   new_subject=${changesubject[$COUNTER]}
   if [[ $new_subject != "" ]]
      then
	    subject=$new_subject
		debug "Mail subject changed to: $new_subject"
   fi
}

function clear_severity {
   SEVERITY=0
}

function readconf() {

#clear mailto, severity and changesubject variables

COUNTER=1
while [[ ${add_recipient[$COUNTER]} != "" ]]; do
   add_recipient[$COUNTER]=""
   ((COUNTER=COUNTER+1))
done
COUNTER=1
while [[ ${severity[$COUNTER]} != "" ]]; do
   severity[$COUNTER]=""
   ((COUNTER=COUNTER+1))
done
while [[ ${changesubject[$COUNTER]} != "" ]]; do
   changesubject[$COUNTER]=""
   ((COUNTER=COUNTER+1))
done
 
    match=0
 
    while read line; do
        # skip comments
        [[ ${line:0:1} == "#" ]] && continue
 
        # skip empty lines
        [[ -z "$line" ]] && continue
 
        # still no match? lets check again
        if [ $match == 0 ]; then
 
            # do we have an opening tag ?
            if [[ ${line:$((${#line}-1))} == "{" ]]; then
 
                # strip "{"
                group=${line:0:$((${#line}-1))}
                # strip whitespace
                group=${group// /}
 
                # do we have a match ?
                if [[ "$group" == "$1" ]]; then
                    match=1
                    continue
                fi
 
                continue
            fi
 
        # found closing tag after config was read - exit loop
        elif [[ ${line:0} == "}" && $match == 1 ]]; then
            break
 
        # got a config line eval it
        else
            eval $line
        fi
 
    done < "$CONFIG"
}

function check_schedule() {
  IN_SCHEDULE="FALSE"   

  for arg; do  
      SCHEDULE_COUNTER=1 
      while [[ ${schedule_name[$SCHEDULE_COUNTER]} != "" ]]; do    
      if [[ $arg == ${schedule_name[$SCHEDULE_COUNTER]} ]]
         then
		 day_of_week=`date +%u`
		 case $day_of_week in
		   1 ) todays_schedule=${schedule_mon[$SCHEDULE_COUNTER]} ;;			
		   2 ) todays_schedule=${schedule_tue[$SCHEDULE_COUNTER]} ;;
		   3 ) todays_schedule=${schedule_wed[$SCHEDULE_COUNTER]} ;;
		   4 ) todays_schedule=${schedule_thu[$SCHEDULE_COUNTER]} ;;
		   5 ) todays_schedule=${schedule_fri[$SCHEDULE_COUNTER]} ;;
		   6 ) todays_schedule=${schedule_sat[$SCHEDULE_COUNTER]} ;;
		   7 ) todays_schedule=${schedule_sun[$SCHEDULE_COUNTER]} ;;
		 esac		 
		 start_hh=`echo $todays_schedule | cut -d- -f1 | awk '{print ($1)}' | cut -d: -f1`
		 start_mm=`echo $todays_schedule | cut -d- -f1 | awk '{print ($1)}' | cut -d: -f2`
		 end_hh=`echo $todays_schedule | cut -d- -f2 | awk '{print ($1)}' | cut -d: -f1`
		 end_mm=`echo $todays_schedule | cut -d- -f2 | awk '{print ($1)}' | cut -d: -f2`
		 current_hh=$( expr `date +%H` + 0 )
		 current_mm=$( expr `date +%M` + 0 )		 
		 (( start_stamp = start_hh * 100 + start_mm ))
		 (( end_stamp = end_hh * 100 + end_mm ))
		 (( current_stamp = current_hh * 100 + current_mm ))
		 if (( $start_stamp < $current_stamp))
		    then
			if (( $current_stamp <= $end_stamp))
			   then
			   IN_SCHEDULE="TRUE"
			   else
			   echo "NOT_IN_SCHEDULE" > /dev/null
			fi
	     fi		 		   
      fi   
      (( SCHEDULE_COUNTER = SCHEDULE_COUNTER +1 ))    
      done
  
  done
  
  echo $IN_SCHEDULE
}

function last_lines() {

#STATUS file should have:
#$current_log_file:PREV_LINES:CURRENT_LINES:CURRENT_PID

  current_log_file=`echo $*`
  
  if [ -f $STATUS_FILE ]
   then
     # citeste cate sunt si cate au fost	 	 
	 lines_files_line=`cat $STATUS_FILE | grep "$current_log_file"`	     
	 old_lines=`echo $lines_files_line | cut -d: -f2`
	 prev_lines=`echo $lines_files_line | cut -d: -f3`
	 prev_pid=`echo $lines_files_line | cut -d: -f4`
	 #debug "Old lines $old_lines ; Previous_lines: $prev_lines ; Previous PID $prev_pid ; "
  fi

  total_lines=`cat $current_log_file | wc -l`
  
 
  if [[ $prev_lines == "" ]]; then 
	    #debug "The STATUS file does not have any information regarding $current_log_file."
	    (( diference = total_lines ))
		if [[ $UPDATE_ROWNUM=="TRUE" ]]; then		
		   echo "${current_log_file}:0:${total_lines}:$CURRENT_PID" >> $STATUS_FILE
		fi
  else	 
	    if [[ $prev_pid == $CURRENT_PID ]]; then
		   #debug "The STATUS file has already been updated for $current_log_file."
		   (( diference = total_lines - old_lines ))
		   else		   
		   (( diference = total_lines - prev_lines ))
		   if [[ $UPDATE_ROWNUM == "TRUE" ]]; then
		     #debug "Updating the STATUS file with new lines $total_lines."
		     `cat $STATUS_FILE | grep -v $current_log_file > $STATUS_FILE.tmp`
		     `mv $STATUS_FILE.tmp $STATUS_FILE`
		     echo "${current_log_file}:${prev_lines}:${total_lines}:$CURRENT_PID" >> $STATUS_FILE
		   fi
		 fi
  fi	

  echo $diference
  
}

function add_to_recipients {

  for arg; do  
      MAILGROUP_COUNTER=1
      while [[ ${mailgroup_name[$MAILGROUP_COUNTER]} != "" ]]; do    
      if [[ $arg == ${mailgroup_name[$MAILGROUP_COUNTER]} ]]
         then
         new_address=${mailgroup_text[$MAILGROUP_COUNTER]} 

         response=`expr match "$recipient" ".*$new_address.*"`

         if [[ $response -ne 0 ]]
            then
             debug "Recipient $new_address already exists in mail list"
            else
			 if [[ $recipient != "" ]]; then			 
                recipient="$recipient , $new_address"
				else
				recipient="$new_address"
			 fi
             debug "New recipient list: $recipient"      
         fi
      fi
	  (( MAILGROUP_COUNTER = MAILGROUP_COUNTER + 1 ))
	  done
	  
  done
}

##############################################################################
#
#  Process input parameters 
#
readconf "default"

for arg; do
   case $arg in
        -f | --force_email )  
           FORCE_EMAIL="TRUE" 
	   ;;
        -n | --no_email )  
	   NO_EMAIL="TRUE"
   	   ;;
        -r | --no_row_update )
	   UPDATE_ROWNUM="FALSE"
	   ;;
        -e | --echo )
	   ECHO_DISPLAY="ON"
	   echo 'Display=ON'
	   ;;
        -d | --debug )
	   DEBUG="TRUE"
	   echo '-- Debug mode ON'
	   ;;	   	   
        -h | --help )
	   usage
	   exit
	   ;;
   esac
   done

##############################################################################
#
#  Pre-requisites 
#

message=""
sql_plus="/opt/oracle/product/10.2/bin/sqlplus"
ORACLE_HEADER="
whenever sqlerror exit sql.sqlcode
set heading off
set pagesize 0
set linesize 1000
set feedback off
set wrap off
set verify off
set define off"

MAX_SEVERITY=0
SEVERITY=0
CURRENT_PID=$$
debug "Current PID is $CURRENT_PID"
log "Script $SCRIPT_VERSION started with pid $CURRENT_PID"

readconf "schedules"
readconf "mail_groups"

if [ -f $SOURCE_ENVIRONMENT ]; then
   . $SOURCE_ENVIRONMENT
   else
   if [[ $SOURCE_ENVIRONMENT != "" ]];then
      debug "$SOURCE_ENVIRONMENT was not found."
	  fi
   fi

add_to_recipients "default_group"

##############################################################################
#
#  Additional localhost details
#
json=`curl -s -X GET http://localhost:4040/api/tunnels`
debug "Raspuns ngrok API: $json"
prop='public_url'
ngrokurl=`jsonval`
debug "parse url: $ngrokurl"
iplist=`ifconfig -a | grep 'inet ' | grep -v '127' | grep -v 'inet6' | cut -d: -f2 | cut -d' ' -f1`

##############################################################################
#
#  JSON Status Init
#


if [ ! -f $JSON_FILE ]; then
  echo "[" >> $JSON_FILE
  echo "{ \"id\":\"loopback\", \"errorlevel\":1, \"details\":\"Just started.\", \"timestamp\":`date +%s` }" >> $JSON_FILE 
  echo "]" >> $JSON_FILE
fi


##############################################################################

display_and_mail "System ====================================================="

##############################################################################
#
#  Check for running processes
#

readconf "command_check"

COUNTER=1
while [[ ${command[$COUNTER]} != "" ]]; do
   SEVERITY=0
   IN_SCHEDULE=`check_schedule ${schedule[$COUNTER]}`      
   debug "Raspuns IN_SCHEDULE: $IN_SCHEDULE"
   debug "Command $COUNTER is ${command[$COUNTER]}." 
   if [[ $IN_SCHEDULE != "FALSE" ]]; then   

      response=`echo ${command[$COUNTER]} | sh`
      debug "Response is $response"
   
      if [ $response -eq ${normalvalue[$COUNTER]} ]
       then
        # Este ok 
		
        display_and_mail ${message_YES[COUNTER]}
        json_add "{ \"id\":\"command $COUNTER\", \"errorlevel\":0, \"details\":\"${message_YES[COUNTER]}\", \"timestamp\":`date +%s` }"
       else
	    check_subject
	    check_severity ${severity[$COUNTER]}
            display_and_mail ${message_NOT[$COUNTER]}
            add_to_recipients ${add_recipient[$COUNTER]} 
	    clear_severity
            json_add "{ \"id\":\"command $COUNTER\", \"errorlevel\":${severity[$COUNTER]}, \"details\":\"${message_NOT[COUNTER]}\", \"timestamp\":`date +%s` }"
      fi   
   fi   
   ((COUNTER=COUNTER+1))
done


##############################################################################
#
#  Check for needed remote connections 
#

readconf "remote_connections"

COUNTER=1
while [[ ${remote_IP[$COUNTER]} != "" ]]; do
   SEVERITY=0
   debug "Remote connection $COUNTER is ${remote_IP[$COUNTER]}:${remote_port[$COUNTER]}." 
   IN_SCHEDULE=`check_schedule ${schedule[$COUNTER]}`
   if [[ $IN_SCHEDULE != "FALSE" ]]; then   
      response=$(printf '%bquit\n' '\035' | telnet ${remote_IP[$COUNTER]} ${remote_port[$COUNTER]} 2>&1 > /dev/null | wc -l)
      debug "Response is $response"
      if (( $response > 0 )) 
         then 
          # NU este OK
		  check_subject
		  check_severity ${severity[$COUNTER]}
                  display_and_mail ${message_NOT[$COUNTER]}
                  add_to_recipients ${add_recipient[$COUNTER]} 		  
		  clear_severity
                  json_add "{ \"id\":\"remote $COUNTER\", \"errorlevel\":${severity[$COUNTER]}, \"details\":\"${message_NOT[COUNTER]}\", \"timestamp\":`date +%s` }"
         else
          display_and_mail ${message_YES[COUNTER]}
          json_add "{ \"id\":\"remote $COUNTER\", \"errorlevel\":0, \"details\":\"${message_YES[COUNTER]}\", \"timestamp\":`date +%s` }"

      fi
   fi    
   ((COUNTER=COUNTER+1))
done


##############################################################################
#
#  Check the DNS
#

readconf "dns_tests"

COUNTER=1
while [[ ${test_ip[$COUNTER]} != "" ]]; do
  SEVERITY=0
  IN_SCHEDULE=`check_schedule ${schedule[$COUNTER]}`
   if [[ $IN_SCHEDULE != "FALSE" ]]; then
   TMP_VAR_reverse=$($nslookup_command ${test_ip[$COUNTER]} 2>&1 | grep "can't find" | wc -l)
   TMP_VAR_direct=$($nslookup_command ${test_host[$COUNTER]} 2>&1 | grep "can't find" | wc -l)

   failure_detected="false"
   if (( $TMP_VAR_direct > 0 ))
      then
           check_subject
           check_severity ${severity[$COUNTER]}
           display_and_mail "[NOT OK] The DNS is not working properly. Direct lookup failed."
           failure_detected="true"
           add_to_recipients ${add_recipient[$COUNTER]}
           clear_severity
           json_add "{ \"id\":\"dns $COUNTER\", \"errorlevel\":${severity[$COUNTER]}, \"details\":\"[NOT OK] The DNS is not working properly. Direct lookup failed.\", \"timestamp\":`date +%s` }"
   fi
   if (( $TMP_VAR_reverse > 0 ))
     then
          check_subject
          check_severity ${severity[$COUNTER]}
          display_and_mail "[NOT OK] The DNS is not working properly. Reverse lookup failed."
          failure_detected="true"
          add_to_recipients ${add_recipient[$COUNTER]}
          clear_severity
          json_add "{ \"id\":\"dns $COUNTER\", \"errorlevel\":${severity[$COUNTER]}, \"details\":\"[NOT OK] The DNS is not working properly. Reverse lookup failed.\", \"timestamp\":`date +%s` }"
   fi

   if [[ $failure_detected = "false" ]]
      then
      display_and_mail "[OK] DNS seems to be working OK"
      json_add "{ \"id\":\"dns $COUNTER\", \"errorlevel\":0, \"details\":\"[OK] DNS seems to be working OK.\", \"timestamp\":`date +%s` }"

   fi

  fi
  ((COUNTER=COUNTER+1))
done
  
##############################################################################
#
#  Check disk space
#

disk_space="OK"
OK_message="[OK] Disk usage seems ok."
NOT_OK_message="[NOT OK] Disk usage is not ok."

readconf "disk_space"

COUNTER=1
while [[ ${mountpoint[$COUNTER]} != "" ]]; do
  SEVERITY=0
  IN_SCHEDULE=`check_schedule ${schedule[$COUNTER]}`
  if [[ $IN_SCHEDULE != "FALSE" ]]; then

  TMP_VAR=$($df_command | grep ${mountpoint[$COUNTER]} | grep -v ${mountpoint[$COUNTER]}/ | awk -F" " '{print $5}' | tr -d "%")
  debug "first attempt for ${mountpoint[$COUNTER]} is: $TMP_VAR"
  if [[ $TMP_VAR == "" ]]; then
     TMP_VAR=$($df_command | grep ${mountpoint[$COUNTER]} | grep -v ${mountpoint[$COUNTER]}/ | awk -F" " '{print $4}' | tr -d "%")
         debug "second attempt for ${mountpoint[$COUNTER]} is: $TMP_VAR"
  fi
  if [[ $TMP_VAR == "" ]]; then
         display_and_mail "[NOT OK] ${mountpoint[$COUNTER]} does not seem to be mounted."
         disk_space="NOT OK"
         json_add "{ \"id\":\"disk $COUNTER\", \"errorlevel\":${severity[$COUNTER]}, \"details\":\"[NOT OK] ${mountpoint[$COUNTER]} does not seem to be mounted.\", \"timestamp\":`date +%s` }"

     else
     if (( $TMP_VAR < ${threshold[$COUNTER]} ))
       then
        echo "< ${threshold[$COUNTER]} is OK" > /dev/null
        json_add "{ \"id\":\"disk $COUNTER\", \"errorlevel\":0, \"details\":\"[OK] Disk space on ${mountpoint[$COUNTER]} is OK - $TMP_VAR < ${threshold[$COUNTER]}\", \"timestamp\":`date +%s` }"

       else
            check_subject
            check_severity ${severity[$COUNTER]}
            display_and_mail "[NOT OK] ${mountpoint[$COUNTER]} usage is $TMP_VAR %."
            disk_space="NOT OK"
            add_to_recipients ${add_recipient[$COUNTER]}
            clear_severity
            json_add "{ \"id\":\"disk $COUNTER\", \"errorlevel\":${severity[$COUNTER]}, \"details\":\"[NOT OK] ${mountpoint[$COUNTER]} usage is $TMP_VAR %.\", \"timestamp\":`date +%s` }"
     fi
  fi

  fi
  ((COUNTER=COUNTER+1))
done


#Disk space overall ===========================================================
  if [[ $disk_space = "OK" ]]
    then 
     display_and_mail $OK_message
    else
     echo "There must have been at least one NOT OK" > /dev/null
  fi


##############################################################################
#
#  Oracle 
#

display_and_mail "ORACLE ====================================================="

readconf "oracle_checks"
debug "Starting oracle checks.."

COUNTER=1
while [[ ${oracle_connect[$COUNTER]} != "" ]]; do
  SEVERITY=0
  IN_SCHEDULE=`check_schedule ${schedule[$COUNTER]}`
  debug "Oracle check no $COUNTER is in schedule: $IN_SCHEDULE"
  
  if [[ $IN_SCHEDULE != "FALSE" ]]; then   

  
  TMP_VAR=`$sql_plus -s /nolog  <<EOF | tr "\012" "|" | tr " " "#" | tr "\011" "@"
    $ORACLE_HEADER
    connect ${oracle_connect[$COUNTER]} 
    ${select_string[$COUNTER]} 
    exit; 
EOF`
  answer=`echo $TMP_VAR | tr "|" "\012" | tr "#" " " | tr "@" "\011"`
  if [[ $answer = ${expected_result[$COUNTER]} ]]
    then
     display_and_mail ${message_YES[$COUNTER]} 
     json_add "{ \"id\":\"oracle $COUNTER\", \"errorlevel\":0, \"details\":\"${message_YES[COUNTER]}\", \"timestamp\":`date +%s` }"
    else
	 check_subject
	 check_severity ${severity[$COUNTER]}
         display_and_mail "${message_NOT[$COUNTER]} : \n $answer "
         add_to_recipients ${add_recipient[$COUNTER]} 
         clear_severity
         json_add "{ \"id\":\"oracle $COUNTER\", \"errorlevel\":${severity[$COUNTER]}, \"details\":\"${message_NOT[COUNTER]}\", \"timestamp\":`date +%s` }"

  fi
  
  fi
  ((COUNTER=COUNTER+1))
done     
debug "Done with oracle checks.."

 ##############################################################################
#
#  External scripts 
#

display_and_mail "External Scripts ==========================================="

readconf "script_check"

COUNTER=1
while [[ ${script[$COUNTER]} != "" ]]; do
  SEVERITY=0
  IN_SCHEDULE=`check_schedule ${schedule[$COUNTER]}`
  if [[ $IN_SCHEDULE != "FALSE" ]]; then   

  debug "Se executa: . ${script[$COUNTER]}"
  TMP_VAR=`. ${script[$COUNTER]}`
  answer=`echo $TMP_VAR`
  debug "Answer is $answer"
  if [[ $answer = ${normaloutput[$COUNTER]} ]]
    then
     display_and_mail ${message_YES[$COUNTER]} 
     json_add "{ \"id\":\"external $COUNTER\", \"errorlevel\":0, \"details\":\"${message_YES[COUNTER]}\", \"timestamp\":`date +%s` }"
    else
	 check_subject
	 check_severity ${severity[$COUNTER]}
         display_and_mail "${message_NOT[$COUNTER]} : \n $answer "
         add_to_recipients ${add_recipient[$COUNTER]} 
         clear_severity
         json_add "{ \"id\":\"external $COUNTER\", \"errorlevel\":${severity[$COUNTER]}, \"details\":\"${message_NOT[COUNTER]}\", \"timestamp\":`date +%s` }"
  fi
  
  fi
  ((COUNTER=COUNTER+1))
done     

 
 
##############################################################################
#
#  Check log for ERRORS 
#

display_and_mail "Logs ======================================================="

readconf "log_checks"

COUNTER=1
while [[ ${log_file[$COUNTER]} != "" ]]; do
  SEVERITY=0
  IN_SCHEDULE=`check_schedule ${schedule[$COUNTER]}`
  debug "Log file: ${log_file[$COUNTER]}"
  debug "Schedule reponse $IN_SCHEDULE"
  debug "$UPDATE_ROWNUM is update rownum"
  if [[ $IN_SCHEDULE != "FALSE" ]]; then   

  DIFERENCE=`last_lines ${log_file[$COUNTER]}`
  debug "DIFERENCE is $DIFERENCE"
  tail_script="${tail_command}${DIFERENCE} ${log_file[$COUNTER]} | ${grep_command[$COUNTER]}"
  response=`echo $tail_script | sh`

  lines=`echo "$response" | grep " " | wc -l`  
  
  if [ $lines -ne 0 ] 
   then
    if ((lines > 40 ))
	   then
	     (( printlines = 40 ))
		else
		 (( printlines = lines ))
	fi
    debug "$lines error lines found"
	check_subject
	check_severity ${severity[$COUNTER]}
    display_and_mail ${message_NOT[$COUNTER]}
    json_add "{ \"id\":\"log $COUNTER\", \"errorlevel\":${severity[$COUNTER]}, \"details\":\"${message_NOT[COUNTER]}\", \"timestamp\":`date +%s` }"

    display_and_mail "$lines lines found matching error messages:"
    if ((lines > 40 ))
		then
		display_and_mail "(only last $printlines will be printed here)"
		response=`echo "$response" | grep " " | ${tail_command}${printlines}`
	fi
    message=`echo "$message" "$response"`
    display_and_mail "--------- \n"
    add_to_recipients ${add_recipient[$COUNTER]} 	
	clear_severity
   else
    display_and_mail ${message_YES[$COUNTER]}
    json_add "{ \"id\":\"log $COUNTER\", \"errorlevel\":0, \"details\":\"${message_YES[COUNTER]}\", \"timestamp\":`date +%s` }"
  fi
  
  fi
  ((COUNTER=COUNTER+1))
done     
 


##############################################################################
#
#  Finishing touches 
#

#Sendmail =====================================================================

todays_date=`date`
display_and_mail "End of checks ==============================================\n"
SEVERITY=100
display_and_mail "-----\nThis message was generated on: $todays_date.\nGenerated with $SCRIPT_VERSION script, customization $CONFIG_VERSION"
display_and_mail "\nHost info:\n local ip: $iplist \n ngrok url: $ngrokurl"

debug "Maximum severity found active: $MAX_SEVERITY"
debug "Recipient list: $recipient" 

if [[ `echo -e "$message" | grep "NOT OK"` = "" ]]
   then
     display_and_mail "Everything seems ok!"
fi

SEVERITY_TEXT="Normal"
if [[ $MAX_SEVERITY == "1" ]]; then SEVERITY_TEXT="Indeterminate"; fi
if [[ $MAX_SEVERITY == "2" ]]; then SEVERITY_TEXT="Warning"; fi
if [[ $MAX_SEVERITY == "3" ]]; then SEVERITY_TEXT="Minor"; fi
if [[ $MAX_SEVERITY == "4" ]]; then SEVERITY_TEXT="Major"; fi
if [[ $MAX_SEVERITY == "5" ]]; then SEVERITY_TEXT="Critical"; fi

if [[ $FORCE_EMAIL = "TRUE" ]] 
  then
    debug "Mailed sent with forced -f option!"
		 debug "Sending mail!"
		 OSfound="FALSE"
		 if [[ $OS == "HP-UX" ]]; then
			echo -e "$message" | /usr/bin/mailx -s "[$SEVERITY_TEXT] $subject" -r $sender $recipient
			OSfound="TRUE"
		 fi
		 if [[ $OS == "SunOS" ]]; then
			echo -e "$message" | /usr/bin/mailx -s "[$SEVERITY_TEXT] $subject" -r $sender $recipient
			OSfound="TRUE"
		 fi
                 if [[ $OS == "Linux" ]]; then
                        echo -e "$message" | /usr/bin/mailx -s "[$SEVERITY_TEXT] $subject" -r $sender $recipient
                        OSfound="TRUE"
                 fi
		 if [[ $OSfound == "FALSE" ]]; then
			echo -e "$message" | /bin/mailx -s "[$SEVERITY_TEXT] $subject" $recipient -- -r $sender
		 fi		
  else
  if [[ `echo -e "$message" | grep "NOT OK"` = "" ]]
   then
     display_and_mail "Everything seems ok!"
   else
    if [[ $MAX_SEVERITY -ge $MIN_SEVERITY_TO_MAIL ]]
	 then
      #send the email
      if [[ $NO_EMAIL = "TRUE" ]]
	     then
	     display_and_mail "Message will not be sent because of --no_email option"
         else	
	     # REALLY! SEND THE EMAIL!
		 debug "Sending mail!"
		 OSfound="FALSE"
		 if [[ $OS == "HP-UX" ]]; then
			echo -e "$message" | /usr/bin/mailx -s "[$SEVERITY_TEXT] $subject" -r $sender $recipient
			OSfound="TRUE"
		 fi
		 if [[ $OS == "SunOS" ]]; then
			echo -e "$message" | /usr/bin/mailx -s "[$SEVERITY_TEXT] $subject" -r $sender $recipient
			OSfound="TRUE"
		 fi
                 if [[ $OS == "Linux" ]]; then
                        echo -e "$message" | /usr/bin/mailx -s "[$SEVERITY_TEXT] $subject" -r $sender $recipient
                        OSfound="TRUE"
                 fi
		 if [[ $OSfound == "FALSE" ]]; then
			echo -e "$message" | /bin/mailx -s "[$SEVERITY_TEXT] $subject" $recipient -- -r $sender
		 fi		 
	  fi
	else
	 debug "Not sending: severity is $MAX_SEVERITY, while severity to send mail is $MIN_SEVERITY_TO_MAIL"	 
	fi
  fi
fi

log "Script $SCRIPT_VERSION (pid $CURRENT_PID) ended normally. Severity was found to be $MAX_SEVERITY."
json_add_loopback "{ \"id\":\"loopback\", \"errorlevel\":0, \"details\":\"Ran OK. severity is ${MAX_SEVERITY}.\", \"timestamp\":`date +%s` }"

#End ==========================================================================
