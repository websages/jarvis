#!/usr/bin/perl
$ENV{'PATH'}='/usr/local/bin:/usr/bin:/bin';
$ENV{'IFS'}=' \t\n';
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
use Jarvis::Persona::Watcher;
use POE::Builder;
$|++;
my $IRC=0;
my $XMPP=1;

################################################################################
# We create a persona session, and give it an alias. We then create IRC/XMPP
# sessions, and tell them to which persona alias to direct incoming messages.
# The 'persona' session will reply to the 'chat' session that sent it the 
# message for which the reply is intended. 
#
# Repeat for multiple chat sesions and personas...
################################################################################

my $poe = new POE::Builder({ 'debug' => '0','trace' => '1' });
exit unless $poe;

# We set up some personas to redirect various traffic to...
$poe->object_session(
                      new Jarvis::Persona::Crunchy(
                                                    { 
                                                      'alias'       => 'crunchy',
                                                      'ldap_domain' => 'websages.com',
                                                      'ldap_binddn' => 'uid=crunchy,ou=People,dc=websages,dc=com',
                                                      'ldap_bindpw' => $ENV{'LDAP_PASSWORD'},
                                                      #'screenname'       => 'capncrunchbot',
                                                      #'username'         => 'capncrunchbot',
                                                      #'password'         => $ENV{'TWITTER_PASSWORD'},
                                                    }
                                                  )
                    );

$poe->object_session(
                      new Jarvis::Persona::System(
                                                    { 
                                                      'alias' => 'system',
                                                    }
                                                  )
                    );


# irc bot sessions are 1:1 session:nick, but that nick may be in several chats
if($IRC){
    $poe->object_session(  
                          new Jarvis::IRC(
                                           {
                                             'alias'        => 'irc_client',
                                             'nickname'     => 'crunchy',
                                             'ircname'      => 'Cap\'n Crunchbot',
                                             'server'       => '127.0.0.1',
                                             'channel_list' => [ 
                                                                 '#soggies',
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
                                                                 '#asgard',
                                                                 '#midgard',
                                                               ],
                                             'persona'      => 'system',
                                           }
                                         ), 
                        );
}

# xmpp bot sessions are 1:n for session:room_nick, #
# (one login can become different nicks in group chats on the same server)

# Adding additional multi-user-chats works, but direct-messages will not go to the chat-persona, 
# but to the last chat persona instanciated, so it's best to define a accout-persona for
# xmpp bots with the 'account-persona' attribute and to keep it the same persona for all xmpp sessions.
# (Right now this is not implemented and it appears the first persona defined is used...)

if($XMPP){
    $poe->object_session( 
                          new Jarvis::Jabber(
                                              {
                                                'alias'           => 'crunchy_xmpp',
                                                'ip'              => 'thor.websages.com',
                                                'port'            => '5222',
                                                'hostname'        => 'websages.com',
                                                'username'        => 'crunchy',
                                                'password'        => $ENV{'XMPP_PASSWORD'},
                                                'channel_list'    => [ 
                                                                       'soggies@conference.websages.com/crunchy',
                                                                     ],
                                                'persona'         => 'crunchy',
                                                'account-persona' => 'crunchy',
                                              }
                                            ), 
                        );
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
                                                                       'system@conference.websages.com/loki',
                                                                     ],
                                                'persona'         => 'system',
                                                'account-persona' => 'crunchy',
                                              }
                                            ), 
                        );
}

POE::Kernel->run();
