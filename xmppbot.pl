#!/usr/bin/perl

###############################################################################
#                          
# XMPPClient Example           
# (c) Nicholas Perez 2006, 2007. 
# Licensed under GPLv2     
#                          
# Please see the included  
# LICENSE file for details
#
# This example client script, instantiates a single PCJ object, connects to a 
# remote server, sends presence, and then begins sending messages to itself on 
# a small random interval
#                          
###############################################################################

use Filter::Template; 						#this is only a shortcut
const XNode POE::Filter::XML::Node

use warnings;
use strict;
use Data::Dumper;

use POE; 									#include POE constants
use POE::Component::Jabber; 				#include PCJ
use POE::Component::Jabber::Error; 			#include error constants
use POE::Component::Jabber::Status; 		#include status constants
use POE::Component::Jabber::ProtocolFactory;#include connection type constants
use POE::Filter::XML::Node; 				#include to build nodes
use POE::Filter::XML::NS qw/ :JABBER :IQ /; #include namespace constants
use POE::Filter::XML::Utils; 				#include some general utilites
use Carp;


# First we create our own session within POE to interact with PCJ
POE::Session->create(
	options => { debug => 1, trace => 1},
	inline_states => {
		_start =>
			sub
			{
				my ($kernel, $heap) = @_[KERNEL, HEAP];
				$kernel->alias_set('Tester');
				
				# our PCJ instance is a fullblown object we should store
				# so we can access various bits of data during use
				
				$heap->{'component'} = 
					POE::Component::Jabber->new(
						IP => 'thor.websages.com',
						Port => '5222',
						Hostname => 'websages.com',
						Username => 'crunchy',
						Password => $ENV{'XMPP_PASSWORD'},
						Alias => 'COMPONENT',

				# Shown below are the various connection types included
				# from ProtocolFactory:
				#
				# 	LEGACY is for pre-XMPP/Jabber connections
				# 	XMPP is for XMPP1.0 compliant connections
				# 	JABBERD14_COMPONENT is for connecting as a service on the
				# 		backbone of a jabberd1.4.x server
				# 	JABBERD20_COMPONENT is for connecting as a service on the
				# 		backbone of a jabberd2.0.x server

						#ConnectionType => +LEGACY,
						ConnectionType => +XMPP,
						#ConnectionType => +JABBERD14_COMPONENT,
						#ConnectionType => +JABBERD20_COMPONENT,
						#Debug => '1',

				# Here is where we define our states for PCJ to use when
				# sending us information from the server. It automatically
				# infers the instantiating session much like a Wheel does.
				# StateParent is optional unless you want another session
				# to receive events from PCJ

						StateParent => 'Tester',
						States => {
							StatusEvent => 'status_event',
							InputEvent => 'input_event',
							ErrorEvent => 'error_event',
						}
					);
				
				# At this point, PCJ is instatiated and hooked up to POE. In
				# 1.x, upon instantiation connect was immedately called. This
				# is not the case anymore with 2.x. This allows for a pool of 
				# connections to be setup and executed when needed.

				$kernel->post('COMPONENT', 'connect');
                                
				
			},

		_stop =>
			sub
			{
				my $kernel = $_[KERNEL];
				$kernel->alias_remove();
			},

		input_event => \&input_event,
		error_event => \&error_event,
		status_event => \&status_event,
		test_message => \&test_message,
		output_event => \&output_event,
                join_channel => \&join_channel,
                leave_channel => \&leave_channel,
                send_presence => \&send_presence,
                presence_subscribe => \&presence_subscribe,
                approve_subscription => \&approve_subscription,
                refuse_subscription=> \&refuse_subscription,
	}
);


# The status event receives all of the various bits of status from PCJ. PCJ
# sends out numerous statuses to inform the consumer of events of what it is 
# currently doing (ie. connecting, negotiating TLS or SASL, etc). A list of 
# these events can be found in PCJ::Status.

