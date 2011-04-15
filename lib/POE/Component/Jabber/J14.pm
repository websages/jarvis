package POE::Component::Jabber::J14;
use Filter::Template;
const XNode POE::Filter::XML::Node
use warnings;
use strict;

use POE qw/ Wheel::ReadWrite Component::Client::TCP /;
use POE::Component::Jabber::Error;
use POE::Component::Jabber::Status;
use POE::Filter::XML;
use POE::Filter::XML::Node;
use POE::Filter::XML::NS qw/ :JABBER :IQ /;
use Digest::SHA1 qw/ sha1_hex /;

use base('POE::Component::Jabber::Protocol');

our $VERSION = '2.02';

sub get_version()
{
	return '0.9';
}

sub get_xmlns()
{
	return +NS_JABBER_ACCEPT;
}

sub get_states()
{
	return [ 'set_auth', 'init_input_handler' ];
}

sub get_input_event()
{
	return 'init_input_handler';
}

sub set_auth()
{
	my ($kernel, $heap, $self) = @_[KERNEL, HEAP, OBJECT];

	my $node = XNode->new('handshake');
	my $config = $heap->config();
	$node->data(sha1_hex($self->{'sid'}.$config->{'password'}));
	$kernel->post($heap->parent(), $heap->status(), +PCJ_AUTHNEGOTIATE);
	$kernel->yield('output_handler', $node, 1);
	return;
}

sub init_input_handler()
{
	my ($kernel, $heap, $self, $node) = @_[KERNEL, HEAP, OBJECT, ARG0];
	
	if($node->name() eq 'handshake')
	{	
		my $config = $heap->config();
		$kernel->post($heap->parent(), $heap->status(), +PCJ_AUTHSUCCESS);
		$kernel->post($heap->parent(), $heap->status(), +PCJ_INIT_FINISHED);
		$heap->jid($config->{'hostname'});
		$heap->relinquish_states();

	} elsif($node->name() eq 'stream:stream') {
	
		$self->{'sid'} = $node->attr('id');
		$kernel->yield('set_auth');
	
	} else {

		$heap->debug_message('Unknown state: ' . $node->to_str());
		$kernel->post($heap->parent(), $heap->error(), +PCJ_AUTHFAIL);
	}
}

1;

__END__

=pod

=head1 NAME

POE::Component::Jabber::J14 - connect to the jabberd14 router as a service

=head1 SYNOPSIS

PCJ::J14 is a Protocol implementation that connects as a service to a jabberd14
server.

=head1 DESCRIPTION

PCJ::J14 authenticates with the server backend using the method outlined in 
XEP-114 (Jabber Component Protocol) 
[http://www.xmpp.org/extensions/xep-0114.html]

=head1 METHODS

Please see PCJ::Protocol for what methods this class supports.

=head1 EVENTS

Listed below are the exported events that end up in PCJ's main session:

=over 2

=item set_auth

This event constructs and sends the <handshake/> element for authentication.

=item init_input_handler

This is out main entry point that PCJ uses to send us all of the input. It
handles the authentication response.

=head1 NOTES AND BUGS

This only implements the jabber:component:accept namespace (ie. the component
initiates the connection to the server).

Also be aware that before this protocol was documented as an XEP, it was widely
implemented with loose rules. I conform to this document. If there is a problem
with the implementation against older server implementations, let me know.

=head1 AUTHOR

Copyright (c) 2003-2007 Nicholas Perez. Distributed under the GPL.

=cut
