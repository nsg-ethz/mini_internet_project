import json
import sys
import random
import requests
import subprocess
import argparse

def send_notification(title, content, group_nb):
    url = "https://hooks.slack.com/services/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"
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
    byte_length = str(sys.getsizeof(slack_data))
    headers = {'Content-Type': "application/json", 'Content-Length': byte_length}
    response = requests.post(url, data=json.dumps(slack_data), headers=headers)
    if response.status_code != 200:
        raise Exception(response.status_code, response.text)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('ASconfig_file', type=str, default='../../config/AS_config.txt', help='AS Config file')
    parser.add_argument('nb_proc_threshold', type=str, default=50, help='Threshold above which a slack warning will be triggered')

    args = parser.parse_args()
    config_file = args.ASconfig_file
    nb_proc_threshold = int(args.nb_proc_threshold)

    as_list = []
    
    with open(config_file, 'r') as fd:
        for line in fd.readlines(): 
            linetab = line.rstrip('\n').split('\t')
            asn = int(linetab[0])
            astype = linetab[1]

            if astype == 'AS':
                as_list.append(asn)

    for asn in as_list:
        process = subprocess.Popen(['docker', 'exec', '-it', '{}_ssh'.format(asn), 'ps'],
                            stdout=subprocess.PIPE, 
                            stderr=subprocess.PIPE)
        stdout, stderr = process.communicate()
        nb_proc = stdout.decode('ascii').count('\n')
        if nb_proc >= nb_proc_threshold:
            print ('send_notification: {} nb_proc: {}'.format(asn, nb_proc))
            send_notification("Warning SSH container", '<@U01LPJ0PPPW>: There are {} processes running in your SSH container.\nThis is too high, please fix this.'.format(nb_proc), asn)