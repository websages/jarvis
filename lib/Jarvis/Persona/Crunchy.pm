package Jarvis::Persona::Crunchy;
use strict;
use warnings;
use parent 'Jarvis::Persona::Base';
use IRCBot::Chatbot::Pirate;
use POE::Component::Client::Twitter;
use POE;
use POSIX qw( setsid );
use Net::LDAP;
use Net::DNS;
use LWP::UserAgent;
use Mail::Send;

sub may {
    my $self=shift;
    return {
             'ldap_domain'  => undef,
             'ldap_binddn'  => undef,
             'ldap_bindpw'  => undef,
             'twitter_name' => undef,
             'username'     => undef,
             'password'     => undef,
             'retry'        => undef,
           };
}

sub persona_states{
    my $self = $_[OBJECT]||shift;
    return {
             'authen_reply'                    => 'authen_reply',
             'channel_join'                    => 'channel_join',
             'enable_twitter'                  => 'enable_twitter',
             'new_tweet'                       => 'new_tweet',
             'twitter_update_success'          => 'twitter_update_success',
             'delay_friend_timeline'           => 'delay_friend_timeline',
             'twitter.friend_timeline_success' => 'twitter_timeline_success',
             'twitter.response_error'          => 'twitter_error',
           }
}


sub persona_start{
    my $self = $_[OBJECT]||shift;
    my $kernel = $_[KERNEL];
    if(! -d "/dev/shm/brain"){ mkdir("/dev/shm/brain"); }
    if(! -d "/dev/shm/brain/crunchy"){ mkdir("/dev/shm/brain/crunchy"); }
    if(! -f "/dev/shm/brain/crunchy/megahal.trn"){
        my $agent = LWP::UserAgent->new();
        $agent->agent( 'Mozilla/5.0' );
        my $response = $agent->get("http://github.com/cjg/megahal/raw/master/data/megahal.trn");
        if ( $response->content ne '0' ) {
            my $fh = FileHandle->new("> /dev/shm/brain/crunchy/megahal.trn");
            if (defined $fh) {
                print $fh $response->content;
                $fh->close;
            }
        }
    }
    $self->{'megahal'} = new AI::MegaHAL(
                                          'Path'     => '/dev/shm/brain/crunchy',
                                          'Banner'   => 0,
                                          'Prompt'   => 0,
                                          'Wrap'     => 0,
                                          'AutoSave' => 1
                                        );
    $self->ldap_srv_records();
    if($self->{'ldap_enabled'} == 1){
        print STDERR "[ ".$self->error()." ]" if $self->{'ERROR'};
    }
    $self->{'cfg'} = { 
                       'screenname' => $self->{'twitter_name'},
                       'username'   => $self->{'twitter_name'},
                       'password'   => $self->{'password'},
                       'retry'      => $self->{'retry'},
                      };

    $self->{'twitter'} = POE::Component::Client::Twitter->spawn(%{ $self->{'cfg'} });
    $self->{'twitter'}->yield('register');
    $kernel->delay('delay_friend_timeline', 5);
    $kernel->delay('enable_twitter', 20);
    return $self;
}


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
        /.*/              && return  [ $self->megahal($line) ];
        /^\s*!*help\s*/   && return  [ $self->help($what);   ]
    }
}

