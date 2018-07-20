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

# This poorly written program powers the botlogic.io web site. It handles 
# the main page, API and API lookups. 

use CGI qw(:all);
use DBI;
use Config::Tiny;
use HTML::StripScripts::Parser();

$xss = HTML::StripScripts::Parser->new({ Context => 'Inline' });

my $config_file = "/etc/bot_lookup.conf"; 

# Load configuration file.

die "$config_file is missing\n" if not -e $config_file;
our $config = Config::Tiny->read( $config_file, 'utf8' );

# POST/GET params. Strip for unwanted stuff. 

my $sn		    = &remove_unwanted(param("sn"));
my $id		    = &remove_unwanted_id(param("id"));
my $v		    = &remove_unwanted_sha1(param("v")); 
my $json	    = &remove_unwanted(param("json")); 
my $api		    = &remove_unwanted(param("api")); 

##############################################################################
# User has requests JSON (API) output.  Format and return the results of the 
# search.
##############################################################################

if ( $json && $sn ) {

	print "Content-Type: application/json; charset=UTF-8\n\r\n\r";

my $db  = "DBI:mysql:database=$config->{MySQL}{mysql_database};host=$config->{MySQL}{mysql_host}";
        my $dbh = DBI ->connect($db, $config->{MySQL}{mysql_user}, $config->{MySQL}{mysql_password}) || die "[E] Cannot connect to MySQL.\n";

        $sql = "SELECT id, type, found_timestamp, name, screen_name, text, score FROM twitter WHERE screen_name = ?";


        $tsql = $dbh->prepare($sql);
        $tsql->bind_param(1, $sn);
        $tsql->execute || die "[E] $DBI::errstr\n";

                while (my(@sqlout)=$tsql->fetchrow_array)
                        {

                        $flag = 1;

                        $id = $xss->filter_html($sqlout[0]);
			$type = $xss->filter_html($sqlout[1]);
                        $found_timestamp = $xss->filter_html($sqlout[2]);
                        $name = $xss->filter_html($sqlout[3]);
                        $screen_name = $xss->filter_html($sqlout[4]);
                        $text = $xss->filter_html($sqlout[5]);
			$score = $xss->filter_html($sqlout[6]); 

                        if ( $type == 1 ) {
                                $display_type = "Fake News";
                        }

                        elsif ( $type == 2 ) {
                                $display_type = "Hate Speach";
                        }

                        elsif ( $type == 3 ) {
                                $display_type = "Bot";
                        }

# Ceate JSON output.

print "
\{
    \"search_status\": \"found\", 
    \"id\": $id,
    \"screen_name\": \"$screen_name\"
    \"name\": \"$name\",
    \"type\": $type, 
    \"type_string\": \"$display_type\",
    \"text\": \"$text\",
    \"score\": $score,
    \"found_timestamp\": \"$found_timestamp\"
\}
"; 
		}

    if ( $flag == 0 ) { 

    $sql = "SELECT id FROM scanned WHERE screen_name = ?";
    $tsql = $dbh->prepare($sql);
    $tsql->bind_param(1, $sn);
    $tsql->execute || die "[E] $DBI::errstr\n";
    @sqlout=$tsql->fetchrow_array;

    if ( $sqlout[0]  ) {
print "
\{
    \"search_status\": \"normal user\"
\}
"; 


    } else { 

print "
\{
     \"search_status\": \"not found\"
\}
"; 
   }
   }

exit;
}

# Use API header/footer.

if ( $api ) {

print header();
open(my $HEADER, "</var/www/html/.just-header") or die "Could not open file .header $!";

while (my $r = <$HEADER>) {
  chomp $r;
  print "$r\n";
}
close(HEADER);

open(my $API, "</var/www/html/.api") or die "Could not open file .api $!";
while (my $r = <$API>) {
  chomp $r;
  print "$r\n";
}
close(API);

open(my $FOOTER, "</var/www/html/.footer") or die "Could not open file .footer $!";
while (my $r = <$FOOTER>) {
  chomp $r;
  print "$r\n";
}
close(FOOTER);

exit 0;
}


# Normal web request here. 

print header();

open(my $HEADER, "</var/www/html/.header") or die "Could not open file .header $!";

while (my $r = <$HEADER>) {
  chomp $r;
  print "$r\n";
}
close(HEADER);

