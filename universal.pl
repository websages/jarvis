#!/usr/bin/perl
$ENV{'PATH'}='/usr/local/bin:/usr/bin:/bin';
$ENV{'IFS'}=' \t\n';
BEGIN { unshift @INC, './lib' if -d './lib'; }

use Data::Dumper;
use Jarvis::IRC;
use Jarvis::Jabber;
#use Jarvis::Personality::Jarvis;
#use Jarvis::Personality::Crunchy;
#use Jarvis::Personality::Watcher;
use POE::Builder;

my $session = new POE::Builder;
   $session->add_poe_object( 
                             new Jarvis::IRC(
                                              {
                                                'handle'    => 'irc',
                                                'nickname' => 'autobot',
                                                'ircname'  => 'Optimus Prime',
                                                'server'   => 'irc.eftdomain.net',
                                                'channels' => [ 
                                                                '#puppies',
                                                              ]
                                              }
                                            ), 
                             'irc'
                           );
   $session->add_poe_object( new Jarvis::Jabber(
                                                 {
                                                   'handle'   => 'xmpp',
                                                   'IP'       => 'thor.websages.com',
                                                   'Port'     => '5222',
                                                   'Hostname' => 'websages.com',
                                                   'Username' => 'crunchy',
                                                   'Password' => $ENV{'XMPP_PASSWORD'},
                                                   'Alias'    => 'xmpp_client',
                                                   'ConnectionType' => +XMPP,
                                                 }
                                               ), 
                             'xmpp'
                           );
   $session->create();

POE::Kernel->run();

print STDERR "\n\n\n\n\n".Data::Dumper->Dump([$session]);
