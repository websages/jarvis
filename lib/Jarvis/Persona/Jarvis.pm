package Jarvis::Persona::Jarvis;
use parent Jarvis::Persona::Base;
use strict;
use warnings;
use CMDB::LDAP;
use POE; # this is needed even though it's in the parent or we don't send events

# gists
use File::Temp qw/ :mktemp  /;
use Time::Local;
# gists

use Data::Dumper;
use YAML;

sub may {
    my $self=shift;
    return {
             'log_dir'     => '/var/log/irc',
             'ldap_uri'    => 'ldaps://127.0.0.1:636',
             'ldap_basedn' => "dc=".join(",dc=",split(/\./,`dnsdomainname`)),
             'ldap_binddn' => undef, # anonymous bind by default
             'ldap_bindpw' => undef,
           };
}

sub persona_states{
    my $self = shift;
    return { 
             'gist'          => 'gist',
             'sets'          => 'sets',
             'invite'        => 'invite',
             'authen_reply'  => 'authen_reply',
           };
}

sub persona_start{
    my ($self, $kernel, $heap, $sender, $msg) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0];
    $self->{'logger'} = POE::Component::Logger->spawn(
        ConfigFile => Log::Dispatch::Config->configure(
                          Log::Dispatch::Configurator::Hardwired->new(
                              # convert me to yaml and put me in the main config
                              {
                                'file'   => {
                                              'class'    => 'Log::Dispatch::File',
                                              'min_level'=> 'debug',
                                              'filename' => "$self->{'log_dir'}/channel.log",
                                              'mode'     => 'append',
                                              'format'   => '%d{%Y%m%d %H:%M:%S} %m %n',
                                            },
                               # 'screen' => {
                               #                'class'    => 'Log::Dispatch::Screen',
                               #                'min_level'=> 'info',
                               #                'stderr'   => 0,
                               #                'format'   => '%m',
                               #             }
                               }
                               )), 'log') or warn "Cannot start Logging $!";
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

    my $nick = undef;
    if(defined($what)){
        if(defined($heap->{'locations'}->{$sender_alias}->{$where})){
            foreach my $chan_nick (@{ $heap->{'locations'}->{$sender_alias}->{$where} }){
                $nick = $chan_nick;
                if($what=~m/^\s*$chan_nick\s*:*\s*/){
                    $what=~s/^\s*$chan_nick\s*:*\s*//;
                    $direct=1;
                }
            }
        }
        my $replies=[];
        for ( $what ) {
        ########################################################################
        # begin input pattern matching                                         #  
        ########################################################################
            /^\s*!*help\s*/ && 
                do { $replies = [ "i need a help routine" ] if($direct); last; };
        ########################################################################
        # this is how the commands should be modeled
            /^\s*!*gist\s*(.*)/ && 
                do { 
                      $msg->{'sender_alias'} = $sender->ID;
                      $kernel->yield('gist',$1,$msg); 
                      last; 
                   };
        ########################################################################
        # this is how the commands should be modeled
            /^\s*!*(sets|members)\s*(.*)/ && 
                do { 
                      my $set = $2;
                      $msg->{'sender_alias'} = $sender->ID; # sending the alias doesn't work
                      $kernel->yield('sets',$set,$msg); 
                      last; 
                   };
        ########################################################################
            /^\s*!*who\s*am\s*i\s*/ && 
                do {   # we hand of this command to the authenticated handler
                       print STDERR "authenticating $who\n";      
                       $kernel->post($sender,'authen',$msg);
                       last;
                   };
        ########################################################################
        # Greetings
            /^\s*hello\s+$nick\s*/i && 
                do { $replies = [ "hello $who" ]; last; };
            /^\s*hello\s*$/i && 
                do { $replies = [ "hello" ] if $direct; last; };
            /^\s*good\s+(morning|day|afternoon|evening|night)\s+$nick\s*/i && 
                do { $replies = [ "good $1 $who" ]; last; };
            /^\s*good\s+(morning|day|evening"afternoon||night)/i && 
                do { $replies = [ "good $1 $who" ] if $direct; last; };
        # Thanks
            /^\s*(thanks|thank you|thx|ty)\s+$nick\s*/i && 
                do { $replies = [ "np" ]; last; };
            /^\s*(thanks|thank you|thx|ty)/i && 
                do { $replies = [ "np" ] if $direct; last; };
        ########################################################################
        # Thanks
            /^\s*(thanks|thank you|thx|ty)\s+$nick\s*/i && 
                do { $replies = [ "np" ]; last; };
            /^\s*(thanks|thank you|thx|ty)/i && 
                do { $replies = [ "np" ] if $direct; last; };
        ########################################################################
            /.*/ && 
                 do { $replies = [ "i don't understand"    ] if($direct); last; };
        ########################################################################
            /.*/ 
                 && do { last; }
        ########################################################################
        # end input pattern matching                                           #
        ########################################################################
        }
        if($direct==1){ 
            foreach my $line (@{ $replies }){
                if( defined($line) && ($line ne "") ){ 
                   if(ref($where) eq 'ARRAY'){  # this was an irc privmsg
                       $where = $where->[0];
                       $kernel->post($sender, $respond_event, $msg, $line); 
                   }else{
                       $kernel->post($sender, $respond_event, $msg, $who.': '.$line); 
                   }
                   $kernel->post($self->{'logger'}, 'log', "$where <$who> $what");
               }else{
                   $kernel->post($self->{'logger'}, 'log', "$where <$nick> $who: $line");
               }
            }
        }else{
            foreach my $line (@{ $replies }){
                if( defined($line) && ($line ne "") ){ 
                    $kernel->post($sender, $respond_event, $msg, $line); 
                    $kernel->post($self->{'logger'}, 'log', "$where <$nick> $line");
                }
            }
        }
    }
    return $self->{'alias'};
}

