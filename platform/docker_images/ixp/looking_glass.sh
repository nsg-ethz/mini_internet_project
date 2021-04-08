while true
do
  duration=$(shuf -i300-900 -n1)

  for i in {0..$duration..30}; do
    date "+%FT%T" > /home/looking_glass.txt
    vtysh -c 'show ip bgp' >> /home/looking_glass.txt
    sleep 30
  done
done
