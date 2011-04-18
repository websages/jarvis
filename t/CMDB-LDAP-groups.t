use Test::More tests => 1;
BEGIN { 
        unshift(@INC,"../lib") if -d "../lib"; 
        unshift(@INC,"lib") if -d "lib"; 
        use_ok('CMDB::LDAP');
      }

my $creds =  {
               'uri'    => 'ldaps://freyr.websages.com:636, ldaps://odin.websages.com:636',
               'basedn' => 'dc=websages,dc=com',
               'binddn' => 'uid=whitejs,ou=People,dc=websages,dc=com',
               'bindpw' => $ENV{'BINDPW'},
               'setou'  => 'Sets',
             };
my $groups = CMDB::LDAP->new($creds);
my @sets = @{ $groups->all_sets() };
foreach $set (@sets){
    print "[ $set ]: \n";
    foreach my $member ($groups->members($set)){
        print "  - $member\n";
    }
}

