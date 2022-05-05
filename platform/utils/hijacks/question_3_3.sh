#!/bin/bash

source ./utils/hijacks/hijack.sh

# Write --clear to undo the hijack.
params="--clear "

seq=100
for asn in 3 5 7 9 11; do
    run_hijack 71 $asn.0.0.0/8 $seq --origin_as $asn $params
    seq=$((seq+1))
done

seq=10
for asn in 4 6 8 10 12; do
    run_hijack 72 $asn.0.0.0/8 $seq --origin_as $asn $params
    seq=$((seq+1))
done

seq=10
for asn in 24 26 28 30; do
    run_hijack 92 $asn.0.0.0/8 $seq --origin_as $asn $params
    seq=$((seq+1))
done

seq=10
for asn in 23 25 27 29; do
    run_hijack 91 $asn.0.0.0/8 $seq --origin_as $asn $params
    seq=$((seq+1))
done

seq=10
for asn in 44 46 48 50 52; do
    run_hijack 112 $asn.0.0.0/8 $seq --origin_as $asn $params
    seq=$((seq+1))
done

seq=10
for asn in 43 45 47 49 51; do
    run_hijack 111 $asn.0.0.0/8 $seq --origin_as $asn $params
    seq=$((seq+1))
done

seq=10
for asn in 64 66 68 70; do
    run_hijack 14 $asn.0.0.0/8 $seq --origin_as $asn $params
    seq=$((seq+1))
done

seq=10
for asn in 63 65 67 69; do
    run_hijack 13 $asn.0.0.0/8 $seq --origin_as $asn $params
    seq=$((seq+1))
done

seq=10
for asn in 84 86 88 90; do
    run_hijack 32 $asn.0.0.0/8 $seq --origin_as $asn $params
    seq=$((seq+1))
done

seq=10
for asn in 83 85 87 89; do
    run_hijack 31 $asn.0.0.0/8 $seq --origin_as $asn $params
    seq=$((seq+1))
done

seq=10
for asn in 104 106 108 110; do
    run_hijack 54 $asn.0.0.0/8 $seq --origin_as $asn $params
    seq=$((seq+1))
done

seq=10
for asn in 103 105 107 109; do
    run_hijack 53 $asn.0.0.0/8 $seq --origin_as $asn $params
    seq=$((seq+1))
done