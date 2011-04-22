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
             'speak'         => 'speak',
           };
}

sub persona_start{
    my ($self, $kernel, $heap, $sender, $msg) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0];
    $self->{'cmdb'} = CMDB::LDAP->new({
                                         'uri'    => $self->{'ldap_uri'},
                                         'basedn' => $self->{'ldap_basedn'},
                                         'binddn' => $self->{'ldap_binddn'},
                                         'bindpw' => $self->{'ldap_bindpw'},
                                       });

print STDERR "$self->{'log_dir'}/channel.log\n";
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
                                #'screen' => {
                                #               'class'    => 'Log::Dispatch::Screen',
                                #               'min_level'=> 'info',
                                #               'stderr'   => 0,
                                #               'format'   => "%m\n",
                                #            }
                               }
                               )), 'log') or warn "Cannot start Logging $!";
    $kernel->post($self->{'logger'}, 'log', "Logging started.");
}

sub persona_stop{
    my ($self, $kernel, $heap, $sender, $msg) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0];
    $kernel->post($self->{'logger'}, 'log', "Logging stopped.");
    $self->{'cmdb'}->unbind();
}

################################################################################
# the messages get routed here from the connectors, a reply is formed, and 
# posted back to the sender_alias,reply event (this function will need to be
# overloaded...
################################################################################
sub input{
    my ($self, $kernel, $heap, $sender, $msg) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0];
    # un-wrap the $msg
    $msg->{'sender_id'} = $_[SENDER]->ID; # the kernel is dropping non-numeric aliases...
    my ( $sender_alias, $sender_id, $respond_event, $who, $where, $what, $id ) =
       ( 
         $msg->{'sender_alias'},
         $msg->{'sender_id'},
         $msg->{'reply_event'},
         $msg->{'conversation'}->{'nick'},
         $msg->{'conversation'}->{'room'},
         $msg->{'conversation'}->{'body'},
         $msg->{'conversation'}->{'id'},
       );
    my $direct = $msg->{'conversation'}->{'direct'}||0;
    my $addressed = $msg->{'conversation'}->{'addressed'}||0;

    ############################################################################
    # determine if we were priv msged (direct) or addressed as in "jarvis: foo"
    # strip our nic off if we were, but set addressed so we can address the 
    # requestor in our response
    #

    my $nick = undef;
    if(defined($what)){
        
        # determine our nick from the message type
        if(defined($heap->{'locations'}->{$sender_alias}->{$where})){
            foreach my $chan_nick (@{ $heap->{'locations'}->{$sender_alias}->{$where} }){
                $nick = $chan_nick; # this will get the last nick?
            }
        }
        if(ref($where) eq 'ARRAY'){ #This was a direct message (privmsg)
            $direct = 1;
            $nick = $where->[0];
        }

        # were we addressed by nick?
        if($what=~m/^\s*$nick\s*:*\s*/){
            $what=~s/^\s*$nick\s*:*\s*//;
            $addressed=1;
            $msg->{'conversation'}->{'body'}=~s/^\s*$nick\s*:*\s*//;
            $msg->{'conversation'}->{'addressed'}=1;
            $addressed=1;
        }

        my $replies=[];
    print STDERR Data::Dumper->Dump([$what]);
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
                      $kernel->yield('gist',$1,$msg); 
                      last; 
                   };
        ########################################################################
        # this is how the commands should be modeled
            /^\s*!*(sets|members)\s*(.*)/ && 
                do { 
                      my $set = $2;
                      $kernel->yield('sets',$set,$msg); 
                      last; 
                   };
        ########################################################################
            ( 
              /^\s*!*who\s*am\s*i\s*/              ||
              /^\s*!*(add)\s+(\S+)\s+to\s+(\S+)/   ||
              /^\s*!*(del)\s+(\S+)\s+from\s+(\S+)/ ||
              /^\s*!*(disown|own|pwn|owners*|who\s*o*wns)\s+(.*)/ 
            ) && 
                do {   # we hand of this command to the authenticated handler
                       $kernel->post($sender,'authen',$msg);
                       last;
                   };
        ########################################################################
        # Greetings
            /^\s*hello\s+$nick\s*/i && 
                do { $replies = [ "hello $who" ]; last; };
            /^\s*hello\s*$/i && 
                do { $replies = [ "hello" ]; last; };
            /^\s*good\s+(morning|day|afternoon|evening|night)\s+$nick\s*/i && 
                do { $replies = [ "good $1 $who" ]; last; };
            /^\s*good\s+(morning|day|evening"afternoon||night)/i && 
                do { $replies = [ "good $1 $who" ]; last; };
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
        $kernel->yield('speak', $msg, $replies);
    }
    return $self->{'alias'};
}

