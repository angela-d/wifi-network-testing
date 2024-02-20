#!/bin/bash
# shellcheck source=/dev/null

# assume where we first run from, will be where it lives
# but check for relative path, first
ConfigTemplateLocation="$(dirname "$0")"
[ "$ConfigTemplateLocation" == "." ] && ConfigTemplateLocation="$(pwd)"

# check for config file
if [ ! -f ~/.nettest/config.conf ];
then
  # add default configs if its not found
  mkdir -p ~/.nettest
  cp "$ConfigTemplateLocation/config-template.conf" ~/.nettest/config.conf && echo "INSTALLPATH=$ConfigTemplateLocation" >> ~/.nettest/config.conf

  # now call it
  source ~/.nettest/config.conf
else
  # already exists; pull the config into the application
  source ~/.nettest/config.conf
fi

# set an os variable for use throughout the script
if [[ "$OSTYPE" == "darwin"* ]];
then
  OS="mac"
elif [[ "$OSTYPE" == "linux"* ]];
then
  OS="linux"
elif [[ "$OSTYPE" == "msys"* ]];
then
  OS="windows"

  # add an addl env, so we can import some applications without needing them 'installed'
  # this is what allows us to run dig, host & bc w/out specifying paths to the exe's
  ADDL_EXE="$INSTALLPATH"/windows/bind9:"$INSTALLPATH"/windows/bc:"$INSTALLPATH"/windows/speedtest:"$INSTALLPATH"/windows/ipcalc
  export PATH=$ADDL_EXE:$PATH
fi

# prettify the output
function boldtext() {
  echo "------------------------------------------------------------------------------"
  echo -e "\033[1;37m$1\033[0m"
  echo "------------------------------------------------------------------------------"
}

function whitebold() {
  echo -e "\033[1;37m$1\033[0m"
}

function green() {
  echo -e "\033[32m$1\033[0m"
}

function purple() {
  echo -e "\033[0;35m$1\033[0m"
}

function red() {
  echo -e "\033[0;31m$1\033[0m"
}

function yellow() {
  echo -e "\033[0;33m$1\033[0m"
}

function twocol() {
  printf "%-20s  %-15s\n" "$1" "$2"
}

function rescol() {
  printf "%-5s  %-15s\n" "$1" "$2"
}

function super() {
  if [ "$OS" == "linux" ];
  then
    echo "$1" | lolcat -f
  else
    purple "$1"
  fi
}

function italic() {
  echo -e "\033[3m$1\033[0m"
}

# progress bar
function spinner() {
  #pass PID to function
  PID=$!

  # While process is running...
  while kill -0 $PID 2> /dev/null;
  do
    printf  "▓"
    sleep 1
  done
}

function manufacturer_check() {
  ## see if we're using multiple ap manufacturers
  IFS=',' read -ra MANUFACTURER <<< "$AP_MANUFACTURER"

  for manu in "${MANUFACTURER[@]}"; do
    if [[ $VENDOR =~ $manu ]];
    then
      MATCH="true"
      twocol " Vendor:" "$VENDOR"
    fi
  done

  if [[ ! $MATCH == "true" ]];
  then
    twocol " Vendor:" "$AP"
    red "\n>> AP Manufacturer $AP_MANUFACTURER doesn't match $VENDOR..\nconnected to a potentially rogue AP!"
    italic "\tIf this is expected and you're outside of $ORGNAME,"
    italic "\tyou can add your router vendor in the ~/.nettest/config.conf file:"
    italic "\tadjust the AP_MANUFACTURER variable."
  fi
}

# check for internet accessibility
function connectivitycheck(){
  if [ ! "$SKIP_PRELIM" == "1" ] || [ "$TESTOPT" -eq 1 ];
  then
    boldtext "Preliminary test to $1 for web connectivity..."
    if [ "$OS" == "linux" ] || [ "$OS" == "mac" ] && [ "$($PINGS -c 1 "$1")" ];
    then
      # we are online
      green "$1 can be reached."
    elif [ "$OS" == "linux" ] || [ "$OS" == "mac" ];
    then
      logger -s "$1 appears to be offline, you have no web access or the nettest config file wasn't properly generated.  Exiting..."
      exit 1
    # windows returns garbage even if the ping fails, so a more explicit condition is necessary
    elif [ "$OS" == "windows" ] && [ "$($PINGS -n 1 "$1" | grep "Request timed out.")" == "" ];
    then
      green "$1 can be reached."
    else
      red "$1 cannot be reached, check your network connectivity.  Exiting..."
      exit 1
    fi
  fi
}

# see if user is on the internal network
function internal_network_check(){
  # mac check doesn't seem to work.. fix later
  if [ "$OS" == "mac" ];
  then
    VPN="$(scutil --nc list | grep Connected)"
  elif [ "$OS" == "linux" ];
  then
    VPN="$(netstat -i | awk '$1 == "ppp0" || $1 == "tun0" { print }')"
  elif [ "$OS" == "windows" ];
  then
    VPN="$(netstat -n | awk '{print $2}' | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | grep "10.*.*.*")"
  fi

  # check external ip from internal_network_check() argument + ping test if conditions are met
  if [ "$1" == "$NAT_IP" ] && [ ! "$VPN" ] && [[ ! "$VPN" && "$($PINGS -c 1 "$INTERNAL_CHECK")" ]] ;
  then
    INTERNAL_CONN="yes"
    INTERNALscreen=$(green "$INTERNAL_CONN")
  else
    INTERNAL_CONN="no"
    INTERNALscreen=$(red "$INTERNAL_CONN")

    if [ "$OS" != 'windows' ];
    then
      logger "$INTERNAL_CHECK cannot be reached; we do not appear to be on the $ORGNAME network."
    fi
  fi

  # cache the ap lookups, otherwise macs will yield macos (23) Failed writing body in some instances
  if [ $INTERNAL_CONN == 'yes' ] && [ ! "$AP_LIST" == "" ] && [ ! -f ~/.nettest/ap.cache ];
  then
    # no cache exists; but a value is set, pull a local copy
    italic "Generating a AP cache, please wait..."
    curl -sS -C - "$AP_LIST" > ~/.nettest/ap.cache
    sleep 2
  fi
}