################################################################################
# 
################################################################################
sub ldap_srv_records{
    my $self=shift;
    if( (!defined($self->{'ldap_domain'})) || (!defined($self->{'ldap_binddn'})) || (!defined($self->{'ldap_bindpw'})) ){
        print STDERR "[ $self->{'ldap_domain'} :: $self->{'ldap_binddn'} :: $self->{'ldap_bindpw'} ]\n";
        print STDERR "WARNING: Not enough LDAP paramaters supplied. LDAP operations will be disabled.\n";
        $self->{'ldap_enabled'}=0;
    }else{
        $self->{'ldap_basedn'} = $self->{'ldap_domain'};
        $self->{'ldap_basedn'} =~s/\./,dc=/g;
        $self->{'ldap_basedn'} = "dc=".$self->{'ldap_basedn'};
        $self->{'resolver'} = Net::DNS::Resolver->new;
        my $srv = $self->{'resolver'}->query( "_ldap._tcp.".$self->{'ldap_domain'}, "SRV" );
        if($srv){
            foreach my $rr (grep { $_->type eq 'SRV' } $srv->answer) {
                my $uri;
                my $order=$rr->priority.".".$rr->weight;
                if($rr->port eq 389){
                    $uri = "ldap://".$rr->target.":".$rr->port;
                }else{
                    $uri = "ldaps://".$rr->target.":".$rr->port;
                }
                if( defined($self->{'ldap_uri'}) ){
                    $self->{'ldap_uri'}=$self->{'ldap_uri'}.", $uri";
                }else{
                    $self->{'ldap_uri'}=$uri;
                }
                $self->{'ldap_enabled'}=1;
            }
        }else{
            print STDERR "Cannot resolve srv records for _ldap._tcp.".$self->{'ldap_domain'}.". LDAP operations will be disabled.\n";
            $self->{'ldap_enabled'}=0;
        }
    }
    return $self;
}

sub authen_reply{
    my ($self, $kernel, $heap, $msg, $user) = @_[OBJECT, KERNEL, HEAP, ARG0, ARG1];
    my $r;
    if(defined($msg->{'reason'})){
        if($msg->{'reason'} eq 'whoami'){
            if(defined($user)){
               $r = "I see you as: $user";
            }else{
               $r = "I cannot authenticate you at this time. Is the room anonymous or am I not a moderator?\n";
            }
            $kernel->post($msg->{'sender_alias'}, $msg->{'reply_event'}, $msg, $r); 
        }elsif($msg->{'reason'} eq 'channel_join'){
            my ($u,$d) = split('@',$user);
            if($d eq $self->{'ldap_domain'}){
                if($self->is_channel_operator($u)){
                    $kernel->post($msg->{'sender_alias'},'elevate_priv',$msg->{'conversation'}->{'nick'},$msg->{'conversation'}->{'room'});
                    print STDERR "/op $msg->{'conversation'}->{'nick'}\n";
                }
            }
        }elsif($msg->{'reason'} eq 'tell_request'){
            $user=~s/\@.*//;
            # if the nick didn't translate to a userid, they may not be logged in, 
            # but the request may have been for a userid, so let's try to look that up...
            if(!defined($user)){
                $user = $msg->{'conversation'}->{'nick'};
            }
            my @user_count = $self->get_ldap_entry("(uid=$user)");
            if($#user_count >=0){
                foreach my $user_entry ( $self->get_ldap_entry("(uid=$user)") ){
                    my @pager_count = $user_entry->get_value('pageremail');
                    if($#pager_count >=0){
                        foreach my $mail ($user_entry->get_value('pageremail') ){
                            my $mx = Mail::Send->new(Subject => $msg->{'conversation'}->{'originator'},To => "$mail"); 
                            my $mail_fh = $mx->open; 
                            print $mail_fh $msg->{'conversation'}->{'body'};
                            $mail_fh->close;
                        }
                        $r = "page sent to $user\n";
                    }else{
                        $r = "$user has no pageremails in their ldap entry\n";
                    }
                }
            }else{
               $r = "$user has no ldap entry\n";
            }
            $kernel->post($msg->{'sender_alias'}, $msg->{'reply_event'}, $msg, $r); 
        }elsif($msg->{'reason'} eq 'enable_shoutout'){
            $r=$self->toggle_shoutout($user,'enable',$msg);
            $kernel->post($msg->{'sender_alias'}, $msg->{'reply_event'}, $msg, $r); 
        }elsif($msg->{'reason'} eq 'disable_shoutout'){
            $r=$self->toggle_shoutout($user,'disable',$msg);
            $kernel->post($msg->{'sender_alias'}, $msg->{'reply_event'}, $msg, $r); 
        }else{ 
            # authorize request_id in the $heap->{'requests'} queue
            print STDERR "implement authorization request queue\n";
        }
    }
}

