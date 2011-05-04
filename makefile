install: install-eft

commit: 
	[ ! -x "${COMMENT}" ] && git commit -a -m "${COMMENT}"

push: commit
	git push

#install-ws-prod: 
#	ping -w1 -c1 odin.websages.com && /var/lib/gems/1.8/bin/wd setup --to=odin
#	ping -w1 -c1 odin.websages.com && /var/lib/gems/1.8/bin/wd deploy --to=odin
#	ping -w1 -c1 freyr.websages.com && /var/lib/gems/1.8/bin/wd setup --to=freyr
#	ping -w1 -c1 freyr.websages.com && /var/lib/gems/1.8/bin/wd deploy --to=freyr
#
#install-ws-test: 
#	ping -w1 -c1 loki.websages.com && /var/lib/gems/1.8/bin/wd setup --to=loki
#	ping -w1 -c1 loki.websages.com && /var/lib/gems/1.8/bin/wd deploy --to=loki
#	ping -w1 -c1 thor.websages.com && /var/lib/gems/1.8/bin/wd setup --to=thor
#	ping -w1 -c1 thor.websages.com && /var/lib/gems/1.8/bin/wd deploy --to=thor
#	ping -w1 -c1 vili.websages.com && /var/lib/gems/1.8/bin/wd setup --to=vili
#	ping -w1 -c1 vili.websages.com && /var/lib/gems/1.8/bin/wd deploy --to=vili
#
install-eft: 
	ping -w1 -c1 redwood.lab.eftdomain.net && /var/lib/gems/1.8/bin/wd setup --to=eft
	ping -w1 -c1 redwood.lab.eftdomain.net && /var/lib/gems/1.8/bin/wd deploy --to=eft

#echo:
#	echo "This makefile is to create the png from the dia file"
#jarvis.png: jarvis.dia
#	dia --export=jarvis.png -t png -s 1024x768 jarvis.dia 2>/dev/null
#
#jarvis.dia:
#
#clean:
##	/bin/rm jarvis.png
#
#install-eft: 
#	ping -w1 -c1 redwood.lab.eftdomain.net && /var/lib/gems/1.8/bin/wd setup --to=eft
#	ping -w1 -c1 redwood.lab.eftdomain.net && /var/lib/gems/1.8/bin/wd deploy --to=eft
#
#echo:
#	echo "This makefile is to create the png from the dia file"
#jarvis.png: jarvis.dia
#	dia --export=jarvis.png -t png -s 1024x768 jarvis.dia 2>/dev/null
#
#jarvis.dia:
#
#clean:
#	/bin/rm jarvis.png
