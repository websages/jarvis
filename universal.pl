#!/usr/bin/perl
$ENV{'PATH'}='/usr/local/bin:/usr/bin:/bin';
$ENV{'IFS'}=' \t\n';
BEGIN { unshift @INC, './lib' if -d './lib'; }
# abort if we have no xmpp creds
if(!defined($ENV{'XMPP_PASSWORD'})){
    print "Please set XMPP_PASSWORD\n";
    exit 1;
}
use Data::Dumper;
use Jarvis::IRC;
use Jarvis::Jabber;
use Jarvis::Persona::Minimal;
use POE::Builder;
use Sys::Hostname::Long;
$|++;

# get our fqd, hostname, and domain name
my $fqdn     = hostname_long;
my $hostname = $fqdn;         $hostname=~s/\..*$//;
my $domain   = $fqdn;         $domain=~s/^[^\.]*\.//;

# get a handle for our builder
my $poe = new POE::Builder({ 'debug' => '0','trace' => '0' });
exit unless $poe;

########################################
# define the system personality 
# (so we have something to talk to)
########################################
my $persona = << "...";
---
class: Jarvis::Persona::Minimal
init: 
  alias: system
...

########################################
# definition to connect to irc
########################################
my $irc_connection = << "...";
---
class: Jarvis::IRC
init:
  alias: ${hostname}_irc
  nickname: ${hostname}
  ircname: ${fqdn}
  server: 127.0.0.1
  domain: ${domain}
  channel_list:
    - #asgard
  persona: system
...

########################################
# definition to connect to ejabberd
########################################
my $xmpp_connection = << "...";
---
class: Jarvis::Jabber
trace: 1
init: 
  alias: ${hostname}_xmpp
  ip: thor.websages.com
  port: 5222
  hostname: ${domain}
  username: ${hostname}
  password: ${ENV{'XMPP_PASSWORD'}}
  channel_list: 
    - asgard\@conference.websages.com/${hostname}
  persona: system
...

################################################################################
# Do the work
################################################################################
$poe->yaml_sess($persona);
$poe->yaml_sess($irc_connection);
$poe->yaml_sess($xmpp_connection);
# fire up the kernel
POE::Kernel->run();
