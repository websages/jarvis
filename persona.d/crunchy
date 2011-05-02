---
persona:
  class: Jarvis::Persona::Crunchy
  init:
    alias: crunchy
    ldap_domain: [% DOMAIN %]
    ldap_binddn: cn=[% HOSTNAME %],ou=Hosts,[% BASEDN %]
    ldap_bindpw: [% LDAP_PASSWORD %]
    twitter_name: capncrunchbot
    password: [% TWITTER_PASSWORD %]
    retry: 150
    start_twitter_enabled: 0
connectors:
  - class: Jarvis::IRC
    init:
      alias: crunchy_irc
      nickname: crunchy
      ircname: "Cap'n Crunchbot"
      server: 127.0.0.1
      domain: [% DOMAIN %]
      channel_list:
        - #soggies
      persona: crunchy

