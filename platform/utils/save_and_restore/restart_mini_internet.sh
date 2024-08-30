#!/bin/bash

WORKDIR="$(pwd)/"
routers=('ZURI' 'BASE' 'GENE' 'LUGA' 'MUNI' 'LYON' 'VIEN' 'MILA')
dchosts=('FIFA' 'UEFA')

# Variables for this script
isDoBackup=false
isDoRestart=false
isDoRestore=false

# save all configs first
save_configs() {
  cd $WORKDIR../
  if ! [[ -d students_config ]]; then
    mkdir students_config
  fi

  cd students_config/
  rm -rf *

  for as in ${students_as[@]}; do
    echo "Saving config on AS: ${as}"

    docker exec -itw /root ${as}_ssh bash -c 'rm -rfv configs*' > /dev/null
    docker exec -itw /root ${as}_ssh "./save_configs.sh" > /dev/null

    configName=$(docker exec -itw /root ${as}_ssh bash -c 'find . -maxdepth 1 -regex \./.*.tar.gz' | sed -e 's/\r$//')
    docker exec -itw /root ${as}_ssh bash -c "mv $configName configs-as-${as}.tar.gz"

    docker cp ${as}_ssh:/root/configs-as-${as}.tar.gz ./configs-as-${as}.tar.gz
  done
}

reset_with_startup() {
  echo "Resetting mini internet with startup.sh again..."
  cd $WORKDIR
  
  # Hard reset
  echo "Executing cleanup.sh & hard_reset.sh ..."
  ./cleanup/cleanup.sh .
  ./cleanup/hard_reset.sh .

  # Then startup
  echo "Executing startup.sh ..."
  ./startup.sh . && ./utils/iptables/filters.sh .

  echo "Waiting for docker container to ready first, sleeping in 3 seconds..."
  sleep 3
  
  # Start MATRIX container
  docker unpause MATRIX
}

restore_configs() {
  for as in ${students_as[@]}; do
    cd $WORKDIR../students_config/

    echo "Restoring config on AS: ${as}"
    docker cp ./configs-as-${as}.tar.gz ${as}_ssh:/root/configs-as-${as}.tar.gz

    docker exec -iw /root ${as}_ssh bash -c "./restore_configs.sh configs-as-${as}.tar.gz all" << EOF
Y
EOF

    # Extract the config file
    cd $WORKDIR../students_config/; rm -rf configs_*; tar -xf configs-as-${as}.tar.gz
    # Get configs folder name
    configs_folder_name=$(ls -d */ | grep configs)

    # Restore router files
    for rc in ${routers[@]}; do
      cd $WORKDIR../students_config/

      container_name=${as}_${rc}router

      # Overwrite backuped router config file to the /etc/frr/frr.conf
      echo "Restoring $container_name configuration..."
      docker cp ${configs_folder_name}${rc}/router.conf ${container_name}:/root/frr.conf

      # Remove the building configuration and current configuration text
      docker exec -itw /root ${container_name} bash -c 'sed '1,3d' /root/frr.conf > /root/frr-removed-header.conf'

      docker exec -itw /root ${container_name} bash -c '/usr/lib/frr/frr-reload.py --reload /root/frr-removed-header.conf'
      sleep 2
      docker exec -itw /root ${container_name} bash -c 'rm /root/{frr,frr-removed-header}.conf'
    done
    
    # Restore router hosts
    for rc in ${routers[@]}; do
      cd $WORKDIR../students_config/

      container_name=${as}_${rc}host

      echo "Restoring $container_name configuration..."
      # Get the IPv4 address
      ipv4=$(cat ${configs_folder_name}${rc}/host.ip | grep -w inet | grep ${rc}router | awk '{print $2}')
      echo "Backuped $container_name IPv4: ${ipv4}"
      # Get the IPv6 address
      ipv6=$(cat ${configs_folder_name}${rc}/host.ip | grep -w inet6 | grep ${rc}router | awk '{print $2}')
      echo "Backuped $container_name IPv6: ${ipv6}"
      # Get default route (IPv4 only?)
      default_route=$(cat ${configs_folder_name}${rc}/host.route | grep -w default | awk '{print $3}')
      echo "Backuped $container_name Default Route: ${default_route}"

      # Adding the IPv4 and IPv6 address
      docker exec -itw /root ${container_name} ip address add ${ipv4} dev ${rc}router &> /dev/null
      docker exec -itw /root ${container_name} ip address add ${ipv6} dev ${rc}router &> /dev/null
      docker exec -itw /root ${container_name} ip route add default via ${default_route} &> /dev/null
    done
    
    # Restore switch files into switch
    for sw in $(seq 1 4); do
      cd $WORKDIR../students_config/

      # Init switch loc
      switch_name=S${sw}
      data_center_loc='DCN'
      if [[ $switch_name == 'S4' ]]; then
        data_center_loc='DCS'
      fi

      container_name=${as}_L2_${data_center_loc}_${switch_name}

      # Get configs folder name
      configs_folder_name=$(ls -d */ | grep configs)

      # Overwrite backuped switch file to the /etc/openvswitch/conf.db
      echo "Restoring $container_name configuration..."
      docker cp ${configs_folder_name}${switch_name}/switch.db ${container_name}:/root/switch.db
      docker exec -itw /root ${container_name} bash -c 'ovsdb-client restore < /root/switch.db'
      sleep 2
      docker exec -itw /root ${container_name} bash -c 'rm /root/switch.db'
    done

    # Restore Datacenter Hosts
    for dc in ${dchosts[@]}; do
      for i in $(seq 1 4); do
        cd $WORKDIR../students_config/

        # Init host loc
        data_center_loc='DCN'
        if [[ $i -eq 4 ]]; then
          data_center_loc='DCS'
        fi

        hostname=${dc}_${i}
        container_name=${as}_L2_${data_center_loc}_${hostname}

        echo "Restoring $container_name configuration..."
        # Get the IPv4 address
        ipv4=$(cat ${configs_folder_name}${hostname}/host.ip | grep -w inet | grep ${as}-S${i} | awk '{print $2}')
        echo "Backuped $container_name IPv4: ${ipv4}"
        # Get the IPv6 address
        ipv6=$(cat ${configs_folder_name}${hostname}/host.ip | grep -w inet6 | grep ${as}-S${i} | awk '{print $2}')
        echo "Backuped $container_name IPv6: ${ipv6}"
        # Get default route (IPv4 only?)
        default_route=$(cat ${configs_folder_name}${hostname}/host.route | grep -w default | awk '{print $3}')
        echo "Backuped $container_name Default Route: ${default_route}"

        # Adding the IPv4 and IPv6 address
        docker exec -itw /root ${container_name} ip address add ${ipv4} dev ${as}-S${i} &> /dev/null
        docker exec -itw /root ${container_name} ip address add ${ipv6} dev ${as}-S${i} &> /dev/null
        docker exec -itw /root ${container_name} ip route add default via ${default_route} &> /dev/null
      done
    done
  done
}

