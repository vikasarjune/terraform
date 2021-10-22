#!/bin/ksh
###################################################################################################
#
# Description: Script to setup Network Bonding for Redhat
#
# Author:  created on July 2015
#
###################################################################################################
# Updates:
#
# November 28, 2015 - Added RHEL6 option and Network Manager compatibility
# July  6, 2017 - Added RHEL7 option and Network Manager compatibility
#
####################################################################################################
#
#
clear
echo "You are configuring Network Bonding on `hostname`. You must be in the Console before doint this."
echo "Else you might be disconnected when the network is restarted."
echo
BackupDir=/var/bonding_backup
ChkConfig=/sbin/chkconfig
NetworkScripts=/etc/sysconfig/network-scripts
Modprobe=/sbin/modprobe
Service=/sbin/service
DateTime=$(date +%d%b%Y)

PrintDone(){
  sleep 1
  echo -n ".."
  sleep 1
  echo "done."
}


echo -n "Enter the NAME of the NetworkBond: "
read BondName
while [ -z "$BondName" ]; do
  echo -n "Enter the NAME of the NetworkBond: "
  read BondName
done

echo "Choose the type of Bonding"
echo "1.) Active/Passive - Supported bond for for HB."
echo "2.) LACP - Preferred for data but not mandatory."
echo
echo -n "Enter number: "
read BondType
while [ -z "$BondType" ]; do
  echo "Choose the type of Bonding"
  echo "1.) Active/passive supported bond for for HB"
  echo "2.) LACP - Preferred for data but not mandatory."
  echo
  echo -n "Enter number: "
  read BondType
done

if [[ "$BondType" != [1-2] ]]; then
  echo "Bond Type can only have 1 or 2 as value. Exiting!"
  exit 1
fi


if [ -e $NetworkScripts/ifcfg-$BondName ]; then
    echo
    echo "$BondName already exist..Exiting!"
    echo
    exit
fi

BondIface=$NetworkScripts/ifcfg-$BondName

echo -n "Enter the IP ADDRESS of the NetworkBond: "
read BondIp
while [ -z $BondIp ]; do
  echo -n "Enter the IP ADDRESS of the NetworkBond: "
  read BondIp
done

echo -n "Enter the NETMASK of NetworkBond: "
read BondMask
while [ -z $BondMask ]; do
  echo -n "Enter the NETMASK of NetworkBond: "
  read BondMask
done

echo
echo -n "Enter the number of NICs in $BondName: "
read NicMaxCount
while [ -z $NicMaxCount ]; do
  echo -n "Enter the number of NICs in $BondName: "
  read NicMaxCount
done

if [[ $NicMaxCount != [0-9] ]]; then
   echo
   echo "Number of NICs should be in digit number [2-9]: "
   echo "Exiting!!"
   echo
   exit
fi


set -A Nics
set -A NicScrptIfaces
set -A NicTempFiles
for ((ncount=1;ncount<$NicMaxCount+1;ncount++)); do
  echo
  echo -n "Enter the ($ncount)nth NIC: "
  read Nics[$ncount]

  while [ -z ${Nics[$ncount]} ]; do
    echo -n "Enter the ($ncount)n NIC: "
    read Nics[$ncount]
  done

  while [ ! -e $NetworkScripts/ifcfg-${Nics[$ncount]} ]; do
    echo
    echo "NIC:[${Nics[$ncount]}] Interface does not exist..!"
    echo
    echo -n "Enter the ($ncount)n NIC: "
    read Nics[$ncount]
  done

  echo -n "Creating backup of ${Nics[$ncount]}..Backup Directory[$BackupDir]."
  if [ ! -d $BackupDir ];  then
     mkdir $BackupDir
  fi
  sleep 1
  NicScrptIfaces[$ncount]=/etc/sysconfig/network-scripts/ifcfg-${Nics[$ncount]}
  NicScrptIfacesHwAddr[$ncount]=$(grep HWADDR $NicScrptIfaces[$ncount] | awk -F"=" '{print $2}')
  NicTempFiles[$ncount]=/tmp/bonding.ifcfg-${Nics[$ncount]}
  cp -ip ${NicScrptIfaces[$ncount]} $BackupDir
  PrintDone

  echo -n "Updating ${Nics[$ncount]}.."
  CHwAddr=$(grep HWADDR ${NicScrptIfaces[$ncount]} | cut -d\= -f2)

