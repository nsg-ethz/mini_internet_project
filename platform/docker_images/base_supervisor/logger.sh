#!/bin/bash
#
# Print all supervisord process log files to the console, so that they can be
# viewed with docker logs.
# Reference: https://unix.stackexchange.com/a/195930/403687

cd /var/log/supervisor

touch ./supervisord.log

tail -f *.log | 
    gawk '/^==> / {
            filename=substr($0, 5, length-12)
            result=match(filename, /^(.+)-std(out|err){1}---supervisor-(.{8})/, arr)
            if (result != 0) {
                if (arr[2] == "err")
                    level="\033[0;31m"toupper(arr[2])"\033[0m"
                else if (arr[2] == "out")
                    level="LOG"
                else
                    level=toupper(arr[2])
                process_id=arr[3]
                process_name=arr[1]
                prefix=level" "process_name" ["process_id"]"
            } else {
                level="LOG"
                process_name=filename
                prefix=level" "process_name
            }
            next
          }
          {print prefix":  "$0}'
