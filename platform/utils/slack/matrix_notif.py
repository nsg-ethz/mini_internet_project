import requests
import urllib.request

# This function sends a notification to the routing_project that indicates the connectivity score.
def send_notification(title, content):
    url = "https://hooks.slack.com/services/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"
    message = (content)
    title = (":male-detective: Connectivity daily report :zap:")
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
    byte_length = len(json.dumps(slack_data))
    headers = {'Content-Type': "application/json", 'Content-Length': byte_length}
    response = requests.post(url, data=json.dumps(slack_data), headers=headers)
    if response.status_code != 200:
        raise Exception(response.status_code, response.text)

# Reads the raw matrix
fp = urllib.request.urlopen("https://duvel.ethz.ch/matrix?raw")
mybytes = fp.read()

matrix_source = mybytes.decode("utf8")
print (matrix_source)