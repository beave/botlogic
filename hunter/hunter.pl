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

use warnings;
use 5.010;
 
use Net::Twitter;
use Config::Tiny;
use Data::Dumper qw(Dumper);
use Date::Parse;
use DBI;
use Digest::SHA qw(sha1_hex); 
use Term::ANSIColor qw(:constants);
use Lingua::Identify qw(:language_identification);
use Getopt::Long;

# Define types.  This should really be pulled from the database.

my $FAKENEWS_TYPE=1;
my $HATE_TYPE=2;
my $BOT_TYPE=3; 

# Where to store raw JSON from users 

my $fakenews_dump = "/var/www/html/fakenews";
my $hate_dump = "/var/www/html/hate";
my $bot_tested = "/var/www/html/bots"; 

my $trend_search_location = 2459115; 	# Where to search trends.  The default is NYC.

# Master configuration files.

my $config_file = "/home/bot/bot.conf"; 

die "$config_file is missing\n" if not -e $config_file;
our $config = Config::Tiny->read( $config_file, 'utf8' );

our $scanned_hit=0; 
our $scanned_missed=0; 
our $bot_hit = 0; 
our $fakenews_hit = 0; 
our $hate_hit = 0; 

my $sha1_hash;
my $tmp_text;
my $number_count;
my $tmp_screen_name;

# Command line switches. 

GetOptions ( "api_key=s"		=> \$api_key,
             "api_secret=s"      	=> \$api_secret,
             "access_token=s"          	=> \$access_token,
             "access_token_secret=s"   	=> \$access_token_secret ); 

# Sanity check of command line switches. 

if ( !$api_key ) {
	die "--api_key not specified.  Abort.\n"; 
	}

if ( !$api_secret ) { 
	die "--api_secret not specified. Abort.\n"; 
	}

if ( !$access_token ) { 
	die "--access_token not specified. Abort.\n";
	}

if ( !$access_token_secret ) { 
	die "--access_token_secret not specified. Abort.\n";
	}

# Wire in the Twitter API! 

our $nt = Net::Twitter->new(
    ssl      => 1,
    traits   => [qw/API::RESTv1_1/],
    consumer_key        => $api_key,
    consumer_secret     => $api_secret,
    access_token        => $access_token,
    access_token_secret => $access_token_secret,
);

# Connect to our database. 

my $db  = "DBI:mysql:database=$config->{MySQL}{mysql_database};host=$config->{MySQL}{mysql_host}";
my $dbh = DBI ->connect($db, $config->{MySQL}{mysql_user}, $config->{MySQL}{mysql_password}) || die "[E] Cannot connect to MySQL.\n"; 

# Clear the screen and enter the loop!  We start hunting from here!

print "\e[H\e[J"; # Clear screen

while(1) 
{

	#Web_Queue();		# This will lookup users in the web queue.  If someone
				# comes to our web site and we don't have data on the user
				# they are looking up,  this hook will scan the target 
				# Twitter screen name.
				
	Bot_Search_Trends();	# Searches trending items (set to NYC)
	Bot_Search_Keywords(); 	# Searches for pre-determined keywords.
	Fake_News();		# Searches for "fake news" domains.
	Hate_Speech(); 		# Searches for "hate speech".

	print YELLOW "[*] Loop complete! Long sleep. [". $config->{Bot_Hunter}{long_sleep} . "]\n"; 
	sleep($config->{Bot_Hunter}{long_sleep});
} 

##############################################################################
# Web_Queue - Searches for screen_names that are not found from the web site. 
# If the user looks up someone and we don't have any data on them, this 
# subroutine will do recon on that user.
##############################################################################

sub Web_Queue {

$sql = "SELECT screen_name FROM queue WHERE scanned_flag = 0";
$tsql = $dbh->prepare($sql);
$tsql->execute || die "[E] $DBI::errstr\n";

print YELLOW "[*] Reading from web queue....\n"; 

while (my(@sqloutn)=$tsql->fetchrow_array)
	{
	$screen_name = $sqloutn[0]; 

	print YELLOW "[*] Scanning '$screen_name'\n"; 

	eval { 
	my $lu_user = $nt->lookup_users({ screen_name => $screen_name });
	};

	if ( $@ eq "" ) { 

		# check here!
		$global_search = "Direct Web Search";
		my $lu_user = $nt->lookup_users({ screen_name => $screen_name });
		Insert_Scanned($lu_user->{user}{id_str}, $lu_user->{user}{screen_name}, $BOT_TYPE);
		Bot_Logic($lu_user); 
		$flag = 1; 

	} else { 

		print YELLOW "[*] No matches for '$screen_name'\n"; 
		$flag = 2; 
	}

	$sql = "UPDATE queue SET scanned_flag = ? WHERE screen_name = ?"; 
	$tsql2 = $dbh->prepare($sql);
	$tsql2->bind_param(1, $flag); 
	$tsql2->bind_param(2, $screen_name);
	$tsql2->execute || die "[E] $DBI::errstr\n";

	}
} 

##############################################################################
# Bot_Search_Trends - This searches trending hashtags to hunt for bots.  It
# searches the $trend_search_location (default == NYC).  As it find users 
# tweeting with trending hashtags,  we analyze the account.   The idea is that
# bots will follow trending hashtags to get more visibility for there message.
##############################################################################

