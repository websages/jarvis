package POE::Builder;
use POE;
sub new { 
    my $class = shift; 
    my $self = {}; 
    my $construct = shift if @_;
    foreach my $attr ("alias"){
         if(defined($construct->{$attr})){
             $self->{$attr} = $construct->{$attr};
         }else{
             print STDERR "Required constructor attribute [$attr] not defined. Terminating __PACKAGE__ session\n";
             return undef;
         }
    }
    $self->{'session_struct'}={};
    bless($self,$class);
    return $self;
}

sub add_poe_object {
use YAML;
    my $self = shift;
    my $object = shift if @_;
    my $handle = shift if @_;
    if(defined($self->{'session_struct'}->{'objects'}->{$handle})){
       print STDERR "Unable to add duplicate handle $handle. Skipping...\n";
       return $self;
    }else{
        $self->{'session_struct'}->{'objects'}->{$handle} = $object;
    }
    my $object_states=$object->states();
    my $handled_object_states;
    foreach my $event (keys(%{ $object_states })){
       $handled_object_states->{$handle.$event} = $object_states->{$event};
    }
    push(@{ $self->{'session_struct'}->{'object_states'} }, $object => $handled_object_states );
    return $self;
}

sub object_states{
    my $self = shift; 
    return $self->{'session_struct'}->{'object_states'} if $self->{'session_struct'}->{'object_states'};
    return undef;
}

sub heap_objects{
    my $self = shift; 
    return $self->{'session_struct'}->{'objects'} if $self->{'session_struct'}->{'objects'};
    return undef;
}

sub create(){
    my $self=shift;
    POE::Session->create(
                          options => { debug => 1, trace => 1 },
                          object_states =>  $self->object_states(), 
                          inline_states =>  {
                                              # loop through all the object's _start methods (_start is required)
                                              _start   => sub { 
                                                                my ($kernel, $heap) = @_[KERNEL, HEAP];
                                                                $kernel->alias_set($self->{'alias'});
                                                                foreach my $poe_handle (keys(%{ $self->heap_objects })){
                                                                    $kernel->yield( $poe_handle."_start");
                                                                } 
                                                                $kernel->yield("_stop");
                                                              }, # loop through all the object's _start methods (_stop is required) # none of these run for some reason, ugh.
                                              _stop    => sub {
                                                                my ($kernel, $heap) = @_[KERNEL, HEAP];
                                                                #foreach my $poe_handle (keys(%{ $self->heap_objects })){
                                                                    $kernel->yield('irc_stop');
                                                                    $kernel->yield('xmpp_stop');
                                                                #} 
                                                              },
    
                                            },
                          heap           => { 'objects'  => $self->heap_objects() }
                    );
}


1;
