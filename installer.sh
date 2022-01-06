#!/bin/bash

#
# read setup wiki first; installer.sh is ONLY for enterprise setups!
# for basic installs: https://github.com/angela-d/wifi-network-testing/wiki/Home-Install
#

# read-only repo, like so: git@bitbucket.org:example/
GIT_REPO_RO=""
# read-only branch you want to use, like: master
GIT_BRANCH=""
# now add a read-only key to the aforementioned repo
# then, modify the addKey function and add the readonly key
#
# your organization's display name
ORGNAME=""
# an intranet site, which is used to gauge whether or not you're at your org
INTERNAL_CHECK=""
# external ip of your org
NAT_IP=""
# internal nameservers of your org
NS1=""
NS2=""
# external host you want to use as a gauge for internet connectivity
CHECK1="9.9.9.9"
CHECK2="example.com"
# ifconfig location; in most cases this won't change
IFCFG="/sbin/ifconfig"
# dns suffix of your org
ORG_DNS="example.com"
# internal list of access point MACs
AP_LIST="http://arrays.example.com/arrays.txt"
# org's AP manufacturer; do not use spaces!
AP_MANUFACTURER="Ubiquiti"
## end config (for this section)

clear

function errorexit() {
  echo "Error. Exiting."
  exit
}

function addkey() {
  # RO ssh key for bit bucket
  echo "-----BEGIN RSA PRIVATE KEY-----" > ~/.ssh/updaterROkey
  echo "## put your read-only key on subsequent lines here ##" >> ~/.ssh/updaterROkey
  # line this, for each line:
  echo "IP3K8q98Nwky4zHukGA2t2oYfWzQl7QqQvHQqQTGS/WyiQ/aF25m" >> ~/.ssh/updaterROkey
  echo "-----END RSA PRIVATE KEY-----" >> ~/.ssh/updaterROkey
}

# menu function
function testoption() {
    echo -e "\033[0;33m1\033[0m -- Install/Update"
    echo -e "\033[0;33m2\033[0m -- Uninstall (Mac only)"
    read -r TESTOPT
if [ ! "$TESTOPT" -le 3 ];
  then
    echo "Your selection has to be 1 or 2.  Try again"
  fi
}
# ask installation location
function install_location() {
  echo "Install location? (default: ~/Desktop) - omit the trailing backslash:"
  echo "Example: $HOME/networktesting"
  read -r InstallLocation

  # set default
  if [ "$InstallLocation" == "" ]
  	then
  		InstallLocation=~/Desktop
  fi
  echo "Install Location: " $InstallLocation
  InstallLocation="$InstallLocation/networktesting"
  }

# run menu
testoption
echo
echo "option chosen: $TESTOPT"


#### option 1 install #####
if [ "$TESTOPT" == "1" ];
	then
		echo "option running: 1"
		install_location
			if [ ! -d "$InstallLocation" ];
				then
					echo "Installing nettest application..."
    			mkdir -p ~/.ssh
    			chmod 700 ~/.ssh
					addkey
					chmod 600 ~/.ssh/updaterROkey
          mkdir -p "$InstallLocation"
					cd "$InstallLocation" || errorexit
					ssh-agent bash -c "ssh-add ~/.ssh/updaterROkey & git clone $GIT_REPO_RO -b $GIT_BRANCH ."
					echo "installation complete"
					echo "running program: $InstallLocation/nettest.sh"
					sleep 3
					exec $InstallLocation/nettest.sh "$InstallLocation"
				else
					echo "already installed, checking for updates..."
					cd $InstallLocation || errorexit
					ssh-agent bash -c 'ssh-add ~/.ssh/updaterROkey & git pull'
					echo "running program: $InstallLocation/nettest.sh"
					sleep 3
					exec "$InstallLocation/nettest.sh"
			fi
	fi
####

#### option 2 uninstall #####
if [ "$TESTOPT" == "2" ];
	echo "option running: 2"
	install_location

	then
		if [ ! -d $InstallLocation/networktesting/ ];
			then
				echo "no installation of nettest found"
		else
			echo "found installation of nettest, uninstalling..."
			rm -Rf ~/.ssh/updaterROkey
			rm -Rf $InstallLocation/networktesting/
			rm -Rf ~/.nettest
			brew remove ipcalc
			brew remove nmap
			brew remove speedtest --force
			rm -rf /Library/Developer/CommandLineTools
			ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/uninstall)"
		fi
fi
####

# check for config file
if [ ! -f ~/.nettest/config.conf ];
then
  # add default configs if its not found
  echo "ORGNAME=$ORGNAME"  >> ~/.nettest/config.conf
  echo "INTERNAL_CHECK=$INTERNAL_CHECK"  >> ~/.nettest/config.conf
  echo "NAT_IP=$NAT_IP"  >> ~/.nettest/config.conf
  echo "NS1=$NS1"  >> ~/.nettest/config.conf
  echo "NS2=$NS2"  >> ~/.nettest/config.conf
  echo "CHECK1=$CHECK1"  >> ~/.nettest/config.conf
  echo "CHECK2=$CHECK2"  >> ~/.nettest/config.conf
  echo "IFCFG=$IFCFG"  >> ~/.nettest/config.conf
  echo "ORG_DNS=$ORG_DNS"  >> ~/.nettest/config.conf
  echo "AP_LIST=$AP_LIST"  >> ~/.nettest/config.conf
  echo "MAC_LIST=$MAC_LIST"  >> ~/.nettest/config.conf
  echo "AP_MANUFACTURER=$AP_MANUFACTURER"  >> ~/.nettest/config.conf
  echo "DEFAULT_TEST="  >> ~/.nettest/config.conf
  echo "SETUP_DONE=0"  >> ~/.nettest/config.conf

  # import the vars, now that its been created
  source ~/.nettest/config.conf
else
  # pull the config into the application
  source ~/.nettest/config.conf
fi
