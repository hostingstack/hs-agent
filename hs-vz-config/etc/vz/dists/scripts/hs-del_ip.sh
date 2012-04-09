#!/bin/bash

VENET_DEV=venet0

ip route del default via ${FAKEGATEWAY} dev ${VENET_DEV} src ${IP_ADDR}
ip addr del ${IP_ADDR} dev ${VENET_DEV}

exit 0