# code that's called multiple times should be in a function, so it doesn't get needlessly repeated and bloat up the place

# install with brew on mac
function macinstall () {
  if [ "$1" != "brew" ];
  then
    brew install "$1"
  elif [ "$1" == "speedtest" ];
  then
    brew tap speedtest-cli
    brew update
    brew install "$1" --force
  fi
}

# install with apt on linux
function linuxinstall () {
  # make sure apt exists
  if [ -f /usr/bin/apt ];
  then
    # make sure user has sudo access to apt at the minimum
    # shellcheck disable=2143
    if [ "$(sudo -l | grep /usr/bin/apt)" ] || [ "$(sudo -l)" != "" ];
    then
      if [ ! "$1" == "network-manager" ];
      then
        sudo apt install "$1"
      fi
    else
      red "You do not appear to have sudo access to /usr/bin/apt"
      echo -e "As root, run: \033[0;35mvisudo\033[0m & append the following:\n"
      echo -e "$USER  ALL=(ALL) NOPASSWD: /usr/bin/apt\n\n"
      rm -rf ~/.nettest
      exit 1
    fi
  else
    red "You aren't using a Debian-based system.. can't install dependencies without apt."
    rm -rf ~/.nettest
    exit 1
  fi
}

# dependency check needed applications
function checkfor() {

  if [ "$OS" == "$2" ];
  then
    purple "Verifying existence of $1 for $2..."
    # on linux, for /sbin applications, this will produce a false-positive
    CHECKIT=$(which "$1")
    APP="$1"

    # if network-manager dir exists, don't prompt
    if [ "$APP" == "network-manager" ] && [ -e /etc/NetworkManager ];
    then
      NM_PROMPT="n"
      purple "Verified existence of $APP (linux-only)..."
    fi

    # had to add addl checks for network-manager because it doesn't have a bin path
    if [[ "$CHECKIT" == "" && ! "$APP" == "network-manager" ]] || [[ "$APP" == "network-manager" && ! "$NM_PROMPT" == "n" ]];
    then
      echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
      echo " Do you want to install $1 for $2?"
      echo -e "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\ny or n: "
      read -r YN
    fi

    if [ "$YN" == "y" ] || [ "$YN" == "Y" ];
    then
      green "Installing $1..."
      if [ "$1" == "brew" ];
      then
        /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
        brew tap speedtest-cli
      fi

      # rest of the dependencies install
      if [ "$OS" == "mac" ];
      then
        macinstall "$APP"
      elif [ "$OS" == "linux" ];
      then
        linuxinstall "$APP"
      fi

      # reset the YN var else no further install prompts will occur
      YN=""
    fi

  else
    echo "$1 not for this OS ($2)... skipping."
  fi
}

# main menu. choose your options
function testoption() {
  boldtext "$(purple "What tests do you want to run?")"
  echo -e "\033[0;33m1\033[0m -- Basic: Wifi strength, access point information"
  echo -e "\033[0;33m2\033[0m -- Extended: Basic + packet loss, IP & DNS information"
  echo -e "\033[0;33m3\033[0m -- Basic + speed test only"
  echo -e "\033[0;33m4\033[0m -- 2g channel usage"
  echo -e "\033[0;33m5\033[0m -- 5g channel usage"
  echo -e "\033[0;33m6\033[0m -- Access point + channel usage"
  boldtext "All or Nothing"
  echo -e "\033[0;33m7\033[0m -- All Tests"
  echo -e "\033[0;33m8\033[0m -- Quit"
  echo
  echo -e "\033[0;33muninstall\033[0m -- uninstall"
  yellow "Type the # that corresponds with your choice: "

  # check if a default test is set
  if [ "$DEFAULT_TEST_RAN" != "1" ] && [ "$DEFAULT_TEST" != "" ];
  then
    TESTOPT=$DEFAULT_TEST
  else
    read -r TESTOPT
  fi

  if [ "$TESTOPT" == "" ];
  then
    # no number entered, so likely a basic test is wanted
    TESTOPT="1"
  elif [ "$TESTOPT" != "uninstall" ] && [ ! "$TESTOPT" -le 8 ];
  then
    red "Your selection has to be 1, 2, 3, 4, 5, 6, 7 or 8.  Try again (otherwise, only basic tests will run!):"
    read -r TESTOPT
  fi
  italic "Option $TESTOPT selected"
}

# MAC address lookup vendor
function macsearch() {
  # look up macs without api keys from IEEE
  # cache this mac address, since it won't change (if the script runs multiple times, no need to make new calls)
  if [ ! -f ~/.nettest/"$1" ];
  then
    LOOKUP=$(echo "$1" | tr -d ':' | head -c 6)

    # cache the mac lookups, this will almost never change so don't litter network requests
    if [ -f ~/.nettest/mac.cache ];
    then
      cat < ~/.nettest/mac.cache | grep -i "$LOOKUP" | cut -d')' -f2 | tr -d '\t' > ~/.nettest/"$LOOKUP"
    else
      if [ $INTERNAL_CONN == 'yes' ];
      then
        # no cache exists, pull a copy
        italic "Generating a MAC cache, please wait..."
        curl -sS -C - "$MAC_LIST" > ~/.nettest/mac.cache && cat < ~/.nettest/mac.cache | grep -i "$LOOKUP" | cut -d')' -f2 | tr -d '\t' > ~/.nettest/"$LOOKUP"
        sleep 2
      else
        # not on the internal network, obtain from the web
        italic "Generating a MAC cache, please wait..."
        curl -sS -C - "http://standards-oui.ieee.org/oui/oui.txt" > ~/.nettest/mac.cache && cat < ~/.nettest/mac.cache | grep -i "$LOOKUP" | cut -d')' -f2 | tr -d '\t' > ~/.nettest/"$LOOKUP"
        sleep 2
      fi

    fi
  fi

  # ap vendor info
  whitebold "Access Point Details"
  twocol " SSID:" "$SSID"
  twocol " Channel:" "$CHANNEL"
  twocol " Radio: " "$RADIO"
  twocol " MAC:" "$1"
  VENDOR="$(cat ~/.nettest/"$LOOKUP")"
  manufacturer_check
}


