#!/bin/bash
# Template script installed to ssh hosts, to restart/reload OSPF configuration
# save_configs.sh appends the list of if-statements for each router to this file

echo_red() {
  tput setaf 1
  echo "$@"
  tput sgr0
}

# run_vtysh_command <router ip> <vtysh/linux> <command>
run_vtysh_command() {
  local router_ip="$1"
  local terminal_type="$2"
  local command="$3"
  if [[ "$terminal_type" = "linux" ]]; then
    ssh -q -t -o StrictHostKeyChecking=no root@"$router_ip" "vtysh -c '${command}'"
  else
    ssh -q -t -o StrictHostKeyChecking=no root@"$router_ip" -- -c "${command}"
  fi
}

# reload_ospf <subnet> <router name> <vtysh/linux>
reload_ospf() {
  local router_ip="${1%???}"
  local router_name="$2"
  local terminal_type="$3"
  local orig_config
  local ospf_config

  echo -n "Loading running OSPF config from ${router_name}: "
  if ! orig_config="$(run_vtysh_command "$router_ip" "$terminal_type" "sh run")"; then
    echo_red "Failed to load the running configuration."
    return 1
  fi

  #echo "$orig_config"

  # Select only the OSPF portion of the configuration
  case "$orig_config" in
  *"router ospf"*)
    ospf_config="router ospf${orig_config#*router ospf}"
    ;;
  *)
    echo_red "Failed to find any OSPF configuration."
    return 1
    ;;
  esac
  echo "Success"

  local reload_command="configure"$'\n'
  local clear_command="configure"$'\n'

  local IFS=$'\r\n'
  for line in ${ospf_config}; do
    case "$line" in
    'router ospf'*) # Delete all top-level OSPF instances, including vrfs
      clear_command="${clear_command}no ${line}"$'\n' ;;
    '!') ;;  # Skip end over the config
    ' '*) ;; # Skip over sub-configuration
    *)       # Stop, we've reached a non-ospf top-level command
      break ;;
    esac
    # Restore accepts the config unmodified
    reload_command="${reload_command}${line}"$'\n'
  done

  echo -n "Clearing OSPF from ${router_name}: "
  if run_vtysh_command "$router_ip" "$terminal_type" "${clear_command}"; then
    echo "Success"
  else
    echo_red "Failed, will attempt the restore regardless"
  fi

  echo -n "Reloading OSPF to ${router_name}: "
  if run_vtysh_command "$router_ip" "$terminal_type" "${reload_command}"; then
    echo "Success"
  else
    echo_red "Failed, will attempt the restore regardless"
  fi

  local running_config
  running_config="$(run_vtysh_command "$router_ip" "$terminal_type" "sh run")"

  if [[ "$running_config" != "$orig_config" ]]; then
    echo_red "There is a difference between the original and running config"
    echo_red "You should manually review and correct this difference"
    diff --color=auto -u <(echo "$orig_config") <(echo "$running_config")
  fi
}
# Map main to reload_ospf, the generated code for each router will call main
main() {
  reload_ospf "$@"
}

if [[ "$#" -ne 1 ]] || [[ ${1:0:1} == "-" ]]; then
  echo "Reloads the ospfd configuration so that the updated router-id (etc.) takes effect"
  echo "Usage: $0 <router name or 'all'>"
  exit 1
fi

router_name="$1"