sub channel_join{
    my ($self, $kernel, $sender, $heap, $nick, $channel) = @_[OBJECT, KERNEL, SENDER, HEAP, ARG0, ARG1];
    # determine who the actual user is
    my $msg = {
                'sender_alias' => $sender->ID,
                'reply_event'  => 'authen_reply',
                'reason'       => 'channel_join',
                'conversation' => {
                                    'id'   => 1,
                                    'nick' => $nick,
                                    'room' => $channel,
                                    'body' => undef,
                                  }
              };
   $kernel->post($sender,'authen',$msg);
}
################################################################################
# 
################################################################################


################################################################################
# Begin Micellaneous events
################################################################################
sub megahal{
    my $self=shift;
    my $what=shift if @_;
    return  $self->{'megahal'}->do_reply( $what );
}

sub fortune{
    my $self=shift;
    return  qx( /usr/games/fortune -s );
}

sub link{
    my $self=shift;
    my $url=shift if @_;
    my $nick=shift if @_;
    return undef unless $url;
    return undef unless $nick;
    my $agent = LWP::UserAgent->new();
    $agent->agent( 'Mozilla/5.0' );
    $url =~ s/\&/\%26/g;
    my $response = $agent->get("http://tumble.wcyd.org/irclink/?user=". $nick . "&source=irc&url=$url");
    if ( $response->content eq '0' ) {
        return 'Invalid link!'
    }else{
        return 'http://tumble.wcyd.org/irclink/?' . $response->content;
    }
}

sub quote{
    my $self=shift;
    my $line=shift if @_;
    my ($quote, $author);
    if($line=~m/^\s*\"(.+?)\"\s+--\s*(.+?)$/){
        $quote  = $1;
        $author = $2;
    }
    return undef unless $quote;
    return undef unless $author;
    # tumble interprets these literally /*FIXME*/
    #$quote  =~ s/</\&lt;/g;  $author =~ s/</\&lt;/g;
    #$quote  =~ s/>/\&gt;/g;  $author =~ s/>/\&gt;/g;
    $quote  =~ s/\&/\%26/g; $author =~ s/\&/\%26/g;
    $quote  =~ s/;/\%3b/g;  $author =~ s/\;/\%3b/g;
    my $agent = LWP::UserAgent->new();
    $agent->agent( 'Mozilla/5.0' );
    my $response = $agent->get('http://tumble.wcyd.org/quote/?quote=' . "$quote" . "&author=$author");
    return "quote added" if($response->is_success);
}

sub tell{
    my $self=shift;
    my $nick=shift if @_;
    my $message=shift if @_;
    return undef unless $nick;
    return undef unless $message;
}

################################################################################
# End Micellaneous events
################################################################################

################################################################################
# Begin LDAP events
################################################################################

sub error{
    my $self=shift;
    if(@_){
        push(@{ $self->{'ERROR'} }, @_);
    }
    if($#{ $self->{'ERROR'} } >= 0 ){
        return join("\n",@{ $self->{'ERROR'} });
    }
    return '';
}

sub get_ldap_entry {
    my $self = shift;
    my $filter = shift if @_;
    $filter = "(objectclass=*)" unless $filter;
    my $servers;
    if($self->{'ldap_uri'}){
        @{ $servers }= split(/\,\s+/,$self->{'ldap_uri'})
    }
    my $mesg;
    while( my $server = shift(@{ $servers })){
        if($server=~m/(.*)/){
            $server=$1 if ($server=~m/(^[A-Za-z0-9\-\.\/:]+$)/);
        }
        my $ldap = Net::LDAP->new($server) || warn "could not connect to $server $@";
        $mesg = $ldap->bind( $self->{'ldap_binddn'}, password => $self->{'ldap_bindpw'});
        if($mesg->code != 0){ $self->error($mesg->error); }
        next if $mesg->code;
        my $records = $ldap->search(
                                     'base'   => "$self->{'ldap_basedn'}",
                                     'scope'  => 'sub',
                                     'filter' => $filter
                                   );
        unless($records->{'resultCode'}){
            undef $servers;
            $self->error($records->{'resultCode'}) if $records->{'resultCode'};
        }
        my $recs;
        my @entries = $records->entries;
        $ldap->unbind();
        return @entries;
    }
    return undef;
}

