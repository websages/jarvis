package Log::Dispatch::Configurator::Hardwired;
use base qw(Log::Dispatch::Configurator);
sub new{
    my $class=shift;
    my $self = {};
    bless $self;
    my $construct = shift if @_;
    foreach my $key (keys(%{ $construct })){
        push (@{ $self->{'dispatchers'} },$key);
        $self->{'attrs'}->{$key} = $construct->{$key};
    }
    #print Data::Dumper->Dump([$self]);
    return $self; 
}
sub get_attrs_global {
    my $self = shift;
    return {
             format => undef,
             dispatchers => $self->{'dispatchers'}
           };
}
sub get_attrs {
    my($self, $name) = @_;
    if (defined $self->{'attrs'}->{$name}) {
        return $self->{'attrs'}->{$name};
    }else{
        warn "invalid dispatcher name: $name";
    }
}
sub needs_reload { 1 }

1;
