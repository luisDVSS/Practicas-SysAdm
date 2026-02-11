#!/bin/bash
ipToint() {
 local  IFS=.
 read -r a b c d <<< "$1"
 echo $(( (a<<24) + (b<<16) + (c<<8) + d))
}

isInt() {
	[[ "$1" =~ ^[0-9]+$ ]]
}



mismo_segmentos(){
	ip1=$(ipToint "$1")
	ip2=$(ipToint "$2")
	mask=$(ipToint "$3")
	if (( (ip1 & mask) == (ip2 & mask) )); then
		return 0
	else
		return 1
	fi
}
