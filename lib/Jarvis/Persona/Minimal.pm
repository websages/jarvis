package Jarvis::Persona::Minimal;
use parent Jarvis::Persona::Base;

################################################################################
# Here is what you must provide: 
#   A function named "input_handler" that takes $what and $directly_addressed
#   as arguments, that will regex out the appropriate commands and act on them.
#   It should return a list reference to the list of one-line replies.
#   You will also need to subroutines or inline code to handle these actions.
################################################################################

sub input_handler{
    my $self=shift;
    my $line=shift;
    my $direct=shift||0;
    for ( $line ) {
print STDERR "==>[ $line ]\n";
        /^\s*!*help(.*)/      && return $self->help($1);
        /^\s*!*spawn(.*)/     && return $self->spawn($1)     if $direct;
        /^\s*!*terminate(.*)/ && return $self->terminate($1) if $direct;
        /.*/                  && return  [];                             # say nothing by default
    }
}

sub help(){
    my $self=shift;
    my $topic=shift if @_;
    $topic=~s/^\s+//;
    return  [ "commands: help spawn terminate" ];
}

sub spawn(){
    my $self=shift;
    my $object=shift if @_;
    $object=~s/^\s+//;
    return  [ "I need a spawn routine" ];
}

sub terminate(){
    my $self=shift;
    my $object=shift if @_;
    $object=~s/^\s+//;
    return  [ "I need a terminate routine" ];
}

1;
