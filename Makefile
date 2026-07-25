.PHONY: dev release

dev:
	cd example && flutter run -d chrome

release:
	cd example && flutter run -d chrome --release
