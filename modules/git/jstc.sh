#!/bin/bash

declare -A authorMap

CUR_DIR=`pwd`
BLD_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

LOGS=`git log --format='%an' --author="intel" --since "Jun 1 2019"`
while read -r author
do
		author=`echo ${author} | tr -d '[:space:]'`
		count=authorMap["${author}"]
		if [ ${count}"X" == "X" ]; then
				count=0
		else
				count=$((count+1))
		fi
		authorMap["${author}"]=${count}
		total=$((total+1))
done <<< ${LOGS}

echo -e "Total Patch # is:${total}"
for author in "${!authorMap[@]}"
do
		echo -e "\t${author:0:6}\t:${authorMap[${author}]}"
done

