---
persona:
  class: Jarvis::Persona::Jarvis
  init:
    alias: jarvis
    connector: jarvis_irc
    ldap_domain: [% DOMAIN %]
    ldap_binddn: cn=[% HOSTNAME %],ou=Hosts,[% BASEDN %]
    ldap_bindpw: [% LDAP_PASSWORD %]
connectors:
  - class: Jarvis::IRC
    init:
      alias: jarvis_irc
      persona: jarvis
      nickname: jarvis
      ircname: "Just another really vigilant infrastructure sysadmin"
      server: [% IRC_SERVER %]
      domain: [% DOMAIN %]
      channel_list:
        - #puppies

