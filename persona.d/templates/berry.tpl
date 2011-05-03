---
persona:
  class: Jarvis::Persona::Crunchy
  init:
    alias: berry
    ldap_domain: [% DOMAIN %]
    ldap_binddn: cn=[% HOSTNAME %],ou=Hosts,[% BASEDN %]
    ldap_bindpw: ${ENV{'LDAP_PASSWORD'}}
    twitter_name: capncrunchbot
    password: ${ENV{'TWITTER_PASSWORD'}}
    retry: 150
    start_twitter_enabled: 1
connectors:
  - class: Jarvis::IRC
    init:
      alias: berry_irc
      nickname: berry
      ircname: "beta Cap'n Crunchbot"
      server: 127.0.0.1
      domain: websages.com
      channel_list:
        - #twoggies
      persona: berry

