package POE::Component::Jabber::J2;
use Filter::Template;
const XNode POE::Filter::XML::Node
use warnings;
use strict;

use POE qw/ Wheel::ReadWrite /;
use POE::Component::SSLify qw/ Client_SSLify /;
use POE::Component::Jabber::Error;
use POE::Component::Jabber::Status;
use POE::Filter::XML;
use POE::Filter::XML::Node;
use POE::Filter::XML::NS qw/ :JABBER :IQ /;
use Digest::MD5 qw/ md5_hex /;
use MIME::Base64;
use Authen::SASL;

use base('POE::Component::Jabber::Protocol');

our $VERSION = '2.02';

sub new()
{   
	my $class = shift;
	my $self = {};
	$self->{'SSLTRIES'} = 0;
	return bless($self, $class);
}

sub get_version()
{
	return '1.0';
}

sub get_xmlns()
{
	return +NS_JABBER_COMPONENT;
}

sub get_states()
{   
	return [ 'set_auth', 'init_input_handler', 'challenge_response', 
				'binding', 'build_tls_wheel' ];
}

sub get_input_event()
{   
	return 'init_input_handler';
}

sub set_auth()
{
	my ($kernel, $heap, $self, $mech) = @_[KERNEL, HEAP, OBJECT, ARG0];
	
	my $config = $heap->config();
	my $sasl = Authen::SASL->new
	(
		mechanism => 'DIGEST_MD5',
		callback  => 
		{
			user => $config->{'username'},
			pass => $config->{'password'},
		}
	);

	$self->{'challenge'} = $sasl;

	my $node = XNode->new('auth',
	['xmlns', +NS_XMPP_SASL, 'mechanism', $mech]);

	$kernel->yield('output_handler', $node, 1);

	return;
}

sub challenge_response()
{
	my ($kernel, $heap, $self, $node) = @_[KERNEL, HEAP, OBJECT, ARG0];
	
	my $config = $heap->config();

	if ($config->{'debug'}) {
		$heap->debug_message(	
			"Server sent a challenge.  Decoded Challenge:\n" .
			decode_base64( $node->data() )
		);
	}
	
	my $sasl = $self->{'challenge'};
	my $conn = $sasl->client_new("xmpp", $config->{'hostname'});
	$conn->client_start();

	my $step = $conn->client_step(decode_base64($node->data()));

	if ($config->{'debug'}) {
		$heap->debug_message("Decoded Response:\n$step");
	}
	
	if(defined($step))
	{
		$step =~ s/\s+//go;
		$step = encode_base64($step);
		$step =~ s/\s+//go;
	}

	my $response = XNode->new('response', ['xmlns', +NS_XMPP_SASL]);
	$response->data($step);

	$kernel->yield('output_handler', $response, 1);
}

sub init_input_handler()
{
	my ($kernel, $heap, $self, $node) = @_[KERNEL, HEAP, OBJECT, ARG0];
	
	my $attrs = $node->get_attrs();
	my $config = $heap->config();
	my $pending = $heap->pending();

	if ($config->{'debug'})
	{
		$heap->debug_message("Recd: ".$node->to_str());
	}
	
	if(exists($attrs->{'id'}))
	{
		if(defined($pending->{$attrs->{'id'}}))
		{
			my $array = delete $pending->{$attrs->{'id'}};
			$kernel->post($array->[0], $array->[1], $node);
			return;
		}
	} elsif($node->name() eq 'stream:stream') {

		$self->{'sid'} = $node->attr('id');

	} elsif($node->name() eq 'challenge') {
		
		$kernel->yield('challenge_response', $node);

	} elsif($node->name() eq 'failure' and 
		$node->attr('xmlns') eq +NS_XMPP_SASL) {

		$heap->debug_message('SASL Negotiation Failed');
		$kernel->yield('shutdown');
		$kernel->post($heap->parent(), $heap->error(), +PCJ_AUTHFAIL);
	
	} elsif($node->name() eq 'stream:features') {

		my $clist = $node->get_children_hash();

		if(exists($clist->{'starttls'}))
		{
			my $starttls = XNode->new('starttls', ['xmlns', +NS_XMPP_TLS]);
			$kernel->yield('output_handler', $starttls, 1);
			$kernel->post($heap->parent(), $heap->status(), +PCJ_SSLNEGOTIATE);
			$self->{'STARTTLS'} = 1;
		
		} elsif(exists($clist->{'mechanisms'})) {
			
			if(!defined($self->{'STARTTLS'}))
			{
				$kernel->post($heap->parent(), $heap->error(), +PCJ_SSLFAIL);
				$kernel->yield('shutdown');
				return;
			}

			my $mechs = $clist->{'mechanisms'}->get_sort_children();
			foreach my $mech (@$mechs)
			{
				if($mech->data() eq 'DIGEST-MD5')
				{
					$kernel->yield('set_auth', $mech->data());
					$kernel->post(
						$heap->parent(),
						$heap->status(),
						+PCJ_AUTHNEGOTIATE);
					return;
				}
			}
			
			$heap->debug_message('Unknown mechanism: '.$node->to_str());
			$kernel->yield('shutdown');
			$kernel->post($heap->parent(), $heap->error(), +PCJ_AUTHFAIL);
		
		} elsif(!keys %$clist) {
			
			if(!defined($self->{'STARTTLS'}))
			{
				$kernel->post($heap->parent(), $heap->error(), +PCJ_SSLFAIL);
				$kernel->yield('shutdown');
				return;
			}

			my $bind = XNode->new('bind' , ['xmlns', +NS_JABBER_COMPONENT])
				->attr(
					'name', 
					$config->{'binddomain'} || 
					$config->{'username'} . '.' . $config->{'hostname'}
					);
			
			if(defined($config->{'bindoption'}))
			{
				$bind->insert_tag($config->{'bindoption'});
			}
			
			$kernel->yield('return_to_sender', 'binding', $bind);
			$kernel->post($heap->parent(), $heap->status(), +PCJ_BINDNEGOTIATE);
		}

	} elsif($node->name() eq 'proceed') {

		$kernel->yield('build_tls_wheel');
		$kernel->yield('initiate_stream');
	
	} elsif($node->name() eq 'success') {

		$kernel->yield('initiate_stream');
		$kernel->post($heap->parent(), $heap->status(), +PCJ_AUTHSUCCESS);
	}

	return;
}

