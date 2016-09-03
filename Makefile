gen:
	perl gen.pl

sync:
	 rsync -vr autopub slugworth.cs.umd.edu:.h

clean:
	rm -Rf autopub

