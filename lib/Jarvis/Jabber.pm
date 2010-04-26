#!/usr/bin/perl
package Jarvis::Jabber;
use Filter::Template;
const XNode POE::Filter::XML::Node
use warnings;
use strict;
use Data::Dumper;
use POE;
use POE::Component::Jabber;
use POE::Component::Jabber::Error;
use POE::Component::Jabber::Status;
use POE::Component::Jabber::ProtocolFactory;
use POE::Filter::XML::Node;
use POE::Filter::XML::NS qw/ :JABBER :IQ /;
use POE::Filter::XML::Utils;
use Carp;

sub new{
    my $class = shift;
    my $self = {};
    my $construct = shift if @_;
    $self->{'DEBUG'} = 3 unless defined $construct->{'debug'}; 
    # list of required constructor elements
    $self->{'must'} = [ "alias", "ip", "hostname", "username", "password" ];

    # hash of optional constructor elements (key), and their default (value) if not specified
    $self->{'may'} = { 
                       "channel_list" => undef,
                       "port"         => 5222,
                     };

    # set our required values fron the constructor or the defaults
    foreach my $attr (@{ $self->{'must'} }){
         if(defined($construct->{$attr})){
             $self->{$attr} = $construct->{$attr};
         }else{
             print STDERR "Required session constructor attribute [$attr] not defined. ";                                                     
             print STDERR "unable to define ". __PACKAGE__ ." object\n";
             return undef;
         }
    }

    # set our optional values fron the constructor or the defaults
    foreach my $attr (keys(%{ $self->{'may'} })){
         if(defined($construct->{$attr})){
             $self->{$attr} = $construct->{$attr};
         }else{
             $self->{$attr} = $self->{'may'}->{$attr};
         }
    }

    bless($self,$class);
    foreach my $key (%{ $construct }){
        $self->{$key} = $construct->{$key};
    }
    $self->{'states'} = {
                          _start               => '_start',
                          _stop                => '_stop',
                          input_event          => 'input_event',
                          error_event          => 'error_event',
                          status_event         => 'status_event',
                          test_message         => 'test_message',
                          output_event         => 'output_event',
                          join_channel         => 'join_channel',
                          leave_channel        => 'leave_channel',
                          send_presence        => 'send_presence',
                          presence_subscribe   => 'presence_subscribe',
                          refuse_subscription  => 'refuse_subscription',
                          approve_subscription => 'approve_subscription',
                        };

    return $self;
}

sub _start{
    my $self = $_[OBJECT]||shift;
    my $heap = $_[HEAP];
    my $kernel = $_[KERNEL];
    my $session = $_[SESSION];
    print STDERR __PACKAGE__ ." start\n";
    $heap->{$self->alias()} = POE::Component::Jabber->new(
                                                        IP             => $self->{'ip'},
                                                        Port           => $self->{'port'},
                                                        Hostname       => $self->{'hostname'},
                                                        Username       => $self->{'username'},
                                                        Password       => $self->{'password'},
                                                        Alias          => $self->alias().'component',
                                                        ConnectionType => +XMPP,
                                                        States         => {
                                                                            StatusEvent => 'status_event',
                                                                            InputEvent  => 'input_event',
                                                                            ErrorEvent  => 'error_event',
                                                                          },
                                                      );
    $kernel->post($self->alias().'component','connect');
    return $self;
}

sub _stop{
     my $self = $_[OBJECT]||shift;
    print STDERR __PACKAGE__ ." stop\n";
     return $self;
}

sub alias{
     my $self = $_[OBJECT]||shift;
     return $self->{'alias'};
}

sub states{
     my $self = $_[OBJECT]||shift;
     return $self->{'states'};
}
# The status event receives all of the various bits of status from PCJ. PCJ
# sends out numerous statuses to inform the consumer of events of what it is 
# currently doing (ie. connecting, negotiating TLS or SASL, etc). A list of 
# these events can be found in PCJ::Status.

sub status_event()
{
        my ($self, $kernel, $sender, $heap, $state) = @_[OBJECT, KERNEL, SENDER, HEAP, ARG0];
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

                my $jid = $heap->{$self->alias()}->jid();
                print "INIT FINISHED! \n";
                print "JID: $jid \n";
                print "SID: ". $sender->ID() ." \n\n";
                
                $heap->{'jid'} = $jid;
                $heap->{'sid'} = $sender->ID();
        
                $kernel->post($self->alias().'component','output_handler', XNode->new('presence'));
                
                # And here is the purge_queue. This is to make sure we haven't sent
                # nodes while something catastrophic has happened (like reconnecting).
                
                $kernel->post($self->alias().'component','purge_queue');

#                my $online_node=XNode->new('presence',[ 'show', 'Online']);
#                $kernel->yield(output_event',$online_node);
#
#                my $reserved_nick_req = XNode->new('iq', [ 
#                                                           'from', $jid,
#                                                           'id', 'crunchy',
#                                                           'to', 'system@websages.com',
#                                                           'type', 'get',
#                                                         ]
#                                                  );
#                $reserved_nick_req->insert_tag('query', [
#                                              'xmlns', 'http://jabber.org/protocol/disco#info', 
#                                              'node', 'x-roomuser-item'
#                                            ]
#                                  );
#                $kernel->yield(output_event', $reserved_nick_req);
#
#                my $node=XNode->new('presence', [ 
#                                                  'to', 'system@conference.websages.com/crunchy',
#                                                  'from', $jid,
#                                                  'x', [xmlns=>"http://jabber.org/protocol/muc"],
#                                                ]
#                                   );
#                my $child_node=XNode->new('x',[xmlns=>"http://jabber.org/protocol/muc"]);
#                $node->insert_tag($child_node);
#
#                $kernel->yield(output_event',$node);
               
                if(defined($self->{'channel_list'})){
                    foreach my $muc (@{ $self->{'channel_list'} }){
                        #$heap->{'roomnick'} = 'system@conference.websages.com/crunchy';
                        #$kernel->yield(presence_subscribe','whitejs@websages.com');
                        $kernel->post($self->alias(),'join_channel', $muc);
                    }
                }

                #for(1..10)
                #{
                #        $kernel->delay_add('test_message', int(rand(10)));
                #}
        }
        print "Status received: $jabstat->[$state] \n";
}