sub sets{
    my ($self, $kernel, $heap, $sender, $top, $msg) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    $self->{'groups'} = CMDB::LDAP->new({
                                          'uri'    => $self->{'ldap_uri'},
                                          'basedn' => $self->{'ldap_basedn'},
                                          'binddn' => $self->{'ldap_binddn'},
                                          'bindpw' => $self->{'ldap_bindpw'},
                                        });
    my @sets = ( $self->{'groups'}->sets_in($top) );
    $kernel->post($msg->{'sender_alias'},$msg->{'reply_event'}, $msg, join(", ",@sets));
}

sub gist{
    my ($self, $kernel, $heap, $sender, $gist, $msg) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    my @gistlist;
    my ($from, $now,$type,$unixlogtime);
    my ($second, $minute, $hour, $dayOfMonth, $month,
        $yearOffset, $dayOfWeek, $dayOfYear, $daylightSavings) = localtime(time);
   $now=timelocal($second,$minute,$hour,$dayOfMonth,$month,$yearOffset);
   my $huh=1;
   if($gist=~m/:/){
       my @timespec=split(/:/,$gist);
       my $s=pop(@timespec)||0;
       my $m=pop(@timespec)||0;
       my $h=pop(@timespec)||0;
       my $deltat=(3600*$h+60*$m+$s);
       $from=$now-$deltat;
       $type='time';
       #print STDERR "gisting from $from to $now\n";
       $huh=0;
    }elsif($gist=~m/^\d+$/){
        $huh=0;
        $type='lines';
        #print STDERR "gisting last $gist lines\n";
    }
    if(!$huh){
        my $fh = FileHandle->new("$self->{'log_dir'}/channel.log", "r");
        if (defined $fh){
            while(my $logline=<$fh>){
                if($logline){
                    chomp($logline);
                    my @parts=split(" ",$logline);
                    #skipped blank and bitched lines
                    if($#parts>2){
                        my $logdate=shift @parts;
                        my $logtime=shift @parts;
                        my $logevent=shift @parts;
                        my $logtext=join(" ",@parts);
                        my $logthen=$logdate." ".$logtime;
                        if ($logthen=~m/(\d\d\d\d)(\d\d)(\d\d) (\d\d):(\d\d):(\d\d)/){
                            # and it better.
                            $unixlogtime=timelocal($6,$5,$4,$3,$2-1,$1-1900);
                        }
                        if($logevent eq $msg->{'conversation'}->{'room'}){
                            if($type eq 'lines'){
                                push(@gistlist, join(" ",($logdate,$logtime,$logevent,$logtext)));
                            }elsif(($from<=$unixlogtime)&&($unixlogtime<=$now)){
                                push(@gistlist, join(" ",($logdate,$logtime,$logevent,$logtext)));
                            }
                        }
                    }
                }
            }
            $fh->close;
        }
    }
    if($type eq 'lines'){
        my @trash=splice(@gistlist,0,$#gistlist-($gist-1));
    }
    my ($fh, $file) = mkstemp( "/dev/shm/gisttmp-XXXXX" );
    open(GISTTMP,">$file");
    foreach my $gistline (@gistlist){
        print GISTTMP "$gistline\n";
    }
    close(GISTTMP);
    open(GIST, "/usr/local/bin/gist -p < $file |");
    chomp(my $url=<GIST>);
    close(GIST);
    unlink($file);
    $kernel->post($msg->{'sender_alias'},$msg->{'reply_event'}, $msg, $url);
}

sub invite{
    my ($self, $kernel, $heap, $sender, @args) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    my ($nick,$ident) = split(/!/,$args[0]) if $args[0];
    print STDERR "invited to $args[1] by $ident ($nick)\n";
}

sub authen_reply{
    my ($self, $kernel, $heap, $sender, $msg, $actual)=@_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    my ( $sender_alias, $respond_event, $who, $where, $what, $id ) =
       (
         $msg->{'sender_alias'},
         $msg->{'reply_event'},
         $msg->{'conversation'}->{'nick'},
         $msg->{'conversation'}->{'room'},
         $msg->{'conversation'}->{'body'},
         $msg->{'conversation'}->{'id'},
       );
    for ( $what ) {
    ############################################################################
         /^\s*!*who\s*am\s*i\s*/ && 
         $kernel->post(
                        $msg->{'sender_alias'},
                        $msg->{'reply_event'}, 
                        $msg, 
                        "I see you as $actual."
                      );
         last;
    ############################################################################
    }
}
1;
