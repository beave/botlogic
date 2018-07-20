#!/bin/bash

##############################################################################
# Copyright (C) 2018 Botlogic LLC <botlogic.io>
# By "Da Beave" (beave@botlogic.io) 
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License Version 2 as
# published by the Free Software Foundation.  You may not use, modify or
# distribute this program under any other version of the GNU General
# Public License.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
##############################################################################

###############################################################################
# poster.sh - Simple shell script that gets data from the "bot.twitter" via 
# the "data_pull.pl" program and sends messages to Twitter users. The shell
# script picks a random sleep time between tweets.  We do this to avoid 
# detection by the Twitter anti-abuse system.
# 
# Usage:
# ./poster.sh {twitter username} {twitter password}
#
###############################################################################

# Sanity check.

if [ "$1" == "" ]; then
	echo "No username!";
	exit 1;
	fi

if [ "$2" == "" ]; then
        echo "No password!";
        exit 1;
        fi

while true
do

./data_pull.pl fakenews | ./nittwit --username=$1 --password=$2 --verbose --cookie=$1\.cookie
r=$(( $RANDOM % 1600 + 2000 ))
echo "[*] Sleeping $r"
sleep $r

./data_pull.pl bot | ./nittwit --username=$1 --password=$2 --verbose --cookie=$1\.cookie
r=$(( $RANDOM % 1600 + 2000 ))
echo "[*] Sleeping $r"
sleep $r

./data_pull.pl hatespeech | ./nittwit --username=$1 --password=$2 --verbose --cookie=$1\.cookie
r=$(( $RANDOM % 1600 + 2000 ))
echo "[*] Sleeping $r"
sleep $r

done