sub binding()
{
	my ($kernel, $heap, $node) = @_[KERNEL, HEAP, ARG0];

	my $attr = $node->attr('error');
	my $config = $heap->config();

	if(!$attr)
	{
		$heap->relinquish_states();
		$kernel->post($heap->parent(),$heap->status(), +PCJ_BINDSUCCESS);
		$kernel->post($heap->parent(),$heap->status(), +PCJ_INIT_FINISHED);
		$heap->jid($config->{'binddomain'} ||
			$config->{'username'} . '.' . $config->{'hostname'});
	
	} else {

		$heap->debug_message('Unable to BIND, yet binding required: '.
			$node->to_str());
		$kernel->yield('shutdown');
		$kernel->post($heap->parent(), $heap->error(), +PCJ_BINDFAIL);
	}
}
		
sub build_tls_wheel()
{
	my ($kernel, $heap, $self) = @_[KERNEL, HEAP, OBJECT];
	
	$heap->wheel(undef);
	eval { $heap->sock(Client_SSLify( $heap->sock() ))};

	if($@)
	{
		if($self->{'SSLTRIES'} > 3)
		{
			$heap->debug_message('Unable to negotiate SSL: '. $@);
			$self->{'SSLTRIES'} = 0;
			$kernel->post($heap->parent(), $heap->error(), +PCJ_SSLFAIL, $@);

		} else {

			$self->{'SSLTRIES'}++;
			$kernel->yield('build_tls_wheel');
		}
		
		return;
	}
	
	$heap->wheel(POE::Wheel::ReadWrite->new
	(
		'Handle'		=> $heap->sock(),
		'Filter'		=> POE::Filter::XML->new(),
		'InputEvent'	=> 'init_input_handler',
		'ErrorEvent'	=> 'server_error',
		'FlushedEvent'	=> 'flushed_event',
	));
	$kernel->post($heap->parent(), $heap->status(), +PCJ_SSLSUCCESS);

	return;
}

1;

__END__

=pod

=head1 NAME

POE::Component::Jabber::J2 - connect to the jabberd20 router as a service

=head1 SYNOPSIS

PCJ::J2 is a Protocol implementation that is used to connect to the jabberd20
router as a service.

=head1 DESCRIPTION

PCJ::J2 implements the jabberd2 component spec located here:
(http://jabberd.jabberstudio.org/dev/docs/component.shtml)
Specifically, PCJ::J2 will negotiate TLS, SASL, and domain binding required
to establish a working connection with jabberd2 as a service.

=head1 METHODS

Please see PCJ::Protocol for what methods this class supports.

=head1 EVENTS

Listed are the exported events that make their way into the PCJ session:

=over 2

=item set_auth

This handles the initial SASL authentication portion of the connection.

=item init_input_handler

This is our entry point. This is what PCJ uses to deliver events to us.
It handles various responses until the connection is initialized fully.

=item build_tls_wheel

If TLS is required by the server, this is where that negotiation process
happens.

=item challenge_response

This handles the subsequent SASL authentication steps.

=item binding

This handles the domain binding

=head1 NOTES AND BUGS

This Protocol may implement the spec, but this spec hasn't been touched in 
quite some time. If for some reason my implementation fails against a
particular jabberd2 version, please let me know.

=head1 AUTHOR

Copyright (c) 2003-2007 Nicholas Perez. Distributed under the GPL.

=cut

