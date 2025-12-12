import bjoern
import random
from flask import request
from flask import Flask



def create_app():
    app = Flask(__name__)

    @app.route('/')
    def return_secret():
        ip = request.remote_addr
        print(ip)
        group_number = int(ip.split(".")[0])
        router_no = int(ip.split(".")[1])
        if router_no >= 0 and router_no <= 50:
            random.seed(group_number)
            random_string = ''.join(random.choice(string.ascii_uppercase + string.digits) for _ in range(20))
            print(random_string)
            return f'Hello, Group {group_number} I see you managed to find the VPN good job. Here is your secret: {random_string}'
        else:
            return f'Hello, Group {group_number} Please try again using the VPN'
    
    
    return app
        



if __name__ == "__main__":
    app = create_app()
    host = "0.0.0.0"
    port = 80
    print(f"Running server on `{host}:{port}`.")
    bjoern.run(app, host, port)
