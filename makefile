install-ws:
	/var/lib/gems/1.8/bin/wd setup --to=loki
	/var/lib/gems/1.8/bin/wd deploy --to=loki

install-eft:
	/var/lib/gems/1.8/bin/wd setup --to=eft
	/var/lib/gems/1.8/bin/wd deploy --to=eft

echo:
	echo "This makefile is to create the png from the dia file"
jarvis.png: jarvis.dia
	dia --export=jarvis.png -t png -s 1024x768 jarvis.dia 2>/dev/null

jarvis.dia:

clean:
	/bin/rm jarvis.png
