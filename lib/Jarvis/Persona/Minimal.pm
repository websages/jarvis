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
        /^\s*!*help\s*/          && return $self->help();
        /^\s*!*spawn\s+(.*)/     && return $self->spawn($1)     if $direct;
        /^\s*!*terminate\s+(.*)/ && return $self->terminate($1) if $direct;
        /.*/                     && return  []; # say nothing by default
    }
}

sub help(){
    my $self=shift;
    return  [ "commands: help spawn terminate" ];
}

sub spawn(){
    my $self=shift;
    return  [ "I need a spawn routine" ];
}

sub terminate(){
    my $self=shift;
    return  [ "I need a terminate routine" ];
}

1;