cat > ${NicTempFiles[$ncount]} << __NIC__
###############################
##  Bond Setup on $DateTime
DEVICE=${Nics[$ncount]}
BOOTPROTO=none
HWADDR=$CHwAddr
USERCTL=no
ONBOOT=yes
MASTER=$BondName
SLAVE=yes
TYPE=ethernet
ETHTOOL_OPTS="autoneg on"
__NIC__

  cp ${NicTempFiles[$ncount]} ${NicScrptIfaces[$ncount]}
  PrintDone

done

echo
echo -n "--> Setting up $BondName Enterface.."
cat > $BondIface << __BOND__
###############################
##  Bond Setup on $DateTime
DEVICE=$BondName
IPADDR=$BondIp
NETMASK=$BondMask
USERCTL=no
BOOTPROTO=none
ONBOOT=yes
__BOND__
PrintDone

echo -n "--> Updating modules.."
RhelVersion=$(cat /etc/redhat-release | awk -F'.' '{print $1}' | awk '{print $7}')

case $RhelVersion in
    "5")
        ModulesConfig=/etc/modprobe.conf
        cp -ip $ModulesConfig $BackupDir/modprobe.conf.$DateTime

        if `grep -qw $BondName $ModulesConfig` ; then
            echo -n "$BondName is already setup..please double check.."
        else
            echo "###############################"                                              >> $ModulesConfig
            echo "##  Bond Setup on $DateTime"                                            >> $ModulesConfig
            echo "alias $BondName bonding"                                                      >> $ModulesConfig

            if [[ "$BondType" = 1 ]]; then
               echo "BONDING_OPTS=\"mode=1 miimon=100\""                                        >> $BondIface
            else
               echo "BONDING_OPTS=\"mode=4 miimon=100 xmit_hash_policy=layer2+3\""              >> $BondIface
            fi

        fi

    ;;
    "6")
        ModulesConfig=/etc/modprobe.d/bonding.conf
        [ ! -f $ModulesConfig ] && touch $ModulesConfig

        if `grep -qw $BondName $ModulesConfig` ; then
            echo -n "$BondName is already setup..please double check.."
        else
            echo "###############################"                                              >> $ModulesConfig
            echo "##  Bond Setup on $DateTime"                                            >> $ModulesConfig
            echo "alias $BondName bonding"                                                      >> $ModulesConfig
            echo "options hangcheck-timer hangcheck_tick=1 hangcheck_margin=10 hangcheck_reboot=1" >> $ModulesConfig

            if [[ "$BondType" = 1 ]]; then
               echo "BONDING_OPTS=\"mode=1 miimon=100\""                                       >> $BondIface
            else
               echo "BONDING_OPTS=\"mode=4 miimon=100 lacp_rate=1\""             >> $BondIface
            fi

        fi
     ;;
    "7")
        ModulesConfig=/etc/modprobe.d/bonding.conf
        [ ! -f $ModulesConfig ] && touch $ModulesConfig

        if `grep -qw $BondName $ModulesConfig` ; then
            echo -n "$BondName is already setup..please double check.."
        else
            echo "###############################"                                              >> $ModulesConfig
            echo "##  Bond Setup on $DateTime"                                            >> $ModulesConfig
            echo "alias $BondName bonding"                                                      >> $ModulesConfig
            echo "options hangcheck-timer hangcheck_tick=1 hangcheck_margin=10 hangcheck_reboot=1" >> $ModulesConfig

            if [[ "$BondType" = 1 ]]; then
               echo "BONDING_OPTS=\"mode=1 miimon=100\""                                       >> $BondIface
            else
               echo "BONDING_OPTS=\"mode=4 miimon=100 lacp_rate=1\""             >> $BondIface
            fi

        fi
     ;;

     *)

        echo
        echo "OS not supported..check the maintainer.."
        echo

esac




PrintDone

$Modprobe bonding
$ChkConfig NetworkManager off

echo
echo -n "--> Restarting Network service.."
$Service network restart
PrintDone

echo
echo "Network Bonding $BondName is now configured.."
echo "Verify IFCONFIG output.."
echo