sub status_event()
{
	my ($kernel, $sender, $heap, $state) = @_[KERNEL, SENDER, HEAP, ARG0];
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
	
		$kernel->post('COMPONENT', 'output_handler', XNode->new('presence'));
		
		# And here is the purge_queue. This is to make sure we haven't sent
		# nodes while something catastrophic has happened (like reconnecting).
		
		$kernel->post('COMPONENT', 'purge_queue');

#                my $online_node=XNode->new('presence',[ 'show', 'Online']);
#                $kernel->yield('output_event',$online_node);
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
#                $kernel->yield('output_event', $reserved_nick_req);
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
#                $kernel->yield('output_event',$node);

                $heap->{'roomnick'} = 'system@conference.websages.com/crunchy';
                #$kernel->yield('presence_subscribe','whitejs@websages.com');
                $kernel->yield('join_channel','system');

		#for(1..10)
		#{
		#	$kernel->delay_add('test_message', int(rand(10)));
		#}
	}
	print "Status received: $jabstat->[$state] \n";
}

# This is the input event. We receive all data from the server through this
# event. ARG0 will a POE::Filter::XML::Node object.

sub input_event()
{
	my ($kernel, $heap, $node) = @_[KERNEL, HEAP, ARG0];
        
	
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

sub test_message()
{
	my ($kernel, $heap) = @_[KERNEL, HEAP];
	
	my $node = XNode->new('message');
	
	# get_bare_jid is a helper method included from POE::Filter::XML::Utils.
	# It returns the user@domain part of the jid (ie. no resources)

	#$node->attr('to', get_bare_jid($heap->{'jid'}));
	$node->attr('to', 'whitejs@websages.com');

	$node->insert_tag('body')->data('This is a test sent at: ' . time());
	
	$kernel->yield('output_event', $node, $heap->{'sid'});

}

# This is our own output_event that is a simple passthrough on the way to
# post()ing to PCJ's output_handler so it can then send the Node on to the
# server

sub output_event()
{
	my ($kernel, $heap, $node, $sid) = @_[KERNEL, HEAP, ARG0, ARG1];
	
	print "\n===PACKET SENT===\n";
	print $node->to_str() . "\n";
	print "=================\n";
	
	$kernel->post($sid, 'output_handler', $node);
}

# This is the error event. Any error conditions that arise from any point 
# during connection or negotiation to any time during normal operation will be
# send to this event from PCJ. For a list of possible error events and exported
# constants, please see PCJ::Error

sub error_event()
{
	my ($kernel, $sender, $heap, $error) = @_[KERNEL, SENDER, HEAP, ARG0];

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
    my ($kernel, $heap, $room) = @_[KERNEL, HEAP, ARG0];
    $heap->{'starttime'} = time;
    #$heap->{'roomnick'} = $room.'@conference.websages.com/crunchy';
    my $node=XNode->new('presence', [ 'to', $heap->{'roomnick'}, 'from', $heap->{'component'}->jid(), ]);
    my $child_node=XNode->new('x',[xmlns=>"http://jabber.org/protocol/muc"]);
    $node->insert_tag($child_node);
    $kernel->yield('output_event',$node,$heap->{'sid'});
} # join channel

sub presence_subscribe() {
    my ($kernel, $heap, $tgt_jid) = @_[KERNEL, HEAP, ARG0];
    $kernel->yield('send_presence',$tgt_jid,'subscribe');
} # presence_subscribe

sub approve_subscription() {
    my ($kernel, $heap, $tgt_jid) = @_[KERNEL, HEAP, ARG0];
    #
    $kernel->yield('send_presence',$tgt_jid,'subscribed');
} # approve_subscription

sub refuse_subscription() {
    my ($kernel, $heap, $tgt_jid) = @_[KERNEL, HEAP, ARG0];
    #
    $kernel->yield('send_presence',$tgt_jid,'unsubscribed');
} # refuse_subscription

sub leave_channel() {
    my ($kernel, $heap) = @_[KERNEL, HEAP];
    $kernel->yield('send_presence', $heap->{'roomnick'},'unavailable');
} # leave_channel


sub send_presence() {
    my ($kernel, $heap, $tgt_jid, $type) = @_[KERNEL, HEAP, ARG0, ARG1];
    my $node=XNode->new('presence');
    $node->attr('to',$tgt_jid );
    $node->attr('from', $heap->{'component'}->jid() );
    $node->attr('type',$type) if $type;
    $kernel->yield('output_event',$node,$heap->{'sid'});
} # send_presence


	
POE::Kernel->run();
