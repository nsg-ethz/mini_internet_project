import bjoern
import random
import string
from flask import request, render_template
from flask import Flask



def create_app():
    app = Flask(__name__,template_folder='/server/')

    @app.route('/')
    def return_secret():
        ip = request.remote_addr
        print(ip)
        group_number = int(ip.split(".")[0])
        router_no = int(ip.split(".")[1])
        subnet = int(ip.split(".")[2])
        if subnet == 10 and router_no >= 101 and router_no <= 108:
            random.seed(group_number)
            random_string = ''.join(random.choice(string.ascii_uppercase + string.digits) for _ in range(20))
            print(random_string)
            
            response = [f'Hello, Group {group_number}', 'I see you managed to find the VPN, well done.',  f'Here is your secret:', f'{random_string}']
        else:
            response = [f'Hello, Group {group_number}', 'Please try again using the VPN']
        return render_template('./vpnsecret.html', response=response)
    
    
    return app
        



if __name__ == "__main__":
    app = create_app()
    host = "0.0.0.0"
    port = 80
    print(f"Running server on `{host}:{port}`.")
    bjoern.run(app, host, port)
