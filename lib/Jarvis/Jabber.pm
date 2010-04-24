package Jarvis::Jabber;
use Filter::Template;                                           #this is only a shortcut
const XNode POE::Filter::XML::Node

use warnings;
use strict;
use Data::Dumper;
use POE;
use POE;                                    #include POE constants
use POE::Component::Jabber;                 #include PCJ
use POE::Component::Jabber::Error;          #include error constants
use POE::Component::Jabber::Status;         #include status constants
use POE::Component::Jabber::ProtocolFactory;#include connection type constants
use POE::Filter::XML::Node;                 #include to build nodes
use POE::Filter::XML::NS qw/ :JABBER :IQ /; #include namespace constants
use POE::Filter::XML::Utils;                #include some general utilites
use Carp;

sub new   { 
             my $class = shift; 
             my $self = {}; 
             my $construct = shift if @_;
             foreach my $attr ("ip", "port", "domain", "username", "password", "alias", "connection_type"){
                 if(defined($construct->{$attr})){ 
                     $self->{$attr} = $construct->{$attr}; 
                 }else{
                     print STDERR "Required constructor attribute [$attr] not defined. Terminating XMPP session\n";
                     return undef;
                 }
             }
             if(defined($construct->{'handle'})){ $self->{'handle'} = $construct->{'handle'}; }
             $self->{'states'} = { 
                                   _start               => '_start',
                                   _stop                => '_stop',
                                   input_event          => 'input_event',
                                   error_event          => 'error_event',
                                   status_event         => 'status_event',
                                   #test_message         => 'test_message',
                                   #output_event         => 'output_event',
                                   #join_channel         => 'join_channel',
                                   #leave_channel        => 'leave_channel',
                                   #send_presence        => 'send_presence',
                                   #presence_subscribe   => 'presence_subscribe',
                                   #approve_subscription => 'approve_subscription',
                                   #refuse_subscription  => 'refuse_subscription',
                                 };
             $self->{'xmpp_client'} =  POE::Component::Jabber->new(
                                                                    IP             => $self->{'ip'},
                                                                    Port           => $self->{'port'},
                                                                    Hostname       => $self->{'domain'},
                                                                    Username       => $self->{'username'},
                                                                    Password       => $self->{'password'},
                                                                    Alias          => $self->{'alias'},
                                                                    ConnectionType => $self->{'connection_type'},
                                                                    States         => {
                                                                                        StatusEvent => 'status_event',
                                                                                        InputEvent => 'input_event',
                                                                                        ErrorEvent => 'error_event',
                                                                                      }
                                                                  );

                                                


             bless($self,$class); 
             return $self 
           }
sub _start { my $self = $_[OBJECT]; print STDERR ref($self)." start\n"; $self->{'xmpp_client'}->yield("connect"); }
sub _stop  { my $self = $_[OBJECT]; print STDERR ref($self)." stop\n";  }
sub states { my $self = $_[OBJECT]; return $self->{'states'}; }
sub handle { my $self = $_[OBJECT]; return $self->{'handle'};           }
sub input_event  { my $self = $_[OBJECT]; print STDERR "xmpp input_event\n"; }
sub error_event  { my $self = $_[OBJECT]; print STDERR "xmpp error_event\n"; }
sub status_event { my $self = $_[OBJECT]; print STDERR "xmpp status_event\n"; }

1;