sub Bot_Search_Trends {

my $t = $nt->trends_place({ id => $trend_search_location });

foreach $s (@ { $t })
	{

	for (my $i=0; $i <= 9; $i++)
		{

		$global_search = $s->{trends}->[$i]->{name};

		print YELLOW "[*] [$i] Searching: \"$global_search\"\n";

		my $search = $nt->search( { q => $global_search, count => 100 } );

			foreach my $s (@{ $search->{statuses} }) 
				{

				if ( Check_Scanned($s->{user}{id_str}, $BOT_TYPE) == 0 ) 
					{
					
					Insert_Scanned($s->{user}{id_str}, $s->{user}{screen_name}, $BOT_TYPE); 

					$lu_user = $nt->lookup_users({ user_id => [ $s->{user}{id} ] });
				        Bot_Logic($lu_user);
					} 

				}

#		print "\e[H\e[J"; # Clear screen
		print MAGENTA "[*] --[Status]--\n"; 
		print YELLOW "[*] Hit: $scanned_hit | Missed: $scanned_missed | Bots: $bot_hit | Fake News: $fakenews_hit | Hate: $hate_hit\n"; 
		print YELLOW "[*] Sleeping " . $config->{Bot_Hunter}{short_sleep} . "\n"; 
		sleep($config->{Bot_Hunter}{short_sleep});

		}

	}

print MAGENTA "[*] --[Status]--\n";
print YELLOW "[*] Hit: $scanned_hit | Missed: $scanned_missed | Bots: $bot_hit | Fake News: $fakenews_hit | Hate: $hate_hit\n";
print YELLOW "[*] Long Sleeping " . $config->{Bot_Hunter}{long_sleep} . "\n"; 
sleep($config->{Bot_Hunter}{long_sleep});
}

##############################################################################
# Bot_Search_Keywords - Search for pre-defined keywords in the bot.conf for
# bots.
##############################################################################

sub Bot_Search_Keywords { 

my @bot_search = split(',',$config->{Bot_Hunter}{bot_search});

foreach our $global_search (@bot_search)
{

print YELLOW "[*] Search Term: '$global_search'\n"; 

my $search = $nt->search( { q => $global_search, count => 100 } ); 

foreach my $s (@{ $search->{statuses} }) {

	if ( Check_Scanned($s->{user}{id_str}, $BOT_TYPE ) == 0 ) 
		{

		Insert_Scanned($s->{user}{id_str}, $s->{user}{screen_name}, $BOT_TYPE);

		my $lu_user = $nt->lookup_users({ user_id => [ $s->{user}{id} ] });

		Bot_Logic($lu_user); 
		
		}

	}

print MAGENTA "[*] --[Status]--\n";
print YELLOW "[*] Hit: $scanned_hit | Missed: $scanned_missed | Bots: $bot_hit | Fake News: $fakenews_hit | Hate: $hate_hit\n";
print YELLOW "[*] Sleeping " . $config->{Bot_Hunter}{short_sleep} . "\n";
sleep($config->{Bot_Hunter}{short_sleep});

}

print MAGENTA "[*] --[Status]--\n";
print YELLOW "[*] Hit: $scanned_hit | Missed: $scanned_missed | Bots: $bot_hit | Fake News: $fakenews_hit | Hate: $hate_hit\n";
print YELLOW "[*] Long sleeping " . $config->{Bot_Hunter}{long_sleep} . "\n";
sleep($config->{Bot_Hunter}{long_sleep});

}

##############################################################################
# Fake_News - Searches for known "fake news" posters.
##############################################################################

