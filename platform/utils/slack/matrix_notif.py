import requests
import urllib.request
import json
import time

# This function sends a notification to the routing_project channel that indicates the connectivity score.
def send_notification(content):
    url = "https://hooks.slack.com/services/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"
    title = (":male-detective: Daily report")
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
                        "value": content,
                        "short": "false",
                    }
                ]
            }
        ]
    }
    byte_length = str(len(json.dumps(slack_data)))
    headers = {'Content-Type': "application/json", 'Content-Length': byte_length}
    response = requests.post(url, data=json.dumps(slack_data), headers=headers)
    if response.status_code != 200:
        raise Exception(response.status_code, response.text)

while True:

    # Reads the raw matrix
    fp = urllib.request.urlopen("https://duvel.ethz.ch/matrix?raw")
    mybytes = fp.read()

    matrix_source = mybytes.decode("utf8")
    json_data = json.loads(matrix_source)

    # List with all the ASes
    as_list = json_data['connectivity'].keys()

    # Connectivity dictionnary
    co_dic = dict.fromkeys(as_list)

    nb_co = 0.
    nb_deco = 0.
    nb_co_invalid = 0.

    # Collect validity and connectivity for every pair of ASes.
    for fromg in json_data['connectivity']:
        co_dic[fromg] = dict.fromkeys(as_list)

        for tog, connectivity in json_data['connectivity'][fromg].items():
            if connectivity:
                try:
                    if json_data['validity'][fromg][tog]:
                        nb_co += 1.
                    else:
                        nb_co_invalid += 1.

                except:
                        nb_co += 1.
                
            elif not connectivity:
                nb_deco += 1.

    total = nb_co+nb_deco+nb_co_invalid
    content = '\n\n:white_check_mark: *{}%* of the AS pairs can reach each other with a valid path.\n\
    :warning: *{}%* can reach each other with an invalid path.\n\
    :no_entry: *{}%* cannot reach each other. \n\nKeep up the good work! :muscle:'\
    .format("%.2f" % (nb_co/total*100), "%.2f" % (nb_co_invalid/total*100), "%.2f" % (nb_deco/total*100))

    send_notification(str(content))

    time.sleep(86400)