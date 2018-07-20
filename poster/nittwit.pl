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

##############################################################################
# nittwit.pl - This is a simple program that will allow you to "tweet" from
# the comand and does NOT use the Twitter API.  This uses the Twitter mobile
# web interface to post tweets.  Warning:  Use this program at your own 
# risk.  Usage of this program is likely against the Twitter ToS! 
#
# Usage: 
#
# echo "hello world" | ./nittwit -u {username} -p {password}
#
##############################################################################

use LWP::UserAgent;
use HTTP::Cookies;
use Time::Piece;
use Getopt::Long;
use LWP::Protocol::https;

use strict;
use warnings;

my $verbose = 0; 			# Used for debugging.

##############################################################################
# Twitter purposely makes logging in via the web difficult for automated 
# routines.  To get around this,  we use a older web browser "User Agent". 
# Twitter will allow us to login via the mobile interface and doesn't require
# as many restrictions. 
#
# This is a losing battle for Twitter.  One day Twitter will disable this 
# method. Abusers can then piviot to WWW::Mechanize::Chrome and/or 
# WWW::Mechanize::Firefox. 
###############################################################################

my $user_agent = "Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.8.0.6) Gecko/20060728 Firefox/1.5.0.6"; 

my $max_text = 280;		# Max Tweet Length

# Used for authentication.

my $bearer = "Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"; 

my $post_url = "https://api.twitter.com/1.1/statuses/update.json";

###############################################################################
# Don't modify below this line.
###############################################################################

my $cookie_file_e = 0;
my $utime = time;
my $trash;
my $form_data;                                                                                        my @login_headers;                                                                                    
my $response;
my $expire_time;
my $cookie_value;
my $auth_token;
my $dt;
my $lwpua;
my $cookie_tmp;
my $cookie_tmp2;
my $cookie_jar;
my $cookie_file;
my $t1;
my $cookie_key;
my $headers;
my $ct0_value;
my $post_headers;
my $username;
my $password;
my @post_headers;
my $expire_tmp;

# Command line options.

GetOptions ( "username=s"                => \$username,
             "password=s"                => \$password, 
	     "cookie=s"			 => \$cookie_file,
    	     "verbose"			 => \$verbose ); 


if ( !$username ) {
	die "[E] Username not specified! Abort!\n";
}

if ( !$password ) { 
	die "[E] Password not specified! Abort!\n"; 
}


# Read data from stdin.

my $text = <STDIN>;
chomp($text);

###############################################################################
# Start basic logic
###############################################################################

$lwpua = LWP::UserAgent->new( ssl_opts => { verify_hostname => 0 },);
$lwpua->agent($user_agent);

if ( ! -e $cookie_file ) { 
	$cookie_file_e = 1; 
	}

if ( length($text) > $max_text ) 
	{ 
	print "[*] Warning - Tweet is over $max_text. Tuncating.....\n";
	$text = substr( $text, 0, $max_text );
	}

$cookie_jar = HTTP::Cookies->new(
              file => $cookie_file,
              autosave => 1,
              ignore_discard => 1);

$lwpua->cookie_jar($cookie_jar);


# If there's no cookie file, Login. 

if ( $cookie_file_e == 1 ) 
   {
   if ( $verbose ) { 
   print "[*] No cookies found.... Login into Twitter....\n";
   }

   &Login(); 

}

# Get ct0 cookie (for CSRF token)

$ct0_value = &Get_CT0();

# Post to mobile site.
#
@post_headers = ('Referer' => 'http://m.twitter.com', 'User-Agent' => $user_agent);

# If we don't have a ct0 cookie, go get one by force.

