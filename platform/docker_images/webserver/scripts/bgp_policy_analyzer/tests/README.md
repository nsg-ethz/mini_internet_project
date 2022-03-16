# Test cases

## Structure
Each of the test?? folders contains three directories and one file:

 - `config`: The configuration of the network.  Only requires
   `external_links_config.txt` for now.
 - `lg_good`: Looking glass files (txt and json) for the correct network
   configuration.
 - `lg_bad`: Looking glass files (txt and json) for the incorrect network
   configuration.
 - `lg_expected`: The expected `stderr` output

The tests can be run by executing `run.sh` from the directory containing
`cfparse.py`, `lgparse.py` and `lganalyze`.

If one of the test cases fail, `run.sh` exits and the captured output and
database file is left in the directory of `run.sh` for further inspection.

### Test 1
Config: 6 AS

Misconfiguration: AS 3 exports all routes to AS 2.

Commands:
```
(AS 3)
root@g3-proxy:~# ./goto.sh ZURI router

Hello, this is FRRouting (version 7.2.1).
Copyright 1996-2005 Kunihiro Ishiguro, et al.

ZURI_router# conf t
ZURI_router(config)# route-map LOCAL_PREF_OUT_2 permit 10
ZURI_router(config-route-map)# no match community 1
```

### Test 2
Config: 6 AS

Misconfiguration: AS 3 blocks exporting routes learned from customers to AS 2.

Commands:
```
(AS 3)
root@g3-proxy:~# ./goto.sh ZURI router

Hello, this is FRRouting (version 7.2.1).
Copyright 1996-2005 Kunihiro Ishiguro, et al.

ZURI_router# conf t
ZURI_router(config)# route-map LOCAL_PREF_OUT_2 permit 10
ZURI_router(config-route-map)# match community 10
```

### Test 3
Config: 6 AS

Misconfiguration: AS 5 is not exporting its own routes to AS 4.

Commands:
```
(AS 5)
root@g5-proxy:~# ./goto.sh ZURI router

Hello, this is FRRouting (version 7.2.1).
Copyright 1996-2005 Kunihiro Ishiguro, et al.

ZURI_router# conf t
ZURI_router(config)# route-map LOCAL_PREF_OUT_4 permit 5
ZURI_router(config-route-map)# match community 10
```

### Test 4
Config: 6 AS

Misconfiguration: AS 2 is not exporting any routes to AS 3, AS 4 is not
exporting any routes to AS 5.

Commands:
```
(AS 2)
root@g2-proxy:~# ./goto.sh ZURI router

Hello, this is FRRouting (version 7.2.1).
Copyright 1996-2005 Kunihiro Ishiguro, et al.

ZURI_router# conf t
ZURI_router(config)# route-map LOCAL_PREF_OUT_3 permit 5
ZURI_router(config-route-map)# match community 10
ZURI_router(config-route-map)# exit
ZURI_router(config)# route-map LOCAL_PREF_OUT_3 permit 10
ZURI_router(config-route-map)# match community 10
(AS 4)
root@g4-proxy:~# ./goto.sh ATLA router

Hello, this is FRRouting (version 7.2.1).
Copyright 1996-2005 Kunihiro Ishiguro, et al.

ATLA_router# conf t
ATLA_router(config)# route-map LOCAL_PREF_OUT_5 permit 5
ATLA_router(config-route-map)# match community 10
ATLA_router(config-route-map)# exit
ATLA_router(config)# route-map LOCAL_PREF_OUT_5 permit 10
ATLA_router(config-route-map)# match community 10
```

### Test 5
Config: 9 AS

Misconfiguration: AS 3 is exporting routes to AS 5 via the IXP

Commands:
```
(AS 3)
root@g3-proxy:~# ./goto.sh NEWY router

Hello, this is FRRouting (version 7.2.1).
Copyright 1996-2005 Kunihiro Ishiguro, et al.

NEWY_router# conf t
NEWY_router(config)# route-map IXP_OUT_121 permit 10
NEWY_router(config-route-map)# set community 121:5 121:7 121:8 121:9
NEWY_router(config-route-map)# exit
NEWY_router(config)# route-map IXP_OUT_121 permit 20
NEWY_router(config-route-map)# set community 121:5 121:7 121:8 121:9
```