function apsearch() {
  # moved above basic stats cause this is needed to determine the external ip, not sure how else to get it atm
  # get external ip or internet ip
  iip=$(dig +short myip.opendns.com @resolver1.opendns.com)

  # test for internal network connectivity
  internal_network_check "$iip"

  if [ "$INTERNAL_CONN" == "yes" ];
  then
    # lookup what array you're connected to, based on bssid
    AP=$(echo "$1" | tr -d ':')
    AP=$( (grep -i "$AP" | head -n1 | awk '{ print $1 }') < ~/.nettest/ap.cache)

    if [ "$AP" == "" ];
    then
      AP="(External)"
    fi

    # this turd is duplicating, why?
    twocol " Connected to:" "$AP"
  elif [ "$AP_MANUFACTURER" == "$VENDOR" ];
  then
    red "Skipping AP lookup, not on the $ORGNAME network..."
  fi

  # var inherited from internal_network_check()
  if [ "$VPN" ];
  then
    yellow ">> VPN/Tunnel connection detected"
  fi
}

function channeltest() {
  for channel in $1;
  do
    if [ "$channel" -ge 1 ] && [ "$channel" -le 13 ] >>/dev/null 2>&1;
    then
      RADIO=2.4GHz
    else
      RADIO=5GHz
    fi
  done
}