if ( !$id && !$v ) 
	{

print "<form action=\"/\" method=\"get\">\n"; 
print "Search for @<input name=\"sn\" length=\"25\" value=\"$screen_name\">\n";
print "<input type=\"submit\" value=\"Botlogic Search!\"></form>\n";

	}

$flag = 0; 

if ( $sn ) 
	{

	my $db  = "DBI:mysql:database=$config->{MySQL}{mysql_database};host=$config->{MySQL}{mysql_host}";
	my $dbh = DBI ->connect($db, $config->{MySQL}{mysql_user}, $config->{MySQL}{mysql_password}) || die "[E] Cannot connect to MySQL.\n";

	$sql = "SELECT id, type, found_timestamp, name, screen_name, text, score, score_text FROM twitter WHERE screen_name = ?"; 

	$tsql = $dbh->prepare($sql);
	$tsql->bind_param(1, $sn);
	$tsql->execute || die "[E] $DBI::errstr\n";

		while (my(@sqlout)=$tsql->fetchrow_array) 
			{

			$flag = 1; 

			$id = $xss->filter_html($sqlout[0]); 
			$type = $xss->filter_html($sqlout[1]);
			$found_timestamp = $xss->filter_html($sqlout[2]);
			$name = $xss->filter_html($sqlout[3]);
			$screen_name = $xss->filter_html($sqlout[4]);
			$text = $xss->filter_html($sqlout[5]);
			$score = $xss->filter_html($sqlout[6]); 
			$score_text = $xss->filter_html($sqlout[7]);

			if ( $type == 1 ) { 
				$display_type = "Fake News"; 
				$dir = "fakenews";
			}

			elsif ( $type == 2 ) { 
				$display_type = "Hate Speach";
				$dir = "hate"; 
			}

			elsif ( $type == 3 ) { 
				$display_type = "Bot"; 
				$dir = "bots";
			}

			print "Screen Name: \"<a href=\"https://twitter.com/$screen_name\">$screen_name\"</a> <br>\n";
			#	( <a href=\"https://botlogic.io/$dir/$screen_name\">Twitter API JSON</a> )<br>\n";
			print "Name: \"$name\"<br>\n"; 
			print "Type: $display_type<br>\n";

			if ( $type == 3 ) 
				{ 
				print "Score: $score<br>\n"; 
				print "Score Text: $score_text<br>\n"; 
				}

			print "Found on $found_timestamp<br>\n";
			print "Example Tweet: \"$text\"<br>\n"; 
			print "<p>\n";
		
			}

			if ( $flag == 0 ) { 

				$sql = "SELECT id FROM scanned WHERE screen_name = ?";
				$tsql = $dbh->prepare($sql);
				$tsql->bind_param(1, $sn); 
				$tsql->execute || die "[E] $DBI::errstr\n";
				@sqlout=$tsql->fetchrow_array;

				# Never scanned before,  lets scan! 
				
				if ( !$sqlout[0] ) 
					{

					$sql = "INSERT IGNORE INTO queue (screen_name) VALUES (?)";
					$tsql = $dbh->prepare($sql);
					$tsql->bind_param(1, $sn);
					$tsql->execute || die "[E] $DBI::errstr\n";

					print "Screen name '$sn' has never been scanned before."; 

					} else { 

					print "Screen name '$sn' has been scanned and does not promote 'Fake News',  use 'Hate Speach' and is not a 'Bot'"; 

					}

				}
	}

	elsif ( $id && $v ) 
	{

	# HERE
	
	my $db  = "DBI:mysql:database=$config->{MySQL}{mysql_database};host=$config->{MySQL}{mysql_host}";
	my $dbh = DBI ->connect($db, $config->{MySQL}{mysql_user}, $config->{MySQL}{mysql_password}) || die "[E] Cannot connect to MySQL.\n";

	$sql = "SELECT id, type, found_timestamp, name, screen_name, text, score, score_text, phone_code FROM twitter WHERE id = ? AND sha1 = ?"; 

	$tsql = $dbh->prepare($sql);
	$tsql->bind_param(1, $id);
	$tsql->bind_param(2, $v); 
	$tsql->execute || die "[E] $DBI::errstr\n";

		while (my(@sqlout)=$tsql->fetchrow_array) 
			{

			print "<input type=\"hidden\" value=\"$id\" id=\"botlogicid\">\n"; 
			print "<script src=\"botlogic.js\"></script>\n";

			$flag = 1; 

			# dont for xss html strip stuff!
			#
			$id = $xss->filter_html($sqlout[0]); 
			$type = $xss->filter_html($sqlout[1]);
			$found_timestamp = $xss->filter_html($sqlout[2]);
			$name = $xss->filter_html($sqlout[3]);
			$screen_name = $xss->filter_html($sqlout[4]);
			$text = $xss->filter_html($sqlout[5]);
			$score = $xss->filter_html($sqlout[6]); 
			$score_text = $xss->filter_html($sqlout[7]); 
			$phone_code = $xss->filter_html($sqlout[8]); 

			$sql1 = "INSERT INTO ip (id, remote_addr, http_user_agent, http_referer, remote_ident) VALUES (?, ?, ?, ?, ?);"; 
			$tsql1 = $dbh->prepare($sql1);
			$tsql1->bind_param(1, $id);
			$tsql1->bind_param(2, $ENV{REMOTE_ADDR}); 
		        $tsql1->bind_param(3, $ENV{HTTP_USER_AGENT}); 
                        $tsql1->bind_param(4, $ENV{HTTP_REFERER}); 
			$tsql1->bind_param(5, $ENV{REMOTE_IDENT});
			$tsql1->execute || die "[E] $DBI::errstr\n";
		
			if ( $type == 1 ) { 
				$display_type = "promote 'Fake News'"; 
				$dir = "fakenews";
			}

			elsif ( $type == 2 ) { 
				$display_type = "use 'Hate Speach'";
				$dir = "hate";
			}

			elsif ( $type == 3 ) { 
				$display_type = "'Bot'"; 
				$dir = "bots";
			}

			print "<b>The Twitter screen name \"$screen_name\" has been determined to $display_type.  If you believe our Machine Learning algorithms are in error,  we would love to hear from you!  Please call 1-866-776-0772 (United States) or +1-650-230-0542.  When prompted, enter the code '$phone_code'. Botlogic.io staff is available 24 hours a day, 7 days a week. <p></b>\n";

			print "<i>If you were contacted via Twitter,  you will <b>not</b> be contacted again</i><p>\n"; 

			print "Screen Name: \"<a href=\"https://twitter.com/$screen_name\">$screen_name\"</a><br>\n";
			#	( <a href=\"https://botlogic.io/$dir/$screen_name\">Twitter API JSON</a> ) <br>\n";
			print "Name: \"$name\"<br>\n"; 


                        if ( $type == 3 )
                                {
                                print "Score: $score<br>\n";
                                print "Score Text: $score_text<br>\n";
                                }

			print "Type: $display_type<br>\n";
			print "Found on: $found_timestamp<br>\n";
			print "Example Tweet: \"$text\"<br>\n"; 
			print "<p>\n";
		
			}

			if ( $flag == 0 ) { 
				print "Not found"; 
				}

	}


