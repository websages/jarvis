package POE::Builder;
################################################################################
# Just a little conceptual integrity wrapper...
################################################################################
use strict;
use warnings;
use JSON;
use POE;
use YAML;
sub new { 
    my $class = shift; 
    my $self = {}; 
    my $construct = shift if @_;
    $self->{'session_struct'}={
                              'connector' => 'connector',
                              };

    # list of required constructor elements
    $self->{'must'} = [];

    # hash of optional constructor elements (key), and their default (value) if not specified
    $self->{'may'} = {
                       "debug" => 0, 
                       "trace" => 1,
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

# As long as the yaml lines up with itself, 
# you can indent as much as you want to keep the here statements pretty
sub indented_yaml{
     my $self = shift;
     my $iyaml = shift if @_;
     return undef unless $iyaml;
     my @lines = split('\n', $iyaml);
     my $min_indent=-1;
     foreach my $line (@lines){
         my @chars = split('',$line);
         my $spcidx=0;
         foreach my $char (@chars){
             if($char eq ' '){
                 $spcidx++;
             }else{
                 if(($min_indent == -1) || ($min_indent > $spcidx)){
                     $min_indent=$spcidx;
                 }
             }
         }
     }
     foreach my $line (@lines){
         $line=~s/ {$min_indent}//;
     }
     my $yaml=join("\n",@lines)."\n";
     return YAML::Load($yaml);
}

# shortcut for yaml
sub yaml_sess(){
   my $self=shift;
   my $yaml=shift if @_;
   my $ctor=$self->indented_yaml($yaml);
   $self->object_session( $ctor->{'class'}->new( $ctor->{'init'} ) );
   print STDERR Data::Dumper->Dump([$ctor->{'class'},$ctor->{'init'}]);
   return $self;
}

sub connector{
    my ($self, $kernel, $heap, $sender, @args) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    my $connection = shift @args if @args;
    print STDERR Data::Dumper->Dump([$connection]);
}

sub object_session(){
    my $self = shift;
    my $object = shift if @_;
    return undef unless $object;
    my $object_states = $object->states();
    push( @{ $self->{'sessions'} }, 
          POE::Session->create(
                                options       => { 
                                                   debug => $self->{'debug'}, 
                                                   trace => $self->{'trace'} 
                                                 },
                                object_states => [ $object => $object_states ],
                                inline_states => {
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
                                heap          => { $object->alias() => $object }
                          ));
    return $self->{'sessions'}->[$#{ $self->{'sessions'} }]->ID;
}
1;
