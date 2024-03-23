# Start from an image with the docker client installed
FROM docker:26.0.0-cli-alpine3.19

# Install python
RUN apk add --no-cache python3 bash uuidgen git

# Autoconfirm new git hosts
RUN git config --global core.sshCommand "ssh -o StrictHostKeyChecking=no"
RUN git config --global init.defaultBranch main

# Copy files
COPY update_history.py /home/update_history.py
COPY update_history.sh /home/update_history.sh

WORKDIR /home
CMD ["python3", "update_history.py"]
