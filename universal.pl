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
                              'debug' => '1',
                              'trace' => '1',
                            } 
                          );
exit unless $poe;
#$poe->object_session(  
#                      new Jarvis::IRC(
#                                       {
#                                         'alias'        => 'irc_client',
#                                         'nickname'     => 'fapestniegd',
#                                         'ircname'      => 'Optimus Prime',
#                                         'server'       => '127.0.0.1',
#                                         'channel_list' => [ 
#                                                             '#puppies',
#                                                           ]
#                                       }
#                                     ), 
#                    );

print $ENV{'XMPP_PASSWORD'}."\n";
$poe->object_session( 
                      new Jarvis::Jabber(
                                          {
                                            'alias'           => 'xmpp_client',
                                            'ip'              => '127.0.0.1',
                                            'port'            => '5222',
                                            'domain'          => 'websages.com',
                                            'username'        => 'crunchy',
                                            'password'        => $ENV{'XMPP_PASSWORD'},
                                          }
                                        ), 
                    );

#print STDERR "\n\n\n\n\n".Data::Dumper->Dump([$poe]);
POE::Kernel->run();
