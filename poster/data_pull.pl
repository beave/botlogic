#!/usr/bin/perl

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

################################################################################
# data_pull.pl - This randomly pulls a Twitter account from the twitter.bot
# database.  It returns a randomly selected tweet to send (based on the bot.conf
# file) to send.  This is done to evade Twitter anti-abuse deteection.
################################################################################

use Term::ANSIColor qw(:constants);
use Config::Tiny; 
use DBI;

# Limits for IDs. 

my $lower_limit = 10;
my $upper_limit = 999999;

my $seconds = 43200;		# How far to search back.  

# What "type" of target Twitter account are we going after.

if ( $ARGV[0] eq "fakenews" )  {
	$type = 1; 
	} 

elsif ( $ARGV[0] eq "hatespeech" ) {
	$type = 2; 
	}

elsif ( $ARGV[0] eq "bot" ) {
	$type = 3; 
	} 

# Sanity check

elsif ( $ARGV[0] ne "fakenews" || $ARGV[0] ne "hatespeech" || $ARGV[0] ne "bot" ) {
	die "Invalid type!\n"; 
	}


# Open our configuration file and pull in into memory.

my $config_file = "/home/bot/bot.conf";
die "$config_file is missing\n" if not -e $config_file;
my $config = Config::Tiny->read( $config_file, 'utf8' );

# Load "posting" messages from our configation file.

my @fake_news = split(',',$config->{Bot_Poster_Data}{fake_news});
my @hate_speech = split(',',$config->{Bot_Poster_Data}{hate_speech});
my @bot = split(',',$config->{Bot_Poster_Data}{bot});

# Get count of the array. 

my $fake_news_total = scalar(@fake_news);
my $hate_speech_total = scalar(@hate_speech);
my $bot_total = scalar(@bot);

# Connect to MySQL database.

my $db  = "DBI:mysql:database=$config->{MySQL}{mysql_database};host=$config->{MySQL}{mysql_host}";
my $dbh = DBI ->connect($db, $config->{MySQL}{mysql_user}, $config->{MySQL}{mysql_password}) || die "[
E] Cannot connect to MySQL.\n";

# Find our target user! 

$sql = "SELECT id, type, tweet_id, sha1, screen_name, text, score, score_text FROM twitter WHERE unix_timestamp(found_timestamp) > ( unix_timestamp(now()) - $seconds ) AND type = $type AND phone_code IS NULL LIMIT 1";

$tsql = $dbh->prepare($sql);
$tsql->execute || die "[E] $DBI::errstr\n";
@sqloutn=$tsql->fetchrow_array;

$id = $sqloutn[0];
$type = $sqloutn[1];
$tweet_id = $sqloutn[2];
$sha1 = $sqloutn[3];
$screen_name = $sqloutn[4];
$tweet = $sqloutn[5];
$score = $sqloutn[6];
$score_text = $sqloutn[7];

# Build the message we want to send based on the bot.conf and the type.

if ( $type == 1 ) { 

$ran = int rand $fake_news_total; 
$send_link = "\@$screen_name  $fake_news[$ran] https://botlogic.io/?id=$id&v=$sha1";
}

elsif ( $type == 2 ) { 
	
$ran = int rand $hate_speech_total; 
$send_link = "\@$screen_name  $hate_speech[$ran] https://botlogic.io/?id=$id&v=$sha1";
}

elsif ( $type == 3 ) { 
	
$ran = int rand $bot_total; 	
$send_link = "\@$screen_name  $bot[$ran] https://botlogic.io/?id=$id&v=$sha1";
}

# Store the link we've sent to the target. 

$sql_response = "UPDATE twitter SET twitter_response = ? WHERE id = ?";
$rsql = $dbh->prepare($sql_response);
$rsql->bind_param(1, $send_link);
$rsql->bind_param(2, $id);
$rsql->execute || die "[E] $DBI::errstr\n";


        $flag = 0;

	# We now need to create a unique "phone code" for the targetted Twitter
	# account.  If they click on the link, this will give the target a "code"
	# they can enter which we can use to identify them.
                
        while ( $flag == 0 ) {

                $random_number = int(rand($upper_limit-$lower_limit)) + $lower_limit;
                
                $sql_phone = "SELECT count(id) FROM twitter WHERE phone_code = ?";
                $psql = $dbh->prepare($sql_phone);
                $psql->bind_param(1, $random_number);
                $psql->execute || die "[E] $DBI::errstr\n";
                @phone_out = $psql->fetchrow_array;

                if ( $phone_out[0] == 0 )
                        {
                        $flag = 1;
                        }
                }

	# Store the phone code.
	
        $sql_phone = "UPDATE twitter SET phone_code = ? WHERE id = ?";
        $psql = $dbh->prepare($sql_phone);
        $psql->bind_param(1, $random_number);
        $psql->bind_param(2, $id);
        $psql->execute || die "[E] $DBI::errstr\n";


# Output the final link! Done.

print "$send_link\n";
