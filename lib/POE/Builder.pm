package POE::Builder;
use POE;
sub new { 
    my $class = shift; 
    my $self = {}; 
    my $construct = shift if @_;
    $self->{'session_struct'}={};
    foreach my $attr ("alias","debug","trace"){
         if(defined($construct->{$attr})){
             $self->{$attr} = $construct->{$attr};
         }else{
             print STDERR "Required session constructor attribute [$attr] not defined. Terminating POE::Builder->create() session\n";
             return undef;
         }
    }
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
                          options => { debug => $self->{'debug'}, trace => $self->{'trace'} },
                          inline_states =>  {
                                              _start   => sub { 
                                                                my ($kernel, $heap) = @_[KERNEL, HEAP];
                                                                $kernel->alias_set($self->{'alias'});
                                                              },
                                              _stop    => sub {
                                                                my ($kernel, $heap) = @_[KERNEL, HEAP];
                                                                $kernel->alias_remove(); 
                                                              }
    
                                            },
                          heap           => [] 
                    );
}


1;