sub Fake_News { 

my @fake_news_domains = split(',', $config->{Bot_Hunter}{fake_news_domains});
foreach our $global_search (@fake_news_domains)
{

print YELLOW "[*] Searching Fake New Domain: $global_search.\n"; 

my $search = $nt->search( { q => $global_search, count => 100 } );

foreach my $s (@{ $search->{statuses} }) 
	{

	if ( Check_Scanned($s->{user}{id_str}, $FAKENEWS_TYPE ) == 0 ) 
		{

		Insert_Scanned($s->{user}{id_str}, $s->{user}{screen_name}, $FAKENEWS_TYPE);

		$user_id = $s->{user}{id};
		$screen_name = $s->{user}{screen_name}; 
		chomp($screen_name); 

		$text = $s->{text}; 
	        chomp($text);

		my $lu_user = $nt->lookup_users({ user_id => [ $s->{user}{id} ] });

		Bot_Logic($lu_user);

		for my $lu_u ( @$lu_user ) 
			{

			$flag = 0; 

			foreach my $expand (@{ $lu_u->{status}{entities}{urls} } )
				{
				$e = $expand->{expanded_url};

				if ( $e =~ m/$global_search/gi ) { 
					$flag = 1; 
					}

				}

			if ( $flag == 1 ) { 

	                print RED "[*] ----[ Fake News ]----\n";
	                print GREEN "[*] Screen Name: $screen_name\n";
	                print GREEN "[*] Search: \"$global_search\"\n";
	                print GREEN "[*] Tweet: \"$text\"\n";
			print GREEN "[*] Tweet ID: " . $lu_u->{status}{id_str} . "\n"; 


                        foreach my $expand (@{ $lu_u->{status}{entities}{urls} } )
                        {
                        $e = $expand->{expanded_url};
                        chomp($e);
			print GREEN "[*] Expanded URL: $e\n"; 
                        }

			$User_Dump_File = $fakenews_dump . "/" . $screen_name;
			open(my $USER_DUMP_FH, '>>', $User_Dump_File) || die "Can't open $User_Dump_File\n";
			$User_Dump = Dumper($lu_u); 
			print $USER_DUMP_FH $User_Dump;	
			close($USER_DUMP_FH); 

			$fakenews_hit++; 

			$sha1_hash = sha1_hex( $screen_name . $total_score . $score_text . "666");
			$tweet_sha1 = sha1_hex( $text );

			$sql = "INSERT INTO twitter (type, search, twitter_id, screen_name, name, text, location, created_at, friends_count, followers_count, lang, time_zone, source, score, sha1, tweet_id, tweet_sha1) VALUES (?, ?, ?, ?, ?, ?, ?, FROM_UNIXTIME(?), ?, ?, ?, ?, ?, ?, ?, ?, ?)";

		        $tmp_time = str2time($lu_u->{created_at});  

		        $tsql = $dbh->prepare($sql);
		        $tsql->bind_param(1, "1");
		        $tsql->bind_param(2, $global_search);
		        $tsql->bind_param(3, $lu_u->{id});
		        $tsql->bind_param(4, $lu_u->{screen_name});
		        $tsql->bind_param(5, $lu_u->{name});
		        $tsql->bind_param(6, $lu_u->{status}{text});
		        $tsql->bind_param(7, $lu_u->{location});
		        $tsql->bind_param(8, $tmp_time);
		        $tsql->bind_param(9, $lu_u->{friends_count});
		        $tsql->bind_param(10, $lu_u->{followers_count});
		        $tsql->bind_param(11, $lu_u->{lang});
		        $tsql->bind_param(12, $lu_u->{time_zone});
		        $tsql->bind_param(13, $lu_u->{status}{source});
		        $tsql->bind_param(14, 0);
			$tsql->bind_param(15, $sha1_hash);
			$tsql->bind_param(16, $lu_u->{status}{id_str});
			$tsql->bind_param(17, $tweet_sha1); 
		        $tsql->execute || die "[E] $DBI::errstr\n";

			$sql = "SELECT LAST_INSERT_ID()";
			$botsql = $dbh->prepare($sql);
			$botsql->execute || die "[E] $DBI::errstr\n";
			$last_id = $botsql->fetchrow();

		        foreach my $expand (@{ $lu_u->{status}{entities}{urls} } ) {
       
			$e = $expand->{expanded_url};
	                chomp($e);	

               		$sql = "INSERT INTO expanded_url (id, expanded_url) VALUES (?, ?)";
                	$tsql = $dbh->prepare($sql);
                	$tsql->bind_param(1, $last_id);
                	$tsql->bind_param(2, $e);
                	$tsql->execute || die "[E] $DBI::errstr\n";

			}
                
                	} # if $flag = 1

			#Insert_Scanned($lu_user, $FAKENEWS_TYPE );
		} #  for my $lu_u
		} #  Check_Scanned

}


print MAGENTA "[*] --[Status]--\n";
print YELLOW "[*] Hit: $scanned_hit | Missed: $scanned_missed | Bots: $bot_hit | Fake News: $fakenews_hit | Hate: $hate_hit\n";
print YELLOW "[*] Sleeping " . $config->{Bot_Hunter}{short_sleep} . "\n";
sleep($config->{Bot_Hunter}{short_sleep});

}


print MAGENTA "[*] --[Status]--\n";
print YELLOW "[*] Hit: $scanned_hit | Missed: $scanned_missed | Bots: $bot_hit | Fake News: $fakenews_hit | Hate: $hate_hit\n";
print YELLOW "[*] Long sleep " . $config->{Bot_Hunter}{long_sleep} . "\n";
sleep($config->{Bot_Hunter}{long_sleep});

} 

##############################################################################
# Hate_Speech - We search for horrible terms here in an effort to identify 
# hate speech.  The terms are pre-defined in the bot.conf.  Again, terrible 
# things. Sorry.
##############################################################################

