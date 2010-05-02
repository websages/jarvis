#!/usr/bin/perl
$ENV{'PATH'}='/usr/local/bin:/usr/bin:/bin';
$ENV{'IFS'}=' \t\n';

# abort if we have no xmpp creds
if(!defined($ENV{'XMPP_PASSWORD'})){
    print "Please set XMPP_PASSWORD\n";
    exit 1;
}

BEGIN { unshift @INC, './lib' if -d './lib'; }
use Data::Dumper;
use Jarvis::IRC;
use Jarvis::Jabber;
use Jarvis::Persona::Crunchy;
#use Jarvis::Persona::Jarvis;
use Jarvis::Persona::System;
#use Jarvis::Persona::Watcher;
use POE::Builder;
$|++;

# get a handle for our builder
my $poe = new POE::Builder({ 'debug' => '0','trace' => '0' });
exit unless $poe;

# instantiate the system personality
$poe->object_session(
                      new Jarvis::Persona::System(
                                                   { 
                                                     'alias' => 'system',
                                                   }
                                                 )
                    );
# connect to irc
$poe->object_session(  
                      new Jarvis::IRC(
                                       {
                                         'alias'        => 'system_session',
                                         'nickname'     => 'loki',
                                         'ircname'      => 'loki.websages.com',
                                         'server'       => '127.0.0.1',
                                         'domain'       => 'websages.com',
                                         'channel_list' => [ 
                                                             '#asgard',
                                                           ],
                                         'persona'      => 'system',
                                       }
                                     ), 
                    );
# connect to jabber
$poe->object_session( 
                      new Jarvis::Jabber(
                                          {
                                            'alias'           => 'loki_xmpp',
                                            'ip'              => 'thor.websages.com',
                                            'port'            => '5222',
                                            'hostname'        => 'websages.com',
                                            'username'        => 'crunchy',
                                            'password'        => $ENV{'XMPP_PASSWORD'},
                                            'channel_list'    => [ 
                                                                   'asgard@conference.websages.com/loki',
                                                                 ],
                                            'persona'         => 'system',
                                            'ignore_direct'   => 1,
                                          }
                                        ), 
                    );
POE::Kernel->run();
