import json
import sys
import random
import requests
import subprocess
import argparse

def send_notification(title, content, group_nb):
    url = # SET YOUR WEBHOOK URL HERE!!
    message = (content)
    title = (":male-detective: Group {}: {} :zap:".format(group_nb, title))
    slack_data = {
        "username": "Mini-Internet Robot",
        "icon_emoji": ":male-detective:",
        #"channel" : "#somerandomcahnnel",
        "attachments": [
            {
                "color": "#9733EE",
                "fields": [
                    {
                        "title": title,
                        "value": message,
                        "short": "false",
                    }
                ]
            }
        ]
    }
    headers = {'Content-Type': "application/json"}
    response = requests.post(url, data=json.dumps(slack_data), headers=headers)
    if response.status_code != 200:
        raise Exception(response.status_code, response.text)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('nb_proc_threshold', type=str, default=50, help='Threshold above which a slack warning will be triggered')

    args = parser.parse_args()
    nb_proc_threshold = int(args.nb_proc_threshold)

    # Get the list of running SSH container
    ps = subprocess.run(['docker', 'ps', '--format', '{{.ID}},{{.Names}}', '--filter', 'ancestor=miniinterneteth/d_ssh'], capture_output=True)
    ps.check_returncode()

    cid2group = {} # Container ID to group
    groups = {} # Running processes in the SSH container for every group
    idlen = 0

    for line in ps.stdout.decode().split('\n'):
        if line == '':
            continue

        # Initialization
        cid, name = line.split(',')
        group = name.split('_')[0]
        groups[cid] = 0
        cid2group[cid] = group

        # Update the ID length and make sure the ID length is always identical across containers
        if idlen == 0:
            idlen = len(cid)
        else:
            assert idlen == len(cid)

    assert idlen > 0

    # Get all the control group of every running process in the server
    ps = subprocess.run(['ps', '-A', '-o', 'cgname'], capture_output=True)
    ps.check_returncode()

    for line in ps.stdout.decode().split('\n'):
        if line == '-':
            continue

        # Check if this process is for a docker container
        if line[:16] != 'systemd:/docker/':
            continue

        # Go to the container ID in the string
        cid = line[16:16+idlen]

        # Increment the number of running processes for that ssh container
        if cid in groups:
            groups[cid] += 1

    # Check containers that have more than the threshold number of running processes
    for cid, nb_proc in groups.items():
        if nb_proc >= nb_proc_threshold:
            print ('send_notification: {} nb_proc: {}'.format(cid2group[cid], nb_proc))
            send_notification("Warning SSH container", 'There are {} processes running in your SSH container.\nThis is too high, please fix this.'.format(nb_proc), cid2group[cid])

        

