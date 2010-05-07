package Jarvis::Persona::Minimal;
use parent Jarvis::Persona::Base;

################################################################################
# Here is what you must provide: 
#   A function named "input" that takes $what and $directly_addressed
#   as arguments, that will regex out the appropriate commands and act on them.
#   It should return a list reference to the list of one-line replies.
#   You will also need to subroutines or inline code to handle these actions.
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
            /^\s*!*help(.*)/      && return $self->help($1);
            /^\s*!*spawn(.*)/     && return $self->spawn($1)     if $direct;
            /^\s*!*terminate(.*)/ && return $self->terminate($1) if $direct;
            /.*/                  && return  [];        # say nothing by default
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


sub help(){
    my $self=shift;
    my $topic=shift if @_;
    $topic=~s/^\s+//;
    return  [ "commands: help spawn terminate" ];
}

sub spawn(){
    my $self=shift;
    my $target=shift if @_;
    $target=~s/^\s+// if $target;
    return  [ "I need a spawn routine" ];
}

sub terminate(){
    my $self=shift;
    my $target=shift if @_;
    $target=~s/^\s+// if $target;
    return  [ "I need a terminate routine" ];
}

1;
