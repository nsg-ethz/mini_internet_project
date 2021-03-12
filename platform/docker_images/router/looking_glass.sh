while true
do
  duration=$(shuf -i300-900 -n1)

  for i in {0..$duration..30}; do
    date "+%FT%T" > /home/looking_glass.txt
    vtysh -c 'show ip bgp' >> /home/looking_glass.txt
    vtysh -c 'show ip bgp json' > /home/looking_glass_json.txt
    sleep 30
  done

  # save router config
  vtysh -c 'write'

  # needed to remove weird interface names when frr starts..
  for intf_name in $(vtysh -c 'show interface brief' | grep _c | cut -f 1 -d ' '); do
      vtysh -c "conf t" -c "interface $intf_name" -c "shutdown" -c "exit" -c "no interface $intf_name"
  done


done
