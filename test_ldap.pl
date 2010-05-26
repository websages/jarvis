#!/usr/bin/perl
$ENV{'PATH'}='/usr/local/bin:/usr/bin:/bin';
$ENV{'IFS'}=' \t\n';
BEGIN { unshift @INC, './lib' if -d './lib'; }
use LDAP::Simple;
use Data::Dumper;

my $ldap = LDAP::Simple->new({ 
                               'domain' => 'websages.com', 
                               'binddn' => 'uid=whitejs,ou=People,dc=websages,dc=com', 
                               'bindpw' => $ENV{'LDAP_PASSWORD'},
                             });

my @membs = $ldap->unique_members("cn=bot_managed");
foreach my $member (@membs){
   $member=~s/,\s*ou=[Hh]osts\s*,$ldap->{'basedn'}//g;
   $member=~s/^cn=//;
   print $member.".websages.com\n";
}