sub Hate_Speech { 

my @hate_speech_search = split(',',$config->{Bot_Hunter}{hate_speach});
foreach our $global_search (@hate_speech_search)
{

print YELLOW "[*] Searching Hate Speech: $global_search...\n"; 

my $search = $nt->search( { q => $global_search, count => 100 } );

foreach my $s (@{ $search->{statuses} }) {

        $text = $s->{text};
        $text =~ s/[^[:ascii:]]+//g;
        chomp($text);

	# Search for the literal since Twitter might return results we aren't 
	# looking for and might not be "hate speach". 
	
	if ( $text =~ / $global_search /i ) {

		if ( Check_Scanned($s->{user}{id_str}, $HATE_TYPE ) == 0 ) {

		Insert_Scanned($s->{user}{id_str}, $s->{user}{screen_name}, $HATE_TYPE);

	        $user_id = $s->{user}{id};
		#$user_id =~ s/[^[:ascii:]]+//g;

	        $screen_name = $s->{user}{screen_name};
		#$screen_name =~ s/[^[:ascii:]]+//g;
	        chomp($screen_name);

       		print RED "[*] ----[ Hate Speach ]----\n";
	        print RED "[*] Screen Name: $screen_name\n";
		print RED "[*] Search: \"$global_search\"\n"; 
        	print RED "[*] Tweet: \"$text\"\n";

		my $lu_user = $nt->lookup_users({ user_id => [ $user_id ] });

		Bot_Logic($lu_user);

		for my $lu_u ( @$lu_user ) {

        	print RED"[*] Tweet ID: " . $lu_u->{status}{id_str} . "\n";
                       
               		foreach my $expand (@{ $lu_u->{status}{entities}{urls} } )
                 		{
		                $e = $expand->{expanded_url};
                 		chomp($e);
                 		print RED "[*] Expanded URL: $e\n";
                 		}

		$Hate_Dump_File = $hate_dump . "/" . $screen_name;
		open(my $HATE_DUMP_FH, '>>', $Hate_Dump_File) || die "Can't open $Hate_Dump_File\n";
		$Hate_Dump = Dumper($lu_u); 
		print $HATE_DUMP_FH $Hate_Dump;	
		close($HATE_DUMP_FH); 

		$hate_hit++; 

		$sha1_hash = sha1_hex( $screen_name . $total_score . $score_text . "666");
		$tweet_sha1 = sha1_hex( $text );

		$sql = "INSERT INTO twitter (type, search, twitter_id, screen_name, name, text, location, created_at, friends_count, followers_count, lang, time_zone, source, score, sha1, tweet_id, tweet_sha1) VALUES (?, ?, ?, ?, ?, ?, ?, FROM_UNIXTIME(?), ?, ?, ?, ?, ?, ?, ?, ?, ?)";
        
        	$tmp_time = str2time($lu_u->{created_at});
        
        	$tsql = $dbh->prepare($sql);
        	$tsql->bind_param(1, "2");
        	$tsql->bind_param(2, $global_search);
        	$tsql->bind_param(3, $lu_u->{id});
        	$tsql->bind_param(4, $lu_u->{screen_name});
        	$tsql->bind_param(5, $lu_u->{name});
        	$tsql->bind_param(6, $lu_u->{status}{text});
        	$tsql->bind_param(7, $lu_u->{location});
        	$tsql->bind_param(8, $tmp_time);
        	$tsql->bind_param(9, $lu_u->{friends_count});
        	$tsql->bind_param(10, $lu_u->{followers_count});
        	$tsql->bind_param(11, $lu_u->{lang});
       		$tsql->bind_param(12, $lu_u->{time_zone});
        	$tsql->bind_param(13, $lu_u->{status}{source});
        	$tsql->bind_param(14, 0);
		$tsql->bind_param(15, $sha1_hash); 
		$tsql->bind_param(16, $lu_u->{status}{id_str}); 
		$tsql->bind_param(17, $tweet_sha1);
        	$tsql->execute || die "[E] $DBI::errstr\n";

        	$sql = "SELECT LAST_INSERT_ID()";
        	$botsql = $dbh->prepare($sql);
        	$botsql->execute || die "[E] $DBI::errstr\n";
        	$last_id = $botsql->fetchrow();

        	foreach my $expand (@{ $lu_u->{status}{entities}{urls} } ) {
      
			$e = $expand->{expanded_url};
        		chomp($e);	

        		$sql = "INSERT INTO expanded_url (id, expanded_url) VALUES (?, ?)";
        		$tsql = $dbh->prepare($sql);
        		$tsql->bind_param(1, $last_id);
        		$tsql->bind_param(2, $e);
        		$tsql->execute || die "[E] $DBI::errstr\n";

			} # foreach expanded_url
               
			#Insert_Scanned($lu_user, $HATE_TYPE );

		} # For user found loop

	} # if Check_Scanned

	} #if text matches

} # foreach result found

print MAGENTA "[*] --[Status]--\n";
print YELLOW "[*] Hit: $scanned_hit | Missed: $scanned_missed | Bots: $bot_hit | Fake News: $fakenews_hit | Hate: $hate_hit\n";
print YELLOW "[*] Sleeping " . $config->{Bot_Hunter}{short_sleep} . "\n";
sleep($config->{Bot_Hunter}{short_sleep});

} # loop of hate
#print "\e[H\e[J"; # Clear screen
print MAGENTA "[*] --[Status]--\n";
print YELLOW "[*] Hit: $scanned_hit | Missed: $scanned_missed | Bots: $bot_hit | Fake News: $fakenews_hit | Hate: $hate_hit\n";
print YELLOW "[*] Long Sleeping " . $config->{Bot_Hunter}{long_sleep} . "\n";
sleep($config->{Bot_Hunter}{long_sleep});

} # End sub Hate_Speech

##############################################################################
# Bot_Logic - This is the primary logic to detect and determine if an account
# is a bot or not.  This is where the fun happens.  To "tune" this, see the
# bot.conf "scoring" section. 
##############################################################################

