#!/usr/bin/perl
use strict;
################################################################################
# a universal bot for multiple personalities
#
$ENV{'PATH'}='/usr/local/bin:/usr/bin:/bin';
$ENV{'IFS'}=' \t\n';
################################################################################
# Add local libraries
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
my $persona = YAML::Load(<< "...");
persona:
  class: Jarvis::Persona::System
  init:
    alias: system
    trace: 0
    debug: 0
    peer_group: cn=bot_managed
    ldap_bindpw: ${ENV{'SECRET'}}
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
    - class: Jarvis::Jabber
      init:
        alias: ${hostname}_xmpp
        ip: ${hostname}.${domain}
        port: 5222
        hostname: ${domain}
        username: ${hostname}
        password: ${ENV{'XMPP_PASSWORD'}}
        channel_list:
          - asgard\@conference.${domain}/${hostname}
        persona: system
...
################################################################################
# a list of the personas I can spawn goes into known_personas
$persona->{'persona'}->{'init'}->{'known_personas'} = YAML::Load(<< "...");
---
  - name: crunchy
    persona:
      class: Jarvis::Persona::Crunchy
      init:
        alias: crunchy
        ldap_domain: ${domain}
        ldap_binddn: cn=${hostname},ou=Hosts,${basedn}
        ldap_bindpw: ${ENV{'LDAP_PASSWORD'}}
        twitter_name: capncrunchbot
        password: ${ENV{'TWITTER_PASSWORD'}}
        retry: 150
        start_twitter_enabled: 0
    connectors:
      - class: Jarvis::IRC
        init:
          alias: crunchy_irc
          nickname: crunchy
          ircname: "Cap'n Crunchbot"
          server: 127.0.0.1
          domain: ${domain}
          channel_list:
            - #soggies
          persona: crunchy
  - name: berry
    persona:
      class: Jarvis::Persona::Crunchy
      init:
        alias: berry
        ldap_domain: ${domain}
        ldap_binddn: cn=${hostname},ou=Hosts,${basedn}
        ldap_bindpw: ${ENV{'LDAP_PASSWORD'}}
        twitter_name: capncrunchbot
        password: ${ENV{'TWITTER_PASSWORD'}}
        retry: 150
        start_twitter_enabled: 1
    connectors:
      - class: Jarvis::IRC
        init:
          alias: berry_irc
          nickname: berry
          ircname: "beta Cap'n Crunchbot"
          server: 127.0.0.1
          domain: ${domain}
          channel_list:
            - #twoggies
          persona: berry
  - name: jarvis
    persona:
      class: Jarvis::Persona::Jarvis
      init:
        alias: jarvis
        connector: jarvis_irc
        ldap_domain: ${domain}
        ldap_binddn: cn=${hostname},ou=Hosts,${basedn}
        ldap_bindpw: ${ENV{'LDAP_PASSWORD'}}
    connectors:
      - class: Jarvis::IRC
        init:
          alias: jarvis_irc
          persona: jarvis
          nickname: jarvis
          ircname: "Just another really vigilant infrastructure sysadmin"
          server: 127.0.0.1
          domain: ${domain}
          channel_list:
            - #puppies
...
###############################################################################
$poe->yaml_sess(YAML::Dump( $persona->{'persona'} ));
foreach my $connector (@{ $persona->{'persona'}->{'connectors'} }){
    $poe->yaml_sess(YAML::Dump($connector));
}
################################################################################
# fire up the kernel
POE::Kernel->run();
