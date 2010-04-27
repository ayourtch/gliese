magnet: magnet.c
	gcc -I/usr/include/lua5.1 -Wall -O2 -g -o magnet magnet.c -lfcgi -llua5.1 -lm -ldl -lssl
install: magnet
	# sudo killall lwp.magnet
	sudo cp magnet /usr/local/bin/lwp.magnet

