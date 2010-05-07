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
     ###########################################################################     
     # Response handlers
     ###########################################################################     
     my $pirate=1;
     my $directly_addressed = $msg->{'conversation'}->{'direct'}||0;
     if(defined($what)){
         if(defined($heap->{'locations'}->{$sender_alias}->{$where})){ 
             foreach my $chan_nick (@{ $heap->{'locations'}->{$sender_alias}->{$where} }){ 
                 if($what=~m/^\s*$chan_nick\s*:*\s*/){ 
                     $what=~s/^\s*$chan_nick\s*:*\s*//;
                     $directly_addressed=1;
                 }
             }
         }
         my $r=""; # response
         if($what=~m/^\s*!*help\s*/){
             my $reply = $self->help($what);
             foreach my $r (@{ $reply }){
                 $kernel->post($sender, $respond_event, $msg, $r); 
             }
             return;
         }elsif($what=~m/\"(.+?)\"\s+--\s*(.+?)$/){
             $r = $self->quote($what);
         }elsif($what=~m/(https*:\S+)/){
             $r = $self->link($what, $who);
         }elsif($what=~m/^\s*fortune\s*$/){
             $r = $self->fortune();
         }elsif($what=~m/^!shoutout\s*(.*)/){
             my $shoutout=$1;
             $r = $self->shoutout($1,$who);
             $pirate=0;
         }elsif($what=~m/^!enable\s+shoutouts*/){
             $msg->{'reason'}='enable_shoutout';
             $kernel->post($sender, 'authen', $msg); 
         }elsif($what=~m/^!disable\s+shoutouts*/){
             $msg->{'reason'}='disable_shoutout';
             $kernel->post($sender, 'authen', $msg); 
         }elsif($what=~m/^!weather\s+(.+?)$/){
             $r = qx( ruby /usr/local/bin/weather.rb $1 );
         }elsif($what=~m/^!insult\s+(.+?)$/){
             $r = qx( ruby /usr/local/bin/insult.rb $1 );
         }elsif($what=~m/^!tell\s+(.+?):*\s+(.+?)$/){
             my ($recipient,$message)=($1,$2);
             # first we try to dereference the nickname
             $msg->{'reason'}  = 'tell_request';
             $msg->{'conversation'}->{'originator'} = $msg->{'conversation'}->{'nick'};
             $msg->{'conversation'}->{'nick'}  = $recipient;
             $msg->{'conversation'}->{'body'}  = $message;
             $kernel->post($sender,'authen',$msg);
             my $r = $self->tell($1,$2);
         }elsif($what=~m/^!standings\s*(.*)/){
             my @r = $self->standings();
             $pirate=0;
             foreach $r (@r){
                 $kernel->post($sender, $respond_event, $msg, $r); 
             }
             return; 
         }elsif($what=~m/^!*follow\s+\@(.\S+)/){
             $r = $self->twitter_follow($1,1);
         }elsif($what=~m/^!*unfollow\s+\@(.\S+)/){
             $r = $self->twitter_follow($1,0);
         }elsif($what=~m/^\s*who\s*am\s*i[?\s]*/){
             $pirate=0;
             $msg->{'reason'}='whoami';
             $kernel->post($sender, 'authen', $msg); 
         }elsif($directly_addressed==1){
             if($msg->{'conversation'}->{'direct'} == 0){
                 $r = "$who: ".$self->megahal($what);
             }else{
                 $r = $self->megahal($what);
             }
         }
         
         if($r){ 
             if($r ne ""){ 
                 if( $pirate ){
                     $kernel->post($sender, $respond_event, $msg, piratespeak( $r ) ); 
                 }else{
                     $kernel->post($sender, $respond_event, $msg, $r); 
                 }
             }
         }
     }
     ###########################################################################     
     # End Response handlers
     ###########################################################################     
}
