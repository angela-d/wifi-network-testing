# Network Testing Config Manual
A config file `.nettest/config.conf` is copied from a **template**, that *must exist in the running directory while the script is first ran*.


In this config, you'll find interchangable variables you can modify to suit your system.  After you change any config variables, relaunch the network tester.

- `ORGNAME=` - The name that will be displayed referencing the network the user should be on.

- `INTERNAL_CHECK=` - should be an internally accessible hostname that will be used to determine whether or not the user is active on the preferred network. (No http(s) prefix.)

- `NS1=` & `NS2=` - Assuming the user passed **INTERNAL_CHECK** successfully, the preferred nameservers of **NS1** and **NS2** will be checked to ensure they're in use.

- `CHECK1` - A reliable IP-based host to ping once to see if the user can reach the internet.

- `CHECK2` - A reliable FQDN to ping once to see if the user can reach the internet with DNS.

- `IFCFG=` - if the **ifconfig** command resides elsewhere, specify such here. In the application, its triggered by the `$IFCFG` variable.

- `PINGPROTOCOL` - See: [ping: socket: Address family not supported by protocol](https://github.com/iputils/iputils/issues/293) - On Debian at least, ping defaults to ipv6 and will throw this error if you're not using ipv6 on your network.  Leave blank to let your OS/ping decide, or set `-4` with `-6` to force ipv6 for pings.

- `DEFAULT_TEST=` - If you want to trigger an immediate test upon each session, enter the test # here.  Leave blank for no default (show the menu every launch).

- `AP_MANUFACTURER=` - Expected manufacturer of the access points - will colorize a warning if a match is not met.  If the manufacuter name has a space in it, use the first part of the name only.  Instead of *Xirrus, Inc.* use *Xirrus*.  This is obtained from the [OUI list](http://standards-oui.ieee.org/oui.txt) the connected AP's Mac is compared to.
