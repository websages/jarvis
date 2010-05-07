package Jarvis::Persona::Base;
use strict;
use warnings;
use AI::MegaHAL;
use POE;
use POSIX qw( setsid );
use POE::Builder;

sub new {
    my $class = shift;
    my $self = {};
    my $construct = shift if @_;
    bless($self,$class);

    # list of required constructor elements
    $self->{'must'} = [ 'alias' ];
    # an optional overloaded subroutine can provide more.
    my $oload_list=$self->must();
    while(my $oload_must = shift @{ $oload_list }){
        push(@{ $self->{'must'} }, $oload_must );
    }

    # hash of optional constructor elements (key), and their default (value) if not specified
    $self->{'may'} = { };
    # an optional overloaded subroutine can provide more.
    my $oload_hash = $self->may();
    foreach my $key (keys(%{ $oload_hash })){
        $self->{'may'}->{ $key } = $oload_hash->{ $key };
    }
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

    # collect our states for POE
    $self->{'states'} = { 
                          'start'         => 'start',
                          'persona_start' => 'persona_start',
                          'stop'          => 'stop',
                          'input'         => 'input',
                          'channel_add'   => 'channel_add',
                          'channel_del'   => 'channel_del',
                        };
    my $pstates = $self->persona_states(); 
    if(ref($pstates) eq 'HASH'){
        # the standard case returning a hash of { 'event' => 'subname' }
        foreach my $key (keys(%{ $pstates })){
            $self->{'states'}->{ $key } = $pstates->{ $key };
        }
    }elsif(ref($pstates) eq 'ARRAY'){
        # for the shorthand case returning a list 
        #   of events that are identical to subroutine names
        foreach my $key (@{ $oload_hash }){
            $self->{'states'}->{ $key } = $key;
        }
    }
    return $self;
}

################################################################################
# Functions typically overloaded in the personas that inherit the base one
################################################################################
# a handler for mandatory constructor variables (overload me)
sub must {
    my $self=shift;
    return [];
}

# a handler for optional constructor variables (overload me)
sub may {
    my $self=shift;
    return {};
}

# a handler for persona init routines (overload me)
sub persona_start{
    my $self = $_[OBJECT]||shift;
    my $kernel = $_[KERNEL];
    print STDERR __PACKAGE__ ." start\n";
    return $self;
}

# a handler for persona POE event states, return a list or hash 
# to be added to $self->{'states'} (overload me)
sub persona_states{
    my $self = $_[OBJECT]||shift;
    return undef;
}

################################################################################
# standard functions each persona needs to communicate with the connectors
################################################################################
sub start{
    my $self = $_[OBJECT]||shift;
    my $kernel = $_[KERNEL];
    print STDERR __PACKAGE__ ." start\n";
    $kernel->post($self->alias(),'persona_start');
    return $self;
}

sub stop{
     my $self = $_[OBJECT]||shift;
     print STDERR __PACKAGE__ ." stop\n";
     return $self;
}

sub states{
     my $self = $_[OBJECT]||shift;
     return $self->{'states'};
}

sub alias{
     my $self = $_[OBJECT]||shift;
     return $self->{'alias'};
}

################################################################################
# let the personality know that the connector is now watching a channel
################################################################################
sub channel_add{
     # expects a constructor hash of { alias => <sender_alias>, channel => <some_tag>, nick => <nick in channel> }
    my ($self, $kernel, $heap, $construct) = @_[OBJECT, KERNEL, HEAP, ARG0];
         push ( 
                @{ $heap->{'locations'}->{ $construct->{'alias'} }->{ $construct->{'channel'} } },
                $construct->{'nick'}
              );
}

################################################################################
# let the personality know that the connector is no longer watching a channel
################################################################################
sub channel_del{
    # expects a constructor hash of { alias => <sender_alias>, channel => <some_tag>, nick => <nick in channel> }
    my ($self, $kernel, $heap, $construct) = @_[OBJECT, KERNEL, HEAP, ARG0];
    # unshift each of the items in the room, push them back if they're not the one we're removing
    my $count=0;
    my $max = $#{ $heap->{'locations'}->{ $construct->{'alias'} }->{ $construct->{'channel'} } };
    while( $count < $max ){
       my $nick = shift(@{ $heap->{'locations'}->{ $construct->{'alias'} }->{ $construct->{'channel'} } });
        push( 
              @{ $heap->{'locations'}->{ $construct->{'alias'} }->{ $construct->{'channel'} } },
              $nick
            ) unless $nick eq $construct->{'nick'};
        $count++;
   }
    # delete the channel if there are no nicks in it
    if($heap->{'locations'}->{ $construct->{'alias'} }->{ $construct->{'channel'} }){
        if($#{ $heap->{'locations'}->{ $construct->{'alias'} }->{ $construct->{'channel'} } } < 0){
            delete $heap->{'locations'}->{ $construct->{'alias'} }->{ $construct->{'channel'} };   
        }
        # delete the alias from locations if there are no channels in it
        if($heap->{'locations'}->{ $construct->{'alias'} }){
            my @channels = keys(%{ $heap->{'locations'}->{ $construct->{'alias'} } });
            if($#channels < 0){ delete $heap->{'locations'}->{ $construct->{'alias'} }; }
        }
    }
}

################################################################################
# the messages get routed here from the connectors, a reply is formed, and 
# posted back to the sender_alias,reply event (this function will need to be
# overloaded...
################################################################################
sub input{
    my ($self, $kernel, $heap, $sender, $msg) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0];
    # un-wrap the $msg
    my ( $sender_alias, $respond_event, $who, $where, $what, $id ) =
       ( 
         $msg->{'sender_alias'},
         $msg->{'reply_event'},
         $msg->{'conversation'}->{'nick'},
         $msg->{'conversation'}->{'room'},
         $msg->{'conversation'}->{'body'},
         $msg->{'conversation'}->{'id'},
       );
    my $direct=$msg->{'conversation'}->{'direct'}||0;
    if(defined($what)){
        if(defined($heap->{'locations'}->{$sender_alias}->{$where})){
            foreach my $chan_nick (@{ $heap->{'locations'}->{$sender_alias}->{$where} }){
                if($what=~m/^\s*$chan_nick\s*:*\s*/){
                    $what=~s/^\s*$chan_nick\s*:*\s*//;
                    $direct=1;
                }
            }
        }
        my $replies=[];
        ########################################################################
        #                                                                      #
        ########################################################################
        for ( $what ) {
            /^\s*!*help\s*/ && do { $replies = [ "i need a help routine" ] if($direct); last; };
            /.*/            && do { $replies = [ "i don't understand"    ] if($direct); last; };
            /.*/            && do { last; }
        }
        ########################################################################
        #                                                                      #
        ########################################################################
        if($direct==1){ 
            foreach my $line (@{ $replies }){
                if($msg->{'conversation'}->{'direct'} == 0){
                    if( defined($line) && ($line ne "") ){ $kernel->post($sender, $respond_event, $msg, $who.': '.$line); }
                }else{
                    if( defined($line) && ($line ne "") ){ $kernel->post($sender, $respond_event, $msg, $line); } 
                }
            }
        }else{
            foreach my $line (@{ $replies }){
                    if( defined($line) && ($line ne "") ){ $kernel->post($sender, $respond_event, $msg, $line); } 
            }
        }
    }
    return $self->{'alias'};
}

1;