sub update{
    my $self = shift;
    my $construct = shift if @_;
    my $entry = $construct->{'entry'} if $construct->{'entry'};
    return undef unless $entry;
    my ($servers,$mesg);
    $servers = [ $construct->{'server'} ] if $construct->{'server'};
    unless($servers){
        @{ $servers } = split(/,/,$self->{'ldap_uri'}) if $self->{'ldap_uri'};
    }
    my @what_to_change;
    while(my $server=shift(@{$servers})){
        $self->error("Updating: ".$entry->dn." at ".$server);
        if($server=~m/(.*)/){ $server=$1 if ($server=~m/(^[A-Za-z0-9\-\.\/:]+$)/); }
        my $ldap = Net::LDAP->new($server) || warn "could not connect to $server $@";
        $mesg = $ldap->bind( $self->{'ldap_binddn'}, password => $self->{'ldap_bindpw'});
        undef $servers unless $mesg->{'resultCode'};
        $mesg->code && $self->error($mesg->code." ".$mesg->error);
        foreach my $change (@{ $entry->{'changes'} }){
            push(@what_to_change, $change);

        }
        $mesg =  $ldap->modify ( $entry->dn, changes => [ @what_to_change ] );
        if(($mesg->code == 10) && ($mesg->error eq "Referral received")){
            $self->error("Received referral");
            foreach my $ref (@{ $mesg->{'referral'} }){
                 if($ref=~m/(ldap.*:.*)\/.*/){
                     $self->update({ 'server'=> $ref, 'entry'=> $entry });
                 }
             }
         }else{
             $mesg->code && $self->error($mesg->code." ".$mesg->error);
         }
    }
    my $errors=$self->error();
    print STDERR "$errors\n" if($errors ne "");
    return $self;
}

sub is_channel_operator{
    my $self=shift;
    my $user=shift;
    return undef unless $user;
    my @list;
    foreach my $entry ( $self->get_ldap_entry( "(cn=channel_operators)" ) ){
        my @opers=$entry->get_value('uniqueMember');
        foreach my $op (@opers){
            $op=~s/,.*//;
            $op=~s/uid=//;
            if($user eq $op){ return $user; }
        }
    }
    return undef;
}

sub toggle_shoutout{
    my $self = shift;
    my $action_user = shift;
    my $action = shift;
    my $msg = shift;
    my $r;
    $action_user=~s/\@.*//;
    $action_user="uid=".$action_user.",ou=People,".$self->{'ldap_basedn'};
    #$action_user="uid=whitejs,ou=People,dc=websages,dc=com";
    foreach my $entry ( $self->get_ldap_entry("(cn=shoutouts)") ){
        my @users=$entry->get_value('uniqueMember');
        my $max=$#users;
        my $count=0;
        my $found=0;
        my $modified=0;
        while($count++ <= $max){
            my $tmp = shift (@users);
            if($action_user eq $tmp){
                $found = 1;
                if($action ne 'disable'){ 
                    push(@users,$tmp); 
                }else{ 
                    $modified = 1; 
                }
            }else{
                push(@users,$tmp); 
            }
        }
        if($action eq 'enable'){ 
            if($found == 0){
                push(@users,$action_user);
                $modified = 1;
            }else{
                $r = "$action_user is already in cn=shoutout (you're already good to go)";
            }
        }
        if($action eq 'disable'){ 
            if($found == 0){
                $r = "$action_user is not in cn=shoutout (you're already removed)";
            }
        }
        if($modified == 1){
            $entry->replace('uniqueMember' => \@users);    
            #print STDERR Data::Dumper->Dump([@users]);
            #print STDERR Data::Dumper->Dump([$entry]);
            $self->update({'entry' => $entry});
            $r = "cn=shoutouts modified.";
        }
    }
    return $r; 
}

sub shoutout{
    my $self=shift;
    my $shoutout=shift if @_;
    my $originator=shift if @_;
    my @list;
    return "shoutout what?" unless $shoutout;
    my $shoutouts;
    push(@{ $shoutouts },$self->get_ldap_entry("(cn=shoutouts)"));
    return $self->error() unless defined($shoutouts);
    foreach my $entry (@{ $shoutouts }){
        my @users = $entry->get_value('uniqueMember');
        foreach my $user (@users){
            $user=~s/,.*//;
            $user=~s/uid=//;
            push(@list,$user);
            foreach my $user_entry ( $self->get_ldap_entry("(uid=$user)") ){
                foreach my $mail ($user_entry->get_value('pageremail') ){
                    my $mx = Mail::Send->new(Subject=> "shoutout![$originator]", To => "$mail"); 
                    my $mail_fh = $mx->open; 
                    print $mail_fh $shoutout;
                    $mail_fh->close;
                }
            }
        }
    }
    return "shoutout sent to: ".join(" ",@list);
}
################################################################################
# End LDAP events
################################################################################

