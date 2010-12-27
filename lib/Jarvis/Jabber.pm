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
use XML::Twig;

sub new{
    my $class = shift;
    my $self = {}; 
    my $construct = shift if @_;
    $self->{'DEBUG'} = 0 unless defined $construct->{'debug'}; 
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
                          start                => 'start',
                          stop                 => 'stop',
                          authen               => 'authen',

                          input_event          => 'input_event',
                          error_event          => 'error_event',
                          status_event         => 'status_event',
                          test_message         => 'test_message',
                          output_event         => 'output_event',

                          enable_input         => 'enable_input',

                          join_channel         => 'join_channel',
                          leave_channel        => 'leave_channel',
                          send_presence        => 'send_presence',
                          presence_subscribe   => 'presence_subscribe',
                          refuse_subscription  => 'refuse_subscription',
                          approve_subscription => 'approve_subscription',
                          xmpp_reply           => 'xmpp_reply',
                          say_public           => 'say_public',
                          reconnect_all        => 'reconnect_all',
                        };

    return $self;
}

sub start{
    my $self = $_[OBJECT]||shift;
    my $heap = $_[HEAP];
    my $kernel = $_[KERNEL];
    my $session = $_[SESSION];
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

sub stop{
     my $self = $_[OBJECT]||shift;
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

sub authen {
    my ($self, $kernel, $heap, $sender, $msg) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0];
    if(defined( $heap->{'presence'}->{ $msg->{'conversation'}->{'room'}.'/'.$msg->{'conversation'}->{'nick'} })){
        my $jid=$heap->{'presence'}->{ $msg->{'conversation'}->{'room'}.'/'.$msg->{'conversation'}->{'nick'} };
        $jid=~s/\/.*//g;
        $kernel->post($sender,'authen_reply', $msg, $jid);
    }else{
        $kernel->post($sender,'authen_reply', $msg, undef);
    }
}

# The status event receives all of the various bits of status from PCJ. PCJ
# sends out numerous statuses to inform the consumer of events of what it is 
# currently doing (ie. connecting, negotiating TLS or SASL, etc). A list of 
# these events can be found in PCJ::Status.

sub status_event()
{
        my ($self, $kernel, $sender, $heap, $state) = @_[OBJECT, KERNEL, SENDER, HEAP, ARG0];
        my $jabstat= [ 
                       'PCJ_CONNECT',       'PCJ_CONNECTING',       'PCJ_CONNECTED',
                       'PCJ_STREAMSTART',   'PCJ_SSLNEGOTIATE',     'PCJ_SSLSUCCESS',
                       'PCJ_AUTHNEGOTIATE', 'PCJ_AUTHSUCCESS',      'PCJ_BINDNEGOTIATE',
                       'PCJ_BINDSUCCESS',   'PCJ_SESSIONNEGOTIATE', 'PCJ_SESSIONSUCCESS',
                       'PCJ_NODESENT',      'PCJ_NODERECEIVED',     'PCJ_NODEQUEUED',
                       'PCJ_RTS_START',     'PCJ_RTS_FINISH',       'PCJ_INIT_FINISHED',
                       'PCJ_STREAMEND',     'PCJ_SHUTDOWN_START',   'PCJ_SHUTDOWN_FINISH', 
                     ];

        # In the example we only watch to see when PCJ is finished building the
        # connection. When PCJ_INIT_FINISHED occurs, the connection ready for use.
        # Until this status event is fired, any nodes sent out will be queued. It's
        # the responsibility of the end developer to purge the queue via the 
        # purge_queue event.

        if($state == +PCJ_INIT_FINISHED){ 
            $heap->{'reconnect_count'} = 0; 
            $heap->{'jid'} = $heap->{$self->alias()}->jid();
            $heap->{'sid'} = $sender->ID();
            $kernel->post($self->alias(), 'reconnect_all'); 
        }
}

sub reconnect_all{
    my ($self, $kernel, $sender, $heap, @args) = @_[OBJECT, KERNEL, SENDER, HEAP, ARG0 .. $#_];
      $kernel->post($self->alias().'component','output_handler', XNode->new('presence'));
          
      # And here is the purge_queue. This is to make sure we haven't sent
      # nodes while something catastrophic has happened (like reconnecting).
      $kernel->post($self->alias().'component','purge_queue');

      if(defined($self->{'channel_list'})){
          foreach my $muc (@{ $self->{'channel_list'} }){
              print STDERR $self->alias()," ",'join_channel'," ", $muc, "\n";
              $kernel->post($self->alias(),'join_channel', $muc);
          }
      }
      # Ignore incoming messages for 1 second, so we don't re-respond to crap in the replay buffer
      $kernel->delay_add('enable_input', 1);
}

# This is the input event. We receive all data from the server through this
# event. ARG0 will a POE::Filter::XML::Node object.
sub pretty_xml{
    my $self=shift;
    my $xml=shift;
    my  $twig = new XML::Twig;
    $twig->set_indent(" "x4);
    $twig->parse( $xml );
    $twig->set_pretty_print( 'indented' );
    #$twig->set_pretty_print( 'nice' );
    #my @prettier=split("\n",$twig->sprint);
    #foreach my $line (@prettier){
    #    if( length($line) > 80){
    #        my ($in_quote, $in_body, $in_tag, $tagdepth) = ( 0, 0, 0, 0 );
    #        my @char=split('',$line);
    #        for( my $i=0; $i <= $#char; $i++ ){
    #            #if($i < $#char-5){
    #                #if(join('',($char[$i],$char[$i+1],$char[$i+2],$char[$i+3])) eq "body"){
    #                #    if($char[$i-1] eq '\\'){
    #                #        $in_body=0; 
    #                #    }else{ 
    #                #        $in_body=1; 
    #                #    }
    #                #}
    #            #}
    #            if($char[$i] eq '<'){ $in_tag = 1; }
    #            if($char[$i] eq '>'){ $in_tag = 0; }
    #            if($char[$i] eq '"'){ if($in_quote == 1){ $in_quote=0; }else{ $in_quote=1; } }
    #            if($char[$i] eq ' ' && $char[$i-1] ne ' '){ 
    #                if($in_quote == 0 && $in_body == 0){ print STDERR "\n  ";} 
    #            } 
    #            print STDERR $char[$i];
    #        }
    #    }
    #}
    return $twig->sprint."\n";
}

sub is_invite{
    my $self=shift;
    my $node=shift if(@_);
    if( $node->name() ne "invite"){
        my $child_nodes = $node->get_children();
        if(ref($child_nodes) ne "ARRAY"){ $child_nodes = [ $child_nodes ]; } # forcearray
        foreach my $cnode( @{ $child_nodes } ){
            print ref($cnode)."\n";
            print STDERR Data::Dumper->Dump([ $cnode->node->name() ])."\n";
            return $self->is_invite($cnode) if $self->is_invite($cnode);
        }
    }else{
        print STDERR "invite found.\n";
        return 1;
    }
    return undef;
}

sub invite_channel{
    my $self=shift;
    return "smeg\@conference.websages.com";
}

sub input_event() {
    my ($self, $kernel, $heap, $node) = @_[OBJECT, KERNEL, HEAP, ARG0];
    print STDERR ">>  ".$node->to_str()."\n\n" if($self->{'DEBUG'} > 2);
    # allow everyone in websages to subscribe to our presence. /*FIXME move regex to constructor */
    if($node->name() eq 'presence'){
        if($node->attr('type') ){
            if($node->attr('type') eq 'subscribe'){
                if($node->attr('from') =~m /\@websages.com/){
                    $kernel->post($self->alias(),'approve_subscription',$node->attr('from'));
                    }
            }
        }
        if( $node->attr('type')){
            if( $node->attr('type') eq 'unavailable'){ 
                # remove from $heap->{'presence'}
                # print STDERR "Departing: ". $node->attr('from')."\n";
                if(defined($heap->{'presence'}->{ $node->attr('from') })){
                    delete $heap->{'presence'}->{ $node->attr('from') };
                }

            }
        }else{
            # print STDERR $self->pretty_xml( $node->to_str() );
            # add to $heap->{'presence'} if we can see the jid
            # print STDERR "Arriving: ". $node->attr('from')."\n";
            my $child_nodes = $node->get_children_hash();
            if(defined($child_nodes->{'x'}) && (ref($child_nodes->{'x'}) eq 'POE::Filter::XML::Node')){
                my $child_child_nodes = $child_nodes->{'x'}->get_children_hash();
                if(defined($child_child_nodes->{'item'}) && (ref($child_nodes->{'x'}) eq 'POE::Filter::XML::Node')){
                    if( $child_child_nodes->{'item'}->attr('jid') ){
                        #print STDERR "Got: ".$child_child_nodes->{'item'}->attr('jid')."\n";
                        $heap->{'presence'}->{ $node->attr('from') } = $child_child_nodes->{'item'}->attr('jid');
                    }
                }
            }
        }
    }elsif($self->is_invite($node)){
        print STDERR "I should join ".$self->invite_channel($node)."\n";
    }else{
        print STDERR "Unhandled Node: node->name(" .$node->name().")\n";
    }

    # figure out to where to reply...
    my $from = $node->attr('from');
    my $to = $node->attr('to');
    my $id = $node->attr('id');
    my $type = $node->attr('type');
    my $replyto = $from;
    my $nick = $from;
    my $direct = 0;

    # don't parse things from this personality.
    my $thatsme=0;
    foreach my $active_channel ( @{ $self->{'channel_list'} }) {
        if($from eq $active_channel){ $thatsme = 1; }
    } 
    if(defined($type)){
        if($type eq 'groupchat'){ 
            $replyto=~s/\/.*//; 
            $nick=~s/.*\///; 
        }else{
            $direct = 1;
        }
    }
    # Retrieve the message data from the xml if it has a body and post the message to the personality...
    my $what=''; 
    my $child_nodes=$node->get_children_hash(); 
    if(defined($child_nodes->{'body'})){ 
         $what = $child_nodes->{'body'}->data();
        if((($type eq 'chat')||($type eq 'groupchat'))&&($thatsme == 0)){
            my $msg = { 
                        'sender_alias' => $self->alias(),
                        'reply_event'  => 'xmpp_reply',
                        'conversation' => { 
                                            'id'   => 1,
                                            'nick' => $nick,
                                            'room' => $replyto,
                                            'body' => $what,
                                            'type' => $type,
                                            'direct' => $direct,
                                          }
                      };
            if($heap->{'input_enabled'}){
                if($direct){
                    if( !$self->{'ignore_direct'}){
                        # print STDERR "$self->{'persona'}\n";
                        $kernel->post("$self->{'persona'}", "input", $msg);
                    }
                }else{
                    $kernel->post("$self->{'persona'}", "input", $msg);
                }
           }
        }
   }
}

sub xmpp_reply{
    # Get the reply from the personality and post it back from whence it came.
    my ($self, $kernel, $heap, $sender, $msg, $reply) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    my ( $who, $type ) = ( $msg->{'conversation'}->{'room'}, $msg->{'conversation'}->{'type'} );
    my $node = XNode->new('message');
    $node->attr('to', $who);
    if($type eq 'groupchat'){ $node->attr('type', $type); }
    $node->insert_tag('body')->data($reply);
    $kernel->post($self->alias(),'output_event', $node, $heap->{'sid'});
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
        
        $kernel->post($self->alias().'component','output_event', $node, $heap->{'sid'});

}

sub enable_input(){
    my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
    $heap->{'input_enabled'} = 1;
}

# This is our own output_event that is a simple passthrough on the way to
# post()ing to PCJ's output_handler so it can then send the Node on to the
# server

sub output_event()
{
    my ($self, $kernel, $heap, $node, $sid) = @_[OBJECT, KERNEL, HEAP, ARG0, ARG1];
    print STDERR "<<  ".$node->to_str()."\n\n"  if $self->{'DEBUG'} > 2;
    #my  $twig= new XML::Twig;
    #$twig->set_indent(" "x4);
    #$twig->parse( $node->to_str() );
    #$twig->set_pretty_print( 'indented' );
    #print STDERR $twig->sprint."\n";
        $kernel->post($sid, 'output_handler', $node);
}

sub say_public(){
    my ($self, $kernel, $heap, $channel, $statement) = @_[OBJECT, KERNEL, HEAP, ARG0, ARG1];
    my ( $who, $type ) = ( $channel, 'groupchat' );
    my $node = XNode->new('message');
    $node->attr('to', $who);
    if($type eq 'groupchat'){ $node->attr('type', $type); }
    $node->insert_tag('body')->data($statement);
    $kernel->post($self->alias(),'output_event', $node, $heap->{'sid'});
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
                if($heap->{'reconnect_count'} < 10){
                    print "Reconnecting!\n";
                    $heap->{'reconnect_count'}++;
                    $kernel->post($sender, 'reconnect');
                }else{
                    print "Max connect attempts exceeded. Giving up for 3 minutes.\n";
                    $kernel->delay('reconnect_all', 180); 
                }
        
        } elsif($error == +PCJ_SOCKETDISCONNECT) {
                
                print "We got disconnected\n";
                if($heap->{'reconnect_count'} < 10){
                    print "Reconnecting!\n";
                    $heap->{'reconnect_count'}++;
                    $kernel->post($sender, 'reconnect');
                }else{
                    print "Max connect attempts exceeded. Giving up for 3 minutes.\n";
                    $kernel->delay('reconnect_all', 180); 
                }
        
        } elsif($error == +PCJ_CONNECTFAIL) {

                print "Connect failed\n";
                if($heap->{'reconnect_count'} < 10){
                    $heap->{'reconnect_count'}++;
                    print "Retrying connection!\n";
                    $kernel->post($sender, 'reconnect');
                }else{
                    print "Max connect attempts exceeded. Giving up for 3 minutes.\n";
                    $kernel->delay('reconnect_all', 180); 
                }
        
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
    my ($r,$n)=split('/',$room);
    $kernel->post(
                   $self->{'persona'},
                   'channel_add',
                   {
                     alias        => $self->alias(),
                     channel      => $r,
                     nick         => $n,
                     output_event => 'say_public',
                   }
                 );
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
