FROM d_base:latest

RUN apk add --no-cache tmux

COPY ping.py /home/ping.py
RUN chmod +x /home/ping.py

CMD ["tail", "-f", "/dev/null"]