################################################################################
# Begin Standings
################################################################################
sub standings{
use LWP::Simple;
use HTML::Parser;
    my $self=shift;
    my $content = get( 'http://sports.yahoo.com/mlb/standings' );
    my $p = HTML::Parser->new(
        api_version => 3,
        start_h     => [ 
                         sub {
                               my ( $self, $tag, $attr ) = @_;
                               return unless $tag eq 'tr';
                               $self->handler( text => [], '@{dtext}' );
                               $self->handler( end  => sub {
                                                             my ( $self, $tag ) = @_;
                                                             my $text = join( '', @{$self->handler( 'text' )} );
                                                             $text =~ s/^\s+//;
                                                             $text =~ s/\s+$//;
                                                             $text =~ s/\s+/ /g;
                                                             return unless (
                                                                             $text =~ /Atlanta Braves/   ||
                                                                             $text =~ /New York Mets/ ||
                                                                             $text =~ /Washington Nationals/ ||
                                                                             $text =~ /Chicago Cubs/
                                                                           );
                                                             if ( $text =~m/(Chicago Cubs|Atlanta Braves|New York Mets|Washington Nationals)\s+(\d+.*)/ ) {
                                                             my $team = $1;
                                                             my $other = $2;
                                                             if ( $other =~ /(\d+)\s(\d+)\s(\d{0,1}\.\d+)\s+(.+?)\s+(\d+\-\d+)\s+(\d+\-\d+)\s+(\d+\-\d+)\s+(\d+\-\d+)\s+(\d+\-\d+)\s+(.+?)\s+(\d+\-\d+)/ ) 
                                                             {
                                                               my ($wins, $losses, $pct, $gb, $home, $road, $east, $west, $central, $streak, $l10) = 
                                                                  ( $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11 );
                                                               my $q = sprintf "%-20s %-5s %-5s %-7s %-6s %-7s\n",
                                                                    $team, $wins, $losses, $pct, $gb, $l10;
                                                               #$arg{'kernel'}->post( localhost => privmsg => $d, $q);
                                                               $q=~s/\s+$//;
                                                               push(@{ $self->{'standings'} }, $q);
                                                               return $self;
                                                             }
                                                                 }
                                                           }, 
                                               'self,tagname' );
                              return $self; 
                             },
                             'self,tagname,attr' 
                       ],
        report_tags => [ qw( tr ) ],
    );
    my $h = sprintf "%-20s %-5s %-5s %-7s %-6s %-7s\n",
        '', 'W', 'L', ' Pct', 'GB', 'L10';
    #$arg{'kernel'}->post( localhost => privmsg => $d, $h);
    $h=~s/\s+$//;
    push(@{  $p->{'standings'} },$h);
    $p->parse( $content );
    return @{ $p->{'standings'} };
}
################################################################################
# End Standings
################################################################################

