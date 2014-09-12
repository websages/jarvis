#!/usr/bin/perl
use strict;
################################################################################
# a universal bot for multiple personalities
#
# all the $ENV varibles should be loaded from /etc/{default,sysconfig}/jarivs
# by the init script before running this script
#
$ENV{'PATH'}='/usr/local/bin:/usr/bin:/bin';
$ENV{'IFS'}=' \t\n';
################################################################################
# Add local libraries (we install them under us)
BEGIN {
        use Cwd;
        my $path=$0;
        $path=~s/\/[^\/]*$//;
        chdir($path);
        my $libdir=cwd()."/lib";
        my $cpanlib=cwd()."/cpan";
        my $libdirs= [
                       "$cpanlib/lib/perl5/site_perl/5.8.8/i386-linux-thread-multi",
                       "$cpanlib/lib/perl5/5.8.8/i386-linux-thread-multi/",
                       "$cpanlib/lib/perl5/site_perl/5.8.8/",
                       "$cpanlib/lib/perl5/5.8.8/",
                       "$libdir",
                     ];
        # add all of these to our library search path
        foreach my $dir (@{$libdirs}){ unshift @INC, $dir if -d $dir; };
      }
################################################################################
# Include our dependencies
use POSIX 'setsid';
use local::lib;
use Data::Dumper;
use Jarvis::IRC;
use Jarvis::Jabber;
use Jarvis::Persona::System;
use Jarvis::Persona::Crunchy;
use Jarvis::Persona::Jarvis;
use POE::Builder;
use Sys::Hostname::Long;
use Cwd;
################################################################################
#sub daemonize {
#    defined( my $pid = fork() ) or die "Can't fork: $!\n";
#    exit if $pid;
#    setsid() or die "Can't start a new session: $!\n";
#}
################################################################################
$|++;

################################################################################
# disable jabber if we have no xmpp creds
my $enable_jabber=1;
if(!defined($ENV{'XMPP_PASSWORD'})){
    $enable_jabber=0;
    print STDERR "no XMPP_PASSWORD, disabling XMPP\n";
}

################################################################################
# get a handle for our builder
my $poe = new POE::Builder({ 'debug' => '0','trace' => '0' });
exit unless $poe;

################################################################################
# get our fqd, hostname, domain name, and base dn (our assumptions)
my $fqdn     = hostname_long;
my $hostname = $fqdn;         $hostname=~s/\..*$//;
my $domain   = $fqdn;         $domain=~s/^[^\.]*\.//;
my $basedn   = "dc=".join(",dc=",split(/\./,$domain));
################################################################################
# This is the base (system) persona that controls the other personas
my $persona = YAML::Load(<< "...");
persona:
  class: Jarvis::Persona::System
  init:
    alias: system
    trace: 0
    debug: 0
    peer_group: cn=bot_managed
    ldap_bindpw: $ENV{'SECRET'}
  connectors:
    - class: Jarvis::IRC
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
################################################################################
# a list of the personas I can spawn goes into known_personas
$persona->{'persona'}->{'init'}->{'known_personas'} = YAML::Load(<< "...");
---
  - name: crunchy
    persona:
      persist: 1
      class: Jarvis::Persona::Crunchy
      init:
        alias: crunchy
        ldap_domain: ${domain}
        ldap_binddn: cn=${hostname},ou=Hosts,${basedn}
        ldap_bindpw: $ENV{'LDAP_PASSWORD'}
        dbi_connect: dbi:mysql:tumble:tumbledb.vpn.websages.com
        dbi_user: tumble
        start_twitter_enabled: 0
        twitter_name: capncrunchbot
        password: $ENV{'TWITTER_PASSWORD'}
        retry: 150
    connectors:
      - class: Jarvis::IRC
        init:
          alias: crunchy_irc
          nickname: crunchy
          ircname: "Cap'n Crunchbot"
          server: 127.0.0.1
          port: 8080
          usessl: 1
          username: $ENV{'IRC_ACCOUNT'}
          password: $ENV{'IRC_PASSWORD'}
          domain: ${domain}
          channel_list:
            - #soggies
          persona: crunchy
...
###############################################################################
# Start the system persona
#
$poe->yaml_sess(YAML::Dump( $persona->{'persona'} ));
#
# add it's connectors
#
foreach my $connector (@{ $persona->{'persona'}->{'connectors'} }){
    $poe->yaml_sess(YAML::Dump($connector));
}
################################################################################
# fire up the kernel
POE::Kernel->run();
