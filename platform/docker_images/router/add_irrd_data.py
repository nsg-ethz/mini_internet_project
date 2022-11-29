import argparse
import json
import requests

from datetime import datetime
from passlib.hash import md5_crypt

if __name__ == '__main__':
    parser = argparse.ArgumentParser(prog='python ./add_irrd_data.py', description='IRRd helper for object creation')
    parser.add_argument('-H', '--host', type=str, default='http://host-ZURI.group2:8080/v1/submit/', help='Host with the server running IRRd')
    parser.add_argument('-j', '--json', action='store_true', help='Export the JSON file, do not update on server')
    parser.add_argument('-o', '--override', type=str, help='Use an override password (only for TAs)')
    parser.add_argument('-d', '--delete', action='store_true', help='Delete the object. Configure as normal, but the object will be deleted')
    parser.add_argument('object',
            choices=['mntner', 'route', 'as-set', 'aut-num', 'person'],
            type=str, help='Object which you want to create / modify')

    args = parser.parse_args()
    host = args.host
    object = args.object

    request = {}
    attributes = []
    list_objects = [{'attributes': attributes}]
    request['objects']=list_objects


    if object == 'mntner':
        # Read in necessary inputs for mntner objects
        mntner = input("Please enter the name of the maintainer you want \nto update (e.g. MAINT-GROUP-3456):\n")
        admin_c = input("Please enter the related person (usually GROUP-X):\n")
        descr = input("Please enter the description for the mntner:\n")
        e_mail = input("Please enter the related e-mail:\n")
        password = input("Please enter your maintainer password (usually the SSH password provided):\n")

        # Rehash the password
        # In case it is wrong, it will not get updated anyway
        hash_pw = md5_crypt.hash(password)

        # Add attributes into data structure
        attributes.append({'name': 'mntner', 'value': mntner})
        attributes.append({'name': 'descr', 'value': descr})
        attributes.append({'name': 'tech-c', 'value': admin_c})
        attributes.append({'name': 'admin-c', 'value': admin_c})
        attributes.append({'name': 'upd-to', 'value': e_mail})
        attributes.append({'name': 'mnt-nfy', 'value': e_mail})
        attributes.append({'name': 'notify', 'value': e_mail})
        attributes.append({'name': 'changed', 'value': '{} {}'.format(e_mail, datetime.today().strftime('%Y%m%d'))})
        attributes.append({'name': 'source', 'value': 'AUTHDATABASE'})
        attributes.append({'name': 'mnt-by', 'value': mntner})
        attributes.append({'name': 'auth', 'value': 'MD5-PW {}'.format(hash_pw)})
    elif object == 'route':
        route = input("Please enter the prefix you want to add (e.g. X.X.X.0/24):\n")
        origin = input("Please enter the origin AS for that route (e.g. AS3456):\n")
        mntner = input("Please enter the maintainer for this route object (e.g. MAINT-GROUP-X):\n")
        password = input("Please enter your maintainer password (usually the SSH password provided):\n")

        attributes.append({'name': 'route', 'value': route})
        attributes.append({'name': 'origin', 'value': origin})
        attributes.append({'name': 'mnt-by', 'value': mntner})
        attributes.append({'name': 'source', 'value': 'AUTHDATABASE'})

    elif object == 'as-set':
        name = input("Please enter the name of the AS-SET (e.g. ASX:AS-CUSTOMERS):\n")
        members = input("Please enter the members of the AS-SET (e.g. AS3456, AS3456:AS-CUSTOMERS):\n")
        mntner = input("Please enter the maintainer for this as-set object (e.g. MAINT-GROUP-X):\n")
        password = input("Please enter your maintainer password (usually the SSH password provided):\n")

        attributes.append({'name': 'as-set', 'value': name})
        attributes.append({'name': 'members', 'value': members})
        attributes.append({'name': 'mnt-by', 'value': mntner})
        attributes.append({'name': 'source', 'value': 'AUTHDATABASE'})

    elif object == 'aut-num':
        as_nr = input("Please enter your AS number (e.g. AS3456):\n")
        name = input("Please enter the name of your AS (e.g. SWISSCOM, GROUP-X):\n")
        mntner = input("Please enter the maintainer for this aut-num object (e.g. MAINT-GROUP-X):\n")
        admin_c = input("Please enter the related person (usually GROUP-X):\n")

        attributes.append({'name': 'aut-num', 'value': as_nr})
        attributes.append({'name': 'as-name', 'value': name})
        attributes.append({'name': 'mnt-by', 'value': mntner})
        attributes.append({'name': 'tech-c', 'value': admin_c})
        attributes.append({'name': 'admin-c', 'value': admin_c})
        attributes.append({'name': 'source', 'value': 'AUTHDATABASE'})

        # As we can have multiple imports / exports, this needs to be possible as well
        imports = input("How many route imports do you want to enter?\nYou can find examples in the IRRd for one of the TA-maintained AS\n")
        for i in range(0, int(imports)):
            imp = input("Enter your import here:\n")
            attributes.append({'name': 'import', 'value': imp})

        exports = input("How many route exports do you want to enter?\n")
        for i in range(0, int(exports)):
            exp = input("Enter your export here:\n")
            attributes.append({'name': 'export', 'value': exp})

        password = input("Please enter your maintainer password (usually the SSH password provided):\n")
    elif object == 'person':
        name = input("Please enter the name of the person (e.g. Urs Mustermann, Group X):\n")
        nichdl = input("Please enter the nickname of the person (e.g. GROUP-X):\n")
        address = input("Please enter the address of the person (e.g. ETH Zurich):\n")
        email = input("Please enter the email of the person:\n")
        phone = input("Please enter the phone number of the person:\n")
        mntner = input("Please enter the maintainer for this person object (e.g. MAINT-GROUP-X):\n")
        password = input("Please enter your maintainer password (usually the SSH password provided):\n")

        attributes.append({'name': 'person', 'value': name})
        attributes.append({'name': 'nic-hdl', 'value': nichdl})
        attributes.append({'name': 'address', 'value': address})
        attributes.append({'name': 'e-mail', 'value': email})
        attributes.append({'name': 'phone', 'value': phone})
        attributes.append({'name': 'mnt-by', 'value': mntner})
        attributes.append({'name': 'source', 'value': 'AUTHDATABASE'})


    # Add the password to the request
    request['passwords'] = [password]

    # In case an override password is provided, use it
    if args.override:
        request['override'] = args.override

    if args.json:
        with open('config.json', 'w') as text_file:
            text_file.write(json.dumps(request, indent=4))
    else:
        if args.delete:
            server_reply = requests.delete(host, data=json.dumps(request))
        else:
            server_reply = requests.post(host, json=request)

        if server_reply.status_code == 200:
            reply_json = server_reply.json()
            if reply_json['objects'][0]['successful']:
                print("Request successful")
            else:
                print(reply_json['objects'][0]['error_messages'][0])
        else:
            print(server_reply.text)

