#!/bin/bash

# All subnets are definded here.
# Whenever an ip is needed this file is loaded

set -o errexit
set -o pipefail
set -o nounset

subnet_group() {
  local n_grp="$1"

  echo "${n_grp}"".0.0.0/8"
}

subnet_host_router() {
  local n_grp="$1" n_router="$2" device="$3" n_vpn_peer="${4:-1}"

  if [ "$device" = "host" ]; then

    echo "${n_grp}"".""$(($n_router + 101))"".0.1/24"

  elif [ "$device" = "router" ]; then

    echo "${n_grp}"".""$(($n_router + 101))"".0.2/24"

  elif [ "$device" = "bridge" ]; then

    echo "${n_grp}"".""$(($n_router + 101))"".0.0/24"

  elif [ "$device" = "vpn_interface" ]; then

    echo "${n_grp}"".""$(($n_router + 101))"".10.1/24"
	  
  elif [ "$device" = "vpn_peer" ]; then

    echo "${n_grp}"".""$(($n_router + 100))"".10.""$((1+$n_vpn_peer))""/32"
  
  else

    echo "subnet_host_router: unknown device $device" 1>&2
    exit 1

  fi
}

subnet_l2_router() {
  local n_grp="$1" l2_id="$2"

  echo "${n_grp}"".$((200 + $l2_id)).0.0/16"
}

subnet_l2() {
  local n_grp="$1" l2_id="$2" vlan="$3" n_host="$4"

  echo "${n_grp}"".$((200 + $l2_id)).$vlan.$n_host/24"
}

gw_l2_() {
  local n_grp="$1" vlan="$2" n_host="$3"

  echo "${n_grp}"".200.$vlan.$n_host/24"
}

subnet_l2_router_ipv6() {
  local n_grp="$1" l2_id="$2"

  echo "${n_grp}"":$((200 + $l2_id))::/32"
}

subnet_l2_ipv6() {
  local n_grp="$1" l2_id="$2" vlan="$3" n_host="$4"

  echo "${n_grp}"":$((200 + $l2_id)):$vlan::$n_host/48"
}

subnet_router() {
  local n_grp="$1" n_router="$2"

  echo "${n_grp}"".""$(($n_router + 151))"".0.1/24"
}

subnet_router_router_intern() {
  local n_grp="$1" n_net="$2" device="$3"

  if [ "${device}" = "1" ]; then

    echo "${n_grp}"".0."$((${n_net} + 1))".1/24"

  elif [ "${device}" = "2" ]; then

    echo "${n_grp}"".0."$((${n_net} + 1))".2/24"

  elif [ "${device}" = "bridge" ]; then

    echo "${n_grp}"".0."$((${n_net} + 1))".0/24"

  else

    echo "subnet_router_router_intern: unknown device $device" 1>&2
    exit 1

  fi
}

subnet_router_router_extern() {
  local n_net="$1" device="$2"

  mod=$((${n_net} % 100))
  div=$((${n_net} / 100))

  if [ "${device}" = "1" ]; then

    echo "179."${div}"."${mod}".1/24"

  elif [ "${device}" = "2" ]; then

    echo "179."${div}"."${mod}".2/24"

  elif [ "${device}" = "bridge" ]; then

    echo "179."${div}"."${mod}".0/24"

  else

      echo "subnet_router_router_extern: unknown device: $device" 1>&2
      exit 1

  fi
}

subnet_router_IXP() {
  local n_grp="$1" n_ixp="$2" device="$3"

  if [ "${device}" = "group" ]; then

    echo "180."${n_ixp}".0."${n_grp}"/24"

  elif [ "${device}" = "IXP" ]; then

    echo "180."${n_ixp}".0."${n_ixp}"/24"

  elif [ "${device}" = "bridge" ]; then

    echo "180."${n_ixp}".0.0/24"

  else

    echo "subnet_router_IXP: unknown device $device" 1>&2
    exit 1

  fi
}

subnet_router_MEASUREMENT() {
  local n_grp="$1" device="$2"

  if [ "${device}" = "group" ]; then

    echo "${n_grp}"".0.199.1/24"

  elif [ "${device}" = "measurement" ]; then

    echo "${n_grp}"".0.199.2/24"

  elif [ "${device}" = "bridge" ]; then

    echo "${n_grp}"".0.199.0/24"

  else

    echo "subnet_router_MEASUREMENT: unknown device $device" 1>&2
    exit 1

  fi
}

subnet_router_MATRIX() {
  local n_grp="$1" device="$2"

  if [ "${device}" = "group" ]; then

    echo "${n_grp}"".0.198.1/24"

  elif [ "${device}" = "matrix" ]; then

    echo "${n_grp}"".0.198.2/24"

  elif [ "${device}" = "bridge" ]; then

    echo "${n_grp}"".0.198.0/24"

  else

    echo "subnet_router_MATRIX: unknown device $device" 1>&2
    exit 1

  fi
}

subnet_router_DNS() {
  local n_grp="$1" device="$2"

  if [ "${device}" = "group" ]; then

    # echo "198.0.0."${n_grp}"/24"
    echo "198.${n_grp}.0.1/24"

  elif [ "${device}" = "measurement" ]; then

    echo "198.255.0.1/24"

  elif [ "${device}" = "dns-group" ]; then

    # echo "198.0.0.100/24"
    echo "198.${n_grp}.0.2/24"

  elif [ "${device}" = "dns" ]; then

    echo "198.0.0.100/24"

  elif [ "${device}" = "dns-measurement" ]; then

    # echo "198.0.0.100/24"
    echo "198.255.0.2/24"

  elif [ "${device}" = "bridge" ]; then

    echo "198.0.0.0/24"

  else

    echo "subnet_router_DNS: unknown device $device" 1>&2
    exit 1

  fi
}

subnet_ext_sshContainer() {
  local n_grp=$1 device="$2"

  if [ "${device}" = "sshContainer" ]; then

    echo "157.0.0.$(($n_grp + 10))/24"

  elif [ "${device}" = "MEASUREMENT" ]; then

    echo "157.0.0.250/24"

  elif [ "${device}" = "bridge" ]; then

    echo "157.0.0.1/24"

  elif [ "${device}" = "docker" ]; then

    echo "157.0.0.0/24"

  else

    echo "subnet_ext_sshContainer: unknown device $device" 1>&2
    exit 1

  fi
}

subnet_sshContainer_groupContainer() {
  local n_grp="$1" n_router="$2" n_layer2="$3" device="$4"

  if [ "${device}" = "sshContainer" ]; then

    echo "158."$n_grp".0.2/16"

  elif [ "${device}" = "MEASUREMENT" ]; then

    echo "158."$n_grp".0.3/16"

  elif [ "${device}" = "router" ]; then

    echo "158."$n_grp".$((n_router + 10)).1/16"

  elif [ "${device}" = "L3-host" ]; then

    echo "158."$n_grp".$((n_router + 10)).2/16"

  elif [ "${device}" = "switch" ]; then

    # echo "158."$n_grp".$((n_router + 10)).$((n_layer2 + 3))/16"
    echo "158."$n_grp".100."$((n_layer2 + 3))"/16"

  elif [ "${device}" = "L2-host" ]; then

    echo "158."$n_grp".200."$((n_layer2 + 3))"/16"

  elif [ "${device}" = "bridge" ]; then

    echo "158."$n_grp".0.1/16"

  elif [ "${device}" = "docker" ]; then

    echo "158."$n_grp".0.0/16"

  else

    echo "subnet_sshContainer_groupContainer: unknown device $device" 1>&2
    exit 1

  fi
}
