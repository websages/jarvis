package LDAP::Simple;
use Net::DNS::Resolver;
use Net::LDAP;

sub new{
    my $class = shift;
    my $self = {};
    my $construct = shift if @_;
    bless($self,$class);
    $self->{'must'} = [ 'domain', 'binddn', 'bindpw' ];
    foreach my $attr (@{ $self->{'must'} }){
        if(defined($construct->{$attr})){
            $self->{$attr} = $construct->{$attr};
        }else{
            print STDERR "Required session constructor attribute [$attr] not defined. ";
            print STDERR "unable to define ". __PACKAGE__ ." object\n";
            return undef;
        }
    }
    $self->ldap_srv_records();
}

sub ldap_srv_records{
    my $self=shift;
    if( (!defined($self->{'domain'})) || (!defined($self->{'binddn'})) || (!defined($self->{'bindpw'})) ){
        print STDERR "[ $self->{'domain'} :: $self->{'binddn'} :: $self->{'bindpw'} ]\n";
        print STDERR "WARNING: Not enough LDAP paramaters supplied. LDAP operations will be disabled.\n";
        $self->{'ldap_enabled'}=0;
    }else{
        $self->{'basedn'} = $self->{'domain'};
        $self->{'basedn'} =~s/\./,dc=/g;
        $self->{'basedn'} = "dc=".$self->{'basedn'};
        $self->{'resolver'} = Net::DNS::Resolver->new;
print Data::Dumper->Dump([$self->{'resolver'}]);
        my $srv = $self->{'resolver'}->query( "_ldap._tcp.".$self->{'domain'}, "SRV" );
        if($srv){
            foreach my $rr (grep { $_->type eq 'SRV' } $srv->answer) {
                my $uri;
                my $order=$rr->priority.".".$rr->weight;
                if($rr->port eq 389){
                    $uri = "ldap://".$rr->target.":".$rr->port;
                }else{
                    $uri = "ldaps://".$rr->target.":".$rr->port;
                }
                if( defined($self->{'uri'}) ){
                    $self->{'uri'}=$self->{'uri'}.", $uri";
                }else{
                    $self->{'uri'}=$uri;
                }
                $self->{'ldap_enabled'}=1;
            }
        }else{
            print STDERR "Cannot resolve srv records for _ldap._tcp.".$self->{'domain'}.". LDAP operations will be disabled.\n";
            $self->{'ldap_enabled'}=0;
        }
    }
    return $self;
}

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

sub unique_members{
    my $self = shift;
    my $groupofuniquenames = shift if @_;
    return undef unless $groupofuniquenames;
    my @values;
    my $entries;
    @{ $entries } = $self->get_ldap_entry($groupofuniquenames);
    foreach my $entry (@{ $entries }){
        my $attribute;
        foreach $attribute ( $entry->get_value('uniqueMember') ){
            push(@values, $attribute);
        }
    }
   return @values;
}

sub entry_attr{
    my $self = shift;
    my $entrydn = shift if @_;
    my $attr = shift if @_;
    return undef unless $entrydn;
    return undef unless $attr;
    my @values;
    my $entries;
    @{ $entries } = $self->get_ldap_entry($entrydn);
    foreach my $entry (@{ $entries }){
        my $attribute;
        foreach $attribute ( $entry->get_value($attr) ){
            push(@values, $attribute);
        }
    }
   return @values;
}

sub get_ldap_entry {
    my $self = shift;
    my $filter = shift if @_;
    $filter = "(objectclass=*)" unless $filter;
    my $servers;
    if($self->{'uri'}){
        @{ $servers }= split(/\,\s+/,$self->{'uri'})
    }
    my $mesg;
    while( my $server = shift(@{ $servers })){
        if($server=~m/(.*)/){
            $server=$1 if ($server=~m/(^[A-Za-z0-9\-\.\/:]+$)/);
        }
        my $ldap = Net::LDAP->new($server) || warn "could not connect to $server $@";
        $mesg = $ldap->bind( $self->{'binddn'}, password => $self->{'bindpw'});
        if($mesg->code != 0){ $self->error($mesg->error); }
        next if $mesg->code;
        my $records = $ldap->search(
                                     'base'   => "$self->{'basedn'}",
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
        @{ $servers } = split(/,/,$self->{'uri'}) if $self->{'uri'};
    }
    my @what_to_change;
    while(my $server=shift(@{$servers})){
        $self->error("Updating: ".$entry->dn." at ".$server);
        if($server=~m/(.*)/){ $server=$1 if ($server=~m/(^[A-Za-z0-9\-\.\/:]+$)/); }
        my $ldap = Net::LDAP->new($server) || warn "could not connect to $server $@";
        $mesg = $ldap->bind( $self->{'binddn'}, password => $self->{'bindpw'});
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

1;
