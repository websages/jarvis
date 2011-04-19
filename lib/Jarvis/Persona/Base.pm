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
    $self->{'job_id'} = 0;

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
                          'start'           => 'start',
                          'persona_start'   => 'persona_start',
                          'stop'            => 'stop',
                          'input'           => 'input',
                          'channel_add'     => 'channel_add',
                          'channel_del'     => 'channel_del',
                          'connector'       => 'connector',
                          'connector_error' => 'connector_error',
                          'pending'         => 'pending',
                          'queue'           => 'queue',
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
    $kernel->post($self->alias(),'persona_start');
    return $self;
}

sub stop{
     my ($self, $kernel, $heap, $sender, $msg) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0];
     foreach my $conn (keys(%{ $self->{'connectors'} })){
        $kernel->post($conn,'stop');
     }
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

################################################################################
# add something to the pending queue
################################################################################
sub queue{
    my ($self, $kernel, $heap, $sender, $event_data)=@_[OBJECT,  KERNEL,  HEAP,  SENDER, ARG0];
    my $edata;
    %{ $edata } = %{ $event_data }; # clone the event_data

    $edata->{'job_id'} = $self->{'job_id'}++;
    push(@{ $heap->{'pending'} }, $edata );

    # post the data to the event to the session...
    my @args = @{ $edata->{'args'} };
    $kernel->post($edata->{'session'}, $edata->{'event'}, @args );

    # add a expiration delay that will fire off pending at t='expire' (epoch time)
    $kernel->alarm_add('pending', $edata->{'expire'}, $edata);
}

################################################################################
# remove something from the pending queue (by reply-event or expiration)
################################################################################
sub pending {
    my ($self, $kernel, $heap, $sender, $event_data)=@_[OBJECT,  KERNEL,  HEAP,  SENDER, ARG0];
    my $max=$#{ $heap->{'pending'} };
    my $count=0;
    my $edata;
    %{ $edata } = %{ $event_data }; # clone the event_data

    # loop through the pending list on the heap and try to find one that matches $edata
    while ($count++ <= $max){
        my $pending = shift (@{ $heap->{'pending'} });
        if( ($edata->{'session'} == $pending->{'session'}) &&
            ($edata->{'reply_event'} eq $pending->{'reply_event'})){
            # this is the session and event that is pending.
            if(time() < $pending->{'expire'}){
                # we're not expired, so do the next_event 
                #print STDERR "clearing: $pending->{'job_id'}\n";
                if(defined($pending->{'next_event'})){
                    $kernel->post(
                                   $pending->{'session'},
                                   $pending->{'next_event'},
                                   $pending->{'data'},
                                 );
                }
            }else{
                # we're expired, so do the expire_event 
                #print STDERR "expiring: $pending->{'job_id'}\n";
                if(defined($pending->{'expire_event'})){
                    $kernel->post(
                                   $pending->{'session'},
                                   $pending->{'expire_event'},
                                   $pending->{'data'},
                                 );
                }
            }
        }else{
            # This is not the pending request that came in
            if(time() < $pending->{'expire'}){
                # but it's expired, so remove it from pending and do the expire_event;
                 #print STDERR "expiring: $pending->{'job_id'}\n";
                 if(defined($pending->{'expire_event'})){
                    $kernel->post( 
                                   $pending->{'session'},
                                   $pending->{'expire_event'},
                                   $pending->{'data'},
                                 );
                }
            }else{
                # and it's still fresh, so put it back in pending
                push(@{ $heap->{'pending'} }, $pending );
            }
        }
    }
}

sub connector{
    my ($self, $kernel, $heap, $sender, @args) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    foreach my $conn (@args){
        my $poe = new POE::Builder({ 
                                     'debug' => $self->{'debug'},
                                     'trace' => $self->{'trace'},
                                  });
        my $new_session_id = $poe->object_session( $conn->{'class'}->new( $conn->{'init'}) );
        $self->{'connectors'}->{ $new_session_id } = $conn;
    }
}

sub connector_error{
    my ($self, $kernel, $heap, $sender, @args) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    # keep trying with an increasing delay.
    if($args[0]=~m/Trying to reconnect too fast./){ # back off and try in 5n
        $kernel->post($sender,'_stop');
        my $conn = $self->{'connectors'}->{$sender->ID};
        $conn->{'init'}->{'delay'}+=5; # delay 5 more each time we try...
        delete $self->{'connectors'}->{$sender};
        $kernel->delay('connector', $conn->{'init'}->{'delay'} ,$conn);
    }
    print STDERR $$.": ".$sender->ID." -> ".$self->alias()." Persona error: ".join("\n",@args)."\n";
    
}

1;