show_passwords() {
  cd $WORKDIR
  echo "--- START OF ASes PASSWORDS ---"
  cat groups/passwords.txt
  echo "---  END OF ASes PASSWORDS  ---"

  echo "--- START OF krill_passwords ---"
  cat groups/krill_passwords.txt
  echo "---  END OF krill_passwords  ---"

  echo "--- START OF MEASUREMENT PASSWORDS ---"
  cat groups/ssh_measurement.txt
  echo "---  END OF MEASUREMENT PASSWORDS  ---"
}

# create function to show red color echo
function red_echo() {
  echo -e "\e[31m$1\e[0m"
}

show_help() {
  echo "usage: $0 [options] [-g <AS groups>]"
  echo "options available:"
  echo -ne "\t-b\tbackup configs to students_config directory (-g is required)\n\t\t"
  red_echo '(CAUTION: this will wipes all existing configs in the directory, ensure you had copy the configs beforehand)'
  echo -ne "\t-s\treset the mini internet, performs startup.sh\n\t\t"
  red_echo '(CAUTION: this will wipes all configs in the project, ensure you had the backup of the configs)'
  echo -ne "\t-r\trestore ASes configs (-g is required)\n\t\t"
  red_echo '(CAUTION: this will override the running configs)'
  echo -e "\t-g\tspecify ASes groups to perform backup/restore with, separated by comma without whitespace (ex: 3,4,13,14)"
  echo -e "\t-p\tshow AS passwords"
  echo -e "\t-h\tshow help"
  echo -e "If you are using all options, the script will do backup configs, reset the mini internet, and restore configs respectively"
}

check_if_root() {
  if [[ $(id -u) -ne 0 ]]; then
    echo "You must run as root, exiting..."
    exit 1
  fi
}

run() {
  # Check if the AS groups are specified when doing backup/restore
  if [[ $isDoBackup == true || $isDoRestore == true ]]; then
    check_students_as_len
  fi

  if [[ $isDoBackup == true ]]; then
    check_if_root
    save_configs
  fi

  if [[ $isDoRestart == true ]]; then
    check_if_root
    reset_with_startup
  fi

  if [[ $isDoRestore == true ]]; then
    check_if_root
    restore_configs
    echo "Restart complete, here are all passwords..."
    show_passwords
  fi
}

check_students_as_len() {
    if [[ ${#students_as[@]} -eq 0 ]]; then
      echo -e "error: students_as is empty\n"
      show_help
      exit 1
    fi
    echo "Students AS groups: ${students_as[@]}"
}

welcome() {
  if [[ $# -eq 0 ]]; then
    show_help
    exit 1
  fi

  while getopts ":bsrg:h" opt; do
    case $opt in
      b)
        isDoBackup=true
        ;;
      r)
        isDoRestore=true
        ;;
      s)
        isDoRestart=true
        ;;
      g)
        # Read the AS groups from the argument
        readarray -t students_as < <(echo $OPTARG | awk -F',' '{ for (x = 1; x <= NF; x++) print $x }')
        # Check if the AS groups are integers
        for i in ${students_as[@]}; do
          if ! [[ $i =~ ^[0-9]+$ ]]; then
            echo -e "error: an AS group must be an integer\n"
            show_help
            exit 1
          fi
        done
        ;;
      h)
        show_help
        ;;
      \?)
        show_help
        ;;
    esac
  done
  run
}

welcome $@