if ( $ct0_value eq "0" ) 
	{
	
	if ( $verbose ) {
	print "[*] Forcing x-csrf-token token!\n"; 
	}

	$headers = HTTP::Headers->new(
        'authorization' => $bearer,
        'x-csrf-token' => 'AAAAAAA',
        'x-twitter-auth-type' => 'OAuth2Session',
        'x-twitter-client-language' => 'en',
        'x-twitter-active-user' => 'yes',
        'content-type' => 'application/x-www-form-urlencoded' );

	$lwpua->default_headers($headers);
	$response = $lwpua->post( $post_url, { 'tweet_mode' => 'extended', 'status' => 'THIS WILL FAIL', 'enable_dm_commands' => 'true', 'fail_dm_commands' => 'true' }, @post_headers );

	$cookie_jar->save;

	# Get the ct0 value after forcing...
	
	$ct0_value = &Get_CT0();

	# Something went wrong,  we have to abort! 
	
	if ( $ct0_value eq "0" ) { 
		die "[E] Could get x-csrf-token token. Abort.\n";
		}

	}

# We are logged in.  Let's do some posting!

if ( $verbose ) {
	print "[*] Posting \"$text\"\n"; 
	}

# Setup our POST headers

$headers = HTTP::Headers->new(
        'authorization' => $bearer, 
        'x-csrf-token' => $ct0_value,
        'x-twitter-auth-type' => 'OAuth2Session',
        'x-twitter-client-language' => 'en',
        'x-twitter-active-user' => 'yes',
        'content-type' => 'application/x-www-form-urlencoded' );


# Send our tweet. 

$lwpua->default_headers($headers);
$response = $lwpua->post( $post_url, { 'tweet_mode' => 'extended', 'status' => $text, 'enable_dm_commands' => 'true', 'fail_dm_commands' => 'true' }, @post_headers );

# Save our cookies.

$cookie_jar->save;

if ( $verbose ) {
	        print "[*] Done!\n";                                                                      }


exit 0; 

###############################################################################
# Get_CT0 - This function searches for the ct0 cookie use in the csrf token.
# We basically force a login and this function hunts own the ct0 cookie in 
# the cookie jar.
###############################################################################

sub Get_CT0
{


# Open cookie jar file. 

if (!open(COOKIE_FILE, "<", $cookie_file)) 
	{ 
	die "[E] Cannot open configuration file [$!]\n"; 
	}

while (<COOKIE_FILE>)
        {

	chomp;

	# Split apart the cookie jar and start search for ct0

        ($cookie_tmp, $t1, $t1, $t1, $t1, $expire_tmp, $t1) = split(/;/, $_);
        ($t1, $cookie_tmp2 ) = split(/:/, $cookie_tmp);
        $cookie_tmp2 =~ s/ //g;

        ($cookie_key, $cookie_value) = split(/=/, $cookie_tmp2);

	# Found ct0! Yay. 

        if ( $cookie_key eq "ct0" ) {

                ( $trash, $expire_time) = split(/"/, $expire_tmp);

		if ( $verbose ) { 
                	print "[*] Found x-csrf-token/ct0 cookie: $cookie_value, Expires: $expire_time\n";
		}

                $dt = Time::Piece->strptime( $expire_time, '%Y-%m-%d %H:%M:%SZ' );

		# Doh! ct0 token has expired.  Let's try this again (login).
	
                if ( $utime >= $dt->epoch ) {

				if ( $verbose ) { 
				print "[*] x-csrf-token token! / ct0 expired.  Logging back into Twitter.\n";
				}

				close(COOKIE_FILE);
				unlink($cookie_file)
				&Login();
				return "0"; 

                }

		close(COOKIE_FILE);
		return $cookie_value; 

        	}
	}


close(COOKIE_FILE);
return "0"; 

}

###############################################################################
# Login - Does the https login to twitter.
###############################################################################

sub Login
{

@login_headers = ('Referer' => 'http://m.twitter.com', 'User-Agent' => $user_agent);

# Get authenticity token.

$response = $lwpua->get('https://mobile.twitter.com/session/new', @login_headers);
$form_data = $response->content;

$form_data =~ s/\n//g;
$form_data =~ /input name="authenticity_token" type="hidden" value="(.*?)"/ig;
$auth_token = $1;

# Login to Twitter

$response = $lwpua->post('https://mobile.twitter.com/session',
                            ['username' => $username,
                             'password' => $password,
                             'authenticity_token' => $auth_token], @login_headers);


if ( $verbose ) 
	{
	print "Login Response: \"" . $response->content . "\"\n";
	}

$cookie_jar->extract_cookies( $response );
$cookie_jar->save;

}
