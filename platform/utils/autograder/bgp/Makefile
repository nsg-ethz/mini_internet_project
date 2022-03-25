.PHONY: all dbs clean

all: runner

runner: runner.go
	go build runner.go

dbs:
	rm -f links.db ovs.db bgp.db config.db
	python3 make_db.py ../../../config
	sudo bash getlinks.sh ${USER}
	sudo bash parse_ovs.sh ${USER}
	python3 make_db_useful.py

clean:
	rm runner scapy*.conf exabgp*.conf
