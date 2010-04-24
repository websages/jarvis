package POE::Builder;
use strict;
use warnings;
use POE;
sub new { 
    my $class = shift; 
    my $self = {}; 
    my $construct = shift if @_;
    $self->{'session_struct'}={};
    foreach my $attr ("debug","trace"){
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

sub object_session(){
    my $self=shift;
    my $object = shift if @_;
    my $object_states = $self->object_states();
    my $aliased_object_states;
    foreach my $event (keys(%{ $object_states })){
        if($key=!m/^_/){
            # if it starts with and _underscore, prepend the alias to it, so we don't collide
            $aliased_object_states->{$alias.$event} = $object_states->{$event};
        }else{
            # otherwise, just pass the event straight through.
            $aliased_object_states->{$event} = $object_states->{$event};
        }
    }
print Data::Dumper->Dump([ $aliased_object_states ]);
    push( @{ $self->{'sessions'} }, POE::Session->create(
                          options => { debug => $self->{'debug'}, trace => $self->{'trace'} },
                          object_states =>  [ $object => $aliased_object_states ],
                          inline_states =>  {
                                              _start   => sub { 
                                                                my ($kernel, $heap) = @_[KERNEL, HEAP];
                                                                $kernel->alias_set($self->{'alias'});
                                                                $kernel->yield($object->alias()."_start");
                                                              },
                                              _stop    => sub {
                                                                my ($kernel, $heap) = @_[KERNEL, HEAP];
                                                                $kernel->yield($object->alias()."_stop");
                                                                $kernel->alias_remove(); 
                                                              }
    
                                            },
                          heap           => { $self->{'alias'} => $object }
                    ));
}


1;
