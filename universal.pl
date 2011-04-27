#!/usr/bin/perl
$ENV{'PATH'}='/usr/local/bin:/usr/bin:/bin';
$ENV{'IFS'}=' \t\n';
BEGIN { 
        my $libdirs= [
                       "/tmp/lib/perl5/site_perl/5.8.8/i386-linux-thread-multi",
                       "/tmp/lib/perl5/5.8.8/i386-linux-thread-multi/",
                       "/tmp/lib/perl5/site_perl/5.8.8/",
                       "/tmp/lib/perl5/5.8.8/",
                       "./lib",
                     ];
        foreach my $dir (@{$libdirs}){ unshift @INC, $dir if -d $dir; };
      }

# abort if we have no xmpp creds
if(!defined($ENV{'XMPP_PASSWORD'})){
    print "Please set XMPP_PASSWORD\n";
    exit 1;
}
use Data::Dumper;
use Jarvis::IRC;
use Jarvis::Jabber;
#use Jarvis::Persona::Minimal;
#use Jarvis::Persona::MegaHAL;
use Jarvis::Persona::System;
use Jarvis::Persona::Crunchy;
use Jarvis::Persona::Jarvis;
use POE::Builder;
use Sys::Hostname::Long;
#daemonize();

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
class: Jarvis::Persona::System
init: 
  alias: system
  trace: 1
  peer_group: cn=bot_managed
  ldap_bindpw: ${ENV{'SECRET'}}
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
init: 
  alias: ${hostname}_xmpp
  ip: ${hostname}.${domain}
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

sub daemonize {
    defined( my $pid = fork() ) or die "Can't fork: $!\n";
    exit if $pid;
    setsid or die "Can't start a new session: $!\n";
}
