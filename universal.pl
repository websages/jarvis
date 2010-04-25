#!/usr/bin/perl
$ENV{'PATH'}='/usr/local/bin:/usr/bin:/bin';
$ENV{'IFS'}=' \t\n';
BEGIN { unshift @INC, './lib' if -d './lib'; }

use Data::Dumper;
use Jarvis::IRC;
use Jarvis::Jabber;
#use Jarvis::Persona::Crunchy;
#use Jarvis::Persona::Jarvis;
#use Jarvis::Persona::System;
#use Jarvis::Persona::Watcher;
use POE::Builder;

my $poe = new POE::Builder({ 'debug' => '0','trace' => '0' });
exit unless $poe;

# irc bot sessions are 1:1 session:nick, but that nick may be in several chats
$poe->object_session(  
                      new Jarvis::IRC(
                                       {
                                         'alias'        => 'irc_client',
                                         'nickname'     => 'crunchy',
                                         'ircname'      => 'Cap\'n Crunchbot',
                                         'server'       => '127.0.0.1',
                                         'channel_list' => [ 
                                                             '#puppies',
                                                           ],
                                         'persona'      => 'crunchy',
                                       }
                                     ), 
                    );

$poe->object_session(  
                      new Jarvis::IRC(
                                       {
                                         'alias'        => 'system_session',
                                         'nickname'     => 'loki',
                                         'ircname'      => 'loki.websages.com',
                                         'server'       => '127.0.0.1',
                                         'channel_list' => [ 
                                                             '#global',
                                                             '#puppies',
                                                           ],
                                         'persona'      => 'system',
                                       }
                                     ), 
                    );

# xmpp bot sessions are 1:n for session:room_nick, #
# (one login can become different nicks in group chats on the same server)

$poe->object_session( 
                      new Jarvis::Jabber(
                                          {
                                            'alias'           => 'xmpp_client',
                                            'ip'              => 'thor.websages.com',
                                            'port'            => '5222',
                                            'hostname'        => 'websages.com',
                                            'username'        => 'crunchy',
                                            'password'        => $ENV{'XMPP_PASSWORD'},
                                            'channel_list'    => [ 
                                                                   'loki@system',
                                                                 ],
                                            'persona'         => 'system',
                                          }
                                        ), 
                    );

POE::Kernel->run();