sub Bot_Logic()
{

  local($s) = @_;

  my $total_score = 0;  
  my $score_text = ""; 
  my $twitter_id = ""; 

  my @normal_agents = split(',',$config->{Bot_Hunter}{normal_agents});
  my @url_shortener = split(',',$config->{Bot_Hunter}{url_shortener});

  if ( !$s->[0]->{status}{text} ) 
  {
  print "[W] No tweets, abort Bot_Logic function\n";
  return; 
  }

  $text = $s->[0]->{status}{text};
  $text =~ s/[^[:ascii:]]+//g;

  $tweet_sha1 = sha1_hex( $text );

  ##################################################
  # Check language.  For example, Lang is "ru" nut #
  # tweeting in "en".                              #
  ##################################################
  
  $tweet_lang = "unknown"; 

  # We test to see if there are common english keywords before handing this off
  # langof().  This was done to improve acuracy. 
  
  my @common_words = ('you', 'and', 'if', 'of', 'why', 'what', 'when', 'but',
                      'so', 'do', 'dont', 'where', 'were', 'am', 'yes', 'be',
	     	      'know', 'knows', 'just', 'from', 'all', 'new', 'for',
	              'the', 'here', 'heres', 'is', 'me', 'our', 'gave', 'give',
	              'our', 'out', 'or', 'up', 'down','more', 'less', 'than', 'only',
	     	      'those', 'them','he', 'she','it','talk', 'talks','out',
	              'tell', 'told', 'out', 'after', 'before', 'fast', 'slow',
	              'here', 'have', 'any', 'anyone', 'in', 'out', 'see', 'make',
	     	      'good', 'bad', 'stop', 'monday', 'tuesday', 'wednesday', 
		      'thursday', 'friday', 'saturday', 'sunday', 'night', 'now', 
		      'forever', 'then' ); 

  # Search "common" words....
  
  $flag = 0; 

  foreach $i ( @common_words) { 

	  if ( $text =~ / $i /i ) {
		  $tweet_lang = "en";
		  $flag = 1; 
		  last;
	  }

  }

  # If the common_word search fails & the text is greater that 90 character, 
  # the text is passed to langof().  

  if ( $flag == 0 && length($text) >= 90) { 

	  $tweet_lang = langof( $text );
  }

  # We need to have a good bit of text to determine the language.  If that
  # criteria isn't meant,  we call the lang "unknown" and move on.
  
  if ( $tweet_lang ne "unknown" ) {
	  
	if ( $s->[0]->{lang} ne $tweet_lang && length($text) >= 90 ) {

	#print "-> ($text) " . length($text) . "\n"; 
        $score_text .= "Tweet language mismatch ($s->[0]->{lang} != $tweet_lang), ";
        $total_score = $total_score + $config->{Bot_Hunter}{tweet_lang_mismatch};

	}

  }

  ############################
  # Standard Agent Detection #
  ############################

  my $flag = 0; 

  # Is the Tweet User_Agent something we would expect to see?
  
  foreach $a (@normal_agents) { 

	if ( $s->[0]->{status}{source} =~ /$a/ || $s->[0]->{status}{retweeted_status}{source} ) { 

		$flag = 1; 
		last; 
	}

	if ( $flag == 1 ) { 
		last;
	}

  }

  if ( $flag == 0 ) { 


	$score_text .= "Non-standard agent, ";	
	$total_score = $total_score + $config->{Bot_Hunter}{not_normal_agent}; 
	
	}

  ###########################################
  # Does the agent of the word "Bot" in it? #
  ###########################################

	if ( $s->[0]->{status}{source} =~ /bot/i ) {

        $score_text .= "Agent has the word bot, ";
	$total_score = $total_score + $config->{Bot_Hunter}{agent_has_bot}

	} 

   ###########################################
   # Does the 'screen_name' have "bot"?      #
   ###########################################

	if ( $s->[0]->{screen_name} =~ /bot/i ) { 

	$score_text .= "Screen name has the word bot, "; 
	$total_score = $total_score + $config->{Bot_Hunter}{screen_name_has_bot}
	
	}

   #############################################
   # Does the 'screen_name' have a log of _'s? #
   #############################################

   my $tmp_screen_name = $s->[0]->{screen_name}; 
   my $number_count = $tmp_screen_name =~ s/_//g;
	
   if ( $number_count >= 4 ) 
	{
	
	$score_text .= "Screen name has a lot of underscores, ";
	$total_score = $total_score + $config->{Bot_Hunter}{many_underscores};

	}

   ###################################
   # The tweet has a lot of hashtags #
   ###################################

   $tmp_text = $s->[0]->{status}{text};
   $number_count = $tmp_text =~ s/#//g;
   
   if ( $number_count >= 6 ) 
	{

	$score_text .= "Tweet has a lot of hashtags, ";
	$total_score = $total_score + $config->{Bot_Hunter}{lots_of_hash_tags};

	}
	

   #########################################################
   # Does the 'screen_name' have a bunch of numbers in it? #
   #########################################################

   $tmp_screen_name = $s->[0]->{screen_name}; 
   $number_count  = $tmp_screen_name =~ s/[0123456789]//g;

   if ( $number_count == 3 ) 
	{
   	
	$score_text .= "3 numbers in screen name, "; 
	$total_score = $total_score + $config->{Bot_Hunter}{three_numbers_in_name}; 

	} 

    elsif ( $number_count == 4 )  
	{

	$score_text .= "4 numbers in screen name, ";
	$total_score = $total_score + $config->{Bot_Hunter}{four_numbers_in_name};

	}

    elsif ( $number_count == 5 )
	{

	$score_text .= "5 numbers in screen name, ";
	$total_score = $total_score + $config->{Bot_Hunter}{five_numbers_in_name};
	
	} 

    elsif ( $number_count >= 6 )
	{
	
	$score_text .= "6 or more numbers in screen name, ";
	$total_score = $total_score + $config->{Bot_Hunter}{six_or_more_numbers_in_name};

	}
	
   ##########################
   # Is the 'time_zone' set #
   ##########################

	if ( !$s->[0]->{time_zone} ) { 

	$score_text .= "Time zone is not set, ";
	$total_score = $total_score + $config->{Bot_Hunter}{no_time_zone}; 

	}

   ####################
   # Is the 'url' set #
   ####################

        if ( !$s->[0]->{url} ) {

	$score_text .= "No URL set, "; 
        $total_score = $total_score + $config->{Bot_Hunter}{no_url};

        } 


   ############################
   # Is the 'description' set #
   ############################

        if ( !$s->[0]->{description} || $s->[0]->{description} eq "" ) {

	$score_text .= "No description set, "; 
        $total_score = $total_score + $config->{Bot_Hunter}{no_description};

        }

   #################################################
   # Does the user have a low amount of followers  #
   #################################################

	if ( $s->[0]->{followers_count} <= 15 ) { 

	$score_text .= "Low followers, "; 
	$total_score = $total_score + $config->{Bot_Hunter}{low_followers}

	} 

   ##############################################
   # Does the user have a low amount of friends #
   ##############################################

        if ( $s->[0]->{friends_count} <= 15 ) {
 
	$score_text .= "Low friends, ";  
        $total_score = $total_score + $config->{Bot_Hunter}{low_friends}

        }

   ##########################################
   # Is the Twitter default profile_url set #
   ##########################################

   if ( $s->[0]->{profile_image_url} eq "http://abs.twimg.com/sticky/default_profile_images/default_profile_normal.png" ) { 

	$score_text .= "Default profile URL, "; 
	$total_score = $total_score + $config->{Bot_Hunter}{default_profile_url};

	}


   ###############################################
   # Is the Twitter default background image set #
   ###############################################

   if ( $s->[0]->{profile_background_image_url} eq "http://abs.twimg.com/images/themes/theme1/bg.png" ) {  

	$score_text .= "Default backgroud image URL, "; 
        $total_score = $total_score + $config->{Bot_Hunter}{default_profile_url};

        }


   ###########################################
   # Is the Twitter default background undef #
   ###########################################

   if ( !$s->[0]->{profile_background_image_url} ) { 

	$score_text .= "Undefined default background image URL, "; 
        $total_score = $total_score + $config->{Bot_Hunter}{undef_default_background_image_url};

        }

   ###############################################
   # Is the Twitter default background color set #
   ###############################################

   if ( $s->[0]->{profile_background_color} eq "C0DEED" ) {

	$score_text .= "Default background color, "; 
        $total_score = $total_score + $config->{Bot_Hunter}{default_background_color};

        }

   ################################
   # When was the account created #
   ################################

   my $current_time = time;
   my $created_timestamp = str2time($s->[0]->{created_at});

   # One year

   if ( $created_timestamp > ( $current_time - 22896000 ) ) {
       
	$score_text .= "Account is newer than a year, ";
        $total_score = $total_score + $config->{Bot_Hunter}{year};

   }

   # Six months. 

   if ( $created_timestamp > ( $current_time - 15552000 ) ) {

	$score_text .= "Account is newer than 6 months, "; 
        $total_score = $total_score + $config->{Bot_Hunter}{six_month};

   }

   # Month 

   if ( $created_timestamp > ( $current_time - 2592000 ) ) {

	$score_text .= "Account is newer than 1 month, "; 
        $total_score = $total_score + $config->{Bot_Hunter}{month};

   }

   # Week

   if ( $created_timestamp > ( $current_time - 604800 ) ) {

	$score_text .= "Account is newer than a week, "; 
        $total_score = $total_score + $config->{Bot_Hunter}{week};

   }

   # Day

   if ( $created_timestamp > ( $current_time - 86400 ) ) { 

	$score_text .= "Account is newer than a day, "; 
	$total_score = $total_score + $config->{Bot_Hunter}{one_day};

   } 

   ########################################
   # Has the account ever tweeted before? #
   # This is silly?  Then why would we    #
   # have FOUND the account! Remove this  #
   ########################################

#   if ( $s->[0]->{statuses_count} == 0 ) 
#   	{ 

#	$score_text .= "No tweets, "; 
#	$total_score = $total_score + $config->{Bot_Hunter}{no_tweets};

#	}

   #######################################
   # Does the account have ANY followers #
   #######################################
   
   if ( $s->[0]->{favourites_count} == 0 ) 
   	{

        $score_text .= "No favorites, ";
        $total_score = $total_score + $config->{Bot_Hunter}{no_favs};

        }

  #####################################
  # How many tweets/favorites per day #
  #####################################
  
  my $tweets_per_day = $s->[0]->{statuses_count} / ( ( $current_time - $created_timestamp ) / 86400 );
  my $favs_per_day = $s->[0]->{favourites_count} / ( ( $current_time - $created_timestamp ) / 86400 );

   if ( $tweets_per_day > 100 && $s->[0]->{statuses_count} > 100 ) 
   	{
	$score_text .= "100+ tweets per/day, ";
	$total_score = $total_score + $config->{Bot_Hunter}{high_tweets_100};
	}

   if ( $favs_per_day > 100 && $s->[0]->{favourites_count} > 100 ) 
   	{
	$score_text .= "100+ favorites per/day, ";
	$total_score = $total_score + $config->{Bot_Hunter}{high_favs_100}; 
	}

   if ( $tweets_per_day > 120 && $s->[0]->{statuses_count} > 100 )
        {
        $score_text .= "120+ tweets per/day, ";
        $total_score = $total_score + $config->{Bot_Hunter}{high_tweets_120};
        }

   if ( $favs_per_day > 120 && $s->[0]->{favourites_count} > 100 )
        {
        $score_text .= "120+ favorites per/day, ";
        $total_score = $total_score + $config->{Bot_Hunter}{high_favs_120};
        }

   if ( $tweets_per_day > 140 && $s->[0]->{statuses_count} > 100 )
        {
        $score_text .= "140+ tweets per/day, ";
        $total_score = $total_score + $config->{Bot_Hunter}{high_tweets_140};
        }

   if ( $favs_per_day > 140 && $s->[0]->{favourites_count} > 100 )
        {
        $score_text .= "140+ favorites per/day, ";
        $total_score = $total_score + $config->{Bot_Hunter}{high_favs_140};
        }

   if ( $tweets_per_day > 160 && $s->[0]->{statuses_count} > 100 )
        {
        $score_text .= "160+ tweets per/day, ";
        $total_score = $total_score + $config->{Bot_Hunter}{high_tweets_160};
        }

   if ( $favs_per_day > 160 && $s->[0]->{favourites_count} > 100 )
        {
        $score_text .= "160+ favorites per/day, ";
        $total_score = $total_score + $config->{Bot_Hunter}{high_favs_160};
        }

   if ( $tweets_per_day > 180 && $s->[0]->{statuses_count} > 100 )
        {
        $score_text .= "180+ tweets per/day, ";
        $total_score = $total_score + $config->{Bot_Hunter}{high_tweets_180};
        }

   if ( $favs_per_day > 180 && $s->[0]->{favourites_count} > 100 )
        {
        $score_text .= "180+ favorites per/day, ";
        $total_score = $total_score + $config->{Bot_Hunter}{high_favs_180};
        }

   if ( $tweets_per_day > 200 && $s->[0]->{statuses_count} > 100 )
        {
        $score_text .= "200+ tweets per/day, ";
        $total_score = $total_score + $config->{Bot_Hunter}{high_tweets_200};
        }

   if ( $favs_per_day > 200 && $s->[0]->{favourites_count} > 100 )
        {
        $score_text .= "200+ favorites per/day, ";
        $total_score = $total_score + $config->{Bot_Hunter}{high_favs_200};
        }

   if ( $tweets_per_day > 500 && $s->[0]->{statuses_count} > 100 )
        {
        $score_text .= "500+ tweets per/day, ";
        $total_score = $total_score + $config->{Bot_Hunter}{high_tweets_500};
        }

   if ( $favs_per_day > 500 && $s->[0]->{favourites_count} > 100 )
        {
        $score_text .= "500+ favorites per/day, ";
        $total_score = $total_score + $config->{Bot_Hunter}{high_favs_500};
        }

   if ( $tweets_per_day > 1000 && $s->[0]->{statuses_count} > 100 )
        {
        $score_text .= "1000+ tweets per/day, ";
        $total_score = $total_score + $config->{Bot_Hunter}{high_tweets_1000};
        }

   if ( $favs_per_day > 1000 && $s->[0]->{favourites_count} > 100 )
        {
        $score_text .= "1000+ favorites per/day, ";
        $total_score = $total_score + $config->{Bot_Hunter}{high_favs_1000};
        }

   if ( $tweets_per_day > 2000 && $s->[0]->{statuses_count} > 100 )
        {
        $score_text .= "2000+ tweets per/day, ";
        $total_score = $total_score + $config->{Bot_Hunter}{high_tweets_2000};
        }

   if ( $favs_per_day > 2000 && $s->[0]->{favourites_count} > 100 )
        {
        $score_text .= "2000+ favorites per/day, ";
        $total_score = $total_score + $config->{Bot_Hunter}{high_favs_2000};
        }

   if ( $tweets_per_day > 3000 && $s->[0]->{statuses_count} > 100 )
        {
        $score_text .= "3000+ tweets per/day, ";
        $total_score = $total_score + $config->{Bot_Hunter}{high_tweets_3000};
        }

   if ( $favs_per_day > 3000 && $s->[0]->{favourites_count} > 100 )
        {
        $score_text .= "3000+ favorites per/day, ";
        $total_score = $total_score + $config->{Bot_Hunter}{high_favs_3000};
        }

   if ( $tweets_per_day > 4000 && $s->[0]->{statuses_count} > 100 )
        {
        $score_text .= "4000+ tweets per/day, ";
        $total_score = $total_score + $config->{Bot_Hunter}{high_tweets_4000};
        }

   if ( $favs_per_day > 4000 && $s->[0]->{favourites_count} > 100 )
        {
        $score_text .= "4000+ favorites per/day, ";
        $total_score = $total_score + $config->{Bot_Hunter}{high_favs_4000};
        }

   if ( $tweets_per_day > 5000 && $s->[0]->{statuses_count} > 100 )
        {
        $score_text .= "5000+ tweets per/day, ";
        $total_score = $total_score + $config->{Bot_Hunter}{high_tweets_5000};
        }

   if ( $favs_per_day > 5000 && $s->[0]->{favourites_count} > 100 )
        {
        $score_text .= "5000+ favorites per/day, ";
        $total_score = $total_score + $config->{Bot_Hunter}{high_favs_5000};
        }

  $scanned_sql = "SELECT COUNT(tweet_sha1) FROM twitter WHERE tweet_sha1 = ?";
  $ssql = $dbh->prepare($scanned_sql);
  $ssql->bind_param(1, $tweet_sha1);
  $ssql->execute || die "[E] $DBI::errstr\n";

  @scanout=$ssql->fetchrow_array;
  $results = $scanout[0]; 

  if ( $results != 0 ) 
  	{
	$score_text .= "Tweet associated with other bots, ";
	$total_score = $total_score + $config->{Bot_Hunter}{dup_text}; 
	}

##############################################
# Does the URL contain another URL shortener #
##############################################
	
foreach my $expand (@{ $s->[0]->{status}{entities}{urls} } )
        {

        $e = $expand->{expanded_url};
        chomp($e);

	foreach $i (@url_shortener) { 

		$short_http = "http://$i/"; 
		$short_https = "https://$i/";
	
		if ( $e =~ /$short_http/i || $e =~ /$short_https/i ) {
			$score_text .= "Expanded URL contains another URL shortener, "; 
			$total_score = $total_score + $config->{Bot_Hunter}{expanded_url_shortener};
			last;
			}

		}
        }


# This add a score that probably doesnt need tobe there.  Rethink this.
#
#if ( ( $favs_per_days + $tweets_per_day ) > 70 ) 
#	{
#
#	$score_text .= " favs + tweets is high, "; 
#	$total_score = $total_score + $config->{Bot_Hunter}{tweets_plus_favs};
#
#	}

##################################
# Total all the scores together! #
##################################

if ( $total_score >= 10 ) {

	$bot_hit++; 

	$score_text =~ s/, $//;		# Remove last ,

        $screen_name = $s->[0]->{screen_name};
        $screen_name =~ s/[^[:ascii:]]+//g;
	chomp($screen_name);

	$tweet_id = $s->[0]->{status}{id_str}; 

#	print "\e[H\e[J"; # Clear screen
	print RED "[*] ----[ Bot Located ]----\n";
	print CYAN "[*] Bot Screen: \"$screen_name\"\n"; 
	print CYAN "[*] Search: \"$global_search\"\n"; 
	print CYAN "[*] Tweet: \"$text\"\n"; 
        print CYAN "[*] Tweet ID: $tweet_id\n"; 
	print CYAN "[*] Source: \"$s->[0]->{status}{source}\"\n"; 
        print CYAN "[*] Tweets per day: $tweets_per_day (per/hour: " . ( $tweets_per_day / 24 ) . ") (total: $s->[0]->{statuses_count})\n";
        print CYAN "[*] Favs per day: $favs_per_day (per/hour: " . ( $favs_per_day / 24 ) . ") (total: $s->[0]->{favourites_count})\n";
	print CYAN "[*] Tweet lang: $tweet_lang. Set language: $s->[0]->{lang}.\n";
	print CYAN "[*] Score: $total_score\n"; 
	print CYAN "[*] Score Text: $score_text\n"; 

	foreach my $expand (@{ $s->[0]->{status}{entities}{urls} } ) 
		{
		$e = $expand->{expanded_url}; 
		chomp($e);
		print CYAN "[*] Expanded URL: $e\n"; 
		}

	$Bot_Tested_Dump_File = $bot_tested . "/" . $screen_name;
	open(my $BOT_TEST_DUMP_FH, '>>', $Bot_Tested_Dump_File) || die "Can't open $Bot_Tested_Dump_File\n";
	$Bot_Tested_Dump = Dumper($s);
	print $BOT_TEST_DUMP_FH $Bot_Tested_Dump;
	close($BOT_TEST_DUMP_FH);

	$sha1_hash = sha1_hex( $screen_name . $total_score . $score_text . "666"); 

	$sql = "INSERT INTO twitter (type, search, twitter_id, screen_name, name, text, location, created_at, friends_count, followers_count, lang, time_zone, source, score, score_text, sha1, tweet_id, tweet_sha1) VALUES (?, ?, ?, ?, ?, ?, ?, FROM_UNIXTIME(?), ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"; 

	$tmp_time = str2time($s->[0]->{created_at});

	$botsql = $dbh->prepare($sql);
	$botsql->bind_param(1, "3");
	$botsql->bind_param(2, $global_search); 
	$botsql->bind_param(3, $s->[0]{id}); 
	$botsql->bind_param(4, $s->[0]->{screen_name}); 
	$botsql->bind_param(5, $s->[0]->{name}); 
	$botsql->bind_param(6, $s->[0]->{status}{text});
	$botsql->bind_param(7, $s->[0]->{location});
	$botsql->bind_param(8, $tmp_time);
	$botsql->bind_param(9, $s->[0]->{friends_count}); 
	$botsql->bind_param(10, $s->[0]->{followers_count}); 
	$botsql->bind_param(11, $s->[0]->{lang}); 
	$botsql->bind_param(12, $s->[0]->{time_zone}); 
	$botsql->bind_param(13, $s->[0]->{status}{source}); 
	$botsql->bind_param(14, $total_score); 
	$botsql->bind_param(15, $score_text); 
	$botsql->bind_param(16, $sha1_hash); 
	$botsql->bind_param(17, $tweet_id); 
	$botsql->bind_param(18, $tweet_sha1);
	$botsql->execute || die "[E] $DBI::errstr\n";


	$sql = "SELECT LAST_INSERT_ID()"; 
	$botsql = $dbh->prepare($sql);
	$botsql->execute || die "[E] $DBI::errstr\n";

	my $last_id = $botsql->fetchrow();


        foreach my $expand (@{ $s->[0]->{status}{entities}{urls} } ) {

		$e = $expand->{expanded_url};
                chomp($e);

		$sql = "INSERT INTO expanded_url (id, expanded_url) VALUES (?, ?)"; 
		$botsql = $dbh->prepare($sql);
		$botsql->bind_param(1, $last_id);
		$botsql->bind_param(2, $e );
		$botsql->execute || die "[E] $DBI::errstr\n";

          }


	}

}