################################################################################
# Begin Help
################################################################################
sub help {
    my $self = shift;
    my $line = shift;
    my $help = {
                 'fortune'    => [ 
                                   'description: Display a random fortune',
                                   'syntax/use : fortune',
                                 ],
                  'image'     => [
                                   "description: Add an image to tumble",
                                   "syntax/use : e-mail to tumble\@wcyd.org",
                                 ],
                  'quote'     => [
                                   "description: Add a quote to tumble",
                                   "syntax/use : \"Quote quote quote...\" -- Author",
                                 ],
                  'link'      => [
                                   "description: Add a link to tumble",
                                   "syntax/use : Cut and paste a link into irc, stupid.",
                                 ],
                  'shoutout'  => [
                                   "description: Send a textpage to everyone",
                                   "syntax/use : !shoutout beer @ bbh now, bitches.",
                                   "enable : !enable shoutout",
                                   "disable : !disable shoutout",
                                 ],
                  'standings' => [
                                   "description: Baseball standings",
                                   "syntax/use : To piss off Heath.",
                                 ],
                  'weather'   => [
                                   "description: Weather report",
                                   "syntax/use : !weather <zip/city/whatevah>.",
                                 ],
                  'insult'    => [
                                   "description: Insult someone",
                                   "syntax/use : !insult <target (optional)>",
                                 ],
                  'tell'      => [
                                   "description: Send a textpage to an individual",
                                   "syntax/use : !tell james: you are a fag.",
                                 ],
                  'tumble'    => [
                                   "description: Our tumblelog",
                                   "syntax/use : http://tumble.wcyd.org/",
                                 ],
               };
    if($line=~m/^!*help\s*$/){
        return [ 'Available help topics: '. join(' ',(keys(%{ $help }))) ];
    }elsif($line=~m/^!*help\s+(.*)\s*/){
        my $subtopic = $1;
        if(defined($help->{$subtopic})){
            return $help->{$subtopic};
        }else{
            return [ "I don't believe I can help you with that." ];
        }
    }
    return $line;
}
################################################################################
# End Help
################################################################################

################################################################################
# Begin Twitter events
################################################################################
sub delay_friend_timeline {
    my($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
    $heap->{ $self->alias() }->{'twitter'}->yield('friend_timeline');
}

sub new_tweet {
    my($self, $kernel, $heap, $status) = @_[OBJECT, KERNEL, HEAP, ARG0];
    $self->{'twitter'}->yield( 'update', $status );
}

sub twitter_update_success {
    my($self, $kernel, $heap, $ret) = @_[OBJECT, KERNEL, HEAP, ARG0];
    #$heap->{ircd}->yield(daemon_cmd_notice => $conf->{botname}, $conf->{channel}, $ret->{text});
}

sub twitter_timeline_success {
    my($self, $kernel, $heap, $ret) = @_[OBJECT, KERNEL, HEAP, ARG0];
    my $count=0;
    foreach my $tweet (@{ $ret }){
        my $text=$tweet->{'text'};
        if($tweet->{'user'}->{'screen_name'} eq 'mediacas'){
            $text=~s/^I used #*Shazam to discover\s+(.*)\s+by\s+(.*)\s+http:\/\/.*/$1 $2/;
            $text=~s/^I used #*Shazam to discover\s+(.*)\s+by\s+(.*)\s+#shazam.*/$1 $2/;
        }
        if($heap->{'twitter_enabled'}){
            foreach my $location (keys(%{ $heap->{'locations'} })){
                foreach my $channel (keys(%{ $heap->{'locations'}->{$location} })){
                    $kernel->post(
                                   $location,
                                   $heap->{'output_event'}->{$location},
                                   $channel,
                                   "[\@". $tweet->{'user'}->{'screen_name'}."]: ".$text
                                 );
                }
            }
        }
    }
    $kernel->delay('delay_friend_timeline', $self->{'retry'});
}

sub twitter_error {
    my($self, $kernel, $heap, $res) = @_[OBJECT, KERNEL, HEAP, ARG0];
    print STDERR "twitter_error\n". Data::Dumper->Dump([$res->{'_rc'}, $res->{'_content'}]) ."\n";
    #$heap->{ircd}->yield(daemon_cmd_notice => $conf->{botname}, $conf->{channel}, 'Twitter error');
}

sub enable_twitter {
    my($self, $kernel, $heap, $res) = @_[OBJECT, KERNEL, HEAP, ARG0];
    $heap->{'twitter_enabled'} = 1;
}

sub twitter_follow {
    my $self = shift;
    my $tweeter = shift if @_;
    my $follow = shift if @_;
    return undef unless defined($tweeter);
    return undef unless defined($follow);
    if($follow == 1){
        $self->{'twitter'}->yield( 'follow', $tweeter );
        return "following \@$tweeter\n";
    }else{
        $self->{'twitter'}->yield( 'unfollow', $tweeter );
        return "unfollowing \@$tweeter\n";
    }
}
################################################################################
# End Twitter events
################################################################################
1;
