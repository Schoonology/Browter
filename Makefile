all: app

clean:
	rm -rf Browter.app

app:
	mkdir -p Browter.app/Contents/MacOS
	clang -lobjc -fobjc-arc -framework Foundation -framework AppKit main.m -o Browter.app/Contents/MacOS/main
	cp Info.plist Browter.app/Contents/.
	rm -rf Browter.app/Contents/MacOS/main.dSYM