###################################################################
# Check to see if the screen_name has already been scanned before #
###################################################################

sub Check_Scanned()
{

my $user = $_[0];
my $type = $_[1];

my $twitter_id;

  # Type = 0 old scans before i started spliting up by types.  Still dont want to rescan! 
  #
  $sql = "SELECT twitter_id FROM scanned WHERE twitter_id=? AND ( type=? OR type=0 ) LIMIT 1";
  $botsql = $dbh->prepare($sql);
  $botsql->bind_param(1, $user);
  $botsql->bind_param(2, $type);
  $botsql->execute || die "[E] $DBI::errstr\n";

  $twitter_id = $botsql->fetchrow();

  if ( $twitter_id  ) {
     $scanned_hit++; 
     return 1;
  }

$scanned_missed++; 
return 0; 

}

sub Insert_Scanned()
{

my $id = $_[0];
my $screen_name = $_[1];
my $type = $_[2];

        $sql = "INSERT INTO scanned (twitter_id, screen_name, type) VALUES (?, ?, ?)";
        $botsql = $dbh->prepare($sql);
        $botsql->bind_param(1, $id);
	$botsql->bind_param(2, $screen_name);
	$botsql->bind_param(3, $type); 
        $botsql->execute || die "[E] $DBI::errstr\n";

}