### Test 6
Config: 6 AS

Misconfiguration: AS is not exporting any routes to AS 3.

Commands:
```
(AS 4)
root@g4-proxy:~# ./goto.sh PARI router

Hello, this is FRRouting (version 7.2.1).
Copyright 1996-2005 Kunihiro Ishiguro, et al.

PARI_router# conf t
PARI_router(config)# route-map LOCAL_PREF_OUT_3 permit 10
PARI_router(config-route-map)# match community 10
PARI_router(config-route-map)# exit
PARI_router(config)# route-map LOCAL_PREF_OUT_3 permit 5
PARI_router(config-route-map)# match community 10
```

### Test 7
Config: 6 AS

Misconfiguration: ASes set too high local-preferences for peers and providers
coupled with strange export rules.

Commands:
```
(AS 3)
root@g3-proxy:~# ./goto.sh PARI router

Hello, this is FRRouting (version 7.2.1).
Copyright 1996-2005 Kunihiro Ishiguro, et al.

PARI_router# conf
PARI_router(config)# route-map LOCAL_PREF_IN_4 permit 10
PARI_router(config-route-map)# set local-preference 150
(AS 5)
root@g5-proxy:~# ./goto.sh ZURI router

Hello, this is FRRouting (version 7.2.1).
Copyright 1996-2005 Kunihiro Ishiguro, et al.

ZURI_router# conf t
ZURI_router(config)# route-map LOCAL_PREF_IN_3 permit 10
ZURI_router(config-route-map)# set local-preference 100
ZURI_router(config-route-map)# exit
ZURI_router(config)# route-map LOCAL_PREF_IN_4 permit 10
ZURI_router(config-route-map)# set local-preference 100
(AS 4)
root@g4-proxy:~# ./goto.sh BOST router

Hello, this is FRRouting (version 7.2.1).
Copyright 1996-2005 Kunihiro Ishiguro, et al.

BOST_router# conf t
BOST_router(config)# route-map LOCAL_PREF_IN_2 permit 10
BOST_router(config-route-map)# set local-preference 150
BOST_router(config-route-map)#
Connection to 158.4.15.1 closed.
root@g4-proxy:~# ./goto.sh LOND router

Hello, this is FRRouting (version 7.2.1).
Copyright 1996-2005 Kunihiro Ishiguro, et al.

LOND_router# conf t
LOND_router(config)# route-map LOCAL_PREF_IN_2 permit 10
LOND_router(config-route-map)# set local-preference 150
LOND_router(config-route-map)#
Connection to 158.4.10.1 closed.
root@g4-proxy:~# ./goto.sh ZURI router

Hello, this is FRRouting (version 7.2.1).
Copyright 1996-2005 Kunihiro Ishiguro, et al.

ZURI_router# conf t
ZURI_router(config)# route-map LOCAL_PREF_IN_1 permit 10
ZURI_router(config-route-map)# set local-preference 10
(AS 5)

root@g5-proxy:~# ./goto.sh ZURI router

Hello, this is FRRouting (version 7.2.1).
Copyright 1996-2005 Kunihiro Ishiguro, et al.

ZURI_router# conf t
ZURI_router(config)# route-map LOCAL_PREF_OUT_4 permit 5
ZURI_router(config-route-map)# match community 10
(AS 6)
root@g6-proxy:~# ./goto.sh ZURI router

Hello, this is FRRouting (version 7.2.1).
Copyright 1996-2005 Kunihiro Ishiguro, et al.

ZURI_router# conf t
ZURI_router(config)# route-map LOCAL_PREF_OUT_4 permit 5
ZURI_router(config-route-map)# match community 10
```

### Test 8
Config: 9 AS

Misconfiguration: AS 4 does not filter outgoing routes to peer AS 3

Commands:
```
root@g4-proxy:~# ./goto.sh PARI router

Hello, this is FRRouting (version 7.2.1).
Copyright 1996-2005 Kunihiro Ishiguro, et al.

PARI_router# conf t
PARI_router(config)# route-map LOCAL_PREF_OUT_3 permit 10
PARI_router(config-route-map)# no match community 1
```