# full path of the running script
filepath() {
  [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}



# check for a channel argument - placed high in the conditions, otherwise gets overruled by other options
# searches the active channel for other aps also on the same channel
# not apart of the menu, must launch as an argument: ntest c
if [ "$1" == "c" ] || [ "$1" == "search" ] && [ "$OS" == "linux" ];
then
  # these should be a condition w/ macs channel trigger, once missing features are implemented to the mac side
  INTERFACE="$(cat < /proc/net/wireless | awk '{print $1}' | tail -n1 | tr -d .:)"

  # check if a channel is being passed as a manual search
  if [ "$1" == "search" ] && [ -n "$2" ];
  then
    CHANNEL="$2"
  elif [ "$1" == "c" ];
  then
    CHANNEL="$(/sbin/iw dev "$INTERFACE" info | grep channel | awk '{ print $2 }')"
  fi

  boldtext "$(super "Access Points Using Channel $CHANNEL")"

  ## duplication of an existing loop, wasn't sure how else to achieve this ##
  # chmatch works, but there's an accuracy bug for things like 1 and 11.. need to fix
  while IFS=$'\n' read -r line; do
    CHAN+=("$line")
  done < <(nmcli -f ssid,bssid,chan,freq,bars,signal dev wifi list | awk -v chmatch="^$CHANNEL$" '$3 ~ chmatch')

  for ARRAYCHAN in "${CHAN[@]}"
  do
    # this loop seems super heavy, but i don't know a better way to do it atm
    IAP="$(echo "$ARRAYCHAN" | awk '{ print $3 }')"
    FREQ="$(echo "$ARRAYCHAN" | awk '{ print $4$5  " " $6 }')"
    UNCLEANSSID="$(echo "$ARRAYCHAN" | awk '{ print $1 }')"
    SIGNAL="$(echo "$ARRAYCHAN" | awk '{ print $7 }')"
    # ssid is sanitized since it returns values to the screen created by untrusted individuals, because, you never know :)
    SSID="${UNCLEANSSID//[^a-zA-Z0-9\_]/}"

    if [ "$INTERNAL_CONN" == "yes" ];
    then
      MAC="$(echo "$ARRAYCHAN" | awk '{ print $2 }')"
      apsearch "$MAC"; echo "SSID: $SSID"
    else
      purple "$SSID"
    fi

    echo -e "Channel: $IAP\tFrequency: $FREQ\tSignal: $SIGNAL%\n"
  done
  ## end duplication.  possibly functionize at some point to cleanup ##


  # allow for a manual search of channel usage, too
  boldtext "Enter a channel number, to search (or ^C to close):"
  read -r SEARCH_CHANNEL
  # the ntest path needs to be added to the config template (needs to be modified during install!)
  ntest search "$SEARCH_CHANNEL"

fi

# check for the dependency file made after initial creation
if [ ! "$SETUP_DONE" -eq 1 ];
then

  # check dependecies
  boldtext "Checking Dependecies.."

  # 1 = first argument, 2 = second argument (in the functions above)
  # check for brew
  checkfor "brew" "mac"

  # a tad heavier than other tools, but so far others aren't able to pull channels w/out being disconnected
  checkfor "network-manager" "linux"

  # check for ipcalc
  checkfor "ipcalc" "mac"
  checkfor "ipcalc" "linux"

  # check for nmap
  checkfor "nmap" "mac"
  checkfor "nmap" "linux"

  # rainbow text to make the cli cooler
  checkfor "lolcat" "linux"

  # check for speedtest
  checkfor "speedtest-cli" "mac"
  checkfor "speedtest-cli" "linux"

  # add a config var, so we don't waste time checking for dependencies next time we run this script on this machine
  boldtext "Setup complete.  Re-run the application to start."
  sed -i.bak "s/SETUP_DONE=0/SETUP_DONE=1/g" ~/.nettest/config.conf
  exit 0
fi

# macs are special with ping, so pull prefs ahead of time
if [ "$OS"  == 'linux' ] || [ "$OS"  == 'windows' ] && [ "$PINGPROTOCOL"  == '-6' ];
then
  PINGS='ping -6'
elif [ "$OS"  == 'linux' ] || [ "$OS"  == 'windows' ] && [ "$PINGPROTOCOL"  == '-4' ];
then
    PINGS='ping -4'
elif [ "$OS"  == 'mac' ] && [ "$PINGPROTOCOL"  == '-6' ];
then
  PINGS='ping6'
else
  PINGS='ping'
fi

# ask the user what they want to do
testoption

## basic tests
if [ "$TESTOPT" != "uninstall" ] && [ "$TESTOPT" -ne 8 ];
then
  # check an external ip to make sure there's at least internet access
  connectivitycheck "$CHECK1"

  # check an external friendly name domain to make sure there's dns access
  connectivitycheck "$CHECK2"
fi

iip=$(dig @resolver1.opendns.com ANY myip.opendns.com +short)

# test for internal network connectivity
internal_network_check "$iip"

# basic tests
if [ "$TESTOPT" != "uninstall" ] && [ "$TESTOPT" == "" ] || [ "$TESTOPT" == 1 ] || [ "$TESTOPT" == 2 ] || [ "$TESTOPT" == 7 ];
then
  ## check operating system
  boldtext "Beginning Network Test..."
  twocol "OS:" "$(uname)"
  twocol "User:" "$(whoami)"
  twocol "Hostname:" "$(hostname)"
  timestamp=$(date +%Y%m%d-%H%M%S)
  filename="$(hostname).$timestamp"
  twocol "Test ID:" "$filename"

  if [ "$OS" != 'windows' ];
  then
    # SC2207 - due to macos bash (v)3.2
    ips=()
    while IFS='' read -r ipline;
    do
      ips+=("$ipline");
    done < <($IFCFG | grep "inet " | grep -v 127.0.0.1 | awk '{ print $2 }')

    mask=()
    while IFS='' read -r maskline;
    do
      mask+=("$maskline");
    done < <($IFCFG | grep 'netmask ' | grep -v 127.0.0.1 | awk '{ print $4 }')

  else
    # grep an expression to only show ipv4 ip addresses
    # shellcheck disable=SC2178
    # sc complains about the ips & mask array; windows vars are handled differently
    ips=$(ipconfig //all | grep -o "IPv4 Address.*" | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | tr '\r\n' ' ')
    # shellcheck disable=SC2178
    mask=$(ipconfig //all | grep -o "Subnet Mask.*" | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | tr '\r\n' ' ')
  fi

  if [ "$TESTOPT" != "uninstall" ] && [ "$TESTOPT" == 2 ] || [ "$TESTOPT" == 7 ];
  then
    # Get the DNS server(s)
    if [ "$OS" != 'windows' ];
    then
      ns=$(cat < /etc/resolv.conf | grep -v '^#' | grep nameserver | awk '{print $2}' | tr '\r\n' ' ')
    else
      # the // is needed, as git bash for windows replaces single slashes
      ns=$(ipconfig //all | sed -n "/DNS Servers/,/NetBIOS over Tcpip./p" | sort -u | grep -v "NetBIOS" | xargs | tr '\r\n' ' ' | sed 's/DNS Servers . . . . . . . . . . . : //g')
    fi

    # Get the gateway but ignore hosts for linux.. regex mac vs linux too messy to be cross-compatible reliably
    if [ "$OS" != 'windows' ];
    then
      gateway=$(netstat -nr -f inet | grep UG | awk '$4 != "UGH" { print }' | tr -s " " | cut -d" " -f2 | tr '\r\n' ' ')

    else
      gateway=$(ipconfig //all | grep -o " Default Gateway.*" | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}")
    fi
  fi

  # calculate subnetmask at CIDR. works for multiple interfaces using arrays
    IParray=()
    CIDRarray=()
    MASKarray=()
    for ((i=0;i<${#ips[@]};++i));
    do
      # COUNTER=$[COUNTER + 1]
      IParray+=("${ips[i]}")
      # ipcalc is loaded directly as a perl script, since there isn't a windows version
      if [ "$OS" != "windows" ];
      then
        MASKs="$(ipcalc  "${ips[i]}" "${mask[i]}" | awk '/Netmask/ {print $2}')"
        MASKarray+=("$MASKs")
        CIDRs="$(ipcalc "${ips[i]}" "$MASKs" | awk '/Network/ {print $2}')"
      else
        # the calculation isn't accurate on windows once it hits the arrays.. need to fix later
        # is accurate when ran directly against ipcalc.pl
        MASKs="$(ipcalc.pl  "${ips[i]}" "${mask[i]}" | awk '/Netmask/ {print $2}')"
        MASKarray+=("$MASKs")
        CIDRs="$(ipcalc.pl "${ips[i]}" "$MASKs" | awk '/Network/ {print $2}')"
      fi
      CIDRarray+=("$CIDRs")
    done

    # sc - false pos due to win/mac sharing var identifiers
    # shellcheck disable=SC2178
    ips=$(printf %s" " "${IParray[@]}")
    # shellcheck disable=SC2178
    mask=$(printf %s" " "${MASKarray[@]}")
    CIDR=$(printf %s" " "${CIDRarray[@]}")

  if [ "$TESTOPT" == 2 ] || [ "$TESTOPT" == 7 ];
  then
    # get ISP name
    if [ ! -f ~/.nettest/"$iip" ];
    then
      isp=$(curl -s ipinfo.io)
    else
      isp=$(cat ~/.nettest/"$iip")
    fi

    # Send to screen
    # sc false pos for unindexed arrays; which is latching onto windows vars that don't utilize them
    boldtext "Network Info"
    twocol "External IP:" "$iip"
    # shellcheck disable=SC2128
    twocol "Internal IP:" "$ips"
    twocol "Gateway:" "$gateway"
    # shellcheck disable=SC2128
    twocol "Netmask:" "$mask"
    twocol "CIDR:" "$CIDR"
    twocol "DNS:" "$ns"
    twocol "$ORGNAME Network:" "$INTERNALscreen"
    twocol "ISP:" "$isp"

    # check for internal dns in wildcard before/after, that way it doesn't care whether its 1st, 2nd or 3rd/whatever dns server
    if [ $INTERNAL_CONN == "yes" ] && [[ $ns != *"$NS1"* ]] && [[ $ns != *"$NS2"* ]];
    then
      red ">> $ORGNAME DNS is not in use!"
    fi
  fi
fi

# not useful outside of basic tests
if [ "$TESTOPT" == "2" ] || [ "$TESTOPT" == "7" ];
then
  # make a cache relative to this ip, because isp data isn't gonna change - no need to keep making calls
  echo "$isp" > ~/.nettest/"$iip"
fi

# check wifi settings
if [ "$TESTOPT" != "uninstall" ] && [ "$TESTOPT" -ne 8 ] && [ "$OS" == "mac" ];
then
  ## get wifi connection info mac only https://apple.stackexchange.com/questions/81221/how-do-i-get-wi-fi-info-from-within-terminal
  boldtext "Checking Wifi..."
  export AIRPORT="/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"

  if  [ "$($AIRPORT -I)" == "AirPort: Off" ];
  then
    red "Wifi is off; exiting"
    exit 1
  fi

  whitebold "Signal"
  # get signal strength(RSSI) from airport utility and determine strength
  RSSI=$($AIRPORT -I | grep "agrCtlRSSI" | awk '{ print $2 }')
  WifiNoise=$($AIRPORT -I | grep "agrCtlNoise" | awk '{ print $2 }')
  SSID=$($AIRPORT -I | grep "SSID" | grep -v "BSSID" | awk '{ print $2 }')
  CHANNEL=$($AIRPORT -I | grep "channel" | awk '{ print $2 }')
  BSSID=$($AIRPORT -I | grep "BSSID" | awk '{ print $2 }')

  # netstat -i gives the tx rate & works on both mac & linux!

  if [ "$RSSI" -ge -73 ];
  then
    green " $RSSI RSSI; Strong Signal"
  elif [ "$RSSI" -ge -72 ] && [ "$RSSI" -le -77 ];
  then
    yellow " $RSSI RSSI; Fair Signal"
    RUNWAVEMON="1"
  else
    red " $RSSI RSSI; Weak Signal"
    RUNWAVEMON="1"
  fi

  # wifinoise
  if [ "$WifiNoise" -le -89 ];
  then
    green " $WifiNoise RF Noise Acceptable"
  elif [ "$WifiNoise" -ge -90 ];
  then
    red " $WifiNoise RF Noise High"
    RUNWAVEMON="1"
  fi


  # test if 2.4 or 5 radio
  channeltest "$CHANNEL"


  # convert hex to decimal
  IFS=: read -ra arr <<< "$BSSID"
  printf -v str "%02s:" "${arr[@]}"
  BSSID=${str%:}

  # lookup BSSID command to find vendor
  if [ ! "$BSSID" == "" ]
  then
    macsearch "${BSSID}"
  fi

  # check which access point the user's connected to
  apsearch "$BSSID"

elif [ "$TESTOPT" != "uninstall" ] && [ "$TESTOPT" -ne 8 ] && [[ "$OS" == "linux"  ||  "$OS" == "windows" ]];
then

  if [ "$OS" == "linux" ];
  then
    # /proc is the pseudo filesystem on linux (files that don't exist; exist in memory)
    # airport seems to be nmcli's mac counterpart, netstat also has some of this, which is a prerequisite for linux
    boldtext "Checking Wifi Settings..."
    INTERFACE="$(cat < /proc/net/wireless | awk '{print $1}' | tail -n1 | tr -d .:)"
    SSID="$(/sbin/iwgetid -r)"
    BSSID="$(nmcli -f bssid,active dev wifi list | awk '$2 ~ /yes/ {print $1}' | head -n1)"
    RSSI="$(cat < /proc/net/wireless | awk '{print $4}' | tail -n1 | tr -d .)"
    QUALITY="$(cat < /proc/net/wireless | awk '{print $3}' | tail -n1 | tr -d .)"
    QUALITYDESC="$(rescol "$QUALITY/70" "Link Quality is")"
    CHANNEL=$(/sbin/iw dev "$INTERFACE" info | grep channel | awk '{print $2 }')
    SIGNALDESC="received signal strength on $SSID"
    CIPHER="$(/sbin/iwlist "$INTERFACE" scan | grep -E "Group Cipher" | head -n 1 | awk '{ print $4 }')"
  else
    INTERFACE=$(netsh wlan show interfaces | grep Name | awk '{print $3}')
    SSID=$(netsh wlan show interfaces | grep SSID | grep -v BSSID | awk '{print $3}')
    BSSID=$(netsh wlan show interfaces | grep BSSID | awk '{print $3}')
    RSSI=$(netsh wlan show interfaces | grep Signal | awk '{print $3}' | tr -d .%)
    QUALITY="$RSSI"
    QUALITYDESC="Link Quality is"
    CHANNEL=$(netsh wlan show interfaces | grep Channel | awk '{print $3}')
    SIGNALDESC="Connected to $SSID on channel $CHANNEL"
    CIPHER=$(netsh wlan show interfaces | grep Cipher | awk '{print $3}')
  fi

  # test if 2.4 or 5 radio
  channeltest "$CHANNEL"

  # thresholds for good or bad signal quality
  if [ "$OS" == "linux" ] && [[ "$QUALITY" -ge 60 ]] || [ "$OS" == "windows" ] && [[ "$QUALITY" -ge 77 ]];
  then
    QUALITYDESC="$QUALITYDESC Strong"
    super "$QUALITYDESC"
  elif [ "$OS" == "linux" ] && [[ "$QUALITY" -le 59 ]] && [[ "$QUALITY" -gt 45 ]]  || [ "$OS" == "windows" ] && [[ "$QUALITY" -le 76 ]] && [[ "$QUALITY" -gt 75 ]];
  then
    QUALITYDESC="$QUALITYDESC Weak"
    yellow "$QUALITYDESC"
    RUNWAVEMON="1"
  else
    QUALITYDESC="$QUALITYDESC Poor"
    red "$QUALITYDESC"
    RUNWAVEMON="1"
  fi

  if [ "$OS" == "linux" ] && [ "$RSSI" -ge -68 ];
  then
    RSSIDESC="$(rescol "$RSSI" "Strong $SIGNALDESC")"
    super "$RSSIDESC"
  elif [ "$OS" == "linux" ] && [ "$RSSI" -le -69 ] && [ "$RSSI" -gt -72 ];
  then
    RSSIDESC="$(rescol "$RSSI" "OK $SIGNALDESC")"
    yellow "$RSSIDESC"
    RUNWAVEMON="1"
  elif [ "$OS" != "windows" ];
  then
    RSSIDESC="$(rescol "$RSSI" "Subpar $SIGNALDESC")"
    red "$RSSIDESC"
    RUNWAVEMON="1"
  # not found a way to get xx/70 rssi for windows, so output generic txt here
  elif [ "$OS" == "windows" ];
  then
    yellow "$SIGNALDESC"
  fi

  boldtext "Checking WAP details..."
  macsearch "$BSSID"

  # check encryption
  if [ "$CIPHER" == "CCMP" ];
  then
    twocol " Cipher: " "$CIPHER"
  else
    red "Cipher: $CIPHER << WEAK CIPHER, change to CCMP!"
  fi
fi

  # check which access point the user's connected to
  apsearch "$BSSID"

  function mac_radios() {
    # mac scanning manipulation leaves much to be desired
    # eloquently warn the user ...
    echo -e "\n\tScanning neighboring broadcasts..."
    yellow "Results can vary by how loud neighbors are at the time of the scan."
    yellow "It's a good idea to run a few scans to get a general consensus of neighboring usage."
    italic "Test 6 will have a more thorough view of active channels."
  }

  function crowding_tip() {
    CROWDED_CHANNEL=$(italic "If you're on a channel with a lot of neighbors, this could impede your wifi speed\nand quality, try to pick the channel with the lowest amount of users.")
    # if this is a home user, make a recommendation about crowded channels
    if [ "$AP_MANUFACTURER" != "$AP" ];
    then
      echo "$CROWDED_CHANNEL"
    fi
  }

  function windows_wifi() {
    # windows appears to have a cache for ms-availablenetworks:, seems to refresh it by triggering the explorer to open it prior to
    # running commands that utilize nearby networks
    explorer.exe ms-availablenetworks:
    # sleep 2s cause sometimes bash is faster than explorer (completely shocking)
    sleep 2
  }

  function windows_notice() {
    boldtext "You may notice your network explorer show:"
    yellow "There appears to be a cache that gets set with (only) the connected router's info.\nBy triggering it, we're able to ensure you get up to date neighbor information."
  }

  function channel_map() {
    # channel data from https://www.accessagility.com/blog/introduction-to-5-ghz-wifi-channels
    # good info about bonding: https://metis.fi/en/2018/02/5ghz-channels/
    purple "Channel used by the AP you're connected to: $CHANNEL\n"
    yellow "N/AC Channels - 20 MHz (Least interference, shortest reach)"
    echo -e "36, 40, 44, 48, 149, 153, 157, 161, 165\n"
    # https://netbeez.net/blog/dfs-channels-wifi/
    red "N/AC DFS/Radar Channels"
    italic "Use of these channels should only be done in areas where the 20MHz are exhausted"
    italic "When radar is in use, wifi will perform extremely poor, if at all!"
    echo -e "52, 56, 60, 64, 100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140\n"
    # 40 MHz is not accessible in most of the arrays to-date
    yellow "N/AC Channels - 40 MHz (Lower interference, shorter reach)"
    echo -e "38, 46, 54, 62, 102, 110, 118, 126, 134, 142, 151, 159\n"
    yellow "AC Channels - 80 MHz (Wider, greater interference)"
    echo -e "42, 58, 106, 122, 138, 155\n"
  }


  # determine the best channels to use
  if [ "$TESTOPT" == 4 ] && [ "$OS" == "linux" ];
  then
    # collect 2g channels in use
    BGN="$(nmcli -f chan dev wifi list | awk '$1 ~ /^1$|^6$|^11$/' | sort | uniq -c | sort -n)"
    purple "\nChannel Usage:"
    yellow "  Users\tChannel"
    echo "$BGN"

    echo "Channel in Use by Connected AP: $CHANNEL"
    crowding_tip

  elif [ "$TESTOPT" == 4 ] && [ "$OS" == "mac" ];
  then
    # collect 2g channels in use
    mac_radios

    # over processing on this; awk behaves differently on macs than linux, this was the easiest way to deal with its shortcomings
    # it still seems like garbage compared to linux awk usage, might need to use a different sorting tool
    BGN="$($AIRPORT -s | awk '{print $4}' | awk '$1 ~ /^1$|^6$|^11$/' | sort | uniq -c | sort -n)"

    purple "\nChannel Usage:"
    yellow "  Users\tChannel"
    echo "$BGN"

    echo "Channel in Use by Connected AP: $CHANNEL"
    crowding_tip

  elif [ "$TESTOPT" == 4 ] && [ "$OS" == "windows" ];
  then
    windows_wifi
    BGN=$(netsh wlan show networks mode=bssid | findstr "Channel" | awk '$3 ~ /^1$|^6$|^11$/' | sort | uniq -c | sort -n | sed 's/Channel            ://g')
    purple "\nYou are using channel $CHANNEL.  Neighbor Channel Usage:"
    yellow "  Users\t\tChannel"
    echo "$BGN"
    windows_notice
    crowding_tip
  fi

  if [ "$TESTOPT" == 5 ] && [ "$OS" == "linux" ];
  then
    # collect 5g channels in use
    NAC="$(nmcli -f chan dev wifi list | awk '$1 ~ /36|38|40|44|46|48|52|54|56|60|62|64|100|102|104|108|110|112|116|118|120|124|126|128|132|134|136|140|142|149|151|153|157|159|161|165/' | sort | uniq -c | sort -n)"
    purple "\nYou are using $CHANNEL.\n\nNeighbor Channel Usage:"
    yellow "  Users\tChannel"
    echo "$NAC"
    channel_map

  elif [ "$TESTOPT" == 5 ] && [ "$OS" == "mac" ];
  then
  mac_radios

  # over processing on this; awk behaves differently on macs than linux, this was the easiest way to deal with its shortcomings
  # it still seems like garbage compared to linux awk usage, might need to use a different sorting tool
  NAC="$($AIRPORT -s | awk '{print $4}' | awk '$1 ~ /36|38|40|44|46|48|52|54|56|60|62|64|100|102|104|108|110|112|116|118|120|124|126|128|132|134|136|140|142|149|151|153|157|159|161|165/' | sort | uniq -c | sort -n)"
  purple "\n\nNeighbor Channel Usage:"
  yellow "  Users\tChannel"
  echo "$NAC"
  channel_map

  elif [ "$TESTOPT" == 5 ] && [ "$OS" == "windows" ];
  then
    windows_wifi
    NAC="$(netsh wlan show networks mode=bssid | findstr "Channel" | awk '$3 ~ /36|38|40|44|46|48|52|54|56|60|62|64|100|102|104|108|110|112|116|118|120|124|126|128|132|134|136|140|142|149|151|153|157|159|161|165/' | sort | uniq -c | sort -n | sed 's/Channel            ://g')"
    purple "\nYou are using channel $CHANNEL.  Neighbor Channel Usage:"
    yellow "  Users\t\tChannel"
    echo "$NAC"
    channel_map
    windows_notice
  fi

# show channel usage by array .. both 2g/5g
if [ "$TESTOPT" == 6 ] && [ "$OS" == "linux" ];
then
  boldtext "Determining channel usage by array..."
  yellow "Sorted descending by signal strength"

  # if someone has a space in their ssid (printers, usually) the preceeding words are cut
  while IFS=$'\n' read -r line; do
    CHAN+=("$line")
  done < <(nmcli -f ssid,bssid,chan,freq,bars,signal dev wifi list | tail -n +2)

  for ARRAYCHAN in "${CHAN[@]}"
  do
    # determine whether or not this is an ssid with spaces and if so, adjust awk columns accordingly
    # we expect 7 columns only
    COUNTSPACES="$(wc -w <<< "$ARRAYCHAN")"
    if [ "$COUNTSPACES" -eq 7 ];
    then
      # this person is not a turd and has no spaces in ssid
      AWKCOL=0
    else
      # set the awk column + whatever the addl count is, as we prob have spaces, then
      AWKCOL=$((COUNTSPACES-7))
    fi

    # this loop seems super heavy, but i don't know a better way to do it atm
    UNCLEANSSID="$(echo "$ARRAYCHAN" | cut -d ' ' -f1-"$((AWKCOL+1))")"
    BSSID="$(echo "$ARRAYCHAN" | awk -v bssidawk="$((AWKCOL+2))" '{ print $bssidawk }')"
    IAP="$(echo "$ARRAYCHAN" | awk -v iapawk="$((AWKCOL+3))" '{ print $iapawk }')"
    FREQ="$(echo "$ARRAYCHAN" | awk -v freqawk="$((AWKCOL+4))" -v freqmhz="$((AWKCOL+5))" -v strawk="$((AWKCOL+6))" '{ print $freqawk $freqmhz  " " $strawk }')"
    SIGNAL="$(echo "$ARRAYCHAN" | awk -v sigawk="$((AWKCOL+7))" '{ print $sigawk }')"
    # ssid is sanitized since it returns values to the screen created by untrusted individuals, because, you never know :)
    SSID="${UNCLEANSSID//[^a-zA-Z0-9 \_-]/}"

    if [ "$INTERNAL_CONN" == "yes" ];
    then
      MAC="$(echo "$ARRAYCHAN" | awk '{ print $2 }')"
      apsearch "$MAC"; echo " SSID: $SSID"
    else
      purple " $SSID"
    fi

    echo -n " Signal Strength:"
    # how far are we from this guy?
    if [ "$SIGNAL" -gt 95 ];
    then
      red " $SIGNAL/100% (closest / loudest signal)"
    elif [ "$SIGNAL" -le 95 ] && [ "$SIGNAL" -ge 70 ];
    then
      yellow " $SIGNAL/100% (fairly close)"
    else
      green " $SIGNAL/100% (far away; poorest signal)"
    fi

    echo -e " Channel: $IAP\n Frequency: $FREQ\n BSSID: $BSSID\n------"
  done
elif [ "$TESTOPT" == 6 ] && [ "$OS" == "mac" ];
then

  boldtext "Determining channel usage by array..."
  yellow "Sorted ascending by signal strength"
  # if someone has a space in their ssid (printers, usually) preceeding words get cut
  while IFS=$'\n' read -r line; do
    CHAN+=("$line")
  done < <("$AIRPORT" -s | tail -n +2)

  for ARRAYCHAN in "${CHAN[@]}"
  do
    # determine whether or not this is an ssid with spaces and if so, adjust awk columns accordingly
    # we expect 7 columns only
    COUNTSPACES="$(wc -w <<< "$ARRAYCHAN")"
    if [ "$COUNTSPACES" -eq 7 ];
    then
      # this person is not a turd and has no spaces in ssid
      AWKCOL=0
    else
      # set the awk column + whatever the addl count is, as we prob have spaces, then
      AWKCOL=$((COUNTSPACES-7))
    fi

    # this loop seems super heavy, but i don't know a better way to do it atm
    UNCLEANSSID="$(echo "$ARRAYCHAN" | awk '{ print $1 }')"
    MAC="$(echo "$ARRAYCHAN" | awk -v bssidawk="$((AWKCOL+2))" '{ print $bssidawk }')"
    RSSID="$(echo "$ARRAYCHAN" | awk -v rssidawk="$((AWKCOL+3))"  '{ print $rssidawk }')"
    IAP="$(echo "$ARRAYCHAN" | awk -v iapawk="$((AWKCOL+4))" '{ print $iapawk }')"
    # ssid is sanitized since it returns values to the screen created by untrusted individuals, because, you never know :)
    SSID="${UNCLEANSSID//[^a-zA-Z0-9\_ -]/}"

    if [ "$INTERNAL_CONN" == "yes" ];
    then
      apsearch "$MAC"; echo " SSID: $SSID"
    else
      purple "$SSID"
    fi

    echo " RSSID: $RSSID"

    # how far are we from this guy?
    if [ "$RSSID" -gt -69 ];
    then
      red " (closest / loudest signal)"
    elif [ "$RSSID" -lt -69 ] && [ "$RSSID" -gt -79 ];
    then
      yellow " (fairly close)"
    else
      green " (far away; poorest signal)"
    fi

    echo -e " Channel: $IAP\n BSSID: $MAC\n--------"
  done

elif [ "$TESTOPT" == 6 ] && [ "$OS" == "windows" ];
then
  windows_wifi
  boldtext "Neighboring networks information"
  netsh wlan show networks mode=bssid
  windows_notice
fi

## extended tests
if [ "$TESTOPT" == 2 ] || [ "$TESTOPT" == 7 ];
then

  # the arguments differ from windows to mac/linux
  function pingOptions {
    if [ "$OS" != 'windows' ];
    then
      "$PINGS" -c 3 -q "$1"
    else
      "$PINGS" -n 3 "$1"
    fi
  }


  ## if you can reach gateway ping gateway test
  boldtext "Testing Connection To Gateway..."
  for i in $gateway;
  do
    if pingOptions "$i" >/dev/null;
    then
      green "$i Gateway is UP"
      echo "Testing packet loss..."

      if [ "$OS" != 'windows' ];
      then
        echo "$($PINGS -c 20 -q "$i" | grep "packet loss" | awk -F ',' '{print $3}' | awk '{print $1}')" "packet loss" & spinner
      else
        "$PINGS" "$i" | grep -o "Lost = .*" & spinner
      fi

      echo
      #nmap $gateway
    else
      red "$i Gateway is DOWN"
    fi
  done

  ## test if we have internet connection
  boldtext "Testing Connection to Internet..."

  # if have connectivity then ping an internet address
  if pingOptions "$CHECK1" >/dev/null;
  then
    green "Connection is UP"
    echo "Testing packet loss..."

    if [ "$OS" != 'windows' ];
    then
      echo "$($PINGS -c 20 -q "$CHECK1" | grep "packet loss" | awk -F ',' '{print $3}' | awk '{print $1}')" "packet loss" & spinner
    else
      "$PINGS" -n 20 "$CHECK1" | grep -o "Lost = .*" & spinner
    fi
  else
    red "Connection is DOWN"
  fi

  ## dns dig test
  boldtext "Testing DNS Response Time..."

  # add a delimiter split, otherwise the mac won't loop
  # compare dns response speeds, system dns - quad9 - cloudflare
  i=$(echo "$i" | cut -d ' ' -f2)
  for dnsServer in $ns;
  do
    ptr=$(host "$dnsServer" | sed 's/Name: //' | sed 's/ .*//g' | head -n 1)

    if dig @"$dnsServer" -t ns "$ORG_DNS" | grep -qai "$ORGNAME";
    then
      whitebold "From $dnsServer"
      green "$dnsServer -- $ptr OK"

      for domain in $ORG_DNS apple.com bbc.co.uk;
      do \
        system_dns=$(dig @"$dnsServer" "${domain}" | awk '/msec/{print $4}');\
        quad9_dns=$(dig @"$CHECK1" "${domain}" | awk '/msec/{print $4}');\
        cloudflare_dns=$(dig @1.1.1.1 "${domain}" | awk '/msec/{print $4}'); \
        echo -e "${domain}\t Workstation DNS ${system_dns}ms\tCloudFlare DNS ${cloudflare_dns}ms\tQuad9 DNS ${quad9_dns}ms\n"
      done
    else
      red "$dnsServer $ptr failed"
    fi
  done
fi

## basic http latency test
if [ "$TESTOPT" == 2 ] || [ "$TESTOPT" == 7 ] ;
then
  boldtext "Testing Latency..."

  curlArray=()
  x=1
  while [ $x -le 5 ]
  do
    curlArray+=("$(curl -o /dev/null -sL -w '%{time_total}' "$LATENCY_DEST" | tail -1)")
    x=$(( x + 1 ))
  done

  sum=$( IFS="+"; bc <<< "${curlArray[*]}" )

  # get average of responses
  average=$( echo "scale=8; $sum / ${#curlArray[@]}" | bc -l )
  echo "Average time to load $LATENCY_DEST = ${average} seconds"

  # test if below number in ms
  if (( $( bc -l <<< "$average > 1.0" ) ));
  then
    red "slow load times"
  else
    green "fast load times"
  fi
fi

## thorough tests
if [ "$TESTOPT" == 3 ] || [ "$TESTOPT" == 7 ];
then
  boldtext "Testing Internet Speed..."
  if [ "$OS" == "windows" ];
  then
    speedtest --accept-license
  else
    speedtest
  fi
fi

if [ "$RUNWAVEMON" == "1" ];
then
  yellow "Signal could use some improvement, run wavemon and check for noise"
fi

if [ "$TESTOPT" == 8 ];
then
  exit
else
  purple "\n== Testing complete! ==\n\n"
fi

#### uninstaller #####
# does not remove bitbucket from knownhosts file YET
# get INSTALLPATH from ~/.nettest/config.conf
if [ "$OS" == "mac" ] || [ "$OS" == "linux" ] && [ "$TESTOPT" == "uninstall" ];
then
	if [ ! -d "$INSTALLPATH" ];
	then
		red "No installation of networktesting found, at $INSTALLPATH"
  elif [ "$OS" == "mac" ];
  then
  	echo "Found installation at: $INSTALLPATH, uninstalling..."
  	rm -Rf ~/.ssh/updaterROkey && echo "Removed ~/.ssh/updaterROkey.."
  	rm -Rf ~/.nettest && echo "Removed ~/.nettest"
  	brew remove ipcalc && echo "Removed ipcalc via brew"
  	brew remove nmap && echo "Removed nmap via brew"
  	brew remove speedtest-cli --force && echo "Removed speedtest via brew"
    purple "For safety reasons & to avoid conflict with other apps you may be using, some items were not automatically removed, see below:"
    red "Not auto-removing CommandLineTools; run: rm -rf /Library/Developer/CommandLineTools to complete removal!"
    red "Not auto-removing brew; run:"
  	red "ruby -e $(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/uninstall) to complete removal"
    red "Not removing parent path: $INSTALLPATH; please delete manually to complete the uninstall."
  elif [ "$OS" == "linux" ];
  then
    rm -Rf ~/.ssh/updaterROkey && echo "Removed ~/.ssh/updaterROkey.."
    rm -Rf ~/.nettest && echo "Removed ~/.nettest"
    purple "For safety reasons & to avoid conflict with other apps you may be using, some items were not automatically removed, see below:"
    red "Not auto-removing parent path: $INSTALLPATH; please delete manually to complete the uninstall."
    red "Not auto-removing Linux dependencies, feel free to check these yourself and ensure they won't also remove other dependencies:"
    red "network-manager lolcat ipcalc nmap speedtest-cli"
  fi
elif [ "$TESTOPT" == "uninstall" ];
then
  red "Uninstall option only for Mac or Linux, to remove from Windows simply delete the \"networktesting\" directory."
  exit 1
fi

# export a var to indicate the default test had already run
DEFAULT_TEST_RAN="1"
export DEFAULT_TEST_RAN

# reload the menu after each test?
if [ "$RELOAD_MENU" -eq 1 ];
then
  MAIN_MENU=$(filepath "$0")
  "$MAIN_MENU"
fi
