#!/bin/bash

VENET_DEV=venet0

if [ -z "${IP_ADDR}" ]; then
  echo "No IP address set, aborting add-ip script"
  exit 0
fi

ip addr flush dev ${VENET_DEV}
ip addr add ${IP_ADDR} dev ${VENET_DEV}
ifconfig venet0 up
ip route flush all
ip route add ${FAKEGATEWAY} dev ${VENET_DEV} scope link
ip route add default via ${FAKEGATEWAY} dev ${VENET_DEV} src ${IP_ADDR}

exit 0
