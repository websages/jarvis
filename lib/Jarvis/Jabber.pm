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
             #foreach my $attr ("ip", "port", "domain", "username", "password", "alias", "parent_session"){
             foreach my $attr ("ip", "port", "domain", "username", "password", "alias"){
                 if(defined($construct->{$attr})){ 
                     $self->{$attr} = $construct->{$attr}; 
                 }else{
                     print STDERR "Required constructor attribute [$attr] not defined. Terminating XMPP session\n";
                     return undef;
                 }
             }
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
             bless($self,$class); 
             return $self 
           }
sub _start { 
    my ($kernel, $heap, $self) = @_[KERNEL, HEAP, OBJECT]; 
    print STDERR ref($self)." start\n"; 
    $self->{'xmpp_client'} =  POE::Component::Jabber->new(
                                                           IP             => $self->{'ip'},
                                                           Port           => $self->{'port'},
                                                           Hostname       => $self->{'domain'},
                                                           Username       => $self->{'username'},
                                                           Password       => $self->{'password'},
                                                           Alias          => $self->{'alias'},
                                                           ConnectionType => +XMPP,
#                                                           StateParent    => $self->{'parent_session'},
                                                           States         => {
                                                                               StatusEvent => 'status_event',
                                                                               InputEvent => 'input_event',
                                                                               ErrorEvent => 'error_event',
                                                                             }
                                                         );

    $kernel->post($self->alias(),"connect"); 
}
sub _stop  { my $self = $_[OBJECT]; print STDERR ref($self)." stop\n";  }
sub states { my $self = $_[OBJECT]; return $self->{'states'}; }
sub alias { my $self = $_[OBJECT]; return $self->{'alias'};           }
sub status_event { 
    my ($kernel, $sender, $heap, $state, $self) = @_[KERNEL, SENDER, HEAP, ARG0, OBJECT]; 
    my $jabstat= [ 'PCJ_CONNECT', 'PCJ_CONNECTING', 'PCJ_CONNECTED',
                       'PCJ_STREAMSTART', 'PCJ_SSLNEGOTIATE', 'PCJ_SSLSUCCESS',
                       'PCJ_AUTHNEGOTIATE', 'PCJ_AUTHSUCCESS', 'PCJ_BINDNEGOTIATE',
                       'PCJ_BINDSUCCESS', 'PCJ_SESSIONNEGOTIATE', 'PCJ_SESSIONSUCCESS',
                       'PCJ_NODESENT', 'PCJ_NODERECEIVED', 'PCJ_NODEQUEUED',
                       'PCJ_RTS_START', 'PCJ_RTS_FINISH', 'PCJ_INIT_FINISHED',
                       'PCJ_STREAMEND', 'PCJ_SHUTDOWN_START', 'PCJ_SHUTDOWN_FINISH', ];

        # In the example we only watch to see when PCJ is finished building the
        # connection. When PCJ_INIT_FINISHED occurs, the connection ready for use.
        # Until this status event is fired, any nodes sent out will be queued. It's
        # the responsibility of the end developer to purge the queue via the 
        # purge_queue event.

        if($state == +PCJ_INIT_FINISHED)
        {
                # Notice how we are using the stored PCJ instance by calling the jid()
                # method? PCJ stores the jid that was negotiated during connecting and 
                # is retrievable through the jid() method

                my $jid = $heap->{'component'}->jid();
                print "INIT FINISHED! \n";
                print "JID: $jid \n";
                print "SID: ". $sender->ID() ." \n\n";

                $heap->{'jid'} = $jid;
                $heap->{'sid'} = $sender->ID();

                $kernel->post($self->alias(), 'output_handler', XNode->new('presence'));

                # And here is the purge_queue. This is to make sure we haven't sent
                # nodes while something catastrophic has happened (like reconnecting).

                $kernel->post($self->alias(), 'purge_queue');

                $heap->{'roomnick'} = 'system@conference.websages.com/crunchy';
                #$kernel->yield('presence_subscribe','whitejs@websages.com');
                $kernel->yield('join_channel','system');

                #for(1..10)
                #{
                #       $kernel->delay_add('test_message', int(rand(10)));
                #}
        }
        print "Status received: $jabstat->[$state] \n";
}

# This is the error event. Any error conditions that arise from any point 
# during connection or negotiation to any time during normal operation will be
# send to this event from PCJ. For a list of possible error events and exported
# constants, please see PCJ::Error

sub error_event()
{
        my ($kernel, $sender, $heap, $error, $self) = @_[KERNEL, SENDER, HEAP, ARG0, OBJECT];

        if($error == +PCJ_SOCKETFAIL)
        {
                my ($call, $code, $err) = @_[ARG1..ARG3];
                print "Socket error: $call, $code, $err\n";
                print "Reconnecting!\n";
                $kernel->post($sender, 'reconnect');

        } elsif($error == +PCJ_SOCKETDISCONNECT) {

                print "We got disconneted\n";
                print "Reconnecting!\n";
                $kernel->post($sender, 'reconnect');

        } elsif($error == +PCJ_CONNECTFAIL) {

                print "Connect failed\n";
                print "Retrying connection!\n";
                $kernel->post($sender, 'reconnect');

        } elsif ($error == +PCJ_SSLFAIL) {

                print "TLS/SSL negotiation failed\n";

        } elsif ($error == +PCJ_AUTHFAIL) {

                print "Failed to authenticate\n";

        } elsif ($error == +PCJ_BINDFAIL) {

                print "Failed to bind a resource\n";

        } elsif ($error == +PCJ_SESSIONFAIL) {

                print "Failed to establish a session\n";
        }
}

sub input_event()
{
        my ($kernel, $heap, $node, $self) = @_[KERNEL, HEAP, ARG0, OBJECT];


        print "\n===PACKET RECEIVED===\n";
        print $node->to_str() . "\n";
        print $node->get_id() . "\n";
        if($node->name() eq 'presence'){
            print Data::Dumper->Dump([$node->get_attrs()]) . "\n";
            if($node->attr('type') eq 'subscribe'){
                if($node->attr('from') eq 'whitejs@websages.com'){
                    $kernel->yield('approve_subscription',$node->attr('from'));
                }
            }
        }
        print "=====================\n";
        #$kernel->delay_add('test_message', int(rand(10)));
}


1;
