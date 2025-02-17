#!/bin/bash
# Template script installed to ssh hosts, to restore a saved configuration
# save_configs.sh appends the list of if-statements for each router to this file

if [[ "$#" -le 1 ]] || [[ ! -e "$1" ]]; then
  echo "This script restores saved configuration to a router, switches are not currently supported."
  echo "Usage: $0 <saved_config> <router name (default 'all')>"
  exit 1
fi

config_path="$1"
device_name="${2:-all}"
case "$1" in
*".tar.gz")
  config_path="$(mktemp -d)"
  trap 'rm -r -- "$config_path"' EXIT
  tar -xzf $1 -C "$config_path" --strip-components=1
  ;;
*) ;;
esac

if [[ ! -d "$config_path" ]]; then
  echo_red "Cannot open configuration directory"
  exit 1
fi

echo "This script will wipe the current configuration from: $2"
echo "Consider saving your current configuration first!"
echo ""
read -p "Are you sure you want to restore saved configuration? [y/N]" -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Restore cancelled"
  exit 1
fi

# _ssh <subnet> <commands>
_ssh() {
  ssh -qt -o StrictHostKeyChecking=no root@"${1%???}" "${@:2}"
}

echo_red() { echo -e "\033[31m$@\033[0m" ; }

# clear_config_vtysh <router ip> <router name>
clear_config_vtysh() {
  local router_subnet="$1"
  local router_name="$2"
  local config
  echo -n "Clearing $router_name configuration: "
  if ! config="$(_ssh $router_subnet vtysh -c 'sh run')"; then
    echo_red "Failed to load the current running configuration."
    return 1
  fi

  case "$config" in
  *"frr defaults traditional"*)
    # Start reading the configuration from the line after 'frr defaults traditional'
    config="${config#*frr defaults traditional}"
    ;;
  *)
    echo_red "Failed to parse the current running configuration."
    return 1
    ;;
  esac

  local IFS=$'\r\n'
  local state="toplevel"
  local clear_command=$'configure\n'

  # Generally speaking it is sufficient to remove only top-level
  # items, for example 'no router bgp' and 'no ip route 1.0.0.0/8 Null0'
  # However this does not work for interfaces if an address is configured.
  # In this case we must remove the address first.
  for line in ${config}; do
    if [[ $state == "toplevel" ]]; then
      case "$line" in
      '') ;;          # Skip blank lines
      ' '*) ;;        # Skip commands that are not top-level
      '!'*) ;;        # Skip configuration separators
      'end'*) ;;      # Skip the final 'end'
      'line'*) ;;     # Don't remove 'line vty'
      'rpki'*) ;;     # There is no `no rpki` command.
      'hostname'*) ;; # Don't remove the hostname
      'interface'*)   # Interfaces are a special case, remove the config instead
        state="interface"
        clear_command="${clear_command}${line}"$'\n'
        ;;
      *) # Remove all remaining top-level configuration with 'no'
        clear_command="${clear_command}no ${line}"$'\n' ;;
      esac
    elif [[ $state == "interface" ]]; then
      # Remove configuration from within an interface
      case "$line" in
      '  '*) # We don't handle sub-configuration options, skip them
        echo_red "Unexpected line: [$line] skipping"
        ;;
      *'link-params'*) ;; # Skip link-params sub-configuration, not supported
      ' !') ;;            # Skip end of sub-configuration blocks
      ' '*)               # Remove this interface configuration line
        clear_command="${clear_command}no${line}"$'\n' ;;
      '!') # End of the interface configuration block
        clear_command="${clear_command}exit"$'\n'
        state="toplevel"
        ;;
      *)
        echo_red "Unexpected line: [$line] stopping"
        return 1
        ;;
      esac
    fi
  done
  clear_command="${clear_command}exit"$'\n'

  if  _ssh "$router_subnet" vtysh -c "$clear_command" ; then
    echo "Success"
  else
    echo_red "Failed, will attempt the restore regardless"
    return 0
  fi
}

# restore_config_vtysh <router ip> <config> <router name>
restore_config_vtysh() {
  local router_subnet="$1"
  local config="$2"
  local router_name="$3"

  # vtysh accepts the configuration file as raw input, no need to modify
  local build_command="configure"$'\n'"${config#*frr defaults traditional}"
  echo -n "Restoring $router_name configuration: "

  if _ssh "$router_subnet" vtysh -c "${build_command}" ; then
    echo "Success"
  else
    echo_red "Failed"
  fi
}

# check_config_vtysh <router ip> <config file> <router name>
check_config_vtysh() {
  local router_subnet="$1"
  local config_file="$2"
  local running_config
  local config_restored
  config_restored="$(cat "$config_file")"
  echo -n "Verifying restored configuration on $3: "
  if ! running_config="$(_ssh $router_subnet vtysh -c 'sh run')"; then
    echo_red "Failed to load the current running configuration."
    return 1
  fi

  if [[ "$config_restored" != "$running_config" ]]; then
    echo_red "There is a difference between the backup and running config"
    echo_red "You should manually review and correct this difference"
    diff -u "$config_file" <(echo "$running_config")
    echo
  else
    echo "Success"
  fi
}

# restore_config <subnet> <router name> <vtysh/linux>
restore_router_config() {
  local router_subnet="$1"
  local router_name="$2"
  local terminal_type="$3"
  local new_config_file="${config_path}/${router_name}/router.conf"
  local new_config

  if new_config=$(cat "$new_config_file"); then
    case "$terminal_type" in
    "vtysh")
      if ! clear_config_vtysh "$router_subnet" "$2"; then
        return
      fi
      restore_config_vtysh "$router_subnet" "$new_config" "$2"
      check_config_vtysh "$router_subnet" "$new_config_file" "$2"
      ;;
    "linux")
      echo "Copying new configuration to $router_name"
      _ssh "$router_subnet" "cat > /etc/frr/frr.conf" < $new_config_file
      echo "Restarting FRR on $router_name"
      _ssh "$router_subnet" /usr/lib/frr/frrinit.sh restart > /dev/null || echo_red "Failed to restart FRR"
      ;;
    "*")
      echo_red "Cannot restore $router_name: misconfigured terminal type $terminal_type"
      ;;
    esac
  else
    echo_red "Cannot restore $router_name: configuration not found in backup"
  fi
}
