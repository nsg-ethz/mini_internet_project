FROM python:3

# We require libev-dev for the bjoern WSGI server.
RUN apt-get update && apt-get install -y libev-dev

COPY server /server
RUN pip install -e /server

CMD ["python3", "/server/run.py", "/server/config.py"]