# This is the input event. We receive all data from the server through this
# event. ARG0 will a POE::Filter::XML::Node object.

sub input_event()
{
        my ($self, $kernel, $heap, $node) = @_[OBJECT, KERNEL, HEAP, ARG0];
        
        
        print "\n===PACKET RECEIVED===\n" if $self->{'DEBUG'} > 2;
        print "1. " . $node->to_str() . "\n" if $self->{'DEBUG'} > 2;
        print "2. " . $node->get_id() . "\n" if $self->{'DEBUG'} > 2;
        print "3. " . ref($node) . "\n" if $self->{'DEBUG'} > 2;
        if($self->{'DEBUG'} > 2){
            my $nodedata = $node->get_attrs();
            foreach my $key ( keys(%{ $nodedata }) ){ print $key .": ". $nodedata->{$key} ."\n";} 
        }
        # allow everyone in websages to subscribe to our presence.
        if($node->name() eq 'presence'){
            if($node->attr('type') ){
                if($node->attr('type') eq 'subscribe'){
                    if($node->attr('from') =~m /\@websages.com/){
                        $kernel->post($self->alias(),'approve_subscription',$node->attr('from'));
                    }
                }
            }
        }
        foreach my $child ($node->get_children()){ 
            print ref($child)."\n";
            foreach my $childnode ( @{ $child } ){ 
                my $childnodedata = $childnode->get_attrs();
                foreach my $ckey ( keys(%{ $childnodedata }) ){ print $ckey .": ". $childnodedata->{$ckey} ."\n";} 
            }
        }

        #$kernel->post("$self->{'persona'}", "$self->{'persona'}_input", $who, $where, $what, 'xmpp_public');

        print "=====================\n" if $self->{'DEBUG'} > 2;
        #$kernel->delay_add('test_message', int(rand(10)));
                
}

sub test_message()
{
        my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
        
        my $node = XNode->new('message');
        
        # get_bare_jid is a helper method included from POE::Filter::XML::Utils.
        # It returns the user@domain part of the jid (ie. no resources)

        #$node->attr('to', get_bare_jid($heap->{'jid'}));
        $node->attr('to', 'whitejs@websages.com');

        $node->insert_tag('body')->data('This is a test sent at: ' . time());
        
        $kernel->post($self->alias(),'output_event', $node, $heap->{'sid'});

}

# This is our own output_event that is a simple passthrough on the way to
# post()ing to PCJ's output_handler so it can then send the Node on to the
# server

sub output_event()
{
        my ($self, $kernel, $heap, $node, $sid) = @_[OBJECT, KERNEL, HEAP, ARG0, ARG1];
        
        print "\n===PACKET SENT===\n" if $self->{'DEBUG'} > 2;
        print $node->to_str() . "\n" if $self->{'DEBUG'} > 2;
        print "=================\n" if $self->{'DEBUG'} > 2;
        
        $kernel->post($sid, 'output_handler', $node);
}

# This is the error event. Any error conditions that arise from any point 
# during connection or negotiation to any time during normal operation will be
# send to this event from PCJ. For a list of possible error events and exported
# constants, please see PCJ::Error

sub error_event()
{
        my ($self, $kernel, $sender, $heap, $error) = @_[OBJECT, KERNEL, SENDER, HEAP, ARG0];

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

sub join_channel() {
    my ($self, $kernel, $heap, $room) = @_[OBJECT, KERNEL, HEAP, ARG0];
    $heap->{'starttime'} = time;
    my $node=XNode->new('presence', [ 'to', $room, 'from', $heap->{ $self->alias() }->jid(), ]);
    my $child_node=XNode->new('x',[xmlns=>"http://jabber.org/protocol/muc"]);
    $node->insert_tag($child_node);
    $kernel->post($self->alias(),'output_event',$node,$heap->{'sid'});
} # join channel

sub presence_subscribe() {
    my ($self, $kernel, $heap, $tgt_jid) = @_[OBJECT, KERNEL, HEAP, ARG0];
    $kernel->post($self->alias(),'send_presence',$tgt_jid,'subscribe');
} # presence_subscribe

sub approve_subscription() {
    my ($self, $kernel, $heap, $tgt_jid) = @_[OBJECT, KERNEL, HEAP, ARG0];
    #
    $kernel->post($self->alias(),'send_presence',$tgt_jid,'subscribed');
} # approve_subscription

sub refuse_subscription() {
    my ($self, $kernel, $heap, $tgt_jid) = @_[OBJECT, KERNEL, HEAP, ARG0];
    #
    $kernel->post($self->alias(),'send_presence',$tgt_jid,'unsubscribed');
} # refuse_subscription

sub leave_channel() {
    my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
    $kernel->post($self->alias(),'send_presence', $heap->{'roomnick'},'unavailable');
} # leave_channel


sub send_presence() {
    my ($self, $kernel, $heap, $tgt_jid, $type) = @_[OBJECT, KERNEL, HEAP, ARG0, ARG1];
    my $node=XNode->new('presence');
    $node->attr('to',$tgt_jid );
    $node->attr('from', $heap->{$self->alias()}->jid() );
    $node->attr('type',$type) if $type;
    $kernel->post($self->alias(),'output_event',$node,$heap->{'sid'});
} # send_presence
1;