sub speak{
    my ($self, $kernel, $heap, $sender, $msg, $replies)=@_[OBJECT,KERNEL,HEAP,SENDER,ARG0 .. $#_];
    $replies = [ $replies ] unless ref($replies);
    my ( $sender_alias, $sender_id, $respond_event, $who, $where, $what, $id) =
       (
         $msg->{'sender_alias'},
         $msg->{'sender_id'},
         $msg->{'reply_event'},
         $msg->{'conversation'}->{'nick'},
         $msg->{'conversation'}->{'room'},
         $msg->{'conversation'}->{'body'},
         $msg->{'conversation'}->{'id'},
       );
    my $direct = $msg->{'conversation'}->{'direct'}||0;
    my $addressed = $msg->{'conversation'}->{'addressed'}||0;
    my $nick;
    if(defined($heap->{'locations'}->{$sender_alias}->{$where})){
        foreach my $chan_nick (@{ $heap->{'locations'}->{$sender_alias}->{$where} }){
            $nick = $chan_nick;
            if($what=~m/^\s*$chan_nick\s*:*\s*/){
                $what=~s/^\s*$chan_nick\s*:*\s*//;
                $direct=1;
            }
        }
    }
    foreach my $line (@{ $replies }){
        if( defined($line) && ($line ne "") ){ 
            if(ref($where) eq 'ARRAY'){ $where = $where->[0]; } # this was an irc privmsg
            if($addressed == 1){
                print STDERR "speak addressed\n";
                $kernel->post($sender_id, $respond_event, $msg, $who.': '.$line); 
                $kernel->post($self->{'logger'}, 'log', "$where <$nick> $who: $line");
            }else{
                print STDERR "speak non-addressed\n";
                $kernel->post($sender_id, $respond_event, $msg, $line); 
                $kernel->post($self->{'logger'}, 'log', "$where <$who> $line");
            }
        }
    }
}

sub sets{
    my ($self, $kernel, $heap, $sender, $top, $msg) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    my @sets = ( $self->{'cmdb'}->sets_in($top) );
    $kernel->yield('speak', $msg, join(", ",@sets));
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
    $kernel->yield('speak', $msg, $url);
}

sub invite{
    my ($self, $kernel, $heap, $sender, @args) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    my ($nick,$ident) = split(/!/,$args[0]) if $args[0];
    print STDERR "invited to $args[1] by $ident ($nick)\n";
}

################################################################################
# these will match the regexes from input() but will be associated with a whois reply argument
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
         do {
              $kernel->post(
                             $msg->{'sender_alias'},
                             $msg->{'reply_event'}, 
                             $msg, 
                             "I see you as $actual."
                           );
              last;
            };
    ############################################################################
    # Commands that require Authentication & Authorization
            ( 
              /^\s*!*(add)\s+(\S+)\s+to\s+(\S+)/   ||
              /^\s*!*(del)\s+(\S+)\s+from\s+(\S+)/ ||
              /^\s*!*(disown|own|pwn|owners*|who\s*o*wns)\s+(.*)/ 
            ) && 
         do {
              my @rxargs = ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10);
              my ($action,$member,$set,$userid,$domain);
              $action = $rxargs[0];
              if($action =~m /add|del/){
                  $member = $rxargs[1];
                  $set    = $rxargs[2];
                  print STDERR "[ $action ] [ $set ] [ $member ]\n";
              }elsif($action =~m /disown|own|pwn|owners|who\s*o*wns/){
                  $set    = $rxargs[1];
                  print STDERR "[ $action ] [ $set ]\n";
              }
              my @owners = $self->{'cmdb'}->owners($set);
           
              # for almost any authenticated action you'll need to see who owns it.
 
              print STDERR Data::Dumper->Dump([@owners]);
              if($action=~m/owners*|who\s*o*wns/){
                  if(@owners){
                      $kernel->yield('speak',$msg,join(", ",@owners));
                  }else{
                      $kernel->yield('speak',$msg,"no owners");
                  }
              }elsif($action=~m/disown/){
              }elsif($action=~m/own|pwn/){
                  $kernel->yield('speak',$msg,"no owners");
              }elsif($action=~m/add/){
                  $kernel->yield('speak',$msg,"icanhaz add routine?");
              }elsif($action=~m/del/){
                  $kernel->yield('speak',$msg,"icanhas del routine?");
              }else{
                  $kernel->yield('speak',$msg,"huh?");
              }
              ##################################################################
#              if($actual=~m/(.*)@(.*)/){
#                  ($userid,$domain) = ($1,$2);
#              }
#              $domain=~s/^(znc|irc)\.//; # something more elegant than this please...
#              $self->{'authorize'} = CMDB::LDAP->new({
#                                                       'uri'    => $self->{'ldap_uri'},
#                                                       'basedn' => $self->{'ldap_basedn'},
#                                                       'binddn' => $self->{'ldap_binddn'},
#                                                       'bindpw' => $self->{'ldap_bindpw'},
#                                                       'setou'  => 'Sets',
#                                                     }) unless $self->{'authorize'};
#              my $authorized = 0;
#              foreach my $owner ( $self->{'authorize'}->owners($set) ){
#                  if($owner eq "uid=$userid"){ $authorized =1; }
#                  print STDERR "$owner == uid=$userid\n";
#              }
#                  print STDERR "authorized == $authorized \n";
#              if($authorized == 1){
#                  $kernel->post(
#                                 $msg->{'sender_alias'},
#                                 $msg->{'reply_event'}, 
#                                 $msg, 
#                                 "adding $member to $set"
#                               );
#              }else{
#                  $kernel->post(
#                                 $msg->{'sender_alias'},
#                                 $msg->{'reply_event'}, 
#                                 $msg, 
#                                 "You don't own $set"
#                               );
#              }
              last;
            };
    ############################################################################
         /.*/ && 
         do {
              print STDERR "not sure what to do with /$what/ (no match)\n"; 
              last;
            };
    }
}
1;