open(my $FOOTER, "</var/www/html/.footer") or die "Could not open file .footer $!";

while (my $r = <$FOOTER>) {
  chomp $r;
  print "$r\n";
}
close(FOOTER);

exit;

##############################################################################
# Data script routines for security
##############################################################################

sub remove_unwanted {
  our $s;
  local($s) = @_;
  $s =~ s/\.\.//g;
  #$s =~ s/[^A-Za-z0-9\@\-\_\/:.]//g if defined $s;
  $s =~ s/[^A-Za-z0-9\-\_\/:.]//g if defined $s;
  return $s;
}

sub remove_unwanted_id {
  our $s;
  local($s) = @_;
  $s =~ s/\.\.//g;
  #$s =~ s/[^A-Za-z0-9\@\-\_\/:.]//g if defined $s;
  #$s =~ s/[^A-Za-z0-9\-\_\/:.]//g if defined $s;
  $s =~ s/[^0-9]//g if defined $s;
  return $s;
}

sub remove_unwanted_sha1 {
  our $s;
  local($s) = @_;
  $s =~ s/\.\.//g;
  #$s =~ s/[^A-Za-z0-9\@\-\_\/:.]//g if defined $s;
  $s =~ s/[^A-Fa-f0-9\-\_\/:.]//g if defined $s;
  return $s;
}


