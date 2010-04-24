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

my $poe = new POE::Builder( 
                            {
                              'debug' => '0',
                              'trace' => '1',
                            } 
                          );
exit unless $poe;
$poe->object_session( 
                      new Jarvis::IRC(
                                       {
                                         'alias'        => 'irc_client',
                                         'nickname'     => 'fapestniegd',
                                         'ircname'      => 'Optimus Prime',
                                         'server'       => 'irc.debian.org',
                                         'channel_list' => [ 
                                                             '#puppies',
                                                           ]
                                       }
                                     ), 
                    );

$poe->object_session( 
                      new Jarvis::Jabber(
                                          {
                                            'alias'           => 'xmpp_client',
                                            'ip'              => 'thor.websages.com',
                                            'port'            => '5222',
                                            'domain'          => 'websages.com',
                                            'username'        => 'crunchy',
                                            'password'        => $ENV{'XMPP_PASSWORD'},
                                          }
                                        ), 
                    );

#print STDERR "\n\n\n\n\n".Data::Dumper->Dump([$poe]);
POE::Kernel->run();

