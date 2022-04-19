#!/bin/bash
# Reinstalls OvS flow rules and brings up related interfaces.
# For use if main OvS instance was accidentally restarted etc.
# This script pulls commands out of groups/ip_setup.sh.

new_script=_recover_ovs_flows.sh
ip_setup=../groups/ip_setup.sh

rm "${new_script}" 2>/dev/null
touch "${new_script}"
while read -r line; do
  case "$line" in
  'port_id1=`ovs-vsctl get Interface'*)
    echo "$line" >>"${new_script}"
    ;;
  'port_id2=`ovs-vsctl get Interface'*)
    echo "$line" >>"${new_script}"
    ;;
  'ovs-ofctl add-flow'*)
    echo "$line" >>"${new_script}"
    ;;
  *netns*);;  # Skip netns related lines, these interfaces are within containers
  PID*);;
  '#'*);;
  source*);;
  *)          # The remaining commands configure interfaces in the main OvS instance
  echo "$line" >>"${new_script}"
  ;;
  esac
done <"$ip_setup"

chmod +x "${new_script}"

echo "OvS commands written to ${new_script}"
read -p "Would you like to reinstall OvS flows now? [y/N]" -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Cancelled"
  exit 1
else
  sudo ./${new_script}
  echo "OvS flows have been installed"
fi
