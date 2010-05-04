package POE::Builder;
#use POE::API::Peek;
use strict;
use warnings;
use YAML;
use POE;
sub new { 
    my $class = shift; 
    my $self = {}; 
    my $construct = shift if @_;
    #my $self->{'peek'} = POE::API::Peek->new();
    $self->{'session_struct'}={};

    # list of required constructor elements
    $self->{'must'} = [];

    # hash of optional constructor elements (key), and their default (value) if not specified
    $self->{'may'} = {
                       "debug" => 0, 
                       "trace" => 0,
                     };


    # set our required values fron the constructor or the defaults
    foreach my $attr (@{ $self->{'must'} }){
         if(defined($construct->{$attr})){
             $self->{$attr} = $construct->{$attr};
         }else{
             print STDERR "Required session constructor attribute [$attr] not defined. ";
             print STDERR "unable to define POE::Builder object\n";
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

# shortcut for yaml
sub yaml_sess(){
   my $self=shift;
   my $yaml=shift if @_;
   my $ctor=YAML::Load($yaml);
   $self->object_session( new $ctor->{'class'}( $ctor->{'init'} ) );
   return $self;
}

sub object_session(){
    my $self=shift;
    my $object = shift if @_;
    my $set_alias = shift if @_;
    my $object_states = $object->states();
    my $aliased_object_states = $object_states;;
    #foreach my $event (keys(%{ $object_states })){
    #    if($event =~m /^_/){
    #        # if it starts with and _underscore, prepend the alias to it, so we don't collide
    #        $aliased_object_states->{$object->alias().$event} = $object_states->{$event};
    #    }else{
    #        # otherwise, just pass the event straight through.
    #        $aliased_object_states->{$event} = $object_states->{$event};
    #    }
    #}
    push( @{ $self->{'sessions'} }, POE::Session->create(
                          options => { debug => $self->{'debug'}, trace => $self->{'trace'} },
                          object_states =>  [ $object => $aliased_object_states ],
                          inline_states =>  {
                                              _start   => sub { 
                                                                my ($kernel, $heap) = @_[KERNEL, HEAP];
                                                                $kernel->post($_[SESSION], "start");
                                                                # set the session_alias
                                                                $kernel->alias_set( $object->alias() );
                                                              },
                                              _stop    => sub {
                                                                my ($kernel, $heap) = @_[KERNEL, HEAP];
                                                                $kernel->post($_[SESSION],"stop");
                                                                # remove the session_alias
                                                                $kernel->alias_remove();
                                                              }
    
                                            },
                          heap           => { $object->alias() => $object }
                    ));
}
1;
