#! /bin/bash

##########################################################
# Adapt the following line to your setup
#   export TARGET=virtio:/var/run/twopence/test.sock
#   export TARGET=ssh:192.168.123.45
#   export TARGET=serial:/dev/ttyS0
##########################################################

function usage() {
    echo
    echo "Usage: $0 -H MACHINE -p PRODUCT_UPGRADE -r PRODUCT_UPGRADE_REPO [-g GUEST_LIST] [-t testTime]"
    echo "       -H, the test machine ip address"
    echo "       -p, the product to upgrade to for guests"
    echo "       -r, the product upgrade repo for guest upgrade"
    echo "       -g, the guest list to be tested, regular expression supported, separeted with comma, for example \"sles-11-sp[34]-64,sles-12-sp1\""
    echo "       -t, the test time"
    exit 1
}


	
if [ $# -eq 0 ];then
        usage
else 
        while getopts "H:p:r:g:t:" OPTION
        do
            case $OPTION in
                H)MACHINE="$OPTARG";;
                p)PRODUCT_UPGRADE="$OPTARG";;
                r)PRODUCT_UPGRADE_REPO="$OPTARG";;
                g)GUEST_LIST="$OPTARG";;
                t)testTime="$OPTARG";;
                \?)usage;;
                \*)usage;;
            esac
        done
fi

export TARGET=ssh:${MACHINE}



#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  exitProject
#   DESCRIPTION:  
#    PARAMETERS:  
#       RETURNS:  
#-------------------------------------------------------------------------------
exitProject ()
{
	return_code=$1
	printer ERROR "Abnornally exit"
	exit ${return_code}	
}	# ----------  end of function exitProject  ----------



#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  printer
#   DESCRIPTION:  
#    PARAMETERS:  
#       RETURNS:  
#-------------------------------------------------------------------------------
printer ()
{
	flag=$1
	output=$2	
	
	echo "[${flag}] : ${output}"
}	# ----------  end of function printer  ----------


#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  detectRemoteSSH
#   DESCRIPTION:  
#    PARAMETERS:  
#       RETURNS:  
#-------------------------------------------------------------------------------
detectRemoteSSH ()
{
	timeout=$1
	start_time=`date +%s`
	while [ `expr $start_time + ${timeout}` -ge `date +%s` ]
	do
		if `nmap ${MACHINE} --host-timeout 2 -PN -p ssh | grep open > /dev/null`;then
			printer INFO "Remote server ${MACHINE} can be connected via ssh"
			return 1
		fi
	done
	printer ERROR "Failed to connect to remote server ${MACHINE} via ssh"
	exitProject
}	# ----------  end of function detectRemoteSSH  ----------


#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  getCMDStatus
#   DESCRIPTION:  
#    PARAMETERS:  
#       RETURNS:  
#-------------------------------------------------------------------------------
getCMDStatus ()
{
	output=$1
	
	test_server_output=`echo ${output} | egrep -o "Return code from the test server: [0-9]"`
	if [ -n "${test_server_output}" ];then
		test_server_status=`echo ${test_server_output} | cut -d":" -f2 | sed 's/ //g'`
	else
		test_server_output=`echo ${output} | egrep -o "Remote command took too long to execute"`
		if [ -n "${test_server_output}" ];then
			test_server_status=10
		fi
	fi

	if [ ${test_server_status} -ne 0 ];then
		printer ERROR "$output"
		exitProject 1
	else
		tested_cmd_output=`echo ${output} | grep -o "Return code of tested command: [0-9]"`
		if [ -n "${tested_cmd_output}" ];then
			return `echo ${tested_cmd_output} | cut -d":" -f2 | sed 's/ //g'`
		else
			return 1
		fi
	fi
}	# ----------  end of function getCMDStatus  ----------



#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  updateRPM()
#   DESCRIPTION:  
#    PARAMETERS:  
#       RETURNS:  
#-------------------------------------------------------------------------------
function updateRPM()
{
	printer INFO "Start update rpms"
	output=`twopence_command -t 4800 -q $TARGET 'source /usr/share/qa/virtautolib/lib/virtlib;update_virt_rpms off on off'`
	getCMDStatus "${output}"
	if [ $? -eq 0 ];then
		printer INFO "Update rpm successfully"
	else
		printer ERROR  $output
		exitProject 1
	fi
}	# ----------  end of function updateRPM()  ----------


#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  rebootHost
#   DESCRIPTION:  
#    PARAMETERS:  
#       RETURNS:  
#-------------------------------------------------------------------------------
rebootHost ()
{
	timeout=$1
	printer INFO "Start reboot host"
	output=`twopence_command  -q $TARGET 'reboot'`
#	getCMDStatus "${output}"
#        if [ $? -eq 0 ];then
#                printer INFO "Reboot successfully"
#        else
#                printer ERROR  $output
#                exitProject 1
#        fi
	detectRemoteSSH $timeout
	
}	# ----------  end of function rebootHost  ----------


#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  prepareENV
#   DESCRIPTION:  
#    PARAMETERS:  
#       RETURNS:  
#-------------------------------------------------------------------------------
prepareENV ()
{
	printer INFO "Start env setting"
        output=`twopence_command -t 120 $TARGET 'rclibvirtd restart'`
        getCMDStatus "${output}"
        if [ $? -eq 0 ];then 
                printer INFO "Finished env setting"
        else    
                printer ERROR  $output
                exitProject 1
        fi
}	# ----------  end of function prepareENV  ----------



installGuest ()
{
	param1=$1
	printer INFO "Start install guest with $param1"
        output=`twopence_command -o /tmp/${param1}.log -t 3600 $TARGET "/usr/share/qa/qa_test_virtualization/virt_installos ${param1}"`
        getCMDStatus "$output"
	if `grep "installation pass" /tmp/${param1}.log >/dev/null`;then
		printer INFO "Test success"
	else
		printer INFO "Test failure"
	fi

        printer INFO "Finished guest installation test"
}	# ----------  end of function installGuest  ----------


#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

detectRemoteSSH 300
updateRPM
rebootHost 300
prepareENV
installGuest sles-12-sp2-64-fv-def-net
