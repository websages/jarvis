install: install-eft

commit: 
	[ ! -x "${COMMENT}" ] && git commit -a -m "${COMMENT}"

push: commit
	git push

install-ws: 
	ping -w1 -c1 loki.websages.com && /var/lib/gems/1.8/bin/wd setup --to=loki
	ping -w1 -c1 loki.websages.com && /var/lib/gems/1.8/bin/wd deploy --to=loki

install-eft: 
	ping -w1 -c1 redwood.lab.eftdomain.net && /var/lib/gems/1.8/bin/wd setup --to=eft
	ping -w1 -c1 redwood.lab.eftdomain.net && /var/lib/gems/1.8/bin/wd deploy --to=eft

install-badger: 
	ping -w1 -c1 badger.lab.eftdomain.net && /var/lib/gems/1.8/bin/wd setup --to=badger
	ping -w1 -c1 badger.lab.eftdomain.net && /var/lib/gems/1.8/bin/wd deploy --to=badger

echo:
	echo "This makefile is to create the png from the dia file"
jarvis.png: jarvis.dia
	dia --export=jarvis.png -t png -s 1024x768 jarvis.dia 2>/dev/null

jarvis.dia:

clean:
	/bin/rm jarvis.png
