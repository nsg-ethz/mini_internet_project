#!/bin/bash

# VPN information
dir=/home/adv-net/mini_internet_project/platform/groups

# Get the current script directory, no matter where we are called from.
# https://stackoverflow.com/questions/59895/how-to-get-the-source-directory-of-a-bash-script-from-within-the-script-itself
cur_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

vpndir="$cur_dir/../vpn"
rm -rf $vpndir
mkdir $vpndir

# Create config
cat << EOM > "$vpndir/client.conf"
client
remote localhost 10000
dev tap
proto udp
resolv-retry infinite
nobind
persist-key
persist-tun
cipher AES-256-CBC
verb 3
auth-user-pass
EOM

# Get certificate into file
echo "<ca>" >> "$vpndir/client.conf"
cat "$dir/g1/vpn/vpn_1/ca.crt" >> "$vpndir/client.conf"
echo "</ca>" >> "$vpndir/client.conf"

# Get credentials
user="group1"
passwd=$(cat "$dir/ssh_passwords.txt" | tr -s ' ' | cut -d ' ' -f2)
cat << EOM > "$vpndir/credentials.txt"
$user
$passwd
EOM

# Create a connect script
cat << EOM > "$vpndir/connect.sh"
#!/bin/bash

cur_dir="\$( cd "\$( dirname "\${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

sudo openvpn --config "\$cur_dir/client.conf" --auth-user-pass "\$cur_dir/credentials.txt"
EOM
chmod +x "$vpndir/connect.sh"
